import 'dart:typed_data';
import '../../core/widgets/pocketlink_app_bar.dart';
import '../../core/widgets/compact_search_field.dart';

import 'package:dio/dio.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../../core/network/server_api.dart';
import '../../core/navigation/pocketlink_navigation.dart';
import 'media_player_screen.dart';
import 'now_playing_screen.dart';
import 'persistent_audio_player.dart';
import '../transfers/transfer_manager_screen.dart';
import '../home/browser_state_store.dart';

enum MediaLibraryType { music, video }

class _MediaFile {
  const _MediaFile({required this.entry, required this.path, this.volume});

  final FileEntry entry;
  final String path;
  final String? volume;
}

class _MediaFolder {
  const _MediaFolder({required this.name, required this.path, required this.volume, required this.items});
  final String name;
  final String path;
  final String? volume;
  final List<_MediaFile> items;
}

class _MediaBrowserScreenState extends State<MediaBrowserScreen> {
  static const _audioExtensions = {
    'mp3', 'm4a', 'aac', 'wav', 'flac', 'ogg', 'opus',
    'wma', 'aiff', 'alac',
  };
  static const _videoExtensions = {
    'mp4', 'm4v', 'mov', 'mkv', 'webm', 'avi', 'wmv',
    'mpeg', 'mpg', '3gp', 'ts', 'm2ts', 'mts', 'flv', 'f4v',
    '3g2', 'm2v', 'ogv', 'vob', 'rmvb',
  };
  static const _maxDirectories = 10000;
  static const _maxDepth = 24;

  List<_MediaFile> _media = const [];
  bool _loading = true;
  String? _error;
  int _scannedDirectories = 0;
  int _skippedDirectories = 0;
  List<StorageVolume> _volumes = const [];
  String? _selectedVolume;
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();
  String _libraryView = 'all';
  String _layoutMode = 'grid';
  String _sortBy = 'name';
  String _currentFolderPath = '';
  late final String _stateKey;
  late final BrowserStateStore _browserState;
  final ScrollController _contentScrollController = ScrollController();
  double _pendingScrollOffset = 0;
  bool _openingMedia = false;

  bool get _isMusic => widget.type == MediaLibraryType.music;
  String get _title => _isMusic ? 'Music' : 'Videos';
  List<String> get _roots => _isMusic ? const ['Music'] : const [''];

  @override
  void initState() {
    super.initState();
    _stateKey = widget.api.baseUrl;
    _browserState = Provider.of<BrowserStateStore>(context, listen: false);
    final saved = _browserState.mediaState(_stateKey, widget.type.name);
    _selectedVolume = saved.selectedVolume;
    _libraryView = saved.view;
    _layoutMode = saved.layoutMode;
    _sortBy = saved.sortBy;
    _currentFolderPath = saved.folderPath;
    _pendingScrollOffset = saved.scrollOffset;
    _contentScrollController.addListener(_saveScrollOffset);
    _scan();
  }

  void _restoreScrollOffset() {
    if (!mounted || !_contentScrollController.hasClients || _pendingScrollOffset <= 0) return;
    _contentScrollController.jumpTo(_pendingScrollOffset.clamp(0, _contentScrollController.position.maxScrollExtent).toDouble());
    _pendingScrollOffset = 0;
  }

  void _saveState({String? folderPath, bool clearVolume = false}) {
    final current = _browserState.mediaState(_stateKey, widget.type.name);
    _browserState.updateMedia(_stateKey, widget.type.name, current.copyWith(
      folderPath: folderPath ?? _currentFolderPath,
      selectedVolume: _selectedVolume,
      clearSelectedVolume: clearVolume || _selectedVolume == null,
      view: _libraryView,
      sortBy: _sortBy,
      layoutMode: _layoutMode,
      scrollOffset: _contentScrollController.hasClients ? _contentScrollController.offset : current.scrollOffset,
    ));
  }

  void _saveScrollOffset() => _saveState();

  bool get _atFolderRoot => _currentFolderPath.isEmpty ||
      (_isMusic && _selectedVolume == 'internal' && _currentFolderPath == 'Music');

  void _goUpFolder() {
    if (_atFolderRoot) return;
    final parts = _currentFolderPath.split('/')..removeLast();
    final parent = parts.join('/');
    setState(() => _currentFolderPath = parent);
    _saveState(folderPath: parent);
    if (_contentScrollController.hasClients) _contentScrollController.jumpTo(0);
  }

  String _volumeName(String? id) {
    if (id == null || id == 'internal') return 'Internal storage';
    for (final volume in _volumes) {
      if (volume.id == id) return volume.name;
    }
    return 'USB / OTG';
  }

  bool _isMedia(FileEntry item) {
    final extension = item.name.contains('.')
        ? item.name.split('.').last.toLowerCase()
        : '';
    return (_isMusic ? _audioExtensions : _videoExtensions)
        .contains(extension);
  }

  Future<({List<_MediaFile> items, MediaIndexStatus status})>
      _readIndexedMedia() async {
    final category = _isMusic ? 'music' : 'video';
    final found = <_MediaFile>[];
    var offset = 0;
    late MediaIndexStatus status;
    do {
      final page = await widget.api.indexedMedia(
        category,
        query: _searchQuery,
        limit: 500,
        offset: offset,
      );
      status = page.status;
      if (!mounted) break;
      found.addAll(page.items.map((item) => _MediaFile(
        entry: item.toFileEntry(),
        path: item.path,
        volume: item.volume == 'internal' ? null : item.volume,
      )));
      offset += page.items.length;
      if (page.items.length < 500) break;
    } while (true);
    found.sort((a, b) =>
        a.entry.name.toLowerCase().compareTo(b.entry.name.toLowerCase()));
    return (items: found, status: status);
  }

  Future<void> _scan({bool refresh = false}) async {
    if (!mounted) return;
    if (refresh) {
      widget.api.invalidateDirectoryCache();
      try {
        await widget.api.startMediaIndexScan();
        if (!mounted) return;
      } on DioException {
        await _scanLegacy(refresh: refresh);
        return;
      }
    }
    if (!mounted) return;
    widget.api.clearMediaCache();
    setState(() {
      _loading = true;
      _error = null;
      _media = const [];
      _scannedDirectories = 0;
      _skippedDirectories = 0;
    });

    try {
      var result = await _readIndexedMedia();
      var found = result.items;
      var status = result.status;
      if (mounted) setState(() => _media = List.unmodifiable(found));

      // Keep the existing index visible while scanning. Poll only lightweight
      // status; reload media once after the scan finishes.
      final wasScanning = status.isScanning;
      while (mounted && status.isScanning) {
        await Future<void>.delayed(const Duration(seconds: 2));
        if (!mounted) return;
        status = await widget.api.mediaIndexStatus();
      }
      if (!mounted) return;
      if (wasScanning && status.state != 'failed') {
        result = await _readIndexedMedia();
        found = result.items;
        status = result.status;
      }

      if ((status.state == 'failed' || status.state == 'partial') && found.isEmpty) {
        await _scanLegacy();
        return;
      }
      if (mounted) {
        setState(() {
          _media = List.unmodifiable(found);
          _loading = false;
          _error = status.state == 'partial' && found.isEmpty
              ? status.lastError
              : null;
        });
        WidgetsBinding.instance.addPostFrameCallback((_) => _restoreScrollOffset());
      }
    } on DioException {
      await _scanLegacy(refresh: refresh);
    } catch (_) {
      await _scanLegacy(refresh: refresh);
    }
  }

  Future<void> _scanLegacy({bool refresh = false}) async {
    if (!mounted) return;
    if (refresh) widget.api.invalidateDirectoryCache();
    widget.api.clearMediaCache();
    setState(() {
      _loading = true;
      _error = null;
      _media = const [];
      _scannedDirectories = 0;
      _skippedDirectories = 0;
    });

    final found = <_MediaFile>[];
    final visited = <String>{};
    final pending = <({String path, int depth, String? volume})>[];

    try {
      try {
        final volumes = await widget.api.listStorageVolumes();
        _volumes = volumes.where((volume) => volume.available).toList(growable: false);
        if (_selectedVolume != null && _selectedVolume != 'internal' && !_volumes.any((volume) => volume.id == _selectedVolume)) {
          _selectedVolume = null;
          _currentFolderPath = '';
          _pendingScrollOffset = 0;
          _saveState(folderPath: '', clearVolume: true);
        }
        for (final volume in _volumes) {
          pending.add((path: '', depth: 0, volume: volume.id));
        }
      } on DioException {
        _skippedDirectories++;
      }

      pending.addAll(
        _roots.map((root) => (path: root, depth: 0, volume: null)),
      );

      var cursor = 0;
      while (mounted && cursor < pending.length && visited.length < _maxDirectories) {
        final current = pending[cursor++];
        final visitKey = '${current.volume ?? 'internal'}:${current.path}';
        if (!visited.add(visitKey)) continue;

        DirectoryListing listing;
        try {
          listing = current.volume == null
              ? await widget.api.listDirectory(current.path)
              : await widget.api.listStorageDirectory(
                  current.volume!,
                  current.path,
                );
          if (!mounted) return;
          _scannedDirectories++;
        } on DioException catch (error) {
          if (error.response?.statusCode == 404) continue;
          if (error.response?.statusCode == 403) {
            _skippedDirectories++;
            continue;
          }
          rethrow;
        }

        for (final item in listing.items) {
          final itemPath = current.path.isEmpty
              ? item.name
              : '${current.path}/${item.name}';
          if (item.isDirectory) {
            if (current.depth < _maxDepth) {
              pending.add((
                path: itemPath,
                depth: current.depth + 1,
                volume: current.volume,
              ));
            } else {
              _skippedDirectories++;
            }
          } else if (_isMedia(item)) {
            found.add(_MediaFile(
              entry: item,
              path: itemPath,
              volume: current.volume,
            ));
          }
        }

        if (mounted) {
          setState(() => _media = List.unmodifiable(found));
        }
      }

      if (cursor < pending.length) _skippedDirectories++;
      found.sort((a, b) =>
          a.entry.name.toLowerCase().compareTo(b.entry.name.toLowerCase()));
    } on DioException catch (error) {
      if (!mounted) return;
      final status = error.response?.statusCode;
      setState(() {
        _error = status == 401
            ? 'Login expired or credentials are incorrect.'
            : error.message ?? 'Could not scan media folders.';
      });
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not scan media folders.');
    } finally {
      if (mounted) {
        setState(() {
          _media = List.unmodifiable(found);
          _loading = false;
        });
        WidgetsBinding.instance.addPostFrameCallback((_) => _restoreScrollOffset());
      }
    }
  }

  Future<void> _openMedia(_MediaFile media, List<_MediaFile> queueItems) async {
    if (_openingMedia) return;
    _openingMedia = true;
    final queue = queueItems
        .map((item) => MediaQueueItem(
              title: item.entry.name,
              path: item.path,
              volume: item.volume,
              size: item.entry.size,
            ))
        .toList(growable: false);
    final index = queueItems.indexWhere(
      (item) => item.path == media.path && item.volume == media.volume,
    );
    try {
      await Navigator.of(context, rootNavigator: true).push<void>(
        MaterialPageRoute<void>(
          settings: _isMusic
              ? const RouteSettings(name: PocketLinkRouteNames.nowPlaying)
              : null,
          builder: (_) => _isMusic
            ? NowPlayingScreen(
                api: widget.api,
                queue: queue,
                initialIndex: index < 0 ? 0 : index,
              )
            : MediaPlayerScreen(
                api: widget.api,
                title: media.entry.name,
                path: media.path,
                volume: media.volume,
                isVideo: true,
                queue: queue,
                initialIndex: index < 0 ? 0 : index,
              ),
        ),
      );
    } finally {
      _openingMedia = false;
    }
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  String _sourceLabel(_MediaFile media) =>
      media.volume == null ? 'Internal storage' : 'USB / OTG';

  String _fileExtension(_MediaFile media) {
    final dot = media.entry.name.lastIndexOf('.');
    return dot < 0 ? '' : media.entry.name.substring(dot + 1).toUpperCase();
  }

  String _displayTitle(_MediaFile media) {
    final dot = media.entry.name.lastIndexOf('.');
    final name = dot > 0 ? media.entry.name.substring(0, dot) : media.entry.name;
    return name.replaceAll('_', ' ').trim();
  }

  String _countLabel(int count, String singular, String plural) =>
      '$count ${count == 1 ? singular : plural}';


  List<_MediaFolder> _foldersAtCurrentLevel(List<_MediaFile> items) {
    final grouped = <String, List<_MediaFile>>{};
    final prefix = _currentFolderPath.isEmpty
        ? <String>[]
        : _currentFolderPath.split('/').where((part) => part.isNotEmpty).toList();
    for (final media in items) {
      final source = media.volume ?? 'internal';
      if (_selectedVolume != null && source != _selectedVolume) continue;
      final parts = media.path.split('/').where((part) => part.isNotEmpty).toList();
      if (parts.length <= prefix.length + 1) continue;
      var matches = true;
      for (var i = 0; i < prefix.length; i++) {
        if (parts[i] != prefix[i]) { matches = false; break; }
      }
      if (!matches) continue;
      final folderPath = parts.take(prefix.length + 1).join('/');
      final key = '$source::$folderPath';
      grouped.putIfAbsent(key, () => <_MediaFile>[]).add(media);
    }
    final result = grouped.entries.map((entry) {
      final separator = entry.key.indexOf('::');
      final source = entry.key.substring(0, separator);
      final path = entry.key.substring(separator + 2);
      return _MediaFolder(
        name: path.split('/').last,
        path: path,
        volume: source == 'internal' ? null : source,
        items: entry.value,
      );
    }).toList();
    result.sort((a, b) {
      if (_sortBy == 'largest') {
        final aSize = a.items.fold<int>(0, (sum, item) => sum + item.entry.size);
        final bSize = b.items.fold<int>(0, (sum, item) => sum + item.entry.size);
        return bSize.compareTo(aSize);
      }
      if (_sortBy == 'newest') {
        DateTime newest(_MediaFolder folder) {
          return folder.items
              .map((item) => DateTime.tryParse(item.entry.modified))
              .whereType<DateTime>()
              .fold<DateTime>(DateTime.fromMillisecondsSinceEpoch(0),
                  (latest, date) => date.isAfter(latest) ? date : latest);
        }
        return newest(b).compareTo(newest(a));
      }
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    return result;
  }

  List<_MediaFile> _filesAtCurrentLevel(List<_MediaFile> items) {
    final prefix = _currentFolderPath.isEmpty
        ? <String>[]
        : _currentFolderPath.split('/').where((part) => part.isNotEmpty).toList();
    return items.where((media) {
      final source = media.volume ?? 'internal';
      if (_selectedVolume != null && source != _selectedVolume) return false;
      final parts = media.path.split('/').where((part) => part.isNotEmpty).toList();
      if (parts.length != prefix.length + 1) return false;
      for (var i = 0; i < prefix.length; i++) {
        if (parts[i] != prefix[i]) return false;
      }
      return true;
    }).toList();
  }

  List<_MediaFile> _sortMedia(List<_MediaFile> items) {
    final result = List<_MediaFile>.of(items);
    if (_sortBy == 'largest') {
      result.sort((a, b) => b.entry.size.compareTo(a.entry.size));
    } else if (_sortBy == 'newest') {
      result.sort((a, b) {
        final aDate = DateTime.tryParse(a.entry.modified);
        final bDate = DateTime.tryParse(b.entry.modified);
        return (bDate?.millisecondsSinceEpoch ?? 0)
            .compareTo(aDate?.millisecondsSinceEpoch ?? 0);
      });
    } else {
      result.sort((a, b) =>
          a.entry.name.toLowerCase().compareTo(b.entry.name.toLowerCase()));
    }
    return result;
  }

  Widget _buildVideoArtwork(_MediaFile media, {required BoxFit fit}) {
    return FutureBuilder<Uint8List?>(
      future: widget.api.videoThumbnail(media.path, volume: media.volume),
      builder: (context, snapshot) {
        final bytes = snapshot.data;
        if (bytes != null && bytes.isNotEmpty) {
          return Image.memory(bytes, fit: fit, gaplessPlayback: true);
        }
        return DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Theme.of(context).colorScheme.primaryContainer,
                Theme.of(context).colorScheme.surfaceContainerHighest,
              ],
            ),
          ),
          child: Icon(Icons.movie_creation_outlined, size: 42,
            color: Theme.of(context).colorScheme.onSurfaceVariant),
        );
      },
    );
  }

  Widget _videoMetadataLabel(_MediaFile media) {
    return FutureBuilder<VideoMetadata?>(
      future: widget.api.videoMetadata(media.path, volume: media.volume),
      builder: (context, snapshot) {
        final metadata = snapshot.data;
        if (metadata == null) return const SizedBox.shrink();
        final parts = <String>[
          if (metadata.resolution.isNotEmpty) metadata.resolution,
          if (metadata.durationMs > 0) _formatDuration(metadata.durationMs),
        ];
        if (parts.isEmpty) return const SizedBox.shrink();
        return Text(parts.join(' · '), maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.bodySmall);
      },
    );
  }

  String _formatDuration(int milliseconds) {
    final totalSeconds = milliseconds ~/ 1000;
    final hours = totalSeconds ~/ 3600;
    final minutes = (totalSeconds % 3600) ~/ 60;
    final seconds = totalSeconds % 60;
    final two = (int value) => value.toString().padLeft(2, '0');
    return hours > 0 ? '${hours}:${two(minutes)}:${two(seconds)}' : '${minutes}:${two(seconds)}';
  }
  Widget _buildVideoGrid(List<_MediaFile> items) {
    return GridView.builder(
      controller: _contentScrollController,
      padding: EdgeInsets.fromLTRB(12, 8, 12, 104 + MediaQuery.paddingOf(context).bottom),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 12,
        mainAxisSpacing: 14,
        childAspectRatio: 0.92,
      ),
      itemCount: items.length,
      itemBuilder: (context, index) {
        final media = items[index];
        final extension = media.entry.name.split('.').last.toUpperCase();
        return Card(
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () => _openMedia(media, items),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      _buildVideoArtwork(media, fit: BoxFit.cover),
                      Positioned(
                        left: 8,
                        top: 8,
                        child: _VideoTag(label: extension),
                      ),
                      Positioned(
                        right: 8,
                        bottom: 8,
                        child: _VideoTag(label: _formatBytes(media.entry.size)),
                      ),
                      Positioned(
                        right: 8,
                        top: 8,
                        child: Icon(
                          Icons.play_circle_fill_rounded,
                          color: Colors.white.withValues(alpha: 0.92),
                          size: 30,
                        ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(10, 9, 10, 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        media.entry.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      const SizedBox(height: 3),
                      _videoMetadataLabel(media),
                      Text(
                        _sourceLabel(media),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildVideoList(List<_MediaFile> items) {
    return ListView.separated(
      controller: _contentScrollController,
      padding: EdgeInsets.fromLTRB(12, 8, 12, 104 + MediaQuery.paddingOf(context).bottom),
      itemCount: items.length,
      separatorBuilder: (_, __) => const SizedBox(height: 4),
      itemBuilder: (context, index) {
        final media = items[index];
        final extension = media.entry.name.split('.').last.toUpperCase();
        return Card(
          clipBehavior: Clip.antiAlias,
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            leading: Container(
              width: 104,
              height: 64,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(10),
              ),
              clipBehavior: Clip.antiAlias,
              child: _buildVideoArtwork(media, fit: BoxFit.cover),
            ),
            title: Text(
              media.entry.name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('$extension · ${_formatBytes(media.entry.size)} · ${_sourceLabel(media)}',
                  maxLines: 1, overflow: TextOverflow.ellipsis),
                _videoMetadataLabel(media),
              ],
            ),
            trailing: const Icon(Icons.play_circle_outline_rounded),
            onTap: () => _openMedia(media, items),
          ),
        );
      },
    );
  }


  Widget _buildFolders(List<_MediaFile> items) {
    final folders = _foldersAtCurrentLevel(items);
    final files = _sortMedia(_filesAtCurrentLevel(items));
    final parts = _currentFolderPath.split('/').where((part) => part.isNotEmpty).toList();
    return Column(
      children: [
        if (_currentFolderPath.isNotEmpty || _selectedVolume != null)
          SizedBox(
            height: 38,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(children: [
                TextButton(
                  onPressed: _currentFolderPath.isEmpty && _selectedVolume == null
                      ? null
                      : () {
                          setState(() { _currentFolderPath = ''; _selectedVolume = null; });
                          _pendingScrollOffset = 0;
                          _saveState(folderPath: '', clearVolume: true);
                          if (_contentScrollController.hasClients) _contentScrollController.jumpTo(0);
                        },
                  child: const Text('All storage'),
                ),
                if (_selectedVolume != null) ...[
                  const Icon(Icons.chevron_right_rounded, size: 16),
                  TextButton(
                    onPressed: _currentFolderPath.isEmpty
                        ? null
                        : () { setState(() => _currentFolderPath = _selectedVolume == 'internal' && _isMusic ? 'Music' : ''); _pendingScrollOffset = 0; _saveState(folderPath: _currentFolderPath); if (_contentScrollController.hasClients) _contentScrollController.jumpTo(0); },
                    child: Text(_volumeName(_selectedVolume)),
                  ),
                ],
                for (var i = 0; i < parts.length; i++) ...[
                  const Icon(Icons.chevron_right_rounded, size: 16),
                  TextButton(
                    onPressed: i == parts.length - 1
                        ? null
                        : () {
                            final path = parts.take(i + 1).join('/');
                            setState(() => _currentFolderPath = path);
                            _saveState(folderPath: path);
                            if (_contentScrollController.hasClients) _contentScrollController.jumpTo(0);
                          },
                    child: Text(parts[i]),
                  ),
                ],
              ]),
            ),
          ),
        Expanded(
          child: ListView(
            controller: _contentScrollController,
            padding: EdgeInsets.fromLTRB(12, 8, 12, 104 + MediaQuery.paddingOf(context).bottom),
            children: [
              for (final folder in folders)
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.folder_rounded),
                    title: Text(folder.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                    subtitle: Text('${_countLabel(folder.items.length, _isMusic ? 'track' : 'video', _isMusic ? 'tracks' : 'videos')} · ${_volumeName(folder.volume)}'),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () {
                      setState(() {
                        _selectedVolume = folder.volume ?? 'internal';
                        _currentFolderPath = folder.path;
                      });
                      _pendingScrollOffset = 0;
                      _saveState(folderPath: folder.path);
                      if (_contentScrollController.hasClients) _contentScrollController.jumpTo(0);
                    },
                  ),
                ),
              for (final media in files)
                Card(
                  child: ListTile(
                    leading: Icon(_isMusic ? Icons.audio_file_outlined : Icons.movie_outlined),
                    title: Text(_isMusic ? _displayTitle(media) : media.entry.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                    subtitle: Text('${_isMusic && _fileExtension(media).isNotEmpty ? '${_fileExtension(media)} · ' : ''}${_formatBytes(media.entry.size)} · ${_volumeName(media.volume)}'),
                    trailing: const Icon(Icons.play_arrow_rounded),
                    onTap: () => _openMedia(media, files),
                  ),
                ),
              if (folders.isEmpty && files.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(32),
                  child: Center(child: Text('No media in this folder')),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _viewPill({
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    final colors = Theme.of(context).colorScheme;
    return Material(
      color: selected ? colors.surfaceContainerHighest : Colors.transparent,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: SizedBox(
          height: 30,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Center(
              child: Text(label, style: TextStyle(
                color: selected ? colors.onSurface : colors.onSurfaceVariant,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              )),
            ),
          ),
        ),
      ),
    );
  }

  Widget _menuPill({
    required String label,
    required List<PopupMenuEntry<String>> items,
    required ValueChanged<String> onSelected,
  }) {
    final colors = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return PopupMenuButton<String>(
      onSelected: onSelected,
      itemBuilder: (_) => items,
      child: Container(
        height: 36,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: colors.surfaceContainerLow,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: colors.outlineVariant.withValues(alpha: 0.62)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Text(label, style: textTheme.labelMedium?.copyWith(
            color: colors.onSurface, fontWeight: FontWeight.w600,
          )),
          const SizedBox(width: 4),
          Icon(Icons.keyboard_arrow_down_rounded, size: 17, color: colors.onSurfaceVariant),
        ]),
      ),
    );
  }

  @override
  void dispose() {
    _saveState();
    _searchController.dispose();
    _contentScrollController.removeListener(_saveScrollOffset);
    _contentScrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final query = _searchQuery.trim().toLowerCase();
    final filtered = _media.where((media) {
      final matchesQuery = query.isEmpty ||
          media.entry.name.toLowerCase().contains(query) ||
          media.path.toLowerCase().contains(query);
      final matchesVolume = _selectedVolume == null ||
          (_selectedVolume == 'internal' ? media.volume == null : media.volume == _selectedVolume);
      return matchesQuery && matchesVolume;
    }).toList(growable: false);
    final visibleMedia = _sortMedia(filtered);
    final isFolderView = _libraryView == 'folders';
    final selectedVolumes = _volumes.where((volume) => volume.id == _selectedVolume).toList();
    final sourceLabel = _selectedVolume == 'internal' ? 'Internal storage' : selectedVolumes.isEmpty ? 'All Storage' : selectedVolumes.first.name;

    return PopScope(
      canPop: _libraryView != 'folders' || _atFolderRoot,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && _libraryView == 'folders' && !_atFolderRoot) _goUpFolder();
      },
      child: Scaffold(
      appBar: PocketLinkAppBar(
        title: Text(_title),
        onHome: widget.onHome,
        actions: [
          PocketLinkAppBarAction(label: 'Transfers', icon: Icons.swap_vert_rounded, onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const TransferManagerScreen()))),
          if (!_isMusic)
            PocketLinkAppBarAction(
              label: _layoutMode == 'grid' ? 'List view' : 'Grid view',
              icon: _layoutMode == 'grid' ? Icons.view_list_rounded : Icons.grid_view_rounded,
              onPressed: () { setState(() { _layoutMode = _layoutMode == 'grid' ? 'list' : 'grid'; }); _saveState(); },
            ),
          PocketLinkAppBarAction(label: 'Scan again', icon: Icons.refresh, onPressed: _loading ? null : () => _scan(refresh: true)),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 22,
                  child: Icon(_isMusic
                      ? Icons.library_music_rounded
                      : Icons.video_library_rounded),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _countLabel(_media.length, _isMusic ? 'track' : 'video', _isMusic ? 'tracks' : 'videos'),
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      Text(
                        _loading
                            ? 'Scanning storage…'
                            : '$_scannedDirectories folders scanned'
                                '${_skippedDirectories > 0 ? ' · $_skippedDirectories skipped' : ''}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (widget.showSearch)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
              child: CompactSearchField(
                controller: _searchController,
                hintText: _isMusic ? 'Search songs or folders' : 'Search videos or folders',
                onChanged: (value) => setState(() => _searchQuery = value),
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  Container(
                    height: 36,
                    padding: const EdgeInsets.all(3),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surfaceContainerLow,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.62)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _viewPill(
                          label: _isMusic ? 'Songs' : 'All videos',
                          selected: _libraryView == 'all',
                          onTap: () { setState(() => _libraryView = 'all'); _saveState(); },
                        ),
                        _viewPill(
                          label: 'Folders',
                          selected: isFolderView,
                          onTap: () { setState(() => _libraryView = 'folders'); _saveState(); },
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  _menuPill(
                    label: sourceLabel,
                    items: [
                      const PopupMenuItem(value: 'all', child: Text('All storage')),
                      const PopupMenuItem(value: 'internal', child: Text('Internal storage')),
                      ..._volumes.where((volume) => volume.available).map((volume) => PopupMenuItem(
                        value: volume.id,
                        enabled: volume.available,
                        child: Text(
                          '${volume.name}${volume.available ? '' : ' · unavailable'}',
                          overflow: TextOverflow.ellipsis,
                        ),
                      )),
                    ],
                    onSelected: (value) {
                      final volume = value == 'all' ? null : value;
                      final rootPath = _isMusic && volume == 'internal' ? 'Music' : '';
                      setState(() {
                        _selectedVolume = volume;
                        _currentFolderPath = rootPath;
                      });
                      _pendingScrollOffset = 0;
                      _saveState(folderPath: rootPath, clearVolume: volume == null);
                      if (_contentScrollController.hasClients) _contentScrollController.jumpTo(0);
                    },
                  ),
                  const SizedBox(width: 8),
                  _menuPill(
                    label: switch (_sortBy) {
                      'newest' => 'Newest',
                      'largest' => 'Largest',
                      _ => 'Name',
                    },
                    items: const [
                      PopupMenuItem(value: 'name', child: Text('Name')),
                      PopupMenuItem(value: 'newest', child: Text('Newest')),
                      PopupMenuItem(value: 'largest', child: Text('Largest')),
                    ],
                    onSelected: (value) { setState(() => _sortBy = value); _saveState(); },
                  ),
                ],
              ),
            ),
          ),
          if (_loading) const LinearProgressIndicator(minHeight: 2),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          Expanded(
            child: _error != null
                ? Center(
                    child: FilledButton(
                      onPressed: _scan,
                      child: const Text('Retry scan'),
                    ),
                  )
                : _loading && _media.isEmpty
                    ? const Center(child: Text('Scanning storage for media…'))
                    : visibleMedia.isEmpty
                        ? Center(
                            child: Padding(
                              padding: const EdgeInsets.all(24),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    _isMusic
                                        ? Icons.library_music_outlined
                                        : Icons.video_library_outlined,
                                    size: 52,
                                    color: Theme.of(context).colorScheme.outline,
                                  ),
                                  const SizedBox(height: 12),
                                  Text(
                                    _media.isEmpty
                                        ? 'No ${_title.toLowerCase()} found. Check internal storage and granted USB/OTG folders, then scan again.'
                                        : 'No matching files. Try another search or storage source.',
                                    textAlign: TextAlign.center,
                                  ),
                                  const SizedBox(height: 12),
                                  if (!_loading)
                                    OutlinedButton.icon(
                                      onPressed: _scan,
                                      icon: const Icon(Icons.refresh),
                                      label: const Text('Scan again'),
                                    ),
                                ],
                              ),
                            ),
                          )
                        : isFolderView
                            ? _buildFolders(visibleMedia)
                            : !_isMusic && _layoutMode == 'grid'
                                ? _buildVideoGrid(visibleMedia)
                                : !_isMusic
                                    ? _buildVideoList(visibleMedia)
                                    : ListView.builder(
                                        controller: _contentScrollController,
                                        padding: EdgeInsets.fromLTRB(12, 8, 12, 104 + MediaQuery.paddingOf(context).bottom),
                                        itemCount: visibleMedia.length,
                                        itemBuilder: (context, index) {
                                          final media = visibleMedia[index];
                                          return ListTile(
                                            leading: CircleAvatar(
                                              child: Icon(_isMusic
                                                  ? Icons.music_note_rounded
                                                  : Icons.movie_outlined),
                                            ),
                                            title: Text(
                                              _isMusic ? _displayTitle(media) : media.entry.name,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                            subtitle: Text(
                                              '${_isMusic ? '${_fileExtension(media)} · ' : ''}${_sourceLabel(media)} · ${_formatBytes(media.entry.size)}',
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                            trailing: const Icon(Icons.play_arrow_rounded),
                                            onTap: () => _openMedia(media, visibleMedia),
                                          );
                                        },
                                      ),
          ),
        ],
      ),
      ),
    );
  }
}

class _VideoTag extends StatelessWidget {
  const _VideoTag({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) => DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.68),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
          child: Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 10,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      );
}

class MediaBrowserScreen extends StatefulWidget {
  const MediaBrowserScreen({
    required this.api,
    required this.type,
    this.showSearch = true,
    this.onHome,
    super.key,
  });

  final ServerApi api;
  final MediaLibraryType type;
  final bool showSearch;
  final VoidCallback? onHome;

  @override
  State<MediaBrowserScreen> createState() => _MediaBrowserScreenState();
}
