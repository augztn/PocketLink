import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import '../../core/network/server_api.dart';
import 'media_player_screen.dart';
import 'persistent_audio_player.dart';

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
  String _libraryView = 'all';
  String _layoutMode = 'grid';
  String _sortBy = 'name';

  bool get _isMusic => widget.type == MediaLibraryType.music;
  String get _title => _isMusic ? 'Music' : 'Videos';
  List<String> get _roots => _isMusic ? const ['Music'] : const [''];

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
        _skippedDirectories++;
      }

      pending.addAll(
        _roots.map((root) => (path: root, depth: 0, volume: null)),
      );

      var cursor = 0;
      while (cursor < pending.length && visited.length < _maxDirectories) {
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
      }
    }
  }

  Future<void> _openMedia(_MediaFile media, List<_MediaFile> queueItems) async {
    final queue = queueItems
        .map((item) => MediaQueueItem(
              title: item.entry.name,
              path: item.path,
              volume: item.volume,
            ))
        .toList(growable: false);
    final index = queueItems.indexWhere(
      (item) => item.path == media.path && item.volume == media.volume,
    );
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => MediaPlayerScreen(
          api: widget.api,
          title: media.entry.name,
          path: media.path,
          volume: media.volume,
          isVideo: !_isMusic,
          queue: queue,
          initialIndex: index < 0 ? 0 : index,
        ),
      ),
    );
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

  Map<String, List<_MediaFile>> _groupByFolder(List<_MediaFile> items) {
    final groups = <String, List<_MediaFile>>{};
    for (final media in items) {
      final folder = media.path.contains('/')
          ? media.path.substring(0, media.path.lastIndexOf('/'))
          : _sourceLabel(media);
      final key = '${media.volume ?? 'internal'}::${folder}';
      groups.putIfAbsent(key, () => <_MediaFile>[]).add(media);
    }
    return groups;
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

  Widget _buildVideoGrid(List<_MediaFile> items) {
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
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
                      DecoratedBox(
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
                        child: Icon(
                          Icons.movie_creation_outlined,
                          size: 54,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
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
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      const SizedBox(height: 3),
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
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
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
              child: const Icon(Icons.movie_outlined, size: 30),
            ),
            title: Text(
              media.entry.name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Text(
              '$extension · ${_formatBytes(media.entry.size)} · ${_sourceLabel(media)}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            trailing: const Icon(Icons.play_circle_outline_rounded),
            onTap: () => _openMedia(media, items),
          ),
        );
      },
    );
  }

  Widget _buildFolders(Map<String, List<_MediaFile>> folders) {
    final entries = folders.entries.toList()
      ..sort((a, b) => a.key.toLowerCase().compareTo(b.key.toLowerCase()));
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
      itemCount: entries.length,
      itemBuilder: (context, index) {
        final entry = entries[index];
        final items = entry.value;
        final first = items.first;
        final folderName = entry.key.split('::').last;
        final bytes = items.fold<int>(0, (sum, item) => sum + item.entry.size);
        return Card(
          clipBehavior: Clip.antiAlias,
          child: ExpansionTile(
            leading: const Icon(Icons.folder_rounded),
            title: Text(
              folderName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Text(
              '${items.length} ${_isMusic ? 'tracks' : 'videos'} · ${_formatBytes(bytes)} · ${_sourceLabel(first)}',
            ),
            children: items.map((media) => ListTile(
              contentPadding: const EdgeInsets.only(left: 28, right: 16),
              leading: Icon(_isMusic ? Icons.audio_file_outlined : Icons.movie_outlined),
              title: Text(
                media.entry.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Text(_formatBytes(media.entry.size)),
              trailing: const Icon(Icons.play_arrow_rounded),
              onTap: () => _openMedia(media, items),
            )).toList(growable: false),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final query = _searchQuery.trim().toLowerCase();
    final filtered = _media.where((media) {
      final matchesQuery = query.isEmpty ||
          media.entry.name.toLowerCase().contains(query) ||
          media.path.toLowerCase().contains(query);
      final matchesVolume = _selectedVolume == null ||
          media.volume == _selectedVolume;
      return matchesQuery && matchesVolume;
    }).toList(growable: false);
    final visibleMedia = _sortMedia(filtered);
    final folders = _groupByFolder(visibleMedia);
    final isFolderView = _libraryView == 'folders';

    return Scaffold(
      appBar: AppBar(
        title: Text(_title),
        actions: [
          if (!_isMusic)
            IconButton(
              tooltip: _layoutMode == 'grid' ? 'List view' : 'Grid view',
              onPressed: () => setState(() {
                _layoutMode = _layoutMode == 'grid' ? 'list' : 'grid';
              }),
              icon: Icon(_layoutMode == 'grid'
                  ? Icons.view_list_rounded
                  : Icons.grid_view_rounded),
            ),
          IconButton(
            tooltip: 'Scan again',
            onPressed: _loading ? null : _scan,
            icon: const Icon(Icons.refresh),
          ),
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
                        '${_media.length} ${_isMusic ? 'tracks' : 'videos'}',
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
                if (_loading)
                  const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: SegmentedButton<String>(
              segments: [
                ButtonSegment(
                  value: 'all',
                  label: Text(_isMusic ? 'Songs' : 'All videos'),
                  icon: Icon(_isMusic ? Icons.music_note : Icons.movie_outlined),
                ),
                const ButtonSegment(
                  value: 'folders',
                  label: Text('Folders'),
                  icon: Icon(Icons.folder_outlined),
                ),
              ],
              selected: {_libraryView},
              onSelectionChanged: (selection) =>
                  setState(() => _libraryView = selection.first),
              showSelectedIcon: false,
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: TextField(
              onChanged: (value) => setState(() => _searchQuery = value),
              decoration: InputDecoration(
                hintText: _isMusic ? 'Search songs or folders' : 'Search videos or folders',
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
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: _selectedVolume ?? 'all',
                    decoration: const InputDecoration(
                      labelText: 'Storage source',
                      prefixIcon: Icon(Icons.storage_outlined),
                      isDense: true,
                    ),
                    items: [
                      const DropdownMenuItem(
                        value: 'all',
                        child: Text('All storage'),
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
                const SizedBox(width: 10),
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: _sortBy,
                    decoration: const InputDecoration(
                      labelText: 'Sort by',
                      prefixIcon: Icon(Icons.sort_rounded),
                      isDense: true,
                    ),
                    items: const [
                      DropdownMenuItem(value: 'name', child: Text('Name')),
                      DropdownMenuItem(value: 'newest', child: Text('Newest')),
                      DropdownMenuItem(value: 'largest', child: Text('Largest')),
                    ],
                    onChanged: (value) =>
                        setState(() => _sortBy = value ?? 'name'),
                  ),
                ),
              ],
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
                    ? const Center(child: Text('Searching media folders…'))
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
                            ? _buildFolders(folders)
                            : !_isMusic && _layoutMode == 'grid'
                                ? _buildVideoGrid(visibleMedia)
                                : !_isMusic
                                    ? _buildVideoList(visibleMedia)
                                    : ListView.builder(
                                        padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
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
                                              media.entry.name,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                            subtitle: Text(
                                              '${_sourceLabel(media)} · ${media.path} · ${_formatBytes(media.entry.size)}',
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                            trailing: const Icon(Icons.play_arrow_rounded),
                                            onTap: () => _openMedia(media, visibleMedia),
                                          );
                                        },
                                      )
                                    : _buildVideoList(visibleMedia),
          ),
        ],
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
    super.key,
  });

  final ServerApi api;
  final MediaLibraryType type;

  @override
  State<MediaBrowserScreen> createState() => _MediaBrowserScreenState();
}
