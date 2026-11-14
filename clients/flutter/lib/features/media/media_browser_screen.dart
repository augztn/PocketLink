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
  // Breadth-first traversal ensures every storage source is visited before
  // deeply nested folders on one large USB volume consume the scan budget.
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
  String _libraryView = 'songs';

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
    final pending = <({String path, int depth, String? volume})>[];

    try {
      try {
        final volumes = await widget.api.listStorageVolumes();
        _volumes = volumes;
        for (final volume in volumes.where((item) => item.available)) {
          pending.add((path: '', depth: 0, volume: volume.id));
        }
      } on DioException {
        // Keep internal media available when the USB bridge is offline.
        _skippedDirectories++;
      }

      // Always include internal storage, even when the USB bridge is offline.
      pending.addAll(
        _roots.map((root) => (path: root, depth: 0, volume: null)),
      );

      // Use a queue (cursor) rather than a stack: depth-first traversal can
      // spend the entire scan budget inside one USB folder tree and never
      // inspect the other OTG volume or internal Music directory.
      var cursor = 0;
      while (cursor < pending.length && visited.length < _maxDirectories) {
        final current = pending[cursor++];
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

  Future<void> _openMedia(_MediaFile media, List<_MediaFile> queueItems) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => MediaPlayerScreen(
          api: widget.api,
          title: media.entry.name,
          path: media.path,
          volume: media.volume,
          isVideo: !_isMusic,
          queue: _isMusic
              ? queueItems.map((item) => MediaQueueItem(
                    title: item.entry.name,
                    path: item.path,
                    volume: item.volume,
                  )).toList(growable: false)
              : const [],
          initialIndex: _isMusic
              ? queueItems.indexWhere((item) =>
                  item.path == media.path && item.volume == media.volume)
              : 0,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final query = _searchQuery.trim().toLowerCase();
    final visibleMedia = _media.where((media) {
      final matchesQuery = query.isEmpty ||
          media.entry.name.toLowerCase().contains(query) ||
          media.path.toLowerCase().contains(query);
      final matchesVolume = _selectedVolume == null ||
          media.volume == _selectedVolume;
      return matchesQuery && matchesVolume;
    }).toList(growable: false);
    final folders = <String, List<_MediaFile>>{};
    for (final media in visibleMedia) {
      final folder = media.path.contains('/')
          ? media.path.substring(0, media.path.lastIndexOf('/'))
          : (media.volume == null ? 'Internal storage' : 'USB storage');
      folders.putIfAbsent(folder, () => <_MediaFile>[]).add(media);
    }

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
          if (_isMusic) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'songs', label: Text('Songs'), icon: Icon(Icons.music_note)),
                  ButtonSegment(value: 'folders', label: Text('Folders'), icon: Icon(Icons.folder_outlined)),
                ],
                selected: {_libraryView},
                onSelectionChanged: (selection) => setState(() => _libraryView = selection.first),
                showSelectedIcon: false,
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: TextField(
                onChanged: (value) => setState(() => _searchQuery = value),
                decoration: InputDecoration(
                  hintText: 'Search songs or folders',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: _searchQuery.isEmpty
                      ? null
                      : IconButton(
                          tooltip: 'Clear search',
                          onPressed: () => setState(() => _searchQuery = ''),
                          icon: const Icon(Icons.close),
                        ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  isDense: true,
                ),
              ),
            ),
            if (_volumes.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: DropdownButtonFormField<String>(
                  initialValue: _selectedVolume ?? 'all',
                  decoration: const InputDecoration(
                    labelText: 'Music source',
                    prefixIcon: Icon(Icons.storage_outlined),
                    isDense: true,
                  ),
                  items: [
                    const DropdownMenuItem(
                      value: 'all',
                      child: Text('All storage locations'),
                    ),
                    ..._volumes.map((volume) => DropdownMenuItem(
                      value: volume.id,
                      enabled: volume.available,
                      child: Text(
                        '${volume.name}${volume.available ? '' : ' · unavailable'}',
                        overflow: TextOverflow.ellipsis,
                      ),
                    )),
                  ],
                  onChanged: (value) => setState(() {
                    _selectedVolume = value == null || value == 'all'
                        ? null
                        : value;
                  }),
                ),
              ),
          ],
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
                    : visibleMedia.isEmpty
                        ? Center(
                            child: Text(
                              _media.isEmpty
                                  ? 'No ${_title.toLowerCase()} files found.\\nCheck internal storage and granted USB/OTG folders, then scan again.'
                                  : 'No matching files. Try another search or storage location.',
                              textAlign: TextAlign.center,
                            ),
                          )
                        : _isMusic && _libraryView == 'folders'
                            ? ListView(
                                children: folders.entries.map((entry) {
                                  final totalBytes = entry.value.fold<int>(
                                    0, (sum, media) => sum + media.entry.size,
                                  );
                                  return ExpansionTile(
                                    leading: const Icon(Icons.folder_rounded),
                                    title: Text(entry.key, maxLines: 1, overflow: TextOverflow.ellipsis),
                                    subtitle: Text('${entry.value.length} tracks · ${(totalBytes / (1024 * 1024)).toStringAsFixed(1)} MB'),
                                    children: entry.value.map((media) => ListTile(
                                      contentPadding: const EdgeInsets.only(left: 32, right: 16),
                                      leading: const Icon(Icons.audio_file_outlined),
                                      title: Text(media.entry.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                                      trailing: const Icon(Icons.play_arrow_rounded),
                                      onTap: () => _openMedia(media, entry.value),
                                    )).toList(growable: false),
                                  );
                                }).toList(growable: false),
                              )
                            : ListView.builder(
                                itemCount: visibleMedia.length,
                                itemBuilder: (context, index) {
                                  final media = visibleMedia[index];
                                  return ListTile(
                                    leading: const CircleAvatar(child: Icon(Icons.music_note_rounded)),
                                    title: Text(media.entry.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                                    subtitle: Text(
                                      '${media.volume == null ? 'Internal storage' : 'USB'} · ${media.path}',
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
