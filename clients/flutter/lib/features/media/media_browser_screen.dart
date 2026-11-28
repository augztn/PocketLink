import 'dart:async';
import 'dart:typed_data';
import 'dart:math' as math;

import 'package:shared_preferences/shared_preferences.dart';
import '../../core/widgets/pocketlink_app_bar.dart';
import '../../core/widgets/pocketlink_scaffold.dart';
import '../../core/widgets/pocketlink_skeleton.dart';
import '../../core/widgets/compact_search_field.dart';
import '../../core/widgets/smoked_glass_popover_menu.dart';

import 'package:dio/dio.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../../core/network/server_api.dart';
import '../../core/storage/home_activity_store.dart';
import 'media_player_screen.dart';
import 'media_library_catalog.dart';
import 'data/media_library_repository.dart';
import 'widgets/video_metadata_label.dart';
import 'widgets/video_duration_badge.dart';
import 'widgets/video_library_header_title.dart';
import 'widgets/video_grid_card.dart';
import 'widgets/video_artwork.dart';
import 'widgets/video_list_tile.dart';
import 'widgets/media_folder_tile.dart';
import 'widgets/media_folder_file_tile.dart';
import 'widgets/media_folder_breadcrumbs.dart';
import 'widgets/media_folder_content.dart';
import 'widgets/music_artwork.dart';
import 'widgets/music_library_header.dart';
import 'music_track_tile.dart';
import 'widgets/music_duration_label.dart';
import 'widgets/media_browser_filter_sheet.dart';
import 'widgets/media_browser_empty_state.dart';
import 'widgets/music_browser_empty_state.dart';
import 'widgets/music_browser_track_list.dart';
import 'persistent_audio_player.dart';
import 'now_playing_overlay_controller.dart';
import '../transfers/transfer_manager_screen.dart';
import '../downloads/download_manager_service.dart';
import 'media_browser_state_store.dart';
import 'discover/imported_playlist_manager_screen.dart';
import '../settings/settings_screen.dart';

class _MediaBrowserScreenState extends State<MediaBrowserScreen> {
  static const _maxDirectories = 10000;
  static const _maxDepth = 24;

  List<MediaFileItem> _media = const [];
  bool _loading = true;
  bool _routeIsCurrent = true;
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
  late final MediaBrowserStateStore _browserState;
  final ScrollController _contentScrollController = ScrollController();
  double _pendingScrollOffset = 0;
  CancelToken? _indexRequestToken;
  Timer? _videoRequestDebounceTimer;
  bool _videoRequestsReady = true;
  bool _openingMedia = false;
  bool _musicMenuOpen = false;
  bool _searchExpanded = false;
  bool _selectionMode = false;
  final Set<String> _selectedTrackKeys = <String>{};
  List<MediaFileItem> _selectedCollectionItems = const [];
  String? _collectionReturnView;
  String? _collectionReturnVolume;
  String? _collectionTitle;

  void _syncBackHandler() {
    final handler = _musicMenuOpen
        ? () => _setMusicMenuOpen(false)
        : _searchExpanded
            ? () => _setSearchExpanded(false)
            : _selectionMode
                ? _clearSelectionMode
                : _libraryView == 'folders' && !_atFolderRoot
                    ? _goUpFolder
                    : _libraryView == 'collection'
                        ? _closeMusicCollection
                        : _isMusic && _libraryView != 'home'
                            ? () => _selectMusicView('home')
                            : null;
    widget.onBackHandlerChanged?.call(handler);
  }

  void _setMusicMenuOpen(bool open) {
    if (_musicMenuOpen == open) return;
    setState(() => _musicMenuOpen = open);
    _syncBackHandler();
  }

  void _clearSelectionMode() {
    if (!_selectionMode) return;
    setState(() {
      _selectionMode = false;
      _selectedTrackKeys.clear();
    });
    _syncBackHandler();
  }

  void _setSearchExpanded(bool expanded) {
    if (_searchExpanded == expanded) return;
    setState(() => _searchExpanded = expanded);
    _syncBackHandler();
  }
  Set<String> _favoriteKeys = <String>{};
  final Map<String, Future<Uint8List?>> _musicArtworkCache = {};
  final Map<String, CancelToken> _videoThumbnailTokens = {};
  final Map<String, CancelToken> _videoMetadataTokens = {};
  final Map<String, Future<int>> _musicDurationRequests = {};

  bool get _isMusic => widget.type == MediaLibraryType.music;
  String get _title => _isMusic ? 'Music' : 'Videos';
  List<String> get _roots => _isMusic ? const ['Music'] : const [''];

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final isCurrent = ModalRoute.of(context)?.isCurrent ?? true;
    if (_routeIsCurrent == isCurrent) return;
    _routeIsCurrent = isCurrent;
    if (!isCurrent) {
      _indexRequestToken?.cancel('Media library route became inactive');
      _videoRequestDebounceTimer?.cancel();
      _videoRequestsReady = false;
      _cancelAllVideoRequests();
    } else if (mounted) {
      _videoRequestsReady = true;
      if (_loading) {
        unawaited(_scan());
      } else {
        setState(() {});
      }
    }
  }

  @override
  void initState() {
    super.initState();
    _stateKey = widget.api.baseUrl;
    _browserState = Provider.of<MediaBrowserStateStore>(context, listen: false);
    final saved = _browserState.stateFor(_stateKey, widget.type.name);
    _selectedVolume = saved.selectedVolume;
    _libraryView = widget.initialView ?? saved.view;
    if (_isMusic && widget.initialView == null && _libraryView == 'all') {
      _libraryView = 'home';
    }
    _searchQuery = widget.initialSearchQuery ?? ''; 
    _searchController.text = _searchQuery;
    _searchExpanded = _searchQuery.isNotEmpty;
    _layoutMode = saved.layoutMode;
    _sortBy = widget.initialSortBy ?? saved.sortBy;
    _currentFolderPath = saved.folderPath;
    _pendingScrollOffset = saved.scrollOffset;
    _contentScrollController.addListener(_onContentScroll);
    if (_isMusic) {
      HomeActivityStore.instance.addListener(_onHomeActivityChanged);
      unawaited(HomeActivityStore.instance.load());
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _syncBackHandler();
    });
    _loadFavorites();
    _scan();
  }

  void _onHomeActivityChanged() {
    if (mounted && _isMusic) setState(() {});
  }

  void _restoreScrollOffset() {
    if (!mounted || !_contentScrollController.hasClients || _pendingScrollOffset <= 0) return;
    _contentScrollController.jumpTo(_pendingScrollOffset.clamp(0, _contentScrollController.position.maxScrollExtent).toDouble());
    _pendingScrollOffset = 0;
  }

  void _saveState({String? folderPath, bool clearVolume = false}) {
    final current = _browserState.stateFor(_stateKey, widget.type.name);
    _browserState.update(_stateKey, widget.type.name, current.copyWith(
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

  void _onContentScroll() {
    _saveScrollOffset();
    if (_isMusic || !_routeIsCurrent) return;
    if (_videoRequestsReady) {
      _videoRequestsReady = false;
      _cancelAllVideoRequests();
    }
    _videoRequestDebounceTimer?.cancel();
    _videoRequestDebounceTimer = Timer(
      const Duration(milliseconds: 160),
      () {
        if (!mounted || !_routeIsCurrent) return;
        setState(() => _videoRequestsReady = true);
      },
    );
  }

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

  bool _isMedia(FileEntry item, {String? mime}) =>
      MediaLibraryCatalog.isMedia(item, type: widget.type, mime: mime);

  Future<MediaLibraryResult> _readIndexedMedia({
    CancelToken? cancelToken,
  }) =>
      MediaLibraryRepository(
        api: widget.api,
        type: widget.type,
      ).readIndexedMedia(
        query: _searchQuery,
        cancelToken: cancelToken,
        shouldContinue: () => mounted && _routeIsCurrent,
      );

  Future<void> _refreshMusic() async {
    if (_loading) return;
    await _scan(refresh: true);
  }

  Future<void> _scan({bool refresh = false}) async {
    if (!mounted || !_routeIsCurrent) return;
    _indexRequestToken?.cancel('Superseded media index request');
    final requestToken = CancelToken();
    _indexRequestToken = requestToken;
    try {
      if (refresh) {
        widget.api.invalidateDirectoryCache();
        try {
          await widget.api.startMediaIndexScan(cancelToken: requestToken);
          if (!mounted || requestToken.isCancelled || !_routeIsCurrent) return;
        } on DioException {
          if (requestToken.isCancelled || !_routeIsCurrent) return;
          await _scanLegacy(refresh: refresh);
          return;
        }
      }
      if (!mounted || requestToken.isCancelled || !_routeIsCurrent) return;
      _cancelAllVideoRequests();
      widget.api.clearMediaCache();
      _musicDurationRequests.clear();
      setState(() {
        _loading = true;
        _error = null;
        if (!refresh) _media = const [];
        _scannedDirectories = 0;
        _skippedDirectories = 0;
        _scanLocation = '';
      });

      var result = await _readIndexedMedia(cancelToken: requestToken);
      if (!mounted || requestToken.isCancelled || !_routeIsCurrent) return;
      var found = result.items;
      var status = result.status;
      setState(() {
        _media = List.unmodifiable(found);
        _scannedDirectories = status.scannedDirectories;
        _skippedDirectories = status.skipped;
        _scanLocation = _indexLocation(status);
      });

      final wasScanning = status.isScanning;
      while (mounted && _routeIsCurrent && !requestToken.isCancelled &&
          status.isScanning) {
        await Future<void>.delayed(const Duration(seconds: 2));
        if (!mounted || requestToken.isCancelled || !_routeIsCurrent) return;
        status = await widget.api.mediaIndexStatus(cancelToken: requestToken);
        if (!mounted || requestToken.isCancelled || !_routeIsCurrent) return;
        setState(() {
          _scannedDirectories = status.scannedDirectories;
          _skippedDirectories = status.skipped;
          _scanLocation = status.isScanning ? _indexLocation(status) : '';
        });
      }
      if (!mounted || requestToken.isCancelled || !_routeIsCurrent) return;
      if (wasScanning && status.state != 'failed') {
        result = await _readIndexedMedia(cancelToken: requestToken);
        if (!mounted || requestToken.isCancelled || !_routeIsCurrent) return;
        found = result.items;
        status = result.status;
      }

      if ((status.state == 'failed' || status.state == 'partial') &&
          found.isEmpty) {
        await _scanLegacy();
        return;
      }
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
    } on DioException {
      if (requestToken.isCancelled || !_routeIsCurrent) return;
      await _scanLegacy(refresh: refresh);
    } catch (_) {
      if (requestToken.isCancelled || !_routeIsCurrent) return;
      await _scanLegacy(refresh: refresh);
    } finally {
      if (identical(_indexRequestToken, requestToken)) {
        _indexRequestToken = null;
      }
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
    _cancelAllVideoRequests();
    widget.api.clearMediaCache();
    _musicDurationRequests.clear();
    setState(() {
      _loading = true;
      _error = null;
      if (!refresh) _media = const [];
      _scannedDirectories = 0;
      _skippedDirectories = 0;
      _scanLocation = '';
    });

    final found = <MediaFileItem>[];
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
            found.add(MediaFileItem(
              entry: item,
              path: itemPath,
              volume: current.volume,
            ));
          }        }

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
    }  }

  Future<void> _openMedia(MediaFileItem media, List<MediaFileItem> queueItems) async {
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

  String _sourceLabel(MediaFileItem media) =>
      media.volume == null ? 'Internal storage' : 'USB / OTG';

  String _fileExtension(MediaFileItem media) {
    final dot = media.entry.name.lastIndexOf('.');
    return dot < 0 ? '' : media.entry.name.substring(dot + 1).toUpperCase();
  }

  String _displayTitle(MediaFileItem media) {
    final taggedTitle = media.title?.trim();
    if (taggedTitle != null && taggedTitle.isNotEmpty) return taggedTitle;
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


  MediaLibraryCatalog get _catalog => MediaLibraryCatalog(
        type: widget.type,
        selectedVolume: _selectedVolume,
        currentFolderPath: _currentFolderPath,
        sortBy: _sortBy,
      );

  List<MediaFolderGroup> _foldersAtCurrentLevel(List<MediaFileItem> items) =>
      _catalog.foldersAtCurrentLevel(items);

  List<MediaFileItem> _filesAtCurrentLevel(List<MediaFileItem> items) =>
      _catalog.filesAtCurrentLevel(items);

  List<MediaFileItem> _sortMedia(List<MediaFileItem> items) =>
      _catalog.sortMedia(items);

  CancelToken _requestToken(
    Map<String, CancelToken> tokens,
    String key,
  ) {
    final existing = tokens[key];
    if (existing != null && !existing.isCancelled) return existing;
    final token = CancelToken();
    tokens[key] = token;
    return token;
  }

  Widget _buildVideoArtwork(MediaFileItem media, {required BoxFit fit}) {
    if (!_routeIsCurrent || !_videoRequestsReady) {
      return VideoArtwork(future: Future<Uint8List?>.value(null), fit: fit);
    }
    final key = _favoriteKey(media);
    final token = _requestToken(_videoThumbnailTokens, key);
    return VideoArtwork(
      future: widget.api.videoThumbnail(
        media.path,
        volume: media.volume,
        cancelToken: token,
      ),
      fit: fit,
    );
  }

  Future<VideoMetadata?> _videoMetadataFor(MediaFileItem media) {
    if (!_routeIsCurrent || !_videoRequestsReady) {
      return Future<VideoMetadata?>.value(null);
    }
    final key = _favoriteKey(media);
    final token = _requestToken(_videoMetadataTokens, key);
    return widget.api.videoMetadata(
      media.path,
      volume: media.volume,
      cancelToken: token,
    );
  }

  void _releaseVideoRequests(MediaFileItem media) {
    widget.api.cancelMediaRequestsFor(media.path, volume: media.volume);
    final key = _favoriteKey(media);
    final thumbnail = _videoThumbnailTokens.remove(key);
    if (thumbnail != null && !thumbnail.isCancelled) {
      thumbnail.cancel('Video card left the viewport');
    }
    final metadata = _videoMetadataTokens.remove(key);
    if (metadata != null && !metadata.isCancelled) {
      metadata.cancel('Video card left the viewport');
    }
  }

  void _cancelAllVideoRequests() {
    for (final media in _media) {
      widget.api.cancelMediaRequestsFor(media.path, volume: media.volume);
    }
    for (final media in _videoThumbnailTokens.keys.toList()) {
      final token = _videoThumbnailTokens.remove(media);
      if (token != null && !token.isCancelled) {
        token.cancel('Video library is closing');
      }
    }
    for (final media in _videoMetadataTokens.keys.toList()) {
      final token = _videoMetadataTokens.remove(media);
      if (token != null && !token.isCancelled) {
        token.cancel('Video library is closing');
      }
    }
    // Music duration metadata uses the same request-token map. Clear its
    // memoized futures too, so reopening the route can request them again.
    _musicDurationRequests.clear();
  }

  Widget _videoMetadataLabel(MediaFileItem media) => VideoMetadataLabel(
        future: _videoMetadataFor(media),
        formatDuration: _formatDuration,
      );

  String _formatDuration(int milliseconds) {
    final totalSeconds = milliseconds ~/ 1000;
    final hours = totalSeconds ~/ 3600;
    final minutes = (totalSeconds % 3600) ~/ 60;
    final seconds = totalSeconds % 60;
    final two = (int value) => value.toString().padLeft(2, '0');
    return hours > 0 ? '${hours}:${two(minutes)}:${two(seconds)}' : '${minutes}:${two(seconds)}';
  }
  Widget _videoDurationBadge(MediaFileItem media) => VideoDurationBadge(
        future: _videoMetadataFor(media),
        formatDuration: _formatDuration,
      );

  Future<void> _downloadMedia(
    BuildContext context,
    MediaFileItem media, {
    required String failureMessage,
  }) async {
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
          SnackBar(content: Text(failureMessage)),
        );
      }
    }
  }

  Widget _buildVideoGrid(List<MediaFileItem> items) {
    return GridView.builder(
      controller: _contentScrollController,
      padding: EdgeInsets.fromLTRB(
        12,
        ((_searchExpanded && widget.showSearch) || _libraryView == 'folders')
            ? 8
            : LayoutInsetsScope.of(context).topClearance,
        12,
        LayoutInsetsScope.of(context).bottomClearance,
      ),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 12,
        mainAxisSpacing: 14,
        childAspectRatio: 0.88,
      ),
      itemCount: items.length,
      itemBuilder: (context, index) {
        final media = items[index];
        final extension = media.entry.name.split('.').last.toUpperCase();
        final favorite = _favoriteKeys.contains(_favoriteKey(media));
        return _VideoRequestLifecycle(
          key: ValueKey(_favoriteKey(media)),
          onDispose: () => _releaseVideoRequests(media),
          child: VideoGridCard(
            title: media.entry.name,
            extension: extension,
            sizeLabel: _formatBytes(media.entry.size),
            favorite: favorite,
            artwork: _buildVideoArtwork(media, fit: BoxFit.cover),
            durationBadge: _videoDurationBadge(media),
            metadataLabel: _videoMetadataLabel(media),
            onOpen: () => _openMedia(media, items),
            onToggleFavorite: () => _toggleFavorite(media),
            onDownload: () => _downloadMedia(
              context,
              media,
              failureMessage: 'Could not add this video to Downloads.',
            ),
          ),
        );
      },
    );
  }

  Widget _buildVideoList(List<MediaFileItem> items) {
    return ListView.separated(
      controller: _contentScrollController,
      padding: EdgeInsets.fromLTRB(
        12,
        ((_searchExpanded && widget.showSearch) || _libraryView == 'folders')
            ? 8
            : LayoutInsetsScope.of(context).topClearance,
        12,
        LayoutInsetsScope.of(context).bottomClearance,
      ),
      itemCount: items.length,
      separatorBuilder: (_, __) => const SizedBox(height: 4),
      itemBuilder: (context, index) {
        final media = items[index];
        final extension = media.entry.name.split('.').last.toUpperCase();
        return _VideoRequestLifecycle(
          key: ValueKey(_favoriteKey(media)),
          onDispose: () => _releaseVideoRequests(media),
          child: VideoListTile(
            title: media.entry.name,
            extension: extension,
            sizeLabel: _formatBytes(media.entry.size),
            sourceLabel: _sourceLabel(media),
            artwork: _buildVideoArtwork(media, fit: BoxFit.cover),
            metadataLabel: _videoMetadataLabel(media),
            onOpen: () => _openMedia(media, items),
            onDownload: () => _downloadMedia(
              context,
              media,
              failureMessage: 'Could not add this video to Downloads.',
            ),
          ),
        );
      },
    );
  }

  Widget _buildFolders(List<MediaFileItem> items) {
    final folders = _foldersAtCurrentLevel(items);
    final files = _sortMedia(_filesAtCurrentLevel(items));
    return MediaFolderContent(
      breadcrumbs: MediaFolderBreadcrumbs(
        currentPath: _currentFolderPath,
        volumeLabel: _selectedVolume == null ? null : _volumeName(_selectedVolume),
        onAllStorage: () {
          setState(() {
            _currentFolderPath = '';
            _selectedVolume = null;
          });
          _pendingScrollOffset = 0;
          _saveState(folderPath: '', clearVolume: true);
          if (_contentScrollController.hasClients) {
            _contentScrollController.jumpTo(0);
          }
          _syncBackHandler();
        },
        onVolumeRoot: () {
          setState(() {
            _currentFolderPath =
                _selectedVolume == 'internal' && _isMusic ? 'Music' : '';
          });
          _pendingScrollOffset = 0;
          _saveState(folderPath: _currentFolderPath);
          if (_contentScrollController.hasClients) {
            _contentScrollController.jumpTo(0);
          }
          _syncBackHandler();
        },
        onFolder: (path) {
          setState(() => _currentFolderPath = path);
          _saveState(folderPath: path);
          if (_contentScrollController.hasClients) {
            _contentScrollController.jumpTo(0);
          }
          _syncBackHandler();
        },
      ),
      controller: _contentScrollController,
      physics: _isMusic ? const AlwaysScrollableScrollPhysics() : null,
      padding: EdgeInsets.fromLTRB(
        12,
        _isMusic
            ? 8
            : ((_searchExpanded && widget.showSearch) ||
                    _libraryView == 'folders')
                ? 8
                : LayoutInsetsScope.of(context).topClearance,
        12,
        LayoutInsetsScope.of(context).bottomClearance,
      ),
      children: [
        for (final folder in folders)
          MediaFolderTile(
            title: folder.name,
            subtitle:
                '${_countLabel(folder.items.length, _isMusic ? 'track' : 'video', _isMusic ? 'tracks' : 'videos')} · ${_volumeName(folder.volume)}',
            onTap: () {
              setState(() {
                _selectedVolume = folder.volume ?? 'internal';
                _currentFolderPath = folder.path;
              });
              _pendingScrollOffset = 0;
              _saveState(folderPath: folder.path);
              if (_contentScrollController.hasClients) {
                _contentScrollController.jumpTo(0);
              }
              _syncBackHandler();            },
          ),
        for (final media in files)
          MediaFolderFileTile(
            title: _isMusic ? _displayTitle(media) : media.entry.name,
            subtitle:
                '${_isMusic && _fileExtension(media).isNotEmpty ? '${_fileExtension(media)} · ' : ''}${_formatBytes(media.entry.size)} · ${_volumeName(media.volume)}',
            isMusic: _isMusic,
            onTap: () => _openMedia(media, files),
          ),
      ],
    );
  }

  @override
  void dispose() {
    widget.onBackHandlerChanged?.call(null);
    if (_isMusic) HomeActivityStore.instance.removeListener(_onHomeActivityChanged);
    _saveState();
    _indexRequestToken?.cancel('Media library disposed');
    _videoRequestDebounceTimer?.cancel();
    _cancelAllVideoRequests();
    _searchController.dispose();
    _contentScrollController.removeListener(_onContentScroll);
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
        } else if (_libraryView == 'collection') {
          _closeMusicCollection();
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
          leading: IconButton(
            tooltip: 'Back',
            onPressed: () => Navigator.of(context).maybePop(),
            icon: const Icon(Icons.arrow_back_rounded),
          ),
          leadingWidth: 56,
          title: TitleDropdownPopover<String>(
tooltip: 'Choose video view',
            onOpenChanged: _setMusicMenuOpen,
            items: [
              SmokedGlassPopoverMenuItem(
                value: 'all',
                label: 'All Videos',
                icon: Icons.video_library_rounded,
                trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                  Text('${visibleMedia.length}', style: const TextStyle(fontFamily: 'monospace', fontSize: 12, color: Color(0xFFA1A7B3))),
                  const SizedBox(width: 8),
                  SizedBox(width: 20, child: _libraryView == 'all' ? const Icon(Icons.check_rounded, size: 18) : null),
                ]),
              ),
              SmokedGlassPopoverMenuItem(
                value: 'folders',
                label: 'Folders',
                icon: Icons.folder_rounded,
                trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                  Text('$folderCount', style: const TextStyle(fontFamily: 'monospace', fontSize: 12, color: Color(0xFFA1A7B3))),
                  const SizedBox(width: 8),
                  SizedBox(width: 20, child: _libraryView == 'folders' ? const Icon(Icons.check_rounded, size: 18) : null),
                ]),
              ),
              SmokedGlassPopoverMenuItem(
                value: 'favorites',
                label: 'Favorites',
                icon: Icons.favorite_rounded,
                trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                  Text('$favoritesCount', style: const TextStyle(fontFamily: 'monospace', fontSize: 12, color: Color(0xFFA1A7B3))),
                  const SizedBox(width: 8),
                  SizedBox(width: 20, child: _libraryView == 'favorites' ? const Icon(Icons.check_rounded, size: 18) : null),
                ]),
              ),
            ],            onSelected: (value) {
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
            child: VideoLibraryHeaderTitle(
              title: headerTitle,
              subtitle:
                  _countLabel(visibleMedia.length, 'video', 'videos') +
                  ' • ${_selectedVolume == null ? 'All storage' : _volumeName(_selectedVolume)}'
                  '${_scannedDirectories > 0 ? ' • $_scannedDirectories scanned' : ''}'
                  '${_skippedDirectories > 0 ? ' · $_skippedDirectories skipped' : ''}'
                  '${_loading && _scanLocation.isNotEmpty ? ' · $_scanLocation' : ''}',
              menuOpen: _musicMenuOpen,
              titleColor: titleColor,
            )
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
            SizedBox(height: LayoutInsetsScope.of(context).topClearance),
          if (_searchExpanded && widget.showSearch)
            Padding(padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: CompactSearchField(controller: _searchController,
                hintText: 'Search videos or folders',
                onChanged: (value) => setState(() => _searchQuery = value))),
          if (_loading && _media.isNotEmpty) const LinearProgressIndicator(minHeight: 2),
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
                    ? isFolderView
                        ? PocketLinkSkeleton.fileList(
                            padding: EdgeInsets.fromLTRB(
                              12,
                              8,
                              12,
                              LayoutInsetsScope.of(context).bottomClearance,
                            ),
                          )
                        : _layoutMode == 'grid'
                            ? PocketLinkSkeleton.videoGrid(
                                padding: EdgeInsets.fromLTRB(
                                  12,
                                  widget.showSearch && _searchExpanded
                                      ? 8
                                      : LayoutInsetsScope.of(context).topClearance,
                                  12,
                                  LayoutInsetsScope.of(context).bottomClearance,
                                ),
                              )
                            : PocketLinkSkeleton.videoList(
                                padding: EdgeInsets.fromLTRB(
                                  12,
                                  widget.showSearch && _searchExpanded
                                      ? 8
                                      : LayoutInsetsScope.of(context).topClearance,
                                  12,
                                  LayoutInsetsScope.of(context).bottomClearance,
                                ),
                              )
                    : visibleMedia.isEmpty
                        ? MediaBrowserEmptyState(
                            icon: _isMusic
                                ? Icons.library_music_outlined
                                : Icons.video_library_outlined,
                            message: _media.isEmpty
                                ? 'No ${_title.toLowerCase()} found. Check internal storage and granted USB/OTG folders, then scan again.'
                                : 'No matching files. Try another search or storage source.',
                            onScan: _scan,
                            showScanAction: !_loading,
                          )
                        : isFolderView
                            ? _buildFolders(visibleMedia)
                            : !_isMusic && _layoutMode == 'grid'
                                ? _buildVideoGrid(visibleMedia)
                                : !_isMusic
                                    ? _buildVideoList(visibleMedia)
                                    : ListView.builder(
                                        controller: _contentScrollController,
                                        padding: EdgeInsets.fromLTRB(12, ((_searchExpanded && widget.showSearch) || _libraryView == 'folders') ? 8 : LayoutInsetsScope.of(context).topClearance, 12, LayoutInsetsScope.of(context).bottomClearance),
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

  String _favoriteKey(MediaFileItem media) => '${media.volume ?? 'internal'}:${media.path}';

  Future<void> _loadFavorites() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() => _favoriteKeys = prefs.getStringList(_favoritesPreferenceKey)?.toSet() ?? <String>{});
  }

  Future<void> _toggleFavorite(MediaFileItem media) async {
    final key = _favoriteKey(media);
    final next = Set<String>.of(_favoriteKeys);
    if (!next.add(key)) next.remove(key);
    setState(() => _favoriteKeys = next);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_favoritesPreferenceKey, next.toList()..sort());
  }

  String _trackArtist(MediaFileItem media) {
    final taggedArtist = media.artist?.trim();
    if (taggedArtist != null && taggedArtist.isNotEmpty) return taggedArtist;
    final parts = media.path.split('/')..removeLast();
    return parts.isEmpty ? _sourceLabel(media) : parts.last;
  }

  Future<Uint8List?> _loadTrackArtwork(MediaFileItem media) =>
      _musicArtworkCache.putIfAbsent(_favoriteKey(media), () => _fetchTrackArtwork(media));

  Future<Uint8List?> _fetchTrackArtwork(MediaFileItem media) async {
    if (media.artworkAvailable && media.volume == null) {
      final embedded = await widget.api.musicArtwork(media.path);
      if (embedded != null && embedded.isNotEmpty) return embedded;
    }
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
    }    return null;
  }

  Future<void> _showMusicFilters() async {
    final selected =
        await showModalBottomSheet<({String? volume, String sort})>(
      context: context,
      useRootNavigator: true,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => MediaBrowserFilterSheet(
        volumes: _volumes,
        initialVolume: _selectedVolume,
        initialSort: _sortBy,
      ),
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

  Widget _musicArtwork(MediaFileItem media, {bool playing = false}) =>
      MusicArtwork(future: _loadTrackArtwork(media), playing: playing);

  Future<void> _queueTrack(MediaFileItem media, {required bool playNext}) async {
    final player = PersistentAudioPlayer.instance;
    final item = MediaQueueItem(title: media.entry.name, path: media.path, volume: media.volume, size: media.entry.size);
    if (player.isActive && player.isMusic) {
      await player.enqueue(item, playNext: playNext);
    } else {
      await player.openQueue(api: widget.api, queue: [item], initialIndex: 0, isMusic: true);
    }
  }

  void _toggleTrackSelection(MediaFileItem media) {
    final key = _favoriteKey(media);
    setState(() {
      if (!_selectedTrackKeys.add(key)) _selectedTrackKeys.remove(key);
    });
  }

  String _musicDurationPreferenceKey(MediaFileItem media) {
    final identity =
        '$_stateKey|${_favoriteKey(media)}|${media.entry.size}|${media.entry.modified}';
    var hash = 0x811c9dc5;
    for (final unit in identity.codeUnits) {
      hash ^= unit;
      hash = (hash * 0x01000193) & 0xffffffff;
    }
    return 'pocketlink.music.duration.${hash.toRadixString(16)}';
  }

  Future<int> _musicDurationFor(MediaFileItem media) {
    final key = _favoriteKey(media);
    return _musicDurationRequests.putIfAbsent(key, () async {
      if ((media.durationMs ?? 0) > 0) return media.durationMs!;
      final preferences = await SharedPreferences.getInstance();
      final preferenceKey = _musicDurationPreferenceKey(media);
      final cached = preferences.getInt(preferenceKey);
      if (cached != null && cached > 0) return cached;
      if (!_routeIsCurrent || !_videoRequestsReady) return 0;

      // Duration reads are screen-owned and cancellable. Previously these
      // requests had no token, so a route change left them queued behind
      // metadata endpoint 404s.
      final token = _requestToken(_videoMetadataTokens, key);
      final metadata = await widget.api.videoMetadata(
        media.path,
        volume: media.volume,
        cancelToken: token,
      );
      final durationMs = metadata?.durationMs ?? 0;
      if (durationMs > 0 && !token.isCancelled) {
        await preferences.setInt(preferenceKey, durationMs);
      }
      return durationMs;
    });
  }

  Widget _musicDurationLabel(MediaFileItem media) => MusicDurationLabel(
        future: _musicDurationFor(media),
        formatDuration: _formatDuration,
      );

  Widget _musicTrackTile(MediaFileItem media, List<MediaFileItem> queueItems) {
    final player = PersistentAudioPlayer.instance;
    final isPlaying = player.currentItem?.path == media.path &&
        player.currentItem?.volume == media.volume &&
        player.isMusic && player.isPlaying;
    final key = _favoriteKey(media);
    return MusicTrackTile(
      title: _displayTitle(media),
      artist: _trackArtist(media),
      artwork: _musicArtwork(media, playing: isPlaying),
      duration: _musicDurationLabel(media),
      playing: isPlaying,
      selected: _selectedTrackKeys.contains(key),
      favorite: _favoriteKeys.contains(key),
      selectionMode: _selectionMode,
      onTap: () => _selectionMode
          ? _toggleTrackSelection(media)
          : _openMedia(media, queueItems),
      onLongPress: () {
        if (!_selectionMode) {
          setState(() => _selectionMode = true);
          _syncBackHandler();
        }
        _toggleTrackSelection(media);
      },
      onToggleFavorite: () => _toggleFavorite(media),
      onPlayNext: () => _queueTrack(media, playNext: true),
      onQueue: () => _queueTrack(media, playNext: false),
      onDownload: () => _downloadMedia(
        context,
        media,
        failureMessage: 'Could not add this track to Downloads.',
      ),
      onDelete: () => _deleteMusicFile(media),
    );
  }

  Future<void> _deleteMusicFile(MediaFileItem media) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete permanently?'),
        content: Text(
          '“${media.entry.name}” will be permanently deleted from '
          '${_volumeName(media.volume)}. This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(dialogContext).colorScheme.error,
            ),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Delete permanently'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final key = _favoriteKey(media);
    try {
      await widget.api.deleteMediaFile(media.path, volume: media.volume);
    } on DioException {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Could not delete this file. Check that the storage is connected and writable.',
          ),
        ),
      );
      return;
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not delete this music file.')),
      );
      return;
    }

    final favorites = Set<String>.of(_favoriteKeys)..remove(key);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(
        _favoritesPreferenceKey,
        favorites.toList()..sort(),
      );
    } catch (_) {
      // File deletion has succeeded; a favorites persistence failure must not
      // report the destructive operation as failed or leave the row visible.
    }

    final player = PersistentAudioPlayer.instance;
    final current = player.currentItem;
    if (current?.path == media.path && current?.volume == media.volume) {
      unawaited(player.dismiss());
    }

    _musicArtworkCache.remove(key);
    _musicDurationRequests.remove(key);
    if (!mounted) return;
    setState(() {
      _media = List.unmodifiable(
        _media.where((item) => _favoriteKey(item) != key),
      );
      _selectedCollectionItems = List.unmodifiable(
        _selectedCollectionItems.where((item) => _favoriteKey(item) != key),
      );
      _favoriteKeys = favorites;
      _selectedTrackKeys.remove(key);
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Deleted ${media.entry.name}')),
    );
    unawaited(_scan(refresh: true));
  }

  void _selectMusicView(String value) {
    if (value == 'playlists') {
      unawaited(_openImportedPlaylists());
      return;
    }
    setState(() {
      if (_libraryView == 'collection') {
        _selectedVolume = _collectionReturnVolume;
      }
      _libraryView = value;
      _selectedCollectionItems = const [];
      _collectionReturnView = null;
      _collectionReturnVolume = null;
      _collectionTitle = null;
      if (value == 'home') _selectedVolume = null;
      _currentFolderPath = value == 'folders' && _selectedVolume == 'internal'
          ? 'Music'
          : '';
    });
    _syncBackHandler();
    _pendingScrollOffset = 0;
    _saveState(folderPath: _currentFolderPath);
    if (_contentScrollController.hasClients) _contentScrollController.jumpTo(0);
  }

  Future<void> _openImportedPlaylists() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => ImportedPlaylistManagerScreen(api: widget.api),
      ),
    );
  }

  List<MediaFileItem> _recentlyPlayedTracks(List<MediaFileItem> source) {
    final recent = HomeActivityStore.instance.itemsForServer(_stateKey)
        .where((item) => item.kind == 'track')
        .toList(growable: false);
    final result = <MediaFileItem>[];
    final seen = <String>{};
    for (final activity in recent) {
      final key = '${activity.volume ?? 'internal'}:${activity.path}';
      if (!seen.add(key)) continue;
      for (final track in source) {
        if (track.path == activity.path &&
            (track.volume ?? 'internal') == (activity.volume ?? 'internal')) {
          result.add(track);
          break;
        }
      }
      if (result.length == 8) break;
    }
    return result;
  }

  List<MediaFileItem> _mostPlayedTracks(List<MediaFileItem> source) {
    final plays = HomeActivityStore.instance.mostPlayedForServer(_stateKey);
    final result = <MediaFileItem>[];
    for (final play in plays) {
      for (final track in source) {
        if (track.path == play.path &&
            (track.volume ?? 'internal') == (play.volume ?? 'internal')) {
          result.add(track);
          break;
        }
      }
      if (result.length == 8) break;
    }
    return result;
  }

  List<MediaFileItem> _recentlyAddedTracks(List<MediaFileItem> source) {
    final result = source.where((item) =>
      DateTime.tryParse(item.entry.created ?? '') != null).toList();
    result.sort((a, b) {
      final aDate = DateTime.tryParse(a.entry.created!)!;
      final bDate = DateTime.tryParse(b.entry.created!)!;
      return bDate.compareTo(aDate);
    });
    return result.take(8).toList(growable: false);
  }

  List<MediaFileItem> _recentlyUpdatedTracks(List<MediaFileItem> source) {
    final result = List<MediaFileItem>.of(source);
    result.sort((a, b) {
      final aDate = DateTime.tryParse(a.entry.modified);
      final bDate = DateTime.tryParse(b.entry.modified);
      return (bDate?.millisecondsSinceEpoch ?? 0)
          .compareTo(aDate?.millisecondsSinceEpoch ?? 0);
    });
    return result.take(8).toList(growable: false);
  }

  Widget _musicHomeShortcut(String label, IconData icon, String view) {
    return ActionChip(
      avatar: Icon(icon, size: 17, color: const Color(0xFFB8C4FF)),
      label: Text(label),
      onPressed: () => _selectMusicView(view),
      backgroundColor: const Color(0xFF1C1C1E),
      side: BorderSide(color: Colors.white.withValues(alpha: 0.06)),
      labelStyle: const TextStyle(color: Colors.white, fontSize: 12),
      padding: const EdgeInsets.symmetric(horizontal: 5),
    );
  }

  Widget _musicSectionTitle(String title, {String? action, VoidCallback? onAction}) {
    return Padding(
      padding: const EdgeInsets.only(top: 22, bottom: 10),
      child: Row(children: [
        Expanded(child: Text(title,
          style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w700))),
        if (action != null && onAction != null)
          TextButton(onPressed: onAction, child: Text(action)),
      ]),
    );
  }

  Widget _buildMusicHome(List<MediaFileItem> visible) {
    final player = PersistentAudioPlayer.instance;
    final current = player.isMusic && player.isActive ? player.currentItem : null;
    MediaFileItem? currentMedia;
    if (current != null) {
      for (final item in visible) {
        if (item.path == current.path &&
            (item.volume ?? 'internal') == (current.volume ?? 'internal')) {
          currentMedia = item;
          break;
        }
      }
    }
    final recentlyPlayed = _recentlyPlayedTracks(visible);
    final mostPlayed = _mostPlayedTracks(visible);
    final recentlyAdded = _recentlyAddedTracks(visible);
    final recentlyUpdated = _recentlyUpdatedTracks(visible);

    return ListView(
      controller: _contentScrollController,
      physics: const AlwaysScrollableScrollPhysics(),
      padding: EdgeInsets.fromLTRB(16, LayoutInsetsScope.of(context).topClearance + 12,
        16, LayoutInsetsScope.of(context).bottomClearance),
      children: [
        if (current != null)
          Material(
            color: const Color(0xFF1C1C1E),
            borderRadius: BorderRadius.circular(22),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: NowPlayingOverlayController.open,
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Row(children: [
                  if (currentMedia != null)
                    _musicCollectionArtwork(currentMedia, size: 72)
                  else
                    Container(
                      width: 72, height: 72,
                      decoration: BoxDecoration(color: const Color(0xFF292B31), borderRadius: BorderRadius.circular(16)),
                      child: const Icon(Icons.music_note_rounded, color: Colors.white70, size: 30),
                    ),
                  const SizedBox(width: 13),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Text('CONTINUE LISTENING',
                      style: TextStyle(color: Color(0xFFB8C4FF), fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 1)),
                    const SizedBox(height: 5),
                    Text(current.title, maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 3),
                    Text(current.artist?.trim().isNotEmpty == true
                        ? current.artist!
                        : currentMedia == null ? 'PocketLink music' : _trackArtist(currentMedia),
                      maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Color(0xFF9A9DA7), fontSize: 12)),
                  ])),
                  IconButton(
                    tooltip: player.isPlaying ? 'Pause' : 'Play',
                    onPressed: player.togglePlayback,
                    icon: Icon(player.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                      color: Colors.white, size: 27),
                  ),
                ]),
              ),
            ),
          )
        else
          Material(
            color: const Color(0xFF1C1C1E),
            borderRadius: BorderRadius.circular(22),
            child: InkWell(
              onTap: () => _selectMusicView('all'),
              borderRadius: BorderRadius.circular(22),
              child: const Padding(
                padding: EdgeInsets.all(18),
                child: Row(children: [
                  Icon(Icons.headphones_rounded, color: Color(0xFFB8C4FF), size: 30),
                  SizedBox(width: 14),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('Your music, in one place', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700)),
                    SizedBox(height: 4),
                    Text('Choose a song to start listening', style: TextStyle(color: Color(0xFF9A9DA7), fontSize: 12)),
                  ])),
                  Icon(Icons.chevron_right_rounded, color: Colors.white54),
                ]),
              ),
            ),
          ),
        _musicSectionTitle('Browse your library'),
        Wrap(spacing: 8, runSpacing: 2, children: [
          _musicHomeShortcut('Songs', Icons.music_note_rounded, 'all'),
          _musicHomeShortcut('Albums', Icons.album_rounded, 'albums'),
          _musicHomeShortcut('Artists', Icons.person_rounded, 'artists'),
          _musicHomeShortcut('Playlists', Icons.queue_music_rounded, 'playlists'),
          _musicHomeShortcut('Folders', Icons.folder_rounded, 'folders'),
          _musicHomeShortcut('Favourites', Icons.favorite_rounded, 'favorites'),
        ]),
        if (recentlyPlayed.isNotEmpty) ...[
          _musicSectionTitle('Recently played', action: 'See all songs', onAction: () => _selectMusicView('all')),
          for (final track in recentlyPlayed) _musicTrackTile(track, visible),
        ],
        if (mostPlayed.isNotEmpty) ...[
          _musicSectionTitle('Most played'),
          for (final track in mostPlayed) _musicTrackTile(track, visible),
        ],
        if (recentlyAdded.isNotEmpty) ...[
          _musicSectionTitle('Recently added', action: 'See all', onAction: () => _selectMusicView('all')),
          for (final track in recentlyAdded) _musicTrackTile(track, visible),
        ],
        if (recentlyUpdated.isNotEmpty) ...[
          _musicSectionTitle('Recently updated', action: 'See all', onAction: () => _selectMusicView('all')),
          for (final track in recentlyUpdated) _musicTrackTile(track, visible),
        ],
        if (visible.isEmpty && !_loading)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 34),
            child: Column(children: [
              const Icon(Icons.library_music_outlined, color: Color(0xFF777B86), size: 38),
              const SizedBox(height: 10),
              const Text('No music found', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
              const SizedBox(height: 5),
              const Text('Refresh the library or check your storage sources.',
                textAlign: TextAlign.center, style: TextStyle(color: Color(0xFF8E939E), fontSize: 12)),
              TextButton(onPressed: _scan, child: const Text('Refresh library')),
            ]),
          ),
      ],
    );
  }

  Widget _musicCollectionArtwork(MediaFileItem media, {double size = 112}) {
    return FutureBuilder<Uint8List?>(
      future: _loadTrackArtwork(media),
      builder: (context, snapshot) {
        final bytes = snapshot.data;
        return ClipRRect(
          borderRadius: BorderRadius.circular(15),
          child: SizedBox(
            width: size, height: size,
            child: bytes == null
                ? const ColoredBox(color: Color(0xFF252832),
                    child: Center(child: Icon(Icons.music_note_rounded, color: Colors.white54, size: 34)))
                : Image.memory(bytes, fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => const ColoredBox(color: Color(0xFF252832),
                      child: Center(child: Icon(Icons.music_note_rounded, color: Colors.white54, size: 34)))),
          ),
        );
      },
    );
  }

  Widget _buildMusicCollections(List<MediaCollectionGroup> groups, {required bool artists}) {
    if (groups.isEmpty) {
      return ListView(
        controller: _contentScrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          SizedBox(height: 320, child: Center(child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Icon(artists ? Icons.people_outline_rounded : Icons.album_outlined,
                color: const Color(0xFF8E939E), size: 40),
              const SizedBox(height: 10),
              Text(artists ? 'No artist folders found' : 'No album folders found',
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
              const SizedBox(height: 5),
              const Text('Collections use embedded music tags when available, with folder names as a fallback.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Color(0xFF8E939E), fontSize: 12)),
            ]),
          ))),
        ],
      );
    }
    return GridView.builder(
      controller: _contentScrollController,
      padding: EdgeInsets.fromLTRB(16, LayoutInsetsScope.of(context).topClearance + 10,
        16, LayoutInsetsScope.of(context).bottomClearance),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2, crossAxisSpacing: 14, mainAxisSpacing: 18, childAspectRatio: 0.78),
      itemCount: groups.length,
      itemBuilder: (context, index) {
        final group = groups[index];
        final first = group.items.first;
        return Material(
          color: const Color(0xFF15161B),
          borderRadius: BorderRadius.circular(19),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () => _openMusicCollection(group),
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(child: Center(child: _musicCollectionArtwork(first, size: 116))),
                const SizedBox(height: 9),
                Text(group.name, maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w700)),
                const SizedBox(height: 3),
                Text('${group.items.length} tracks',
                  maxLines: 1, style: const TextStyle(color: Color(0xFF9296A1), fontSize: 11)),
              ]),
            ),
          ),
        );
      },
    );
  }

  void _openMusicCollection(MediaCollectionGroup group) {
    setState(() {
      _collectionReturnView = _libraryView;
      _collectionReturnVolume = _selectedVolume;
      _collectionTitle = group.name;
      _selectedCollectionItems = group.items;
      _libraryView = 'collection';
      _selectedVolume = group.volume ?? 'internal';
    });
    _pendingScrollOffset = 0;
    _syncBackHandler();
    if (_contentScrollController.hasClients) _contentScrollController.jumpTo(0);
  }

  void _closeMusicCollection() {
    if (_libraryView != 'collection') return;
    setState(() {
      _libraryView = _collectionReturnView ?? 'albums';
      _selectedCollectionItems = const [];
      _selectedVolume = _collectionReturnVolume;
      _collectionReturnView = null;
      _collectionReturnVolume = null;
      _collectionTitle = null;
    });
    _syncBackHandler();
    if (_contentScrollController.hasClients) _contentScrollController.jumpTo(0);
  }

  Widget _buildMusicContent(List<MediaFileItem> visible) {
    if (_libraryView == 'collection') {
      return RefreshIndicator(
        onRefresh: _refreshMusic,
        child: MusicBrowserTrackList(
          controller: _contentScrollController,
          itemCount: visible.length,
          itemBuilder: (context, index) => _musicTrackTile(visible[index], visible),
          topPadding: LayoutInsetsScope.of(context).topClearance,
          bottomPadding: LayoutInsetsScope.of(context).bottomClearance,
        ),
      );
    }
    if (_libraryView == 'home') {
      return RefreshIndicator(onRefresh: _refreshMusic, child: _buildMusicHome(visible));
    }
    if (_libraryView == 'albums') {
      return RefreshIndicator(onRefresh: _refreshMusic,
        child: _buildMusicCollections(_catalog.albumsFromFolders(visible), artists: false));
    }
    if (_libraryView == 'artists') {
      return RefreshIndicator(onRefresh: _refreshMusic,
        child: _buildMusicCollections(_catalog.artistsFromFolders(visible), artists: true));
    }
    if (_libraryView == 'folders') {
      return Padding(
        padding: EdgeInsets.only(top: LayoutInsetsScope.of(context).topClearance),
        child: RefreshIndicator(
          onRefresh: _refreshMusic,
          child: _loading && _media.isEmpty
              ? PocketLinkSkeleton.fileList(padding: EdgeInsets.fromLTRB(
                  12, 8, 12, LayoutInsetsScope.of(context).bottomClearance))
              : _buildFolders(visible),
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _refreshMusic,
      displacement: 48,
      child: _error != null || (_loading && _media.isEmpty) || visible.isEmpty
          ? MusicBrowserEmptyState(
              error: _error,
              loading: _loading && _media.isEmpty,
              favoritesView: _libraryView == 'favorites',
              onRetry: _scan,
              topPadding: LayoutInsetsScope.of(context).topClearance,
              bottomPadding: LayoutInsetsScope.of(context).bottomClearance,
            )
          : MusicBrowserTrackList(
              controller: _contentScrollController,
              itemCount: visible.length,
              itemBuilder: (context, index) => _musicTrackTile(visible[index], visible),
              topPadding: LayoutInsetsScope.of(context).topClearance,
              bottomPadding: LayoutInsetsScope.of(context).bottomClearance,
            ),
    );
  }

  Widget _musicScreen(BuildContext context) {
    final query = _searchQuery.trim().toLowerCase();
    final matches = _media.where((media) {
      final q = query.isEmpty ||
          media.entry.name.toLowerCase().contains(query) ||
          media.path.toLowerCase().contains(query) ||
          (media.title?.toLowerCase().contains(query) ?? false) ||
          (media.artist?.toLowerCase().contains(query) ?? false) ||
          (media.album?.toLowerCase().contains(query) ?? false);
      final volume = _selectedVolume == null || (_selectedVolume == 'internal' ? media.volume == null : media.volume == _selectedVolume);
      final favorite = _libraryView != 'favorites' || _favoriteKeys.contains(_favoriteKey(media));
      return q && volume && favorite;
    }).toList(growable: false);
    final visible = _sortMedia(
      _libraryView == 'collection' ? _selectedCollectionItems : matches,
    );
    final folderCount = _foldersAtCurrentLevel(_media).length;
    final favoriteCount = _media.where((m) => _favoriteKeys.contains(_favoriteKey(m))).length;
    final top = MediaQuery.paddingOf(context).top;
    final foreground = Theme.of(context).brightness == Brightness.dark
        ? Colors.white
        : const Color(0xFF172033);

    return PopScope(
      canPop: widget.onBackHandlerChanged != null ||
          (!_searchExpanded && !_selectionMode &&
              _libraryView != 'collection' &&
              (_libraryView != 'folders' || _atFolderRoot)),
      onPopInvokedWithResult: (didPop, result) {
        if (didPop || widget.onBackHandlerChanged != null) return;
        if (_searchExpanded) {
          _setSearchExpanded(false);
        } else if (_selectionMode) {
          setState(() {
            _selectionMode = false;
            _selectedTrackKeys.clear();
          });
        } else if (_libraryView == 'collection') {
          _closeMusicCollection();
        } else if (_libraryView == 'folders' && !_atFolderRoot) {
          _goUpFolder();
        }
      },
      child: AnimatedBuilder(
        animation: PersistentAudioPlayer.instance,
        builder: (context, _) => Scaffold(
          extendBodyBehindAppBar: true,          body: Stack(children: [
            Positioned.fill(child: _buildMusicContent(visible)),
            if (_loading && _media.isNotEmpty)              Positioned(
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
            MusicLibraryHeader(
              topInset: top,
              foreground: foreground,
              searchExpanded: _searchExpanded,
              selectionMode: _selectionMode,
              selectedCount: _selectedTrackKeys.length,
              searchController: _searchController,
              searchQuery: _searchQuery,
              menuOpen: _musicMenuOpen,
              subtitle: _libraryView == 'collection'
                  ? '${_collectionTitle ?? 'Collection'} • ${visible.length} tracks'
                  : _libraryView == 'home'
                      ? '${visible.length} tracks • Your collection'
                  : _libraryView == 'albums'
                      ? '${_catalog.albumsFromFolders(visible).length} albums • from tags and folders'
                      : _libraryView == 'artists'
                          ? '${_catalog.artistsFromFolders(visible).length} artists • from tags and folders'
                          : '${visible.length} tracks • ${_selectedVolume == null ? 'All storage' : _volumeName(_selectedVolume)}',
              viewItems: [
                const SmokedGlassPopoverMenuItem(value: 'home', label: 'Music Home', icon: Icons.home_rounded),
                SmokedGlassPopoverMenuItem(value: 'all', label: 'Songs', icon: Icons.music_note_rounded,
                  trailing: Text('${visible.length}', style: const TextStyle(fontFamily: 'monospace', fontSize: 12, color: Color(0xFFA1A7B3)))),
                SmokedGlassPopoverMenuItem(value: 'albums', label: 'Albums', icon: Icons.album_rounded,
                  trailing: Text('${_catalog.albumsFromFolders(visible).length}', style: const TextStyle(fontFamily: 'monospace', fontSize: 12, color: Color(0xFFA1A7B3)))),
                SmokedGlassPopoverMenuItem(value: 'artists', label: 'Artists', icon: Icons.people_alt_rounded,
                  trailing: Text('${_catalog.artistsFromFolders(visible).length}', style: const TextStyle(fontFamily: 'monospace', fontSize: 12, color: Color(0xFFA1A7B3)))),
                const SmokedGlassPopoverMenuItem(value: 'playlists', label: 'Imported playlists', icon: Icons.queue_music_rounded),
                SmokedGlassPopoverMenuItem(value: 'folders', label: 'Folders', icon: Icons.folder_rounded,
                  trailing: Text('${folderCount}', style: const TextStyle(fontFamily: 'monospace', fontSize: 12, color: Color(0xFFA1A7B3)))),
                SmokedGlassPopoverMenuItem(value: 'favorites', label: 'Favourites', icon: Icons.favorite_rounded,
                  trailing: Text('${favoriteCount}', style: const TextStyle(fontFamily: 'monospace', fontSize: 12, color: Color(0xFFA1A7B3)))),
              ],
              onSearchChanged: (value) => setState(() => _searchQuery = value),
              onSearchClearOrClose: () {
                if (_searchQuery.isNotEmpty) {
                  _searchController.clear();
                  setState(() => _searchQuery = '');
                } else {
                  _setSearchExpanded(false);
                }
              },
              onSearchToggle: () => _setSearchExpanded(true),
              onFilter: _showMusicFilters,
              onViewSelected: _selectMusicView,
              onMenuOpenChanged: _setMusicMenuOpen,
              onShuffle: visible.isEmpty
                  ? null
                  : () {
                      final shuffled = List<MediaFileItem>.of(visible)
                        ..shuffle(math.Random());
                      _openMedia(shuffled.first, shuffled);
                    },
              onSelect: () {
                setState(() {
                  _selectionMode = true;
                  _selectedTrackKeys.clear();
                });
                _syncBackHandler();
              },
              onScan: () {
                if (!_loading) _scan(refresh: true);
              },
              onSettings: () {
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const SettingsScreen(),
                  ),
                );
              },
              onHome: () => PocketLinkAppBar.goToDashboard(context),
              onSelectionDone: _clearSelectionMode,
            ),
          ]),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => _isMusic ? _musicScreen(context) : _buildVideoScreen(context);

}

class MediaBrowserScreen extends StatefulWidget {
  const MediaBrowserScreen({
    required this.api,
    required this.type,
    this.showSearch = true,
    this.initialView,
    this.initialSortBy,
    this.initialSearchQuery,
    this.onHome,
    this.onBackHandlerChanged,
    super.key,
  });

  final ServerApi api;
  final MediaLibraryType type;
  final bool showSearch;
  final String? initialView;
  final String? initialSortBy;
  final String? initialSearchQuery;
  final VoidCallback? onHome;
  final ValueChanged<VoidCallback?>? onBackHandlerChanged;

  @override
  State<MediaBrowserScreen> createState() => _MediaBrowserScreenState();
}

class _VideoRequestLifecycle extends StatefulWidget {
  const _VideoRequestLifecycle({
    required this.child,
    required this.onDispose,
    super.key,
  });

  final Widget child;
  final VoidCallback onDispose;

  @override
  State<_VideoRequestLifecycle> createState() => _VideoRequestLifecycleState();
}

class _VideoRequestLifecycleState extends State<_VideoRequestLifecycle> {
  @override
  void dispose() {
    widget.onDispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
