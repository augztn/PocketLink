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

class ExploreScreen extends StatefulWidget {
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

  @override
  State<ExploreScreen> createState() => _ExploreScreenState();
}

class _ExploreScreenState extends State<ExploreScreen> {
  late ExploreCategory _category = widget.category;
  late String _fileCategory = widget.fileCategory;
  late final Set<ExploreCategory> _initialized = {widget.category};

  @override
  void didUpdateWidget(covariant ExploreScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.category != widget.category) {
      _category = widget.category;
      _initialized.add(widget.category);
    }
    if (oldWidget.fileCategory != widget.fileCategory) {
      _fileCategory = widget.fileCategory;
    }
  }

  void _select(ExploreCategory category) {
    setState(() {
      _initialized.add(category);
      _category = category;
      if (category == ExploreCategory.files) _fileCategory = 'All';
    });
    widget.onCategoryChanged(category);
  }

  @override
  Widget build(BuildContext context) {
    final categories = ExploreCategory.values;
    final selectedIndex = categories.indexOf(_category);
    final pages = <Widget>[
      for (final category in categories)
        if (!_initialized.contains(category))
          const SizedBox.shrink()
        else if (category == ExploreCategory.files)
          FileManagerScreen(
            api: widget.api,
            initialCategory: _fileCategory,
            isActive: _category == category,
            onBackAtRoot: widget.onBackAtRoot,
          )
        else if (category == ExploreCategory.drives)
          StorageBrowserScreen(api: widget.api)
        else if (category == ExploreCategory.photos)
          PhotoGalleryScreen(api: widget.api)
        else if (category == ExploreCategory.music)
          MediaBrowserScreen(api: widget.api, type: MediaLibraryType.music)
        else
          MediaBrowserScreen(api: widget.api, type: MediaLibraryType.video),
    ];

    return Column(
      children: [
        SizedBox(
          height: 58,
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            scrollDirection: Axis.horizontal,
            children: [
              for (final category in categories)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    selected: _category == category,
                    showCheckmark: false,
                    avatar: Icon(_icon(category), size: 17),
                    label: Text(_label(category)),
                    onSelected: (_) => _select(category),
                  ),
                ),
            ],
          ),
        ),
        Expanded(child: IndexedStack(index: selectedIndex, children: pages)),
      ],
    );
  }

  String _label(ExploreCategory category) => switch (category) {
    ExploreCategory.files => 'Files',
    ExploreCategory.drives => 'Drives',
    ExploreCategory.photos => 'Photos',
    ExploreCategory.music => 'Music',
    ExploreCategory.videos => 'Videos',
  };

  IconData _icon(ExploreCategory category) => switch (category) {
    ExploreCategory.files => Icons.folder_outlined,
    ExploreCategory.drives => Icons.usb_rounded,
    ExploreCategory.photos => Icons.photo_outlined,
    ExploreCategory.music => Icons.headphones_rounded,
    ExploreCategory.videos => Icons.movie_outlined,
  };
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
  static const _extensions = <String, Set<String>>{
    'Audio': {'mp3', 'm4a', 'aac', 'wav', 'flac', 'ogg', 'opus', 'wma', 'aiff', 'alac'},
    'Video': {'mp4', 'm4v', 'mov', 'mkv', 'webm', 'avi', 'wmv', 'mpeg', 'mpg', '3gp', 'ts', 'm2ts', 'mts', 'flv', 'ogv'},
    'Docs': {'pdf', 'doc', 'docx', 'odt', 'rtf', 'txt', 'md', 'csv', 'xls', 'xlsx', 'ods', 'ppt', 'pptx', 'odp'},
    'Images': {'jpg', 'jpeg', 'png', 'webp', 'gif', 'bmp', 'heic', 'heif', 'avif'},
  };

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
    if (_filter == 'All') return true;
    return _extensions[_filter]!.contains(_extension(result.file.name));
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
    final isAudio = _extensions['Audio']!.contains(extension);
    final isVideo = _extensions['Video']!.contains(extension);
    if (isAudio || isVideo) {
      final queue = _visibleResults
          .where((item) => isAudio
              ? _extensions['Audio']!.contains(_extension(item.file.name))
              : _extensions['Video']!.contains(_extension(item.file.name)))
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
                for (final filter in const ['All', 'Audio', 'Video', 'Docs', 'Images'])
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
    if (_extensions['Audio']!.contains(extension)) return Icons.audio_file_rounded;
    if (_extensions['Video']!.contains(extension)) return Icons.video_file_rounded;
    if (_extensions['Images']!.contains(extension)) return Icons.image_rounded;
    if (_extensions['Docs']!.contains(extension)) return Icons.description_rounded;
    return Icons.insert_drive_file_outlined;
  }
}
