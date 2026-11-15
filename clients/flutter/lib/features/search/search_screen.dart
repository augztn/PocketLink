import 'dart:async';
import '../../core/widgets/home_server_app_bar.dart';
import 'dart:convert';
import 'dart:typed_data';

import 'package:cross_file/cross_file.dart';
import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:open_filex/open_filex.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/network/server_api.dart';
import '../../core/network/offline_file_cache.dart';
import 'dart:io';
import '../files/file_manager_screen.dart';
import '../media/media_player_screen.dart';
import '../media/now_playing_screen.dart';
import '../media/persistent_audio_player.dart';
import '../storage/storage_browser_screen.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({required this.api, this.onHome, super.key});
  final ServerApi api;
  final VoidCallback? onHome;
  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _Result {
  const _Result(this.file, this.path, this.volumeName, this.volume, {this.localPath});
  final String? localPath;
  final FileEntry file;
  final String path;
  final String volumeName;
  final String? volume;
}

class _SearchScreenState extends State<SearchScreen> {
  static const _audio = {'mp3','m4a','aac','wav','flac','ogg','opus','wma','aiff','alac'};
  static const _video = {'mp4','m4v','mov','mkv','webm','avi','wmv','mpeg','mpg','3gp','ts','m2ts','mts','flv','ogv'};
  static const _photo = {'jpg','jpeg','png','webp','gif','bmp','heic','heif','avif'};
  static const _docs = {'pdf','doc','docx','xls','xlsx','ppt','pptx','txt','rtf','odt','ods','csv','md'};
  static const _historyKey = 'homeserver_recent_searches';
  static const _secure = FlutterSecureStorage();

  final _controller = TextEditingController();
  final _results = <_Result>[];
  final _offlineCache = OfflineFileCache();
  final _volumes = <StorageVolume>[];
  Timer? _debounce;
  String _category = 'All';
  String? _scope;
  String? _quick;
  List<String> _history = [];
  bool _loading = false;
  bool _scanned = false;
  String? _error;
  int _scanGeneration = 0;
  int _scannedFolders = 0;
  final _pendingDirectories = <({String path, String? volume, String name, int depth})>[];
  final _visitedDirectories = <String>{};
  final _allFound = <_Result>[];
  int _directoryCursor = 0;
  bool _scanInitialized = false;
  bool _scanTruncated = false;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_queryChanged);
    _loadHistory();
    _loadVolumes();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.removeListener(_queryChanged);
    _controller.dispose();
    super.dispose();
  }

  Future<void> _loadHistory() async {
    try {
      final raw = await _secure.read(key: _historyKey);
      if (!mounted || raw == null) return;
      final value = jsonDecode(raw);
      if (value is List) setState(() => _history = value.whereType<String>().take(8).toList());
    } catch (_) {}
  }

  Future<void> _saveHistory(String query) async {
    if (query.trim().isEmpty) return;
    final values = [query.trim(), ..._history.where((v) => v.toLowerCase() != query.trim().toLowerCase())].take(8).toList();
    if (mounted) setState(() => _history = values);
    try { await _secure.write(key: _historyKey, value: jsonEncode(values)); } catch (_) {}
  }

  Future<void> _removeHistory(String query) async {
    final values = _history.where((v) => v != query).toList();
    setState(() => _history = values);
    try { await _secure.write(key: _historyKey, value: jsonEncode(values)); } catch (_) {}
  }

  Future<void> _loadVolumes() async {
    try {
      final values = await widget.api.listStorageVolumes();
      if (mounted) setState(() { _volumes..clear()..addAll(values.where((v) => v.available)); });
    } catch (_) {}
  }

  void _queryChanged() {
    _quick = null;
    _debounce?.cancel();
    if (_controller.text.trim().isEmpty) {
      setState(() { _error = null; _loading = false; });
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 300), _scan);
    setState(() {});
  }

  String _ext(String name) {
    final dot = name.lastIndexOf('.');
    return dot < 0 ? '' : name.substring(dot + 1).toLowerCase();
  }

  bool _categoryMatch(_Result r) {
    final e = _ext(r.file.name);
    return switch (_category) {
      'Photos' => _photo.contains(e),
      'Audio' => _audio.contains(e),
      'Videos' => _video.contains(e),
      'Documents' => _docs.contains(e),
      'Files' => !_photo.contains(e) && !_audio.contains(e) && !_video.contains(e),
      _ => true,
    };
  }

  bool _scopeMatch(_Result r) => _scope == null ||
      (_scope == 'internal' ? r.volume == null : r.volume == _scope);

  bool _quickMatch(_Result r) {
    if (_quick == 'large') return r.file.size > 100 * 1024 * 1024;
    if (_quick == 'offline') return r.localPath != null;
    if (_quick == 'today') {
      final d = DateTime.tryParse(r.file.created ?? r.file.modified)?.toLocal();
      final n = DateTime.now();
      return d != null && d.year == n.year && d.month == n.month && d.day == n.day;
    }
    return _quick == null || _quick == 'offline';
  }

  List<_Result> get _visible {
    final q = _controller.text.trim().toLowerCase();
    return _results.where((r) => _categoryMatch(r) && _scopeMatch(r) && _quickMatch(r) &&
      (q.isEmpty || r.file.name.toLowerCase().contains(q) || r.path.toLowerCase().contains(q) || r.volumeName.toLowerCase().contains(q)))
      .toList(growable: false);
  }

  Future<void> _scan({bool refresh = false, bool continueExisting = false}) async {
    if (_quick == 'offline') { await _loadOfflineResults(); return; }
    final query = _controller.text.trim();
    if (query.isEmpty && _quick == null) return;
    if (_loading) return;
    if (_scanned && !refresh && !continueExisting) {
      if (query.isNotEmpty) _saveHistory(query);
      setState(() {});
      return;
    }

    final generation = ++_scanGeneration;
    final isNewScan = refresh || !_scanInitialized;
    if (isNewScan) {
      _scanInitialized = true;
      _scanTruncated = false;
      _directoryCursor = 0;
      _pendingDirectories.clear();
      _visitedDirectories.clear();
      _allFound.clear();
      _scannedFolders = 0;
    }
    setState(() {
      _loading = true;
      _error = null;
      if (isNewScan) _results.clear();
    });

    try {
      if (_volumes.isEmpty) await _loadVolumes();
      if (isNewScan) {
        _pendingDirectories.addAll([
          for (final root in const ['', 'DCIM', 'Pictures', 'Download', 'Documents', 'Music', 'Movies'])
            if (_scope == null || _scope == 'internal')
              (path: root, volume: null, name: 'Internal storage', depth: 0),
          for (final v in _volumes)
            if (_scope == null || _scope == v.id)
              (path: '', volume: v.id, name: v.name, depth: 0),
        ]);
      }

      final startingDirectories = _visitedDirectories.length;
      final startingFiles = _allFound.length;
      var completedBatches = 0;
      while (_directoryCursor < _pendingDirectories.length &&
          _visitedDirectories.length - startingDirectories < 1800 &&
          _allFound.length - startingFiles < 10000 &&
          generation == _scanGeneration) {
        final batch = <({String path, String? volume, String name, int depth})>[];
        while (_directoryCursor < _pendingDirectories.length &&
            batch.length < 12 &&
            _visitedDirectories.length - startingDirectories < 1800) {
          final item = _pendingDirectories[_directoryCursor++];
          final key = '${item.volume ?? 'internal'}:${item.path}';
          if (_visitedDirectories.add(key)) batch.add(item);
        }
        await Future.wait(batch.map((item) async {
          try {
            final listing = item.volume == null
                ? await widget.api.listDirectory(item.path)
                : await widget.api.listStorageDirectory(item.volume!, item.path);
            _scannedFolders++;
            for (final file in listing.items) {
              if (file.name.startsWith('.')) continue;
              final path = item.path.isEmpty ? file.name : '${item.path}/${file.name}';
              if (file.isDirectory) {
                if (item.depth < 18) {
                  _pendingDirectories.add((
                    path: path,
                    volume: item.volume,
                    name: item.name,
                    depth: item.depth + 1,
                  ));
                }
              } else {
                _allFound.add(_Result(file, path, item.name, item.volume));
              }
            }
          } on DioException catch (e) {
            if (e.response?.statusCode != 403 && e.response?.statusCode != 404) rethrow;
          } catch (_) {
            // A revoked or unavailable folder must not abort other volumes.
          }
        }));
        if (generation != _scanGeneration) return;

        // Publish immediately on the first wave, then batch UI work to avoid
        // repeatedly copying and rebuilding the entire result list.
        completedBatches++;
        if (mounted && (completedBatches == 1 || completedBatches % 2 == 0)) {
          setState(() {
            _results
              ..clear()
              ..addAll(_allFound);
          });
        }
      }

      _scanTruncated = _directoryCursor < _pendingDirectories.length;
      _allFound.sort((a, b) => a.file.name.toLowerCase().compareTo(b.file.name.toLowerCase()));
      if (mounted && generation == _scanGeneration) {
        setState(() {
          _results
            ..clear()
            ..addAll(_allFound);
          _scanned = !_scanTruncated;
        });
        if (!_scanTruncated && query.isNotEmpty) _saveHistory(query);
      }
    } on DioException catch (e) {
      if (mounted && generation == _scanGeneration) {
        setState(() => _error = e.response?.statusCode == 401
            ? 'Login expired or credentials are incorrect.'
            : e.message ?? 'Could not search server storage. Check the connection and try again.');
      }
    } catch (_) {
      if (mounted && generation == _scanGeneration) {
        setState(() => _error = 'Could not search server storage.');
      }
    } finally {
      if (mounted && generation == _scanGeneration) setState(() => _loading = false);
    }
  }

  void _chooseQuick(String value) {
    final next = _quick == value ? null : value;
    _controller.clear();
    setState(() => _quick = next);
    if (_quick == 'offline') { _loadOfflineResults(); }
    else if (_quick != null) _scan();
  }

  void _chooseScope(String? value) {
    _scanGeneration++;
    setState(() { _scope = value; _scanned = false; _scanInitialized = false; _loading = false; });
    if (_controller.text.trim().isNotEmpty || _quick != null) _scan(refresh: true);
  }

  String _parent(String path) {
    final i = path.lastIndexOf('/');
    return i < 0 ? '' : path.substring(0, i);
  }

  String _size(int bytes) {
    if (bytes < 1024) return '$bytes B';
    const units = ['KB','MB','GB','TB'];
    var value = bytes / 1024, index = 0;
    while (value >= 1024 && index < units.length - 1) { value /= 1024; index++; }
    return '${value.toStringAsFixed(1)} ${units[index]}';
  }

  String _time(String raw) {
    final date = DateTime.tryParse(raw)?.toLocal();
    if (date == null) return 'Date unavailable';
    final delta = DateTime.now().difference(date);
    if (delta.inMinutes < 1) return 'Just now';
    if (delta.inHours < 1) return '${delta.inMinutes}m ago';
    if (delta.inDays < 1) return '${delta.inHours}h ago';
    if (delta.inDays < 7) return '${delta.inDays}d ago';
    return '${date.day}/${date.month}/${date.year}';
  }

  IconData _icon(_Result r) {
    final e = _ext(r.file.name);
    if (_audio.contains(e)) return Icons.audio_file_rounded;
    if (_video.contains(e)) return Icons.video_file_rounded;
    if (_photo.contains(e)) return Icons.image_rounded;
    if (_docs.contains(e)) return Icons.description_rounded;
    return Icons.insert_drive_file_outlined;
  }

  TextSpan _highlight(String name, String query, TextStyle? style) {
    final i = name.toLowerCase().indexOf(query.toLowerCase());
    if (query.isEmpty || i < 0) return TextSpan(text: name, style: style);
    return TextSpan(style: style, children: [
      TextSpan(text: name.substring(0, i)),
      TextSpan(text: name.substring(i, i + query.length), style: const TextStyle(backgroundColor: Color(0x665B8DEF), fontWeight: FontWeight.w800)),
      TextSpan(text: name.substring(i + query.length)),
    ]);
  }

  void _openFolder(_Result r) {
    if (r.volume == null) {
      Navigator.push(context, MaterialPageRoute<void>(builder: (_) => FileManagerScreen(api: widget.api, initialPath: _parent(r.path))));
    } else {
      Navigator.push(context, MaterialPageRoute<void>(builder: (_) => StorageBrowserScreen(api: widget.api, initialVolume: r.volume, initialPath: _parent(r.path))));
    }
  }

  Future<void> _open(_Result r) async {
    final e = _ext(r.file.name);
    final audio = _audio.contains(e), video = _video.contains(e);
    if (r.localPath != null && _photo.contains(e)) {
      await Navigator.push(context, MaterialPageRoute<void>(builder: (_) => Scaffold(
        appBar: AppBar(title: Text(r.file.name)),
        body: Center(child: InteractiveViewer(child: Image.file(File(r.localPath!), fit: BoxFit.contain))))));
    } else if (audio || video) {
      final queue = r.localPath != null
        ? [MediaQueueItem(title: r.file.name, path: r.path, volume: r.volume, localPath: r.localPath, size: r.file.size)]
        : _visible.where((v) => audio ? _audio.contains(_ext(v.file.name)) : _video.contains(_ext(v.file.name)))
          .map((v) => MediaQueueItem(title: v.file.name, path: v.path, volume: v.volume, localPath: v.localPath, size: v.file.size)).toList(growable: false);
      final index = queue.indexWhere((v) => v.path == r.path && v.volume == r.volume);
      await Navigator.push(context, MaterialPageRoute<void>(builder: (_) => audio
        ? NowPlayingScreen(api: widget.api, queue: queue, initialIndex: index < 0 ? 0 : index)
        : MediaPlayerScreen(
            api: widget.api, title: r.file.name, path: r.path, volume: r.volume,
            isVideo: true, queue: queue, initialIndex: index < 0 ? 0 : index)));
    } else if (_photo.contains(e)) {
      await Navigator.push(context, MaterialPageRoute<void>(builder: (_) => Scaffold(
        appBar: AppBar(title: Text(r.file.name)),
        body: Center(child: InteractiveViewer(child: Image.network(
          widget.api.mediaStreamUrl(r.path, volume: r.volume), headers: widget.api.mediaHeaders,
          fit: BoxFit.contain, errorBuilder: (_, __, ___) => const Icon(Icons.broken_image_outlined, size: 56)))))));
    } else if (r.localPath != null) {
      await OpenFilex.open(r.localPath!);
    } else {
      _openFolder(r);
    }
  }

  Future<void> _loadOfflineResults() async {
    setState(() { _loading = true; _error = null; });
    try {
      final cached = await _offlineCache.list(server: _offlineCache.serverId(widget.api));
      if (!mounted) return;
      setState(() {
        _results
          ..clear()
          ..addAll(cached.map((entry) => _Result(
            entry.entry, entry.path,
            entry.volume == null ? 'Internal storage' : entry.volume!,
            entry.volume,
            localPath: entry.localPath,
          )));
        _scanned = true;
      });
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not read offline cache.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _saveOffline(_Result r) async {
    try {
      await _offlineCache.cache(
        api: widget.api, path: r.path, volume: r.volume,
        name: r.file.name, size: r.file.size, modified: r.file.modified,
      );
      if (!mounted) return;
      _message('Saved original file for offline access.');
      if (_quick == 'offline') await _loadOfflineResults();
    } catch (e) {
      if (mounted) _message(e is StateError ? e.message.toString() : 'Could not cache this file.');
    }
  }

  Future<void> _removeOffline(_Result r) async {
    await _offlineCache.remove(_offlineCache.serverId(widget.api), r.volume, r.path);
    if (!mounted) return;
    setState(() => _results.remove(r));
    _message('Removed from offline cache.');
  }

  Future<Uint8List> _bytes(_Result r) async {
    if (r.localPath != null) return File(r.localPath!).readAsBytes();
    return r.volume == null
      ? widget.api.downloadFile(r.path)
      : widget.api.downloadStorageFile(r.volume!, r.path);
  }

  Future<void> _download(_Result r) async {
    try {
      final bytes = await _bytes(r);
      final saved = await FilePicker.platform.saveFile(dialogTitle: 'Save ${r.file.name}', fileName: r.file.name, bytes: bytes);
      if (saved != null && mounted) _message('Saved ${r.file.name}');
    } catch (_) { _message('Could not download this file.'); }
  }

  Future<void> _share(_Result r) async {
    try { await Share.shareXFiles([XFile.fromData(await _bytes(r), name: r.file.name)], text: r.file.name); }
    catch (_) { _message('Could not prepare this file for sharing.'); }
  }

  Future<void> _rename(_Result r) async {
    final c = TextEditingController(text: r.file.name);
    final name = await showDialog<String>(context: context, builder: (ctx) => AlertDialog(
      title: const Text('Rename file'),
      content: TextField(controller: c, autofocus: true, decoration: const InputDecoration(labelText: 'New name')),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(ctx, c.text.trim()), child: const Text('Rename')),
      ]));
    c.dispose();
    if (name == null || name.isEmpty || name == r.file.name) return;
    try {
      if (r.volume == null) { await widget.api.renameItem(r.path, name); }
      else { await widget.api.renameStorageItem(r.volume!, r.path, name); }
      setState(() => _scanned = false);
      _scan(refresh: true);
    } catch (_) { _message('Could not rename this file.'); }
  }

  Future<void> _delete(_Result r) async {
    final ok = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
      title: const Text('Delete file?'),
      content: Text('Delete "${r.file.name}"? This cannot be undone.'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete')),
      ]));
    if (ok != true) return;
    try {
      if (r.volume == null) { await widget.api.deleteItem(r.path); }
      else { await widget.api.deleteStorageItem(r.volume!, r.path); }
      setState(() => _results.remove(r));
    } catch (_) { _message('Could not delete this file.'); }
  }

  void _message(String value) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(value)));
  }

  Widget _resultsList(ThemeData theme, {bool shrink = false}) {
    final list = _visible;
    final q = _controller.text.trim();
    if (_error != null) return Padding(padding: const EdgeInsets.all(24), child: Text(_error!, textAlign: TextAlign.center));
    if (_loading && list.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(height: 12),
            Text(
              'Searching storage…',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '$_scannedFolders folders checked',
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      );
    }
    if (list.isEmpty) return Padding(padding: const EdgeInsets.all(24), child: Center(child: Text(
      _quick == 'large' ? 'No files larger than 100 MB found.' : _quick == 'today' ? 'No files added today.' : 'No matching files found.',
      style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant))));
    return ListView.separated(
      shrinkWrap: shrink,
      physics: shrink ? const NeverScrollableScrollPhysics() : const AlwaysScrollableScrollPhysics(),
      padding: EdgeInsets.fromLTRB(12, 8, 12, 96 + MediaQuery.paddingOf(context).bottom),
      itemCount: list.length,
      separatorBuilder: (_, __) => const Divider(height: 1, indent: 62),
      itemBuilder: (ctx, i) {
        final r = list[i];
        final breadcrumb = '${r.volumeName}  ›  ${r.path.replaceAll('/', '  ›  ')}';
        return ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
          leading: Container(width: 44, height: 44, decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(14)),
            child: Icon(_icon(r), color: theme.colorScheme.primary)),
          title: RichText(maxLines: 1, overflow: TextOverflow.ellipsis,
            text: _highlight(r.file.name, q, theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700))),
          subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(breadcrumb, maxLines: 1, overflow: TextOverflow.ellipsis),
            Text('${_size(r.file.size)}  ·  ${r.file.created == null ? 'Modified' : 'Added'} ${_time(r.file.created ?? r.file.modified)}', style: theme.textTheme.labelSmall),
          ]),
          isThreeLine: true,
          onTap: () => _open(r),
          trailing: PopupMenuButton<String>(
            onSelected: (v) {
              switch (v) {
                case 'folder': _openFolder(r); break;
                case 'offline': _saveOffline(r); break;
                case 'removeOffline': _removeOffline(r); break;
                case 'download': _download(r); break;
                case 'share': _share(r); break;
                case 'rename': _rename(r); break;
                case 'delete': _delete(r); break;
              }
            },
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'folder', child: Text('Open containing folder')),
              const PopupMenuItem(value: 'offline', child: Text('Save for offline')),
              if (r.localPath != null) const PopupMenuItem(value: 'removeOffline', child: Text('Remove offline copy')),
              const PopupMenuItem(value: 'download', child: Text('Download')),
              const PopupMenuItem(value: 'share', child: Text('Share')),
              const PopupMenuItem(value: 'rename', child: Text('Rename')),
              const PopupMenuItem(value: 'delete', child: Text('Delete')),
            ]),
        );
      });
  }

  Widget _quickChip(String label, String value, IconData icon) => Padding(
    padding: const EdgeInsets.only(right: 8),
    child: FilterChip(
      selected: _quick == value,
      avatar: Icon(icon, size: 16),
      label: Text(label),
      onSelected: (_) => _chooseQuick(value)));

  Widget _idle(ThemeData theme) => ListView(
    padding: EdgeInsets.fromLTRB(16, 20, 16, 96 + MediaQuery.paddingOf(context).bottom),
    children: [
      if (_history.isNotEmpty) ...[
        Row(children: [
          Expanded(child: Text('Recent searches', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800))),
          TextButton(onPressed: () async {
            setState(() => _history = []);
            try { await _secure.delete(key: _historyKey); } catch (_) {}
          }, child: const Text('Clear')),
        ]),
        Wrap(spacing: 8, children: [for (final item in _history)
          InputChip(label: Text(item), onPressed: () { _controller.text = item; _scan(); },
            onDeleted: () => _removeHistory(item))]),
        const SizedBox(height: 24),
      ],
      Text('Quick filters', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
      const SizedBox(height: 10),
      Wrap(children: [
        _quickChip('Large files · 100 MB+', 'large', Icons.data_usage_rounded),
        _quickChip('Added / modified today', 'today', Icons.today_rounded),
        _quickChip('Offline cached', 'offline', Icons.offline_pin_rounded),
      ]),
      if (_quick == 'offline') Padding(padding: const EdgeInsets.only(top: 12),
        child: Text('Offline copies are stored privately on this device. Cache limit: 512 MB; least-recently-used files are evicted automatically.',
          style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant))),
      if (_quick == 'large' || _quick == 'today' || _quick == 'offline') ...[
        const SizedBox(height: 18),
        _resultsList(theme, shrink: true),
      ],
    ]);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final query = _controller.text.trim();
    final categories = const ['All','Files','Photos','Audio','Videos','Documents'];
    final scopes = <DropdownMenuItem<String?>>[
      const DropdownMenuItem(value: null, child: Text('All Drives')),
      const DropdownMenuItem(value: 'internal', child: Text('Internal storage')),
      for (final v in _volumes) DropdownMenuItem(value: v.id, child: Text(v.name, overflow: TextOverflow.ellipsis)),
    ];
    return Scaffold(
      appBar: HomeServerAppBar(title: const Text('Search'), onHome: widget.onHome),
      body: Column(children: [
        Padding(padding: const EdgeInsets.fromLTRB(16, 8, 16, 8), child: TextField(
          controller: _controller,
          textInputAction: TextInputAction.search,
          onSubmitted: (_) { _debounce?.cancel(); _scan(); },
          decoration: InputDecoration(
            hintText: 'Search across all drives and media...',
            prefixIcon: const Icon(Icons.search_rounded),
            suffixIcon: query.isEmpty ? null : IconButton(
              tooltip: 'Clear search', onPressed: () { _controller.clear(); setState(() => _quick = null); },
              icon: const Icon(Icons.close_rounded)),
            filled: true, fillColor: theme.colorScheme.surfaceContainerLow,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: BorderSide.none),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: BorderSide.none),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(20),
              borderSide: BorderSide(color: theme.colorScheme.primary.withValues(alpha: 0.6))),
          ))),
        SizedBox(height: 44, child: ListView(scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 14), children: [
            for (final item in categories) Padding(padding: const EdgeInsets.only(right: 7),
              child: ChoiceChip(label: Text(item), selected: _category == item, onSelected: (_) => setState(() => _category = item))),
          ])),
        Padding(padding: const EdgeInsets.fromLTRB(16, 4, 16, 10), child: Row(children: [
          Icon(Icons.storage_rounded, size: 18, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: 8),
          Text('Search in', style: theme.textTheme.labelLarge),
          const SizedBox(width: 10),
          Expanded(child: DropdownButtonFormField<String?>(
            value: _scope, isDense: true, items: scopes, onChanged: _chooseScope,
            decoration: InputDecoration(contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
              filled: true, fillColor: theme.colorScheme.surfaceContainerLow,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none)),
          )),
        ])),
        if (_loading) ...[
          const LinearProgressIndicator(minHeight: 2),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 5, 16, 2),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Searching storage · $_scannedFolders folders · ${_visible.length} matches found',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ),
        ],
        if (_quick != null) Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
          child: Align(
            alignment: Alignment.centerLeft,
            child: InputChip(
              selected: true,
              label: Text(switch (_quick) {
                'offline' => 'Offline cached',
                'large' => 'Large files · 100 MB+',
                'today' => 'Added / modified today',
                _ => 'Filter active',
              }),
              onDeleted: () => _chooseQuick(_quick!),
            ),
          ),
        ),
        Expanded(child: query.isEmpty && _quick == null
          ? _idle(theme)
          : _quick == 'offline'
            ? _resultsList(theme)
            : query.isEmpty
              ? ListView(padding: EdgeInsets.only(bottom: 96 + MediaQuery.paddingOf(context).bottom),
                  children: [_resultsList(theme, shrink: true)])
              : _resultsList(theme)),
        if (!_loading && _scanTruncated && _quick != 'offline' && (query.isNotEmpty || _quick != null))
          Padding(padding: const EdgeInsets.fromLTRB(12, 4, 12, 8), child: Row(
            children: [
              Expanded(child: Text('${_visible.length} shown · $_scannedFolders folders scanned. More folders/files remain.',
                style: theme.textTheme.labelSmall)),
              TextButton(onPressed: () => _scan(continueExisting: true), child: const Text('Continue')),
            ],
          )),
        if (_scanned && !_loading && (query.isNotEmpty || _quick != null))
          Padding(padding: const EdgeInsets.only(bottom: 6, top: 2),
            child: Text('${_visible.length} results · $_scannedFolders folders scanned', style: theme.textTheme.labelSmall)),
      ]),
    );
  }
}
