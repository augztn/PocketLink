import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import '../../core/network/server_api.dart';
import 'media_player_screen.dart';

enum MediaLibraryType { music, video }

class _MediaFile {
  const _MediaFile({required this.entry, required this.path, this.volume});

  final FileEntry entry;
  final String path;
  final String? volume;
}

class _MediaBrowserScreenState extends State<MediaBrowserScreen> {
  static const _audioExtensions = {
    'mp3', 'm4a', 'aac', 'wav', 'flac', 'ogg', 'opus',
    'wma', 'aiff', 'alac',
  };
  static const _videoExtensions = {
    'mp4', 'm4v', 'mov', 'mkv', 'webm', 'avi', 'wmv',
    'mpeg', 'mpg', '3gp', 'ts',
  };
  static const _maxDirectories = 2000;
  static const _maxDepth = 20;

  List<_MediaFile> _media = const [];
  bool _loading = true;
  String? _error;
  int _scannedDirectories = 0;
  int _skippedDirectories = 0;

  bool get _isMusic => widget.type == MediaLibraryType.music;
  String get _title => _isMusic ? 'Music' : 'Videos';
  List<String> get _roots =>
      _isMusic ? const ['Music'] : const ['Movies', 'Videos'];

  @override
  void initState() {
    super.initState();
    _scan();
  }

  bool _isMedia(FileEntry item) {
    final extension = item.name.contains('.')
        ? item.name.split('.').last.toLowerCase()
        : '';
    return (_isMusic ? _audioExtensions : _videoExtensions)
        .contains(extension);
  }

  Future<void> _scan() async {
    setState(() {
      _loading = true;
      _error = null;
      _media = const [];
      _scannedDirectories = 0;
      _skippedDirectories = 0;
    });

    final found = <_MediaFile>[];
    final visited = <String>{};
    final pending = <({String path, int depth, String? volume})>[
      for (final root in _roots) (path: root, depth: 0, volume: null),
    ];

    try {
      try {
        final volumes = await widget.api.listStorageVolumes();
        for (final volume in volumes.where((item) => item.available)) {
          pending.add((path: '', depth: 0, volume: volume.id));
        }
      } on DioException {
        // Keep internal media available when the USB bridge is offline.
        _skippedDirectories++;
      }

      while (pending.isNotEmpty && visited.length < _maxDirectories) {
        final current = pending.removeLast();
        final visitKey = '${current.volume ?? 'internal'}:${current.path}';
        if (!visited.add(visitKey)) continue;

        DirectoryListing listing;
        try {
          listing = current.volume == null
              ? await widget.api.listDirectory(current.path)
              : await widget.api.listStorageDirectory(current.volume!, current.path);
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
              pending.add((path: itemPath, depth: current.depth + 1, volume: current.volume));
            } else {
              _skippedDirectories++;
            }
          } else if (_isMedia(item)) {
            found.add(_MediaFile(entry: item, path: itemPath, volume: current.volume));
          }
        }

        if (mounted) {
          setState(() {
            _media = List.unmodifiable(found);
          });
        }
      }

      if (pending.isNotEmpty) _skippedDirectories++;
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
      }
    }
  }

  Future<void> _openMedia(_MediaFile media) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => MediaPlayerScreen(
          api: widget.api,
          title: media.entry.name,
          path: media.path,
          volume: media.volume,
          isVideo: !_isMusic,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_title),
        actions: [
          IconButton(
            tooltip: 'Scan again',
            onPressed: _loading ? null : _scan,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: Column(
        children: [
          ListTile(
            leading: Icon(_isMusic ? Icons.library_music : Icons.video_library),
            title: Text(_roots.join(' + ')),
            subtitle: Text(
              _loading
                  ? 'Scanning folders…'
                  : '$_scannedDirectories folders scanned'
                    '${_skippedDirectories > 0 ? ' · $_skippedDirectories skipped' : ''}',
            ),
          ),
          if (_loading) const LinearProgressIndicator(),
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
                    ? const Center(child: Text('Searching media folders…'))
                    : _media.isEmpty
                        ? Center(
                            child: Text(
                              'No ${_title.toLowerCase()} files found.\n'
                              'Add files to ${_roots.join(' or ')} and scan again.',
                              textAlign: TextAlign.center,
                            ),
                          )
                        : ListView.builder(
                            itemCount: _media.length,
                            itemBuilder: (context, index) {
                              final media = _media[index];
                              return ListTile(
                                leading: Icon(_isMusic
                                    ? Icons.audio_file
                                    : Icons.play_circle_outline),
                                title: Text(media.entry.name),
                                subtitle: Text(
                                  '${media.path} · '
                                  '${(media.entry.size / (1024 * 1024)).toStringAsFixed(1)} MB',
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                trailing: const Icon(Icons.play_arrow),
                                onTap: () => _openMedia(media),
                              );
                            },
                          ),
          ),
        ],
      ),
    );
  }
}

class MediaBrowserScreen extends StatefulWidget {
  const MediaBrowserScreen({
    required this.api,
    required this.type,
    super.key,
  });

  final ServerApi api;
  final MediaLibraryType type;

  @override
  State<MediaBrowserScreen> createState() => _MediaBrowserScreenState();
}
