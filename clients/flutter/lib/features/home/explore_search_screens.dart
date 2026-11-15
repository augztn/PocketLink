import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import '../../core/network/server_api.dart';
import '../files/file_manager_screen.dart';
import '../library/photo_gallery_screen.dart';
import '../media/media_browser_screen.dart';
import '../media/media_player_screen.dart';
import '../media/persistent_audio_player.dart';
import '../storage/storage_browser_screen.dart';
import '../transfers/transfer_manager_screen.dart';

enum ExploreCategory { files, drives, photos, music, videos }

class ExploreScreen extends StatelessWidget {
  const ExploreScreen({
    required this.api,
    required this.category,
    required this.onCategoryChanged,
    this.fileCategory = 'All',
    this.onBackAtRoot,
    super.key,
  });

  final ServerApi api;
  final ExploreCategory category;
  final ValueChanged<ExploreCategory> onCategoryChanged;
  final String fileCategory;
  final VoidCallback? onBackAtRoot;

  void _open(BuildContext context, String title, Widget screen) {
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => screen,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    Widget card({
      required String title,
      required String subtitle,
      required IconData icon,
      required Color tint,
      required VoidCallback onTap,
    }) {
      return Material(
        color: colors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(22),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Container(
            decoration: BoxDecoration(
              border: Border.all(color: colors.onSurface.withValues(alpha: 0.06)),
              borderRadius: BorderRadius.circular(22),
            ),
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: tint.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(15),
                  ),
                  child: Icon(icon, color: tint, size: 25),
                ),
                const Spacer(),
                Text(title, style: theme.textTheme.titleMedium?.copyWith(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.2,
                )),
                const SizedBox(height: 3),
                Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant)),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Explore')),
      body: GridView.count(
        padding: EdgeInsets.fromLTRB(16, 12, 16, 112 + MediaQuery.paddingOf(context).bottom),
        crossAxisCount: 2,
        crossAxisSpacing: 14,
        mainAxisSpacing: 14,
        childAspectRatio: 1.15,
        children: [
          card(
            title: 'Photos', subtitle: 'Your picture collection',
            icon: Icons.photo_library_rounded, tint: const Color(0xFFE5A044),
            onTap: () => _open(context, 'Photos', PhotoGalleryScreen(api: api)),
          ),
          card(
            title: 'Music', subtitle: 'Albums and playlists',
            icon: Icons.headphones_rounded, tint: const Color(0xFF8D72E8),
            onTap: () => _open(context, 'Music', MediaBrowserScreen(api: api, type: MediaLibraryType.music)),
          ),
          card(
            title: 'Videos', subtitle: 'Movies and clips',
            icon: Icons.play_circle_fill_rounded, tint: const Color(0xFF279D91),
            onTap: () => _open(context, 'Videos', MediaBrowserScreen(api: api, type: MediaLibraryType.video)),
          ),
          card(
            title: 'Documents', subtitle: 'PDF, Office and text',
            icon: Icons.description_rounded, tint: const Color(0xFF4C8ED9),
            onTap: () => _open(context, 'Documents', FileManagerScreen(api: api, initialCategory: 'Documents')),
          ),
          card(
            title: 'Files', subtitle: 'Browse server folders',
            icon: Icons.folder_rounded, tint: const Color(0xFF7186C8),
            onTap: () => _open(context, 'Files', FileManagerScreen(api: api)),
          ),
          card(
            title: 'Drives', subtitle: 'Internal & external SSDs',
            icon: Icons.usb_rounded, tint: const Color(0xFF28B8C8),
            onTap: () => _open(context, 'Drives', StorageBrowserScreen(api: api)),
          ),
        ],
      ),
    );
  }
}

class GlobalSearchScreen extends StatefulWidget {
  const GlobalSearchScreen({required this.api, super.key});

  final ServerApi api;

  @override
  State<GlobalSearchScreen> createState() => _GlobalSearchScreenState();
}

class _SearchResult {
  const _SearchResult({
    required this.file,
    required this.path,
    this.volume,
    required this.volumeName,
  });

  final FileEntry file;
  final String path;
  final String? volume;
  final String volumeName;
}

class _GlobalSearchScreenState extends State<GlobalSearchScreen> {
  static const _audio = {'mp3', 'm4a', 'aac', 'wav', 'flac', 'ogg', 'opus', 'wma', 'aiff', 'alac'};
  static const _video = {'mp4', 'm4v', 'mov', 'mkv', 'webm', 'avi', 'wmv', 'mpeg', 'mpg', '3gp', 'ts', 'm2ts', 'mts', 'flv', 'ogv'};
  static const _photo = {'jpg', 'jpeg', 'png', 'webp', 'gif', 'bmp', 'heic', 'heif', 'avif'};

  final _searchController = TextEditingController();
  final _focusNode = FocusNode();
  final List<_SearchResult> _results = [];
  String _filter = 'All';
  bool _loading = false;
  bool _searched = false;
  String? _error;
  int _scannedDirectories = 0;
  bool _scanInProgress = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  String _extension(String name) {
    final dot = name.lastIndexOf('.');
    return dot < 0 ? '' : name.substring(dot + 1).toLowerCase();
  }

  bool _matchesFilter(_SearchResult result) {
    final extension = _extension(result.file.name);
    return switch (_filter) {
      'All' => true,
      'Photos' => _photo.contains(extension),
      'Audio' => _audio.contains(extension),
      'Videos' => _video.contains(extension),
      'Files' => !_photo.contains(extension) && !_audio.contains(extension) && !_video.contains(extension),
      _ => true,
    };
  }

  List<_SearchResult> get _visibleResults {
    final query = _searchController.text.trim().toLowerCase();
    if (query.isEmpty) return const [];
    return _results.where((result) =>
      _matchesFilter(result) &&
      (result.file.name.toLowerCase().contains(query) ||
       result.path.toLowerCase().contains(query) ||
       result.volumeName.toLowerCase().contains(query))
    ).take(250).toList(growable: false);
  }

  Future<void> _search() async {
    final query = _searchController.text.trim();
    if (query.isEmpty || _scanInProgress) return;
    setState(() {
      _loading = true;
      _scanInProgress = true;
      _searched = true;
      _error = null;
      _results.clear();
      _scannedDirectories = 0;
    });

    final volumes = <StorageVolume>[];
    try {
      try {
        volumes.addAll((await widget.api.listStorageVolumes()).where((v) => v.available));
      } catch (_) {
        // Internal storage search remains available when the volume API is unavailable.
      }
      final pending = <({String path, String? volume, String volumeName, int depth})>[
        for (final root in const ['', 'DCIM', 'Pictures', 'Download', 'Documents', 'Music', 'Movies'])
          (path: root, volume: null, volumeName: 'Internal storage', depth: 0),
        for (final volume in volumes)
          (path: '', volume: volume.id, volumeName: volume.name, depth: 0),
      ];
      final visited = <String>{};
      final found = <_SearchResult>[];
      var cursor = 0;
      while (cursor < pending.length && visited.length < 1800) {
        if (!mounted) return;
        final batch = <({String path, String? volume, String volumeName, int depth})>[];
        while (cursor < pending.length && batch.length < 8 && visited.length < 1800) {
          final current = pending[cursor++];
          final key = '${current.volume ?? 'internal'}:${current.path}';
          if (visited.add(key)) batch.add(current);
        }

        await Future.wait(batch.map((current) async {
          try {
            final listing = current.volume == null
                ? await widget.api.listDirectory(current.path)
                : await widget.api.listStorageDirectory(current.volume!, current.path);
            _scannedDirectories++;
            for (final item in listing.items) {
              if (item.name.startsWith('.')) continue;
              final path = current.path.isEmpty ? item.name : '${current.path}/${item.name}';
              if (item.isDirectory) {
                if (current.depth < 18) {
                  pending.add((path: path, volume: current.volume, volumeName: current.volumeName, depth: current.depth + 1));
                }
              } else if (found.length < 10000) {
                found.add(_SearchResult(file: item, path: path, volume: current.volume, volumeName: current.volumeName));
              }
            }
          } on DioException catch (error) {
            final status = error.response?.statusCode;
            if (status == 403 || status == 404) return;
            rethrow;
          } catch (_) {
            // Continue through other folders when a folder is unavailable.
          }
        }));

        if (mounted) {
          setState(() {
            _results
              ..clear()
              ..addAll(found);
          });
        }
      }
      found.sort((a, b) => a.file.name.toLowerCase().compareTo(b.file.name.toLowerCase()));
      if (mounted) {
        setState(() {
          _results
            ..clear()
            ..addAll(found);
        });
      }
    } on DioException catch (error) {
      if (mounted) {
        final status = error.response?.statusCode;
        setState(() => _error = status == 401
            ? 'Login expired or credentials are incorrect.'
            : error.message ?? 'Could not search server storage. Check the connection and try again.');
      }
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not search server storage. Check the connection and try again.');
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
          _scanInProgress = false;
        });
      }
    }
  }

  Future<void> _openResult(_SearchResult result) async {
    final extension = _extension(result.file.name);
    final isAudio = _audio.contains(extension);
    final isVideo = _video.contains(extension);
    if (isAudio || isVideo) {
      final queue = _visibleResults
          .where((item) => isAudio
              ? _audio.contains(_extension(item.file.name))
              : _video.contains(_extension(item.file.name)))
          .map((item) => MediaQueueItem(title: item.file.name, path: item.path, volume: item.volume))
          .toList(growable: false);
      final index = queue.indexWhere((item) => item.path == result.path && item.volume == result.volume);
      await Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => MediaPlayerScreen(
          api: widget.api,
          title: result.file.name,
          path: result.path,
          volume: result.volume,
          isVideo: isVideo,
          queue: queue,
          initialIndex: index < 0 ? 0 : index,
        ),
      ));
      return;
    }
    if (result.volume == null) {
      await Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => FileManagerScreen(api: widget.api, initialPath: _parent(result.path)),
      ));
    } else {
      await Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => StorageBrowserScreen(api: widget.api, initialVolume: result.volume, initialPath: _parent(result.path)),
      ));
    }
  }

  String _parent(String path) {
    final separator = path.lastIndexOf('/');
    return separator < 0 ? '' : path.substring(0, separator);
  }

  @override
  Widget build(BuildContext context) {
    final query = _searchController.text.trim();
    final results = _visibleResults;
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Search'),
        actions: [
          IconButton(
            tooltip: 'Transfers',
            onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const TransferManagerScreen())),
            icon: const Icon(Icons.swap_vert_rounded),
          ),
          IconButton(
            tooltip: 'Search storage',
            onPressed: _loading || query.isEmpty ? null : _search,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
            child: TextField(
              controller: _searchController,
              focusNode: _focusNode,
              autofocus: true,
              textInputAction: TextInputAction.search,
              onSubmitted: (_) => _search(),
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                hintText: 'Search files, photos, music and videos',
                prefixIcon: const Icon(Icons.search_rounded),
                suffixIcon: query.isEmpty ? null : IconButton(
                  onPressed: () {
                    _searchController.clear();
                    setState(() {});
                  },
                  icon: const Icon(Icons.close_rounded),
                ),
                filled: true,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: BorderSide.none),
              ),
            ),
          ),
          SizedBox(
            height: 48,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              children: [
                for (final filter in const ['All', 'Files', 'Photos', 'Audio', 'Videos'])
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(filter),
                      selected: _filter == filter,
                      onSelected: (_) => setState(() => _filter = filter),
                    ),
                  ),
              ],
            ),
          ),
          if (_loading) const LinearProgressIndicator(minHeight: 2),
          Expanded(
            child: query.isEmpty
                ? Center(child: Text('Search your HomeServer storage', style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)))
                : !_searched
                    ? Center(child: FilledButton.icon(onPressed: _search, icon: const Icon(Icons.search), label: const Text('Search storage')))
                    : _error != null
                        ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(_error!, textAlign: TextAlign.center)))
                        : results.isEmpty
                            ? Center(child: Text(_loading ? 'Scanning folders…' : 'No matching files found', style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)))
                            : ListView.separated(
                                padding: EdgeInsets.fromLTRB(12, 8, 12, 104 + MediaQuery.paddingOf(context).bottom),
                                itemCount: results.length,
                                separatorBuilder: (_, __) => const Divider(height: 1, indent: 66),
                                itemBuilder: (context, index) {
                                  final result = results[index];
                                  return ListTile(
                                    leading: CircleAvatar(child: Icon(_resultIcon(_extension(result.file.name)))),
                                    title: Text(result.file.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                                    subtitle: Text('${result.volumeName} · ${result.path}', maxLines: 1, overflow: TextOverflow.ellipsis),
                                    trailing: const Icon(Icons.chevron_right_rounded),
                                    onTap: () => _openResult(result),
                                  );
                                },
                              ),
          ),
          if (_searched && !_loading)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text('${results.length} results · $_scannedDirectories folders scanned', style: theme.textTheme.labelSmall),
            ),
        ],
      ),
    );
  }

  IconData _resultIcon(String extension) {
    if (_audio.contains(extension)) return Icons.audio_file_rounded;
    if (_video.contains(extension)) return Icons.video_file_rounded;
    if (_photo.contains(extension)) return Icons.image_rounded;
    if (!_photo.contains(extension) && !_audio.contains(extension) && !_video.contains(extension)) return Icons.description_rounded;
    return Icons.insert_drive_file_outlined;
  }
}
