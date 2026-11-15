import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import '../../core/network/server_api.dart';
import 'media_player_screen.dart';
import 'now_playing_screen.dart';
import 'persistent_audio_player.dart';
import '../transfers/transfer_manager_screen.dart';

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
              size: item.entry.size,
            ))
        .toList(growable: false);
    final index = queueItems.indexWhere(
      (item) => item.path == media.path && item.volume == media.volume,
    );
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
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
                        maxLines: 2,
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

  Widget _buildFolders(Map<String, List<_MediaFile>> folders) {
    final entries = folders.entries.toList()
      ..sort((a, b) => a.key.toLowerCase().compareTo(b.key.toLowerCase()));
    return ListView.builder(
      padding: EdgeInsets.fromLTRB(12, 8, 12, 104 + MediaQuery.paddingOf(context).bottom),
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

  Widget _viewPill({
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) => Material(
    color: selected ? const Color(0xFF343438) : Colors.transparent,
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
              color: selected ? Colors.white : Colors.white60,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            )),
          ),
        ),
      ),
    ),
  );

  Widget _menuPill({
    required String label,
    required List<PopupMenuEntry<String>> items,
    required ValueChanged<String> onSelected,
  }) => PopupMenuButton<String>(
    onSelected: onSelected,
    itemBuilder: (_) => items,
    child: Container(
      height: 36,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF1C1C1E),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Text(label, style: const TextStyle(
          color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600,
        )),
        const SizedBox(width: 4),
        const Icon(Icons.keyboard_arrow_down_rounded, size: 17, color: Colors.white70),
      ]),
    ),
  );

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
    final selectedVolumes = _volumes.where((volume) => volume.id == _selectedVolume).toList();
    final sourceLabel = selectedVolumes.isEmpty ? 'All Storage' : selectedVolumes.first.name;

    return Scaffold(
      appBar: AppBar(
        title: Text(_title),
        actions: [
          IconButton(
            tooltip: 'Transfers',
            onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const TransferManagerScreen())),
            icon: const Icon(Icons.swap_vert_rounded),
          ),
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
              ],
            ),
          ),
          if (widget.showSearch) Padding(
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
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  Container(
                    height: 36,
                    padding: const EdgeInsets.all(3),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1C1C1E),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _viewPill(
                          label: _isMusic ? 'Songs' : 'Videos',
                          selected: _libraryView == 'all',
                          onTap: () => setState(() => _libraryView = 'all'),
                        ),
                        _viewPill(
                          label: 'Folders',
                          selected: isFolderView,
                          onTap: () => setState(() => _libraryView = 'folders'),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  _menuPill(
                    label: sourceLabel,
                    items: [
                      const PopupMenuItem(value: 'all', child: Text('All Storage')),
                      ..._volumes.map((volume) => PopupMenuItem(
                        value: volume.id,
                        enabled: volume.available,
                        child: Text(
                          '${volume.name}${volume.available ? '' : ' · unavailable'}',
                          overflow: TextOverflow.ellipsis,
                        ),
                      )),
                    ],
                    onSelected: (value) => setState(() {
                      _selectedVolume = value == 'all' ? null : value;
                    }),
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
                    onSelected: (value) => setState(() => _sortBy = value),
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
                            ? _buildFolders(folders)
                            : !_isMusic && _layoutMode == 'grid'
                                ? _buildVideoGrid(visibleMedia)
                                : !_isMusic
                                    ? _buildVideoList(visibleMedia)
                                    : ListView.builder(
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
                                      ),
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
          color: Colors.black.withOpacity(0.68),
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
    super.key,
  });

  final ServerApi api;
  final MediaLibraryType type;
  final bool showSearch;

  @override
  State<MediaBrowserScreen> createState() => _MediaBrowserScreenState();
}
