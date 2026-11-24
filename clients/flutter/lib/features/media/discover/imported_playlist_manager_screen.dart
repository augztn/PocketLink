import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart' as file_picker;
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'playlist_import_service.dart';

class ImportedPlaylistStore {
  static const _key = 'pocketlink.discover.imported_playlists.v1';

  static Future<List<ImportedPlaylist>> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return decoded
          .whereType<Map>()
          .map((item) => ImportedPlaylist.fromJson(
                item.map((key, value) => MapEntry(key.toString(), value)),
              ))
          .where((playlist) => playlist.name.trim().isNotEmpty && playlist.tracks.isNotEmpty)
          .toList(growable: false);
    } on FormatException {
      return const [];
    }
  }

  static Future<void> save(ImportedPlaylist playlist) async {
    final current = await load();
    final key = _identity(playlist);
    final next = [
      playlist,
      ...current.where((item) => _identity(item) != key),
    ];
    if (next.length > 200) {
      throw StateError('PocketLink can store up to 200 imported playlists.');
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(next.map((item) => item.toJson()).toList()));
  }

  static Future<void> remove(ImportedPlaylist playlist) async {
    final current = await load();
    final key = _identity(playlist);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _key,
      jsonEncode(current.where((item) => _identity(item) != key).map((item) => item.toJson()).toList()),
    );
  }

  static String _identity(ImportedPlaylist playlist) =>
      '${playlist.provider ?? ''}|${playlist.sourceUrl ?? ''}|${playlist.name.toLowerCase()}';
}

class ImportedPlaylistManagerScreen extends StatefulWidget {
  const ImportedPlaylistManagerScreen({this.onPlay, super.key});

  final ValueChanged<ImportedPlaylist>? onPlay;

  @override
  State<ImportedPlaylistManagerScreen> createState() => _ImportedPlaylistManagerScreenState();
}

class _ImportedPlaylistManagerScreenState extends State<ImportedPlaylistManagerScreen> {
  final PlaylistImportService _importer = PlaylistImportService();
  List<ImportedPlaylist> _playlists = const [];
  bool _loading = true;
  bool _working = false;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final playlists = await ImportedPlaylistStore.load();
    if (!mounted) return;
    setState(() {
      _playlists = playlists;
      _loading = false;
    });
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
      await ImportedPlaylistStore.save(ImportedPlaylist(
        name: result.name,
        tracks: result.tracks,
        provider: result.provider,
        sourceUrl: url,
      ));
    });
  }

  Future<void> _importFile() async {
    if (_working) return;
    try {
      final result = await file_picker.FilePicker.pickFiles(
        type: file_picker.FileType.custom,
        allowedExtensions: const ['csv', 'm3u', 'm3u8'],
        withData: true,
      );
      if (result == null || result.files.isEmpty) return;
      final file = result.files.single;
      final bytes = file.bytes;
      if (bytes == null) throw const FormatException('Could not read the selected playlist file.');
      final text = utf8.decode(bytes, allowMalformed: false);
      final extension = file.extension?.toLowerCase() ?? '';
      final fallbackName = file.name.replaceFirst(RegExp(r'\.[^.]+$'), '');
      final playlists = switch (extension) {
        'm3u' || 'm3u8' => [
            PlaylistImportService.parseM3u(text, fallbackPlaylistName: fallbackName),
          ],
        'csv' => PlaylistImportService.parseCsvPlaylists(text, fallbackPlaylistName: fallbackName),
        _ => throw const FormatException('Choose a CSV or M3U playlist export.'),
      };
      await _runImport(() async {
        for (final playlist in playlists) {
          await ImportedPlaylistStore.save(playlist);
        }
      });
    } catch (error) {
      if (mounted) _message(error is FormatException ? error.message : 'Could not import this playlist file.');
    }
  }

  Future<void> _runImport(Future<void> Function() action) async {
    setState(() => _working = true);
    try {
      await action();
      await _reload();
      if (mounted) _message('Playlist imported into Discover Library.');
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
      final directory = await getTemporaryDirectory();
      final file = File('${directory.path}/pocketlink-discover-playlists.csv');
      await file.writeAsString(csv, flush: true);
      await SharePlus.instance.share(ShareParams(
        files: [XFile(file.path, mimeType: 'text/csv')],
        subject: 'PocketLink Discover playlists',
      ));
    } catch (_) {
      if (mounted) _message('Could not export playlists.');
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _delete(ImportedPlaylist playlist) async {
    await ImportedPlaylistStore.remove(playlist);
    await _reload();
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
          IconButton(
            tooltip: 'Export playlists as CSV',
            onPressed: _working || _playlists.isEmpty ? null : _exportCsv,
            icon: const Icon(Icons.ios_share_rounded),
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
          if (_working) const Padding(
            padding: EdgeInsets.only(top: 18),
            child: LinearProgressIndicator(),
          ),
          const SizedBox(height: 18),
          if (_loading)
            const Center(child: CircularProgressIndicator())
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
), '');
      final playlists = switch (extension) {
        'm3u' || 'm3u8' => [
            PlaylistImportService.parseM3u(text, fallbackPlaylistName: fallbackName),
          ],
        'csv' => PlaylistImportService.parseCsvPlaylists(text, fallbackPlaylistName: fallbackName),
        _ => throw const FormatException('Choose a CSV or M3U playlist export.'),
      };
      await _runImport(() async {
        for (final playlist in playlists) {
          await ImportedPlaylistStore.save(playlist);
        }
      });
    } catch (error) {
      if (mounted) _message(error is FormatException ? error.message : 'Could not import this playlist file.');
    }
  }

  Future<void> _runImport(Future<void> Function() action) async {
    setState(() => _working = true);
    try {
      await action();
      await _reload();
      if (mounted) _message('Playlist imported into Discover Library.');
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
      final directory = await getTemporaryDirectory();
      final file = File('${directory.path}/pocketlink-discover-playlists.csv');
      await file.writeAsString(csv, flush: true);
      await SharePlus.instance.share(ShareParams(
        files: [XFile(file.path, mimeType: 'text/csv')],
        subject: 'PocketLink Discover playlists',
      ));
    } catch (_) {
      if (mounted) _message('Could not export playlists.');
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _delete(ImportedPlaylist playlist) async {
    await ImportedPlaylistStore.remove(playlist);
    await _reload();
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
          IconButton(
            tooltip: 'Export playlists as CSV',
            onPressed: _working || _playlists.isEmpty ? null : _exportCsv,
            icon: const Icon(Icons.ios_share_rounded),
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
          if (_working) const Padding(
            padding: EdgeInsets.only(top: 18),
            child: LinearProgressIndicator(),
          ),
          const SizedBox(height: 18),
          if (_loading)
            const Center(child: CircularProgressIndicator())
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
