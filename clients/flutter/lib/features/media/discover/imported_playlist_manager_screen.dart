import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart' as file_picker;
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/network/server_api.dart';

import '../playlist_import_service.dart';

class ImportedPlaylistStore {
  static const folderPath = 'PocketLink/Discover/Playlists';
  static const filePath = '$folderPath/playlists.json';
  static const _legacyLocalKey = 'pocketlink.discover.imported_playlists.v1';
  static const _folderSegments = ['PocketLink', 'Discover', 'Playlists'];

  static Future<void> ensureFolder(ServerApi api) async {
    var parent = '';
    for (final segment in _folderSegments) {
      final listing = await api.listDirectory(parent);
      if (!listing.items.any((item) => item.isDirectory && item.name == segment)) {
        await api.createFolder(parent, segment);
      }
      parent = parent.isEmpty ? segment : '$parent/$segment';
    }
  }

  static Future<List<ImportedPlaylist>> load(ServerApi api) async {
    await ensureFolder(api);
    final listing = await api.listDirectory(folderPath);
    if (!listing.items.any((item) => !item.isDirectory && item.name == 'playlists.json')) {
      return const [];
    }
    final serverPlaylists = await _readServerFile(api, listing.items.any(
      (item) => !item.isDirectory && item.name == 'playlists.json',
    ));
    final prefs = await SharedPreferences.getInstance();
    final legacyRaw = prefs.getString(_legacyLocalKey);
    if (legacyRaw == null || legacyRaw.isEmpty) return serverPlaylists;

    // Migrate the old on-device collection only after the server write succeeds.
    try {
      final decoded = jsonDecode(legacyRaw);
      if (decoded is! List) return serverPlaylists;
      final localPlaylists = decoded
          .whereType<Map>()
          .map((item) => ImportedPlaylist.fromJson(
                item.map((key, value) => MapEntry(key.toString(), value)),
              ))
          .where((playlist) => playlist.name.trim().isNotEmpty && playlist.tracks.isNotEmpty)
          .toList(growable: false);
      if (localPlaylists.isEmpty) return serverPlaylists;
      final merged = _merge(serverPlaylists, localPlaylists);
      await _writeServerFile(api, merged);
      await prefs.remove(_legacyLocalKey);
      return merged;
    } on FormatException {
      return serverPlaylists;
    }
  }

  static Future<void> saveAll(ServerApi api, Iterable<ImportedPlaylist> playlists) async {
    final current = await load(api);
    final next = _merge(current, playlists);
    await _writeServerFile(api, next);
  }

  static Future<void> remove(ServerApi api, ImportedPlaylist playlist) async {
    final current = await load(api);
    final key = _identity(playlist);
    final next = current.where((item) => _identity(item) != key).toList(growable: false);
    await _writeServerFile(api, next);
  }

  static Future<List<ImportedPlaylist>> _readServerFile(ServerApi api, bool exists) async {
    if (!exists) return const [];
    final bytes = await api.downloadFile(filePath);
    final decoded = jsonDecode(utf8.decode(bytes, allowMalformed: false));
    if (decoded is! Map || decoded['format'] != 'pocketlink-discover-playlists' ||
        decoded['version'] != 1 || decoded['playlists'] is! List) {
      throw const FormatException('The server playlist library file is not a valid PocketLink backup.');
    }
    return (decoded['playlists'] as List)
        .whereType<Map>()
        .map((item) => ImportedPlaylist.fromJson(
              item.map((key, value) => MapEntry(key.toString(), value)),
            ))
        .where((playlist) => playlist.name.trim().isNotEmpty && playlist.tracks.isNotEmpty)
        .toList(growable: false);
  }

  static List<ImportedPlaylist> _merge(
    Iterable<ImportedPlaylist> existing,
    Iterable<ImportedPlaylist> incoming,
  ) {
    final byKey = <String, ImportedPlaylist>{};
    for (final playlist in existing) {
      byKey[_identity(playlist)] = playlist;
    }
    for (final playlist in incoming) {
      byKey[_identity(playlist)] = playlist;
    }
    if (byKey.length > 200) {
      throw StateError('PocketLink can store up to 200 imported playlists.');
    }
    return List.unmodifiable(byKey.values);
  }

  static Future<void> _writeServerFile(
    ServerApi api,
    List<ImportedPlaylist> playlists,
  ) async {
    final backup = jsonEncode({
      'format': 'pocketlink-discover-playlists',
      'version': 1,
      'playlists': playlists.map((item) => item.toJson()).toList(),
    });
    await api.uploadFile(
      folderPath,
      'playlists.json',
      Uint8List.fromList(utf8.encode(backup)),
    );
  }

  static String _identity(ImportedPlaylist playlist) =>
      '${playlist.provider ?? ''}|${playlist.sourceUrl ?? ''}|${playlist.name.toLowerCase()}';
}

class ImportedPlaylistManagerScreen extends StatefulWidget {
  const ImportedPlaylistManagerScreen({required this.api, this.onPlay, super.key});

  final ServerApi api;
  final ValueChanged<ImportedPlaylist>? onPlay;

  @override
  State<ImportedPlaylistManagerScreen> createState() => _ImportedPlaylistManagerScreenState();
}

class _ImportedPlaylistManagerScreenState extends State<ImportedPlaylistManagerScreen> {
  final PlaylistImportService _importer = PlaylistImportService();
  List<ImportedPlaylist> _playlists = const [];
  bool _loading = true;
  bool _working = false;
  String? _loadError;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    if (mounted) setState(() { _loading = true; _loadError = null; });
    try {
      final playlists = await ImportedPlaylistStore.load(widget.api);
      if (!mounted) return;
      setState(() {
        _playlists = playlists;
        _loading = false;
        _loadError = null;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadError = 'Could not read playlists from your PocketLink server.';
      });
    }
  }

  Future<void> _importFromUrl() async {
    final controller = TextEditingController();
    final url = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Import playlist link'),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: TextInputType.url,
          decoration: const InputDecoration(
            hintText: 'YouTube Music or Spotify playlist URL',
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, controller.text.trim()), child: const Text('Import')),
        ],
      ),
    );
    controller.dispose();
    if (url == null || url.isEmpty || _working) return;
    await _runImport(() async {
      final result = await _importer.importPublicUrl(url);
      await ImportedPlaylistStore.saveAll(widget.api, [ImportedPlaylist(
        name: result.name,
        tracks: result.tracks,
        provider: result.provider,
        sourceUrl: url,
      )]);
    });
  }

  Future<void> _importFile() async {
    if (_working) return;
    try {
      final file = await file_picker.FilePicker.pickFile(
        type: file_picker.FileType.custom,
        allowedExtensions: const ['csv', 'm3u', 'm3u8', 'json'],
      );
      if (file == null) return;
      final bytes = await file.readAsBytes();
      final text = utf8.decode(bytes, allowMalformed: false);
      final extension = file.extension?.toLowerCase() ?? '';
      final fallbackName = file.name.replaceFirst(RegExp(r'\.[^.]+$'), '');
      final playlists = switch (extension) {
        'm3u' || 'm3u8' => [
            PlaylistImportService.parseM3u(text, fallbackPlaylistName: fallbackName),
          ],
        'csv' => PlaylistImportService.parseCsvPlaylists(text, fallbackPlaylistName: fallbackName),
        'json' => _decodePocketLinkBackup(text),
        _ => throw const FormatException('Choose a CSV, M3U or PocketLink JSON playlist export.'),
      };
      await _runImport(() => ImportedPlaylistStore.saveAll(widget.api, playlists));
    } catch (error) {
      if (mounted) _message(error is FormatException ? error.message : 'Could not import this playlist file.');
    }
  }

  List<ImportedPlaylist> _decodePocketLinkBackup(String input) {
    final decoded = jsonDecode(input);
    if (decoded is! Map || decoded['format'] != 'pocketlink-discover-playlists' ||
        decoded['version'] != 1 || decoded['playlists'] is! List) {
      throw const FormatException('This is not a supported PocketLink Discover playlist backup.');
    }
    final playlists = (decoded['playlists'] as List)
        .whereType<Map>()
        .map((item) => ImportedPlaylist.fromJson(
              item.map((key, value) => MapEntry(key.toString(), value)),
            ))
        .where((playlist) => playlist.name.trim().isNotEmpty && playlist.tracks.isNotEmpty)
        .toList(growable: false);
    if (playlists.isEmpty) throw const FormatException('The backup contains no valid playlists.');
    return playlists;
  }

  Future<void> _runImport(Future<void> Function() action) async {
    setState(() => _working = true);
    try {
      await action();
      await _reload();
      if (mounted) _message('Playlist saved to your PocketLink server.');
    } catch (error) {
      if (mounted) _message(error is FormatException || error is StateError
          ? error.toString().replaceFirst('FormatException: ', '')
          : 'Playlist import failed. Check the link or file and try again.');
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _exportCsv() async {
    if (_playlists.isEmpty || _working) return;
    setState(() => _working = true);
    try {
      final rows = <({String playlist, ImportedTrack track})>[
        for (final playlist in _playlists)
          for (final track in playlist.tracks)
            (playlist: playlist.name, track: track),
      ];
      final csv = PlaylistImportService.exportCsv(rows);
      await widget.api.uploadFile(
        ImportedPlaylistStore.folderPath,
        'playlists-export.csv',
        Uint8List.fromList(utf8.encode(csv)),
      );
      final directory = await getTemporaryDirectory();
      final file = File('${directory.path}/pocketlink-discover-playlists.csv');
      await file.writeAsString(csv, flush: true);
      await SharePlus.instance.share(ShareParams(
        files: [XFile(file.path, mimeType: 'text/csv')],
        subject: 'PocketLink Discover playlists',
      ));
    } catch (_) {
      if (mounted) _message('Could not save or export playlists from your server.');
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _exportJson() async {
    if (_playlists.isEmpty || _working) return;
    setState(() => _working = true);
    try {
      final backup = jsonEncode({
        'format': 'pocketlink-discover-playlists',
        'version': 1,
        'playlists': _playlists.map((playlist) => playlist.toJson()).toList(),
      });
      await widget.api.uploadFile(
        ImportedPlaylistStore.folderPath,
        'playlists-backup.json',
        Uint8List.fromList(utf8.encode(backup)),
      );
      final directory = await getTemporaryDirectory();
      final file = File('${directory.path}/pocketlink-discover-playlists.json');
      await file.writeAsString(backup, flush: true);
      await SharePlus.instance.share(ShareParams(
        files: [XFile(file.path, mimeType: 'application/json')],
        subject: 'PocketLink Discover playlist backup',
      ));
    } catch (_) {
      if (mounted) _message('Could not save or export the PocketLink playlist backup.');
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _delete(ImportedPlaylist playlist) async {
    try {
      await ImportedPlaylistStore.remove(widget.api, playlist);
      await _reload();
    } catch (_) {
      if (mounted) _message('Could not remove this playlist from your server.');
    }
  }

  void _message(String value) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(value)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Imported playlists'),
        actions: [
          PopupMenuButton<String>(
            tooltip: 'Export playlists',
            enabled: !_working && _playlists.isNotEmpty,
            onSelected: (value) {
              if (value == 'csv') _exportCsv();
              if (value == 'json') _exportJson();
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'csv', child: Text('Export CSV')),
              PopupMenuItem(value: 'json', child: Text('Export PocketLink backup')),
            ],
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          Row(children: [
            Expanded(child: OutlinedButton.icon(
              onPressed: _working ? null : _importFromUrl,
              icon: const Icon(Icons.link_rounded),
              label: const Text('Import link'),
            )),
            const SizedBox(width: 10),
            Expanded(child: FilledButton.icon(
              onPressed: _working ? null : _importFile,
              icon: const Icon(Icons.file_open_rounded),
              label: const Text('Import file'),
            )),
          ]),
          const SizedBox(height: 8),
          const Text(
            'Supports public YouTube / YouTube Music and Spotify playlist links, plus CSV and M3U exports from other music services.',
            style: TextStyle(color: Colors.grey, fontSize: 12),
          ),
          const SizedBox(height: 8),
          const Row(children: [
            Icon(Icons.cloud_done_rounded, size: 14, color: Colors.grey),
            SizedBox(width: 6),
            Expanded(
              child: Text(
                'Saved on server: /sdcard/PocketLink/Discover/Playlists',
                style: TextStyle(color: Colors.grey, fontSize: 11),
              ),
            ),
          ]),
          if (_working) const Padding(
            padding: EdgeInsets.only(top: 18),
            child: LinearProgressIndicator(),
          ),
          const SizedBox(height: 18),
          if (_loading)
            const Center(child: CircularProgressIndicator())
          else if (_loadError != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 42),
              child: Column(children: [
                const Icon(Icons.cloud_off_rounded, size: 40, color: Colors.grey),
                const SizedBox(height: 10),
                Text(_loadError!, textAlign: TextAlign.center),
                TextButton(onPressed: _reload, child: const Text('Retry')),
              ]),
            )
          else if (_playlists.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 42),
              child: Column(children: [
                Icon(Icons.queue_music_rounded, size: 42, color: Colors.grey),
                SizedBox(height: 12),
                Text('No imported playlists yet'),
                SizedBox(height: 5),
                Text('Import a playlist to keep it in Discover Library.', style: TextStyle(color: Colors.grey, fontSize: 12)),
              ]),
            )
          else ...[
            Text('${_playlists.length} PLAYLIST${_playlists.length == 1 ? '' : 'S'}',
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1.1, color: Colors.grey)),
            const SizedBox(height: 8),
            for (final playlist in _playlists)
              Card(
                child: ListTile(
                  leading: const CircleAvatar(child: Icon(Icons.queue_music_rounded)),
                  title: Text(playlist.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle: Text('${playlist.tracks.length} tracks${playlist.provider == null ? '' : ' · ${playlist.provider}'}'),
                  onTap: widget.onPlay == null ? null : () => widget.onPlay!(playlist),
                  trailing: PopupMenuButton<String>(
                    onSelected: (value) {
                      if (value == 'play' && widget.onPlay != null) widget.onPlay!(playlist);
                      if (value == 'delete') _delete(playlist);
                    },
                    itemBuilder: (_) => [
                      if (widget.onPlay != null) const PopupMenuItem(value: 'play', child: Text('Play playlist')),
                      const PopupMenuItem(value: 'delete', child: Text('Remove playlist')),
                    ],
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }
}
