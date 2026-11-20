import 'dart:typed_data';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:shared_preferences/shared_preferences.dart';
import '../../core/widgets/pocketlink_app_bar.dart';
import '../../core/widgets/compact_search_field.dart';
import '../../core/widgets/feathered_glass_header.dart';
import '../../core/widgets/liquid_glass_pill.dart';
import '../../core/widgets/smoked_glass_popover_menu.dart';

import 'package:dio/dio.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../../core/network/server_api.dart';
import 'media_player_screen.dart';
import 'persistent_audio_player.dart';
import 'now_playing_overlay_controller.dart';
import '../transfers/transfer_manager_screen.dart';
import '../downloads/download_manager_service.dart';
import '../home/browser_state_store.dart';
import '../settings/settings_screen.dart';

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
    'mp3', 'flac', 'm4a', 'wav', 'ogg', 'aac', 'opus', 'wma',
  };
  static const _videoExtensions = {
    'mp4', 'mkv', 'webm', 'mov', 'avi', 'm4v', '3gp', 'ts',
  };
  static const _audioMimeTypes = {
    'audio/mpeg', 'audio/flac', 'audio/x-flac', 'audio/mp4', 'audio/x-m4a',
    'audio/wav', 'audio/x-wav', 'audio/ogg', 'audio/aac', 'audio/opus',
    'audio/x-ms-wma',
  };
  static const _videoMimeTypes = {
    'video/mp4', 'video/x-m4v', 'video/x-matroska', 'video/webm',
    'video/quicktime', 'video/x-msvideo', 'video/3gpp', 'video/mp2t',
  };
  static const _maxDirectories = 10000;
  static const _maxDepth = 24;

  List<_MediaFile> _media = const [];
  bool _loading = true;
  String? _error;
  int _scannedDirectories = 0;
  int _skippedDirectories = 0;
  String _scanLocation = '';
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
  bool _musicMenuOpen = false;
  bool _searchExpanded = false;
  bool _selectionMode = false;
  final Set<String> _selectedTrackKeys = <String>{};

  void _syncBackHandler() {
    final handler = _searchExpanded
        ? () => _setSearchExpanded(false)
        : _libraryView == 'folders' && !_atFolderRoot
            ? _goUpFolder
            : null;
    widget.onBackHandlerChanged?.call(handler);
  }

  void _setSearchExpanded(bool expanded) {
    if (_searchExpanded == expanded) return;
    setState(() => _searchExpanded = expanded);
    _syncBackHandler();
  }
  Set<String> _favoriteKeys = <String>{};
  final Map<String, Future<Uint8List?>> _musicArtworkCache = {};
  final Map<String, Future<VideoMetadata?>> _videoMetadataCache = {};

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
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _syncBackHandler();
    });
    _loadFavorites();
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
    _syncBackHandler();
  }

  String _volumeName(String? id) {
    if (id == null || id == 'internal') return 'Internal storage';
    for (final volume in _volumes) {
      if (volume.id == id) return volume.name;
    }
    return 'USB / OTG';
  }

  bool _isMedia(FileEntry item, {String? mime}) {
    final extension = item.name.contains('.')
        ? item.name.split('.').last.toLowerCase()
        : '';
    final allowedExtension = (_isMusic ? _audioExtensions : _videoExtensions)
        .contains(extension);
    if (!allowedExtension) return false;
    final normalizedMime = mime?.split(';').first.trim().toLowerCase() ?? '';
    if (normalizedMime.isEmpty || normalizedMime == 'application/octet-stream') {
      return true;
    }
    return (_isMusic ? _audioMimeTypes : _videoMimeTypes)
        .contains(normalizedMime);
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
      found.addAll(page.items
          .where((item) => _isMedia(item.toFileEntry(), mime: item.mime))
          .map((item) => _MediaFile(
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

  Future<void> _refreshMusic() async {
    if (_loading) return;
    await _scan(refresh: true);
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
      _scanLocation = '';
    });

    try {
      var result = await _readIndexedMedia();
      var found = result.items;
      var status = result.status;
      if (mounted) {
        setState(() {
          _media = List.unmodifiable(found);
          _scannedDirectories = status.scannedDirectories;
          _skippedDirectories = status.skipped;
          _scanLocation = _indexLocation(status);
        });
      }

      // Keep the existing index visible while scanning. Poll only lightweight
      // status; reload media once after the scan finishes.
      final wasScanning = status.isScanning;
      while (mounted && status.isScanning) {
        await Future<void>.delayed(const Duration(seconds: 2));
        if (!mounted) return;
        status = await widget.api.mediaIndexStatus();
        if (mounted) {
          setState(() {
            _scannedDirectories = status.scannedDirectories;
            _skippedDirectories = status.skipped;
            _scanLocation = status.isScanning ? _indexLocation(status) : '';
          });
        }
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
          _scannedDirectories = status.scannedDirectories;
          _skippedDirectories = status.skipped;
          _scanLocation = '';
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

  String _indexLocation(MediaIndexStatus status) {
    final source = status.currentSource;
    if (source == null || source.isEmpty) return '';
    final label = source == 'internal' ? 'Internal' : source.toUpperCase();
    final path = status.currentPath;
    return path == null || path.isEmpty ? label : '$label/$path';
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
      _scanLocation = '';
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
          _syncBackHandler();
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
      if (_isMusic) {
        await PersistentAudioPlayer.instance.openQueue(
          api: widget.api,
          queue: queue,
          initialIndex: index < 0 ? 0 : index,
          isMusic: true,
        );
        NowPlayingOverlayController.open();
      } else {
        await Navigator.of(context, rootNavigator: true).push<void>(
          MaterialPageRoute<void>(
            builder: (_) => MediaPlayerScreen(
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
    final name = (dot > 0 ? media.entry.name.substring(0, dot) : media.entry.name)
        .replaceAll('_', ' ')
        .trim();
    final artist = _trackArtist(media).trim();
    final suffixStart = name.lastIndexOf(' - ');
    if (suffixStart >= 0 &&
        artist.isNotEmpty &&
        name.substring(suffixStart + 3).trim().toLowerCase() ==
            artist.toLowerCase()) {
      return name.substring(0, suffixStart).trim();
    }
    return name;
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

  Future<VideoMetadata?> _videoMetadataFor(_MediaFile media) =>
      _videoMetadataCache.putIfAbsent(_favoriteKey(media), () => widget.api.videoMetadata(media.path, volume: media.volume));

  Widget _videoMetadataLabel(_MediaFile media) {
    return FutureBuilder<VideoMetadata?>(
      future: _videoMetadataFor(media),
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
  Widget _videoDurationBadge(_MediaFile media) {
    return FutureBuilder<VideoMetadata?>(
      future: _videoMetadataFor(media),
      builder: (context, snapshot) {
        final duration = snapshot.data?.durationMs ?? 0;
        if (duration <= 0) return const SizedBox.shrink();
        return _VideoTag(label: _formatDuration(duration));
      },
    );
  }

  Widget _buildVideoGrid(List<_MediaFile> items) {
    return GridView.builder(
      controller: _contentScrollController,
      padding: EdgeInsets.fromLTRB(12, ((_searchExpanded && widget.showSearch) || _libraryView == 'folders') ? 8 : MediaQuery.paddingOf(context).top + kToolbarHeight + 8, 12, 104 + MediaQuery.paddingOf(context).bottom),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2, crossAxisSpacing: 12, mainAxisSpacing: 14,
        childAspectRatio: 0.88,
      ),
      itemCount: items.length,
      itemBuilder: (context, index) {
        final media = items[index];
        final extension = media.entry.name.split('.').last.toUpperCase();
        final favorite = _favoriteKeys.contains(_favoriteKey(media));
        final colors = Theme.of(context).colorScheme;
        return Material(
          color: colors.surfaceContainerLow,
          borderRadius: BorderRadius.circular(16),
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: () => _openMedia(media, items),
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: colors.outlineVariant.withValues(alpha: 0.48)),
              ),
              clipBehavior: Clip.antiAlias,
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Expanded(child: Stack(fit: StackFit.expand, children: [
                  _buildVideoArtwork(media, fit: BoxFit.cover),
                  Positioned(left: 8, bottom: 8, child: _VideoTag(label: extension)),
                  Positioned(right: 8, bottom: 8, child: _videoDurationBadge(media)),
                  Center(child: ClipOval(child: BackdropFilter(
                    filter: ui.ImageFilter.blur(sigmaX: 14, sigmaY: 14),
                    child: Container(width: 44, height: 44,
                      decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.42), shape: BoxShape.circle,
                        border: Border.all(color: Colors.white.withValues(alpha: 0.35))),
                      child: const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 28),
                    ),
                  ))),
                  Positioned(left: 8, top: 8, child: SmokedGlassPopoverMenu<String>(
                    tooltip: 'Video actions',
                    items: const [
                      SmokedGlassPopoverMenuItem(value: 'download', label: 'Download', icon: Icons.download_rounded),
                    ],
                    onSelected: (action) async {
                      if (action != 'download') return;
                      try {
                        await DownloadManagerService.instance.enqueueServerFile(
                          api: widget.api,
                          name: media.entry.name,
                          sourcePath: media.path,
                          volume: media.volume,
                          size: media.entry.size,
                        );
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('Added to Downloads: ${media.entry.name}')),
                          );
                        }
                      } catch (_) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Could not add this video to Downloads.')),
                          );
                        }
                      }
                    },
                    child: const GlassCircleButton(
                      tooltip: 'Video actions',
                      onPressed: null,
                      child: Icon(Icons.more_vert_rounded, size: 18),
                    ),
                  )),
                  Positioned(right: 4, top: 4, child: IconButton(
                    visualDensity: VisualDensity.compact,
                    tooltip: favorite ? 'Remove favourite' : 'Add favourite',
                    onPressed: () => _toggleFavorite(media),
                    icon: Icon(favorite ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                      color: favorite ? const Color(0xFFFF6B8A) : Colors.white),
                  )),
                ])),
                Padding(padding: const EdgeInsets.fromLTRB(10, 8, 10, 9), child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(media.entry.name, maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 3),
                    Row(children: [
                      Expanded(child: _videoMetadataLabel(media)),
                      Text(_formatBytes(media.entry.size), style: Theme.of(context).textTheme.bodySmall),
                    ]),
                  ],
                )),
              ]),
            ),
          ),
        );
      },
    );
  }

  Widget _buildVideoList(List<_MediaFile> items) {
    return ListView.separated(
      controller: _contentScrollController,
      padding: EdgeInsets.fromLTRB(12, ((_searchExpanded && widget.showSearch) || _libraryView == 'folders') ? 8 : MediaQuery.paddingOf(context).top + kToolbarHeight + 8, 12, 104 + MediaQuery.paddingOf(context).bottom),
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
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SmokedGlassPopoverMenu<String>(
                  tooltip: 'Video actions',
                  items: const [
                    SmokedGlassPopoverMenuItem(value: 'download', label: 'Download', icon: Icons.download_rounded),
                  ],
                  onSelected: (action) async {
                    if (action != 'download') return;
                    try {
                      await DownloadManagerService.instance.enqueueServerFile(
                        api: widget.api,
                        name: media.entry.name,
                        sourcePath: media.path,
                        volume: media.volume,
                        size: media.entry.size,
                      );
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Added to Downloads: ${media.entry.name}')),
                        );
                      }
                    } catch (_) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Could not add this video to Downloads.')),
                        );
                      }
                    }
                  },
                  child: const Padding(
                    padding: EdgeInsets.all(8),
                    child: Icon(Icons.more_vert_rounded),
                  ),
                ),
                const Icon(Icons.play_circle_outline_rounded),
              ],
            ),
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
                          _syncBackHandler();
                        },
                  child: const Text('All storage'),
                ),
                if (_selectedVolume != null) ...[
                  const Icon(Icons.chevron_right_rounded, size: 16),
                  TextButton(
                    onPressed: _currentFolderPath.isEmpty
                        ? null
                        : () { setState(() => _currentFolderPath = _selectedVolume == 'internal' && _isMusic ? 'Music' : ''); _pendingScrollOffset = 0; _saveState(folderPath: _currentFolderPath); if (_contentScrollController.hasClients) _contentScrollController.jumpTo(0); _syncBackHandler(); },
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
                            _syncBackHandler();
                          },
                    child: Text(parts[i]),
                  ),
                ],
              ]),
            ),
          ),
        Expanded(
          child: ListView(
            physics: _isMusic ? const AlwaysScrollableScrollPhysics() : null,
            controller: _contentScrollController,
            padding: EdgeInsets.fromLTRB(12, _isMusic ? 8 : ((_searchExpanded && widget.showSearch) || _libraryView == 'folders') ? 8 : MediaQuery.paddingOf(context).top + kToolbarHeight + 8, 12, 104 + MediaQuery.paddingOf(context).bottom),
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
                      _syncBackHandler();
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

  @override
  void dispose() {
    widget.onBackHandlerChanged?.call(null);
    _saveState();
    _searchController.dispose();
    _contentScrollController.removeListener(_saveScrollOffset);
    _contentScrollController.dispose();
    super.dispose();
  }

  Widget _buildVideoScreen(BuildContext context) {
    final query = _searchQuery.trim().toLowerCase();
    final filtered = _media.where((media) {
      final matchesQuery = query.isEmpty ||
          media.entry.name.toLowerCase().contains(query) ||
          media.path.toLowerCase().contains(query);
      final matchesVolume = _selectedVolume == null ||
          (_selectedVolume == 'internal' ? media.volume == null : media.volume == _selectedVolume);
      final matchesFavorite = _libraryView != 'favorites' || _favoriteKeys.contains(_favoriteKey(media));
      return matchesQuery && matchesVolume && matchesFavorite;
    }).toList(growable: false);
    final visibleMedia = _sortMedia(filtered);
    final isFolderView = _libraryView == 'folders';

    final favoritesCount = _media.where((m) => _favoriteKeys.contains(_favoriteKey(m))).length;
    final folderCount = _foldersAtCurrentLevel(_media).length;
    final headerTitle = _libraryView == 'folders' ? 'Folders' : _libraryView == 'favorites' ? 'Favorites' : 'Videos';
    final dark = Theme.of(context).brightness == Brightness.dark;
    final titleColor = dark ? Colors.white : const Color(0xFF0F172A);

    return PopScope(
      canPop: widget.onBackHandlerChanged != null ||
          (!_searchExpanded && (_libraryView != 'folders' || _atFolderRoot)),
      onPopInvokedWithResult: (didPop, result) {
        if (didPop || widget.onBackHandlerChanged != null) return;
        if (_searchExpanded) {
          _setSearchExpanded(false);
        } else if (_libraryView == 'folders' && !_atFolderRoot) {
          _goUpFolder();
        }
      },
      child: Scaffold(
        extendBodyBehindAppBar: true,
        appBar: PocketLinkAppBar(
          feathered: true,
          showHome: false,
          automaticallyImplyLeading: false,
            title: SmokedGlassPopoverMenu<String>(
            tooltip: 'Choose video view',
            onOpenChanged: (open) => setState(() => _musicMenuOpen = open),
            items: [
              SmokedGlassPopoverMenuItem(
                value: 'all',
                label: 'All Videos',
                icon: Icons.video_library_rounded,
                trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                  Text('${_media.length}', style: const TextStyle(fontFamily: 'monospace', fontSize: 12, color: Color(0xFFA1A7B3))),
                  if (_libraryView == 'all') const Padding(padding: EdgeInsets.only(left: 8), child: Icon(Icons.check_rounded, size: 18)),
                ]),
              ),
              SmokedGlassPopoverMenuItem(
                value: 'folders',
                label: 'Folders',
                icon: Icons.folder_rounded,
                trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                  Text('$folderCount', style: const TextStyle(fontFamily: 'monospace', fontSize: 12, color: Color(0xFFA1A7B3))),
                  if (_libraryView == 'folders') const Padding(padding: EdgeInsets.only(left: 8), child: Icon(Icons.check_rounded, size: 18)),
                ]),
              ),
              SmokedGlassPopoverMenuItem(
                value: 'favorites',
                label: 'Favorites',
                icon: Icons.favorite_rounded,
                trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                  Text('$favoritesCount', style: const TextStyle(fontFamily: 'monospace', fontSize: 12, color: Color(0xFFA1A7B3))),
                  if (_libraryView == 'favorites') const Padding(padding: EdgeInsets.only(left: 8), child: Icon(Icons.check_rounded, size: 18)),
                ]),
              ),
            ],
            onSelected: (value) {
              setState(() {
                _libraryView = value;
                if (value != 'folders') _currentFolderPath = '';
              });
              _syncBackHandler();
              _saveState(folderPath: _currentFolderPath);
              if (_contentScrollController.hasClients) {
                _contentScrollController.jumpTo(0);
              }
            },
            child: Row(children: [
              Expanded(
                child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(mainAxisSize: MainAxisSize.min, children: [
                    Flexible(child: Text(headerTitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 25, fontWeight: FontWeight.w800, color: titleColor))),
                    const SizedBox(width: 6),
                    AnimatedRotation(turns: _musicMenuOpen ? 0.5 : 0, duration: const Duration(milliseconds: 200), child: const Icon(Icons.keyboard_arrow_down_rounded)),
                  ]),
                  Text(
                  _countLabel(visibleMedia.length, 'video', 'videos') + ' • ${_selectedVolume == null ? 'All storage' : _volumeName(_selectedVolume)}'
                  '${_scannedDirectories > 0 ? ' • $_scannedDirectories scanned' : ''}'
                  '${_skippedDirectories > 0 ? ' · $_skippedDirectories skipped' : ''}'
                  '${_loading && _scanLocation.isNotEmpty ? ' · $_scanLocation' : ''}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 10, fontFamily: 'monospace', color: Color(0xFFA1A7B3)),
                  ),
                ]),
              ),
              const SizedBox(width: 8),
            ]),
          ),
          actions: [
            if (widget.showSearch) PocketLinkAppBarAction(label: _searchExpanded ? 'Close search' : 'Search videos', icon: _searchExpanded ? Icons.close_rounded : Icons.search_rounded, onPressed: () => _setSearchExpanded(!_searchExpanded)),
            PocketLinkAppBarAction(label: 'Filter & sort', icon: Icons.tune_rounded, onPressed: _showMusicFilters),
            PocketLinkAppBarAction(label: 'Transfers', icon: Icons.swap_vert_rounded,
              onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const TransferManagerScreen())), dividerBefore: true),
            PocketLinkAppBarAction(label: 'Scan again', icon: Icons.refresh_rounded, onPressed: _loading ? null : () => _scan(refresh: true)),
          ],
        ),
        body: Column(children: [
          if ((_searchExpanded && widget.showSearch) || isFolderView)
            SizedBox(height: MediaQuery.paddingOf(context).top + kToolbarHeight + 4),
          if (_searchExpanded && widget.showSearch)
            Padding(padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: CompactSearchField(controller: _searchController,
                hintText: 'Search videos or folders',
                onChanged: (value) => setState(() => _searchQuery = value))),
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
                                        padding: EdgeInsets.fromLTRB(12, ((_searchExpanded && widget.showSearch) || _libraryView == 'folders') ? 8 : MediaQuery.paddingOf(context).top + kToolbarHeight + 8, 12, 104 + MediaQuery.paddingOf(context).bottom),
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

  String get _favoritesPreferenceKey => 'pocketlink.media.favorites.$_stateKey.${widget.type.name}';

  String _favoriteKey(_MediaFile media) => '${media.volume ?? 'internal'}:${media.path}';

  Future<void> _loadFavorites() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() => _favoriteKeys = prefs.getStringList(_favoritesPreferenceKey)?.toSet() ?? <String>{});
  }

  Future<void> _toggleFavorite(_MediaFile media) async {
    final key = _favoriteKey(media);
    final next = Set<String>.of(_favoriteKeys);
    if (!next.add(key)) next.remove(key);
    setState(() => _favoriteKeys = next);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_favoritesPreferenceKey, next.toList()..sort());
  }

  String _trackArtist(_MediaFile media) {
    final parts = media.path.split('/')..removeLast();
    return parts.isEmpty ? _sourceLabel(media) : parts.last;
  }

  Future<Uint8List?> _loadTrackArtwork(_MediaFile media) =>
      _musicArtworkCache.putIfAbsent(_favoriteKey(media), () => _fetchTrackArtwork(media));

  Future<Uint8List?> _fetchTrackArtwork(_MediaFile media) async {
    final folder = media.path.contains('/')
        ? media.path.substring(0, media.path.lastIndexOf('/') + 1)
        : '';
    try {
      final listing = media.volume == null
          ? await widget.api.listDirectory(folder)
          : await widget.api.listStorageDirectory(media.volume!, folder);
      const names = ['cover.jpg', 'cover.jpeg', 'cover.png', 'cover.webp',
        'folder.jpg', 'folder.png', 'album.jpg', 'album.png', 'front.jpg'];
      for (final name in names) {
        for (final item in listing.items) {
          if (!item.isDirectory && item.name.toLowerCase() == name) {
            final path = '$folder${item.name}';
            final bytes = media.volume == null
                ? await widget.api.downloadFile(path)
                : await widget.api.downloadStorageFile(media.volume!, path);
            if (bytes.isNotEmpty) return bytes;
          }
        }
      }
    } catch (_) {
      // Embedded artwork is optional; playback must not depend on it.
    }
    return null;
  }

  Future<void> _showMusicFilters() async {
    final selected = await showModalBottomSheet<({String? volume, String sort})>(
      context: context,
      useRootNavigator: true,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (sheetContext) {
        var volume = _selectedVolume;
        var sort = _sortBy;
        final isDark = Theme.of(sheetContext).brightness == Brightness.dark;
        return StatefulBuilder(builder: (context, update) => Padding(
          padding: const EdgeInsets.all(12),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(24),
            child: BackdropFilter(
              filter: ui.ImageFilter.blur(sigmaX: 24, sigmaY: 24),
              child: Container(
                padding: const EdgeInsets.fromLTRB(18, 18, 18, 22),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xEE17191F) : const Color(0xEEF8FAFC),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: Colors.white.withValues(alpha: isDark ? 0.14 : 0.55)),
                ),
                child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Filter & sort', style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 18),
                  const Text('STORAGE SOURCE', style: TextStyle(fontSize: 11, letterSpacing: 1.1, color: Color(0xFFA1A7B3), fontWeight: FontWeight.w700)),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String?>(
                    initialValue: volume,
                    decoration: const InputDecoration(border: OutlineInputBorder(), isDense: true),
                    items: [
                      const DropdownMenuItem<String?>(value: null, child: Text('All storage')),
                      const DropdownMenuItem<String?>(value: 'internal', child: Text('Internal storage')),
                      ..._volumes.where((v) => v.available).map((v) => DropdownMenuItem<String?>(value: v.id, child: Text(v.name))),
                    ],
                    onChanged: (value) => update(() => volume = value),
                  ),
                  const SizedBox(height: 18),
                  const Text('SORT ORDER', style: TextStyle(fontSize: 11, letterSpacing: 1.1, color: Color(0xFFA1A7B3), fontWeight: FontWeight.w700)),
                  const SizedBox(height: 8),
                  Wrap(spacing: 8, children: [
                    for (final option in [('name', 'Name'), ('newest', 'Newest'), ('largest', 'Largest')])
                      ChoiceChip(label: Text(option.$2), selected: sort == option.$1, onSelected: (_) => update(() => sort = option.$1)),
                  ]),
                  const SizedBox(height: 18),
                  SizedBox(width: double.infinity, child: FilledButton(
                    onPressed: () => Navigator.pop(sheetContext, (volume: volume, sort: sort)),
                    child: const Text('Apply'),
                  )),
                ]),
              ),
            ),
          ),
        ));
      },
    );
    if (selected == null || !mounted) return;
    final rootPath = _isMusic && selected.volume == 'internal' ? 'Music' : '';
    setState(() {
      _selectedVolume = selected.volume;
      _sortBy = selected.sort;
      _currentFolderPath = rootPath;
    });
    _pendingScrollOffset = 0;
    _saveState(folderPath: rootPath, clearVolume: selected.volume == null);
    if (_contentScrollController.hasClients) _contentScrollController.jumpTo(0);
    _syncBackHandler();
  }

  Widget _musicArtwork(_MediaFile media, {bool playing = false}) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: SizedBox(
        width: 48, height: 48,
        child: Stack(fit: StackFit.expand, children: [
          const DecoratedBox(decoration: BoxDecoration(
            gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight,
              colors: [Color(0xFF536DFE), Color(0xFF252B52), Color(0xFF141722)]),
          )),
          FutureBuilder<Uint8List?>(
            future: _loadTrackArtwork(media),
            builder: (context, snapshot) => snapshot.data == null
                ? const Center(child: Icon(Icons.music_note_rounded, color: Colors.white70, size: 24))
                : Image.memory(snapshot.data!, fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => const Center(child: Icon(Icons.music_note_rounded, color: Colors.white70))),
          ),
          if (playing) const ColoredBox(color: Color(0x66000000), child: Center(child: _MusicEqualizer())),
        ]),
      ),
    );
  }

  Future<void> _queueTrack(_MediaFile media, {required bool playNext}) async {
    final player = PersistentAudioPlayer.instance;
    final item = MediaQueueItem(title: media.entry.name, path: media.path, volume: media.volume, size: media.entry.size);
    if (player.isActive && player.isMusic) {
      await player.enqueue(item, playNext: playNext);
    } else {
      await player.openQueue(api: widget.api, queue: [item], initialIndex: 0, isMusic: true);
    }
  }

  void _toggleTrackSelection(_MediaFile media) {
    final key = _favoriteKey(media);
    setState(() {
      if (!_selectedTrackKeys.add(key)) _selectedTrackKeys.remove(key);
    });
  }

  String _musicDurationLabel(_MediaFile media) {
    final player = PersistentAudioPlayer.instance;
    final current = player.currentItem;
    if (current == null || current.path != media.path || current.volume != media.volume || !player.isMusic) {
      return '—:—';
    }
    final duration = player.player.state.duration;
    return duration > Duration.zero ? _formatDuration(duration.inMilliseconds) : '—:—';
  }

  Widget _musicTrackTile(_MediaFile media, List<_MediaFile> queueItems) {
    final player = PersistentAudioPlayer.instance;
    final isPlaying = player.currentItem?.path == media.path &&
        player.currentItem?.volume == media.volume &&
        player.isMusic && player.isPlaying;
    final selected = _selectedTrackKeys.contains(_favoriteKey(media));
    final favorite = _favoriteKeys.contains(_favoriteKey(media));
    return Material(
      color: selected
          ? const Color(0x22536DFE)
          : isPlaying
              ? Colors.white.withValues(alpha: 0.07)
              : Colors.transparent,
      child: InkWell(
        onTap: () => _selectionMode
            ? _toggleTrackSelection(media)
            : _openMedia(media, queueItems),
        onLongPress: () {
          if (!_selectionMode) setState(() => _selectionMode = true);
          _toggleTrackSelection(media);
        },
        child: SizedBox(
          height: 64,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            child: Row(children: [
              _musicArtwork(media, playing: isPlaying),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _displayTitle(media),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFFFFFFFF),
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        height: 1.15,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      _trackArtist(media),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFF8E939E),
                        fontSize: 13,
                        height: 1.1,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(
                _musicDurationLabel(media),
                style: const TextStyle(
                  color: Color(0xFF8E939E),
                  fontSize: 12.5,
                  fontFamily: 'JetBrains Mono',
                  fontFeatures: [ui.FontFeature.tabularFigures()],
                ),
              ),
              if (_selectionMode)
                SizedBox(
                  width: 36,
                  height: 36,
                  child: Icon(
                    selected ? Icons.check_circle_rounded : Icons.circle_outlined,
                    size: 18,
                    color: selected ? const Color(0xFF536DFE) : const Color(0xFF8E939E),
                  ),
                )
              else
                SmokedGlassPopoverMenu<String>(
                  tooltip: 'Track actions',
                  items: [
                    const SmokedGlassPopoverMenuItem(value: 'next', label: 'Play next', icon: Icons.skip_next_rounded),
                    const SmokedGlassPopoverMenuItem(value: 'queue', label: 'Add to queue', icon: Icons.queue_music_rounded),
                    const SmokedGlassPopoverMenuItem(value: 'download', label: 'Download', icon: Icons.download_rounded, dividerBefore: true),
                    SmokedGlassPopoverMenuItem(value: 'favorite', label: favorite ? 'Remove favourite' : 'Add to favourites', icon: favorite ? Icons.favorite_rounded : Icons.favorite_border_rounded),
                  ],
                  onSelected: (action) async {
                    if (action == 'favorite') await _toggleFavorite(media);
                    if (action == 'next') await _queueTrack(media, playNext: true);
                    if (action == 'queue') await _queueTrack(media, playNext: false);
                    if (action == 'download') {
                      try {
                        await DownloadManagerService.instance.enqueueServerFile(
                          api: widget.api,
                          name: media.entry.name,
                          sourcePath: media.path,
                          volume: media.volume,
                          size: media.entry.size,
                        );
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('Added to Downloads: ${media.entry.name}')),
                          );
                        }
                      } catch (_) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Could not add this track to Downloads.')),
                          );
                        }
                      }
                    }
                  },
                  child: const SizedBox(
                    width: 28,
                    height: 36,
                    child: Center(
                      child: Icon(Icons.more_vert_rounded, size: 18, color: Color(0xFF8E939E)),
                    ),
                  ),
                ),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _musicScreen(BuildContext context) {
    final query = _searchQuery.trim().toLowerCase();
    final matches = _media.where((media) {
      final q = query.isEmpty || media.entry.name.toLowerCase().contains(query) || media.path.toLowerCase().contains(query);
      final volume = _selectedVolume == null || (_selectedVolume == 'internal' ? media.volume == null : media.volume == _selectedVolume);
      final favorite = _libraryView != 'favorites' || _favoriteKeys.contains(_favoriteKey(media));
      return q && volume && favorite;
    }).toList(growable: false);
    final visible = _sortMedia(matches);
    final folderCount = _foldersAtCurrentLevel(_media).length;
    final favoriteCount = _media.where((m) => _favoriteKeys.contains(_favoriteKey(m))).length;
    final top = MediaQuery.paddingOf(context).top;
    final foreground = Colors.white;

    Widget iconAction(IconData icon, String tooltip, VoidCallback onPressed) =>
        SizedBox(
          width: 36,
          height: 36,
          child: IconButton(
            tooltip: tooltip,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints.tightFor(width: 36, height: 36),
            onPressed: onPressed,
            icon: Icon(icon, size: 18, color: foreground),
          ),
        );

    return PopScope(
      canPop: widget.onBackHandlerChanged != null ||
          (!_searchExpanded && !_selectionMode && (_libraryView != 'folders' || _atFolderRoot)),
      onPopInvokedWithResult: (didPop, result) {
        if (didPop || widget.onBackHandlerChanged != null) return;
        if (_searchExpanded) {
          _setSearchExpanded(false);
        } else if (_selectionMode) {
          setState(() {
            _selectionMode = false;
            _selectedTrackKeys.clear();
          });
        } else if (_libraryView == 'folders' && !_atFolderRoot) {
          _goUpFolder();
        }
      },
      child: AnimatedBuilder(
        animation: PersistentAudioPlayer.instance,
        builder: (context, _) => Scaffold(
          extendBodyBehindAppBar: true,
          body: Stack(children: [
            Positioned.fill(
              child: _libraryView == 'folders'
                  ? Padding(
                      padding: EdgeInsets.only(top: top + 64),
                      child: RefreshIndicator(
                        onRefresh: _refreshMusic,
                        child: _buildFolders(visible),
                      ),
                    )
                  : RefreshIndicator(
                      onRefresh: _refreshMusic,
                      displacement: 48,
                      child: _error != null || (_loading && _media.isEmpty) || visible.isEmpty
                          ? ListView(
                              physics: const AlwaysScrollableScrollPhysics(),
                              padding: EdgeInsets.fromLTRB(0, top + 64, 0, 112 + MediaQuery.paddingOf(context).bottom),
                              children: [
                                SizedBox(
                                  height: MediaQuery.sizeOf(context).height * 0.55,
                                  child: Center(
                                    child: _error != null
                                        ? FilledButton(onPressed: _scan, child: const Text('Retry scan'))
                                        : Text(_loading && _media.isEmpty
                                            ? 'Scanning music library…'
                                            : _libraryView == 'favorites'
                                                ? 'No favourite tracks yet.'
                                                : 'No music found. Scan storage to find tracks.'),
                                  ),
                                ),
                              ],
                            )
                          : ListView.separated(
                              physics: const AlwaysScrollableScrollPhysics(),
                              controller: _contentScrollController,
                              padding: EdgeInsets.fromLTRB(0, top + 64, 0, 112 + MediaQuery.paddingOf(context).bottom),
                              itemCount: visible.length,
                              separatorBuilder: (_, __) => Container(
                                height: 1,
                                margin: const EdgeInsets.only(left: 76),
                                color: Colors.white.withValues(alpha: 0.06),
                              ),
                              itemBuilder: (context, index) => _musicTrackTile(visible[index], visible),
                            ),
                    ),
            ),
            if (_loading)
              Positioned(
                top: top + 60,
                left: 16,
                right: 16,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(2),
                  child: const LinearProgressIndicator(minHeight: 2),
                ),
              ),
            if (_error != null)
              Positioned(
                top: top + 68,
                left: 16,
                right: 16,
                child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
              ),
            Positioned(
              top: top + 8,
              left: 16,
              right: 16,
              height: 44,
              child: Row(children: [
                AnimatedSize(
                  duration: const Duration(milliseconds: 260),
                  curve: Curves.easeOutCubic,
                  child: _searchExpanded
                      ? SizedBox(
                          width: MediaQuery.sizeOf(context).width - 32,
                          height: 44,
                          child: LiquidGlassSurface(
                            radius: BorderRadius.circular(22),
                            refractive: true,
                            child: Row(children: [
                              const SizedBox(width: 14),
                              const Icon(Icons.search_rounded, size: 18, color: Colors.white70),
                              const SizedBox(width: 8),
                              Expanded(
                                child: TextField(
                                  controller: _searchController,
                                  autofocus: true,
                                  onChanged: (value) => setState(() => _searchQuery = value),
                                  textInputAction: TextInputAction.search,
                                  style: const TextStyle(color: Colors.white, fontSize: 14),
                                  decoration: const InputDecoration(
                                    hintText: 'Search songs or folders',
                                    hintStyle: TextStyle(color: Color(0xFF8E939E), fontSize: 14),
                                    border: InputBorder.none,
                                    isDense: true,
                                  ),
                                ),
                              ),
                              IconButton(
                                tooltip: 'Clear search',
                                onPressed: () {
                                  _searchController.clear();
                                  setState(() => _searchQuery = '');
                                },
                                icon: const Icon(Icons.close_rounded, size: 18, color: Colors.white70),
                              ),
                            ]),
                          ),
                        )
                      : SizedBox(
                          height: 44,
                          child: SmokedGlassPopoverMenu<String>(
                          tooltip: 'Choose music view',
                          onOpenChanged: (open) => setState(() => _musicMenuOpen = open),
                          items: [
                            SmokedGlassPopoverMenuItem(value: 'all', label: 'Songs', icon: Icons.music_note_rounded,
                              trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                                Text('${_media.length}', style: const TextStyle(fontFamily: 'monospace', fontSize: 12, color: Color(0xFFA1A7B3))),
                                if (_libraryView == 'all') const Padding(padding: EdgeInsets.only(left: 8), child: Icon(Icons.check_rounded, size: 18)),
                              ])),
                            SmokedGlassPopoverMenuItem(value: 'folders', label: 'Folders', icon: Icons.folder_rounded,
                              trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                                Text('$folderCount', style: const TextStyle(fontFamily: 'monospace', fontSize: 12, color: Color(0xFFA1A7B3))),
                                if (_libraryView == 'folders') const Padding(padding: EdgeInsets.only(left: 8), child: Icon(Icons.check_rounded, size: 18)),
                              ])),
                            SmokedGlassPopoverMenuItem(value: 'favorites', label: 'Favorites', icon: Icons.favorite_rounded,
                              trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                                Text('$favoriteCount', style: const TextStyle(fontFamily: 'monospace', fontSize: 12, color: Color(0xFFA1A7B3))),
                                if (_libraryView == 'favorites') const Padding(padding: EdgeInsets.only(left: 8), child: Icon(Icons.check_rounded, size: 18)),
                              ])),
                          ],
                          onSelected: (value) {
                            setState(() {
                              _libraryView = value;
                              _currentFolderPath = value == 'folders' && _selectedVolume == 'internal' ? 'Music' : '';
                            });
                            _syncBackHandler();
                            _pendingScrollOffset = 0;
                            _saveState(folderPath: _currentFolderPath);
                            if (_contentScrollController.hasClients) _contentScrollController.jumpTo(0);
                          },
                          child: LiquidGlassSurface(
                            radius: BorderRadius.circular(22),
                            refractive: true,
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 16),
                              child: Row(mainAxisSize: MainAxisSize.min, children: [
                                Text('Music', style: TextStyle(color: foreground, fontSize: 15, fontWeight: FontWeight.w700)),
                                const SizedBox(width: 4),
                                AnimatedRotation(
                                  turns: _musicMenuOpen ? 0.5 : 0,
                                  duration: const Duration(milliseconds: 200),
                                  child: const Icon(Icons.keyboard_arrow_down_rounded, color: Colors.white, size: 19),
                                ),
                              ]),
                            ),
                          ),
                          ),
                        ),
                ),
                const Spacer(),
                if (!_searchExpanded && !_selectionMode)
                  SizedBox(
                    height: 44,
                    child: LiquidGlassSurface(
                      radius: BorderRadius.circular(22),
                      refractive: true,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 6),
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                        iconAction(Icons.search_rounded, 'Search', () => _setSearchExpanded(true)),
                        iconAction(Icons.tune_rounded, 'Sort and filter', _showMusicFilters),
                        SmokedGlassPopoverMenu<String>(
                          tooltip: 'More music actions',
                          items: [
                            const SmokedGlassPopoverMenuItem(value: 'shuffle', label: 'Shuffle all', icon: Icons.shuffle_rounded),
                            const SmokedGlassPopoverMenuItem(value: 'select', label: 'Select tracks', icon: Icons.checklist_rounded),
                            const SmokedGlassPopoverMenuItem(value: 'scan', label: 'Scan library', icon: Icons.refresh_rounded),
                            const SmokedGlassPopoverMenuItem(value: 'settings', label: 'Settings', icon: Icons.settings_rounded, dividerBefore: true),
                          ],
                          onSelected: (value) {
                            if (value == 'shuffle' && visible.isNotEmpty) {
                              final shuffled = List<_MediaFile>.of(visible)..shuffle(math.Random());
                              _openMedia(shuffled.first, shuffled);
                            }
                            if (value == 'select') {
                              setState(() {
                                _selectionMode = true;
                                _selectedTrackKeys.clear();
                              });
                            }
                            if (value == 'scan' && !_loading) _scan(refresh: true);
                            if (value == 'settings') {
                              Navigator.of(context).push(MaterialPageRoute<void>(
                                builder: (_) => const SettingsScreen(),
                              ));
                            }
                          },
                          child: SizedBox(
                            width: 36,
                            height: 36,
                            child: Center(child: Icon(Icons.more_horiz_rounded, size: 18, color: foreground)),
                          ),
                        ),
                        ]),
                      ),
                    ),
                  ),
                if (_selectionMode)
                  Padding(
                    padding: const EdgeInsets.only(left: 8),
                    child: LiquidGlassSurface(
                      radius: BorderRadius.circular(22),
                      refractive: true,
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Padding(
                          padding: const EdgeInsets.only(left: 10),
                          child: Text('${_selectedTrackKeys.length} selected', style: const TextStyle(color: Colors.white, fontSize: 12)),
                        ),
                        IconButton(
                          tooltip: 'Done selecting',
                          onPressed: () => setState(() {
                            _selectionMode = false;
                            _selectedTrackKeys.clear();
                          }),
                          icon: const Icon(Icons.close_rounded, size: 18, color: Colors.white),
                        ),
                      ]),
                    ),
                  ),
              ]),
            ),
          ]),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => _isMusic ? _musicScreen(context) : _buildVideoScreen(context);

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
    this.onBackHandlerChanged,
    super.key,
  });

  final ServerApi api;
  final MediaLibraryType type;
  final bool showSearch;
  final VoidCallback? onHome;
  final ValueChanged<VoidCallback?>? onBackHandlerChanged;

  @override
  State<MediaBrowserScreen> createState() => _MediaBrowserScreenState();
}

class _MusicActionPill extends StatelessWidget {
  const _MusicActionPill({required this.label, required this.icon, required this.onTap, this.primary = false});
  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final bool primary;
  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Material(
          color: primary ? const Color(0x33536DFE) : (dark ? Colors.white.withValues(alpha: 0.08) : Colors.white.withValues(alpha: 0.75)),
          child: InkWell(
            onTap: onTap,
            child: Container(
              height: 44,
              alignment: Alignment.center,
              decoration: BoxDecoration(borderRadius: BorderRadius.circular(24),
                border: Border.all(color: primary ? const Color(0x66536DFE) : Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.5))),
              child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                Icon(icon, size: 19, color: primary ? const Color(0xFF8C9EFF) : Theme.of(context).colorScheme.onSurface),
                const SizedBox(width: 7),
                Text(label, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

class _MusicEqualizer extends StatefulWidget {
  const _MusicEqualizer();
  @override
  State<_MusicEqualizer> createState() => _MusicEqualizerState();
}

class _MusicEqualizerState extends State<_MusicEqualizer> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 650))..repeat();
  @override
  void dispose() { _controller.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _controller,
    builder: (context, _) => Row(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.end, children: [
      for (var i = 0; i < 4; i++)
        Container(
          width: 3, height: 5 + 12 * (0.5 + 0.5 * math.sin((_controller.value * math.pi * 2) + i * 1.35)),
          margin: const EdgeInsets.symmetric(horizontal: 1),
          decoration: BoxDecoration(color: const Color(0xFF536DFE), borderRadius: BorderRadius.circular(3)),
        ),
    ]),
  );
}
