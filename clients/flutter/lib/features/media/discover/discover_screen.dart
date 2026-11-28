import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/network/server_api.dart';
import '../../../core/logging/app_logger.dart';
import '../../../core/settings/app_settings.dart';
import '../../../core/widgets/pocketlink_app_bar.dart';
import '../../../core/widgets/pocketlink_scaffold.dart';
import '../../../core/widgets/smoked_glass_popover_menu.dart';
import '../../../core/widgets/pocketlink_section_header.dart';
import '../data/media_library_repository.dart';
import '../media_library_catalog.dart';
import '../../../core/navigation/pocketlink_navigation.dart';
import '../now_playing_overlay_controller.dart';
import '../music_library_screen.dart';
import 'imported_playlist_manager_screen.dart';
import '../playlist_import_service.dart';
import '../persistent_audio_player.dart';
import 'discover_models.dart';
import 'discover_service.dart';
import 'discover_cache.dart';
import 'discover_thumbnail_cache.dart';
import 'discover_recently_played_store.dart';
import 'discover_speed_dial_store.dart';
import 'discover_home_feed_store.dart';
import 'discover_moods_screen.dart';

class _DiscoverShelf {
  const _DiscoverShelf(this.title, this.tracks, {this.items = const []});
  final String title;
  final List<DiscoverTrack> tracks;
  final List<DiscoverHomeItem> items;
}

class _DiscoverFeedSnapshot {
  const _DiscoverFeedSnapshot(this.shelves, this.sectionTitle, this.continuation);

  final List<_DiscoverShelf> shelves;
  final String sectionTitle;
  final String continuation;
}

class DiscoverScreen extends StatefulWidget {
  const DiscoverScreen({this.api, this.embedded = false, super.key});

  final ServerApi? api;
  final bool embedded;

  @override
  State<DiscoverScreen> createState() => _DiscoverScreenState();
}

class _DiscoverScreenState extends State<DiscoverScreen>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver,
        AutomaticKeepAliveClientMixin<DiscoverScreen> {
  static final Map<String, List<IndexedFile>> _localLibraryCache = {};
  static final Map<String, DateTime> _localLibraryCacheUpdated = {};
  final DiscoverService _service = DiscoverService();
  late final AnimationController _shimmerController;
  List<DiscoverTrack> _tracks = const [];
  List<DiscoverTrack> _recentlyPlayed = const [];
  List<DiscoverTrack> _speedDial = const [];
  int _speedDialGeneration = 0;
  List<DiscoverTrack> _listeningPicks = const [];
  String _listeningPicksSeed = '';
  int _listeningPicksGeneration = 0;
  int _recentlyPlayedGeneration = 0;
  List<_DiscoverShelf> _homeShelves = const [];
  List<IndexedFile> _localLibrary = const [];
  bool _loading = false;
  bool _localLibraryLoading = false;
  Future<void>? _localLibraryRequest;
  bool _startingPlayback = false;
  bool _resolvingImportedPlaylist = false;
  String? _error;
  String _sectionTitle = 'Top charts in India';
  int _requestGeneration = 0;
  int _playRequestGeneration = 0;
  int _resolverGeneration = 0;
  bool _appResumed = true;
  String _homeContinuation = '';
  bool _loadingMore = false;
  Future<void>? _homeRequest;
  final ScrollController _scrollController = ScrollController();
  static const int _spotlightInitialPage = 10000;
  final PageController _spotlightPageController = PageController(
    viewportFraction: 1,
    initialPage: _spotlightInitialPage,
  );
  Timer? _spotlightAutoAdvanceTimer;
  final ValueNotifier<double> _heroScrollProgress = ValueNotifier(0);
  int _spotlightPage = _spotlightInitialPage;
  late String _lastRegion;
  late bool _lastLocalLossless;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _appResumed = WidgetsBinding.instance.lifecycleState == null ||
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
    AppLogger.event('screen.opened', category: 'screen', component: 'discover');
    _shimmerController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat();
    _lastRegion = AppSettings.instance.discoverRegion;
    _lastLocalLossless = AppSettings.instance.discoverLocalLossless;
    _scrollController.addListener(_onDiscoverScroll);
    AppSettings.instance.addListener(_onSettingsChanged);
    _loadHome();
    _startSpotlightAutoAdvance();
    unawaited(_loadRecentlyPlayed());
    unawaited(_loadSpeedDial());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final resumed = state == AppLifecycleState.resumed;
    if (_appResumed == resumed) return;
    _appResumed = resumed;
    if (!resumed) {
      _spotlightUserDragging = false;
      _spotlightAutoAdvanceTimer?.cancel();
      _spotlightAutoAdvanceTimer = null;
      // MethodChannel resolution already in flight cannot be interrupted, but
      // its batch is invalidated so no further tracks are resolved or queued.
      _resolverGeneration++;
      AppLogger.event(
        'discover_resolver.prefetch_paused',
        category: 'media',
        component: 'discover_resolver',
        fields: {'lifecycle_state': state.name},
      );
    } else {
      _startSpotlightAutoAdvance();
    }
  }

  bool _canContinueQueueResolution(
    int generation,
    int session,
    PersistentAudioPlayer player,
  ) =>
      mounted &&
      _appResumed &&
      generation == _resolverGeneration &&
      session == player.queueSession;

  Future<void> _loadSpeedDial() async {
    final generation = ++_speedDialGeneration;
    try {
      final tracks = await DiscoverSpeedDialStore.read();
      if (!mounted || generation != _speedDialGeneration) return;
      setState(() => _speedDial = tracks);
    } catch (error) {
      AppLogger.warning(
        'Discover Speed Dial could not be restored',
        category: 'discover',
        component: 'discover_screen',
        fields: {'failure_type': error.runtimeType.toString()},
      );
    }
  }

  bool _isSpeedDialPinned(DiscoverTrack track) =>
      _speedDial.any((item) => item.videoId == track.videoId);

  Future<void> _toggleSpeedDial(DiscoverTrack track) async {
    ++_speedDialGeneration;
    final wasPinned = _isSpeedDialPinned(track);
    try {
      final updated = wasPinned
          ? await DiscoverSpeedDialStore.remove(track.videoId)
          : await DiscoverSpeedDialStore.pin(track);
      if (!mounted) return;
      setState(() => _speedDial = updated);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(wasPinned
              ? 'Removed from Speed Dial'
              : 'Added to Speed Dial'),
          duration: const Duration(seconds: 2),
        ),
      );
    } catch (error) {
      AppLogger.warning(
        'Discover Speed Dial update failed',
        category: 'discover',
        component: 'discover_screen',
        fields: {'failure_type': error.runtimeType.toString()},
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not update Speed Dial.')),
      );
    }
  }

  Future<void> _loadRecentlyPlayed() async {
    final generation = _recentlyPlayedGeneration;
    final recent = await DiscoverRecentlyPlayedStore.read();
    if (!mounted || generation != _recentlyPlayedGeneration) return;
    setState(() => _recentlyPlayed = recent);
    if (recent.isNotEmpty) unawaited(_loadListeningPicks(recent.first));
  }

  Future<void> _openMood(DiscoverMood mood) async {
    final generation = ++_requestGeneration;
    setState(() {
      _loading = true;
      _error = null;
      _sectionTitle = mood.title;
      _homeShelves = const [];
      _homeContinuation = '';
    });
    try {
      final tracks = await _service.browseMood(mood, limit: 50);
      if (!mounted || generation != _requestGeneration) return;
      setState(() {
        _tracks = tracks;
        if (tracks.isEmpty) _error = 'No tracks found for this mood.';
      });
    } on PlatformException catch (error) {
      if (!mounted || generation != _requestGeneration) return;
      setState(() => _error = error.message ?? 'Could not open this mood.');
    } catch (_) {
      if (!mounted || generation != _requestGeneration) return;
      setState(() => _error = 'Could not load this mood right now.');
    } finally {
      if (mounted && generation == _requestGeneration) {
        setState(() => _loading = false);
      }
    }
  }

  void _ensureListeningPicks(List<_DiscoverShelf> shelves) {
    if (_recentlyPlayed.isNotEmpty ||
        _listeningPicks.isNotEmpty ||
        _listeningPicksSeed.isNotEmpty) {
      return;
    }
    for (final shelf in shelves) {
      if (shelf.tracks.isNotEmpty) {
        unawaited(_loadListeningPicks(shelf.tracks.first));
        return;
      }
    }
  }

  Future<void> _loadListeningPicks(DiscoverTrack seed) async {
    if (_listeningPicksSeed == seed.videoId) return;
    final generation = ++_listeningPicksGeneration;
    _listeningPicksSeed = seed.videoId;
    try {
      final picks = await _service.radio(seed, limit: 12);
      if (!mounted || generation != _listeningPicksGeneration) return;
      setState(() => _listeningPicks = picks
          .where((track) => track.videoId != seed.videoId)
          .toList(growable: false));
    } catch (_) {
      if (mounted && generation == _listeningPicksGeneration) {
        setState(() => _listeningPicks = const []);
      }
    }
  }

  void _recordRecentlyPlayed(DiscoverTrack track) {
    unawaited(DiscoverRecentlyPlayedStore.record(track).catchError((Object _) {}));
    if (!mounted) return;
    _recentlyPlayedGeneration++;
    final recent = [
      track,
      ..._recentlyPlayed.where((item) => item.videoId != track.videoId),
    ].take(20).toList(growable: false);
    setState(() => _recentlyPlayed = recent);
    unawaited(_loadListeningPicks(track));
  }

  void _onSettingsChanged() {
    final settings = AppSettings.instance;
    final region = settings.discoverRegion;
    final localLossless = settings.discoverLocalLossless;
    if (localLossless != _lastLocalLossless) {
      _lastLocalLossless = localLossless;
      if (localLossless && _homeShelves.isNotEmpty) {
        unawaited(_loadLocalLibrary());
      }
    }
    if (!mounted) return;
    setState(() {});
    if (region == _lastRegion) return;
    _lastRegion = region;
    _requestGeneration++;
    _listeningPicksSeed = '';
    final pendingHome = _homeRequest;
    if (pendingHome == null) {
      unawaited(_loadHome(forceRefresh: true));
    } else {
      unawaited(_reloadHomeAfterPending(region, pendingHome));
    }
    if (_recentlyPlayed.isNotEmpty) {
      unawaited(_loadListeningPicks(_recentlyPlayed.first));
    }
  }

  Future<void> _reloadHomeAfterPending(
    String region,
    Future<void> pending,
  ) async {
    try {
      await pending;
    } catch (_) {}
    if (!mounted || region != AppSettings.instance.discoverRegion) return;
    if (identical(_homeRequest, pending)) _homeRequest = null;
    await _loadHome(forceRefresh: true);
  }

  String get _regionName =>
      AppSettings.discoverRegions[AppSettings.instance.discoverRegion] ?? 'India';

  @override
  void dispose() {
    AppLogger.event('screen.closed', category: 'screen', component: 'discover',
      fields: {'loading': _loading, 'track_count': _tracks.length, 'shelf_count': _homeShelves.length});
    WidgetsBinding.instance.removeObserver(this);
    _resolverGeneration++;
    AppSettings.instance.removeListener(_onSettingsChanged);
    _scrollController.removeListener(_onDiscoverScroll);
    _scrollController.dispose();
    _spotlightAutoAdvanceTimer?.cancel();
    _heroScrollProgress.dispose();
    _spotlightPageController.dispose();
    _shimmerController.dispose();
    super.dispose();
  }


  Future<void> _openMoodsAndMoments() async {
    PocketLinkNavigation.discoverSearchVisible.value = true;
    try {
      await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => DiscoverMoodsScreen(
          service: _service,
          shimmerController: _shimmerController,
          onOpenTracks: (title, tracks) {
            if (!mounted) return;
            setState(() {
              _tracks = tracks;
              _homeShelves = const [];
              _homeContinuation = '';
              _sectionTitle = title;
              _error = tracks.isEmpty ? 'No tracks found for this mood.' : null;
              _loading = false;
            });
          },
          onPlay: (track, queue) => _play(track, queueOverride: queue),
        ),
      ),
      );
    } finally {
      PocketLinkNavigation.discoverSearchVisible.value = false;
    }
  }

  Future<void> _loadLocalLibrary({bool forceRefresh = false}) async {
    if (!AppSettings.instance.discoverLocalLossless) return;
    final api = widget.api;
    if (api == null) return;
    final cacheKey = api.baseUrl;
    final cached = _localLibraryCache[cacheKey];
    if (cached != null) {
      _localLibrary = cached;
      final updated = _localLibraryCacheUpdated[cacheKey];
      if (!forceRefresh && updated != null &&
          DateTime.now().difference(updated) < const Duration(minutes: 2)) {
        return;
      }
    }

    final pending = _localLibraryRequest;
    if (pending != null) {
      // The pending request already refreshes this server's snapshot. Reuse
      // its result even when this caller requested a forced refresh.
      await pending;
      return;
    }

    if (mounted && !_localLibraryLoading) {
      setState(() => _localLibraryLoading = true);
    } else {
      _localLibraryLoading = true;
    }
    final request = () async {
      try {
        final result = await MediaLibraryRepository(
          api: api,
          type: MediaLibraryType.music,
        ).readIndexedMedia();
        final items = result.items.map((item) => IndexedFile(
          volume: item.volume ?? 'internal',
          path: item.path,
          name: item.entry.name,
          type: item.entry.type,
          size: item.entry.size,
          modified: item.entry.modified,
          mime: '',
          category: 'music',
        )).toList(growable: false);
        _localLibraryCache[cacheKey] = items;
        _localLibraryCacheUpdated[cacheKey] = DateTime.now();
        _localLibrary = items;
      } catch (_) {
        // Keep a previously indexed snapshot usable during temporary outages.
      } finally {
        if (mounted) {
          setState(() => _localLibraryLoading = false);
        } else {
          _localLibraryLoading = false;
        }
      }
    }();
    _localLibraryRequest = request;
    try {
      await request;
    } finally {
      if (identical(_localLibraryRequest, request)) {
        _localLibraryRequest = null;
      }
    }
  }

  Future<void> _loadHome({bool forceRefresh = false}) async {
    final region = AppSettings.instance.discoverRegion;
    final cacheKey = 'home:$region';
    var cached = DiscoverCache.instance.read<_DiscoverFeedSnapshot>(cacheKey);
    var persistedStale = false;

    // Restore the last successful feed after process restart before making a
    // network request. A stale snapshot remains visible while it refreshes.
    if (cached == null) {
      final persisted = await DiscoverHomeFeedStore.read(region);
      if (!mounted || region != AppSettings.instance.discoverRegion) return;
      if (persisted != null) {
        final snapshot = _DiscoverFeedSnapshot(
          List.unmodifiable(persisted.feed.shelves.map(
            (shelf) => _DiscoverShelf(shelf.title, shelf.tracks, items: shelf.items),
          )),
          'Discover in ${AppSettings.discoverRegions[region] ?? region}',
          persisted.feed.continuation,
        );
        DiscoverCache.instance.write(cacheKey, snapshot);
        cached = DiscoverCache.instance.read<_DiscoverFeedSnapshot>(cacheKey);
        persistedStale = persisted.isStale;
      }
    }

    final cacheEntry = cached;
    if (cacheEntry != null) {
      void restore() {
        _homeShelves = cacheEntry.value.shelves;
        _tracks = cacheEntry.value.shelves.isEmpty
            ? const []
            : cacheEntry.value.shelves.first.tracks;
        _sectionTitle = cacheEntry.value.sectionTitle;
        _homeContinuation = cacheEntry.value.continuation;
        _error = null;
        _loading = false;
      }

      if (mounted) {
        setState(restore);
      } else {
        restore();
      }
      _ensureListeningPicks(cacheEntry.value.shelves);
      final stale = persistedStale || DiscoverCache.instance.isStale(cacheEntry);
      AppLogger.event('discover.home_cache_restored', category: 'discover',
        component: 'discover_screen',
        fields: {'shelf_count': cacheEntry.value.shelves.length,
          'track_count': cacheEntry.value.shelves.fold<int>(0, (sum, shelf) => sum + shelf.tracks.length),
          'stale': stale, 'persistent': true});
      if (!forceRefresh && !stale) return;
      if (!forceRefresh) {
        unawaited(_fetchHome(cacheKey, showLoading: false));
        return;
      }
    } else if (_homeShelves.isNotEmpty && mounted) {
      setState(() {
        _homeShelves = const [];
        _tracks = const [];
      });
    }
    await _fetchHome(cacheKey, showLoading: true);
  }

  Future<void> _fetchHome(
    String cacheKey, {
    required bool showLoading,
  }) {
    final pending = _homeRequest;
    if (pending != null) return pending;
    final request = _performFetchHome(cacheKey, showLoading: showLoading);
    _homeRequest = request;
    return request.whenComplete(() {
      if (identical(_homeRequest, request)) _homeRequest = null;
    });
  }

  Future<void> _performFetchHome(
    String cacheKey, {
    required bool showLoading,
  }) async {
    final generation = ++_requestGeneration;
    AppLogger.event('discover.home_loading_started', category: 'discover',
      component: 'discover_screen',
      fields: {'show_loading': showLoading, 'generation': generation,
        'cache_hit': _homeShelves.isNotEmpty});
    if (showLoading) {
      setState(() {
        _loading = true;
        _error = null;
        if (_homeShelves.isEmpty) _sectionTitle = 'Discover in $_regionName';
      });
    }
    final region = AppSettings.instance.discoverRegion;
    try {
      final feed = await _service.homeFeed(limit: 50, region: region);
      if (!mounted || generation != _requestGeneration ||
          region != AppSettings.instance.discoverRegion) return;
      final shelves = feed.shelves
          .map((shelf) => _DiscoverShelf(shelf.title, shelf.tracks, items: shelf.items))
          .where((shelf) => shelf.tracks.isNotEmpty || shelf.items.isNotEmpty)
          .toList(growable: false);
      if (shelves.isEmpty) {
        if (_homeShelves.isEmpty) {
          setState(() => _error = 'No music recommendations are available right now.');
        }
        return;
      }
      final snapshot = _DiscoverFeedSnapshot(
        List.unmodifiable(shelves),
        'Discover in $_regionName',
        feed.continuation,
      );
      DiscoverCache.instance.write(cacheKey, snapshot);
      unawaited(DiscoverHomeFeedStore.write(
        region,
        DiscoverHomeFeed(
          shelves: feed.shelves,
          continuation: feed.continuation,
        ),
      ).catchError((Object error) {
        AppLogger.warning('Discover feed cache persistence failed',
          category: 'discover', component: 'discover_screen',
          fields: {'failure_type': error.runtimeType.toString()});
      }));
      AppLogger.event('discover.home_loading_completed', category: 'discover',
        component: 'discover_screen',
        fields: {'generation': generation, 'shelf_count': snapshot.shelves.length,
          'track_count': snapshot.shelves.fold<int>(0, (sum, shelf) => sum + shelf.tracks.length),
          'has_continuation': snapshot.continuation.isNotEmpty});
      setState(() {
        _homeShelves = snapshot.shelves;
        _tracks = shelves.first.tracks;
        _homeContinuation = snapshot.continuation;
        _error = null;
      });
      _ensureListeningPicks(shelves);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _onDiscoverScroll();
      });
    } on PlatformException catch (error) {
      AppLogger.warning('Discover home loading failed', category: 'discover',
        component: 'discover_screen',
        fields: {'generation': generation, 'failure_type': 'platform', 'error_code': error.code});
      if (!mounted || generation != _requestGeneration) return;
      if (_homeShelves.isEmpty) {
        setState(() => _error = error.message ?? 'YouTube Music home is unavailable.');
      }
    } catch (error) {
      AppLogger.warning('Discover home loading failed', category: 'discover',
        component: 'discover_screen',
        fields: {'generation': generation, 'failure_type': error.runtimeType.toString()});
      if (!mounted || generation != _requestGeneration) return;
      if (_homeShelves.isEmpty) {
        setState(() => _error = 'Could not load YouTube Music home. Check your connection and try again.');
      }
    } finally {
      if (mounted && generation == _requestGeneration && showLoading) {
        setState(() => _loading = false);
      }
    }
  }

  void _onDiscoverScroll() {
    if (_scrollController.hasClients) {
      final heroHeight = MediaQuery.sizeOf(context).height * .60;
      final progress = (_scrollController.offset / heroHeight).clamp(0.0, 1.0).toDouble();
      if ((_heroScrollProgress.value - progress).abs() > .001) {
        _heroScrollProgress.value = progress;
      }
    }
    if (!_scrollController.hasClients ||
        _loading ||
        _loadingMore ||
        _homeContinuation.isEmpty ||
        _homeShelves.isEmpty) {
      return;
    }
    if (_scrollController.position.extentAfter < 600) {
      unawaited(_loadMoreHome());
    }
  }

  Future<void> _loadMoreHome() async {
    final continuation = _homeContinuation;
    if (_loading || _loadingMore || continuation.isEmpty || _homeShelves.isEmpty) return;
    setState(() => _loadingMore = true);
    final generation = _requestGeneration;
    final region = AppSettings.instance.discoverRegion;
    try {
      final feed = await _service.moreHome(continuation, limit: 50, region: region);
      if (!mounted || generation != _requestGeneration ||
          region != AppSettings.instance.discoverRegion) return;
      final mergedFeed = mergeDiscoverHomeShelves(
        _homeShelves
            .map((shelf) => DiscoverHomeShelf(
                  title: shelf.title,
                  tracks: shelf.tracks,
                  items: shelf.items,
                ))
            .toList(growable: false),
        feed.shelves,
      );
      final merged = mergedFeed
          .map((shelf) => _DiscoverShelf(shelf.title, shelf.tracks, items: shelf.items))
          .toList(growable: false);
      if (merged.length == _homeShelves.length &&
          merged.every((shelf) => _homeShelves.any((old) =>
              old.title == shelf.title &&
              old.tracks.length == shelf.tracks.length &&
              old.items.length == shelf.items.length))) {
        final snapshot = _DiscoverFeedSnapshot(
          List.unmodifiable(_homeShelves),
          'Discover in $_regionName',
          '',
        );
        DiscoverCache.instance.write(
          'home:${AppSettings.instance.discoverRegion}',
          snapshot,
        );
        unawaited(DiscoverHomeFeedStore.write(
          region,
          DiscoverHomeFeed(
            shelves: _homeShelves.map((shelf) => DiscoverHomeShelf(
              title: shelf.title, tracks: shelf.tracks, items: shelf.items,
            )).toList(growable: false),
          ),
        ).catchError((Object error) {
          AppLogger.warning('Discover feed cache persistence failed',
            category: 'discover', component: 'discover_screen',
            fields: {'failure_type': error.runtimeType.toString()});
        }));
        setState(() => _homeContinuation = '');
        return;
      }
      final nextContinuation = feed.continuation == continuation
          ? ''
          : feed.continuation;
      final snapshot = _DiscoverFeedSnapshot(
        List.unmodifiable(merged),
        'Discover in $_regionName',
        nextContinuation,
      );
      DiscoverCache.instance.write('home:${AppSettings.instance.discoverRegion}', snapshot);
      unawaited(DiscoverHomeFeedStore.write(
        region,
        DiscoverHomeFeed(
          shelves: snapshot.shelves.map((shelf) => DiscoverHomeShelf(
            title: shelf.title, tracks: shelf.tracks, items: shelf.items,
          )).toList(growable: false),
          continuation: snapshot.continuation,
        ),
      ).catchError((Object error) {
        AppLogger.warning('Discover feed cache persistence failed',
          category: 'discover', component: 'discover_screen',
          fields: {'failure_type': error.runtimeType.toString()});
      }));
      setState(() {
        _homeShelves = snapshot.shelves;
        _homeContinuation = snapshot.continuation;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _onDiscoverScroll();
      });
    } on PlatformException catch (error) {
      AppLogger.warning('Discover home continuation failed', category: 'discover',
        component: 'discover_screen', fields: {'error_code': error.code});
    } catch (error) {
      AppLogger.warning('Discover home continuation failed', category: 'discover',
        component: 'discover_screen', fields: {'failure_type': error.runtimeType.toString()});
    } finally {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  Future<void> _loadRadio(DiscoverTrack track) async {
    final generation = ++_requestGeneration;
    setState(() {
      _loading = true;
      _error = null;
      _sectionTitle = 'Radio · ${track.title}';
      _homeShelves = const [];
      _homeContinuation = '';
    });
    try {
      final results = await _service.radio(track);
      if (!mounted || generation != _requestGeneration) return;
      setState(() {
        _tracks = results;
        if (results.isEmpty) _error = 'No radio recommendations are available for this track.';
      });
    } on PlatformException catch (error) {
      if (!mounted || generation != _requestGeneration) return;
      setState(() => _error = error.message ?? 'Radio is unavailable right now.');
    } catch (_) {
      if (!mounted || generation != _requestGeneration) return;
      setState(() => _error = 'Could not load radio recommendations.');
    } finally {
      if (mounted && generation == _requestGeneration) setState(() => _loading = false);
    }
  }

  Future<void> _play(DiscoverTrack track, {List<DiscoverTrack>? queueOverride}) async {
    // Warm the cover independently; artwork decoding must never delay opening.
    unawaited(DiscoverThumbnailCache.load(
      DiscoverThumbnailCache.urlForSize(track.thumbnailUrl, 544),
    ).then((bytes) {
      if (mounted && bytes != null) {
        unawaited(precacheImage(
          ResizeImage(MemoryImage(bytes), width: 544),
          context,
        ));
      }
    }));

    final request = ++_playRequestGeneration;
    _startingPlayback = true;
    var sourceTracks = queueOverride ?? _tracks;
    if (queueOverride == null) {
      for (final shelf in _homeShelves) {
        if (shelf.tracks.any((item) => item.videoId == track.videoId)) {
          sourceTracks = shelf.tracks;
          break;
        }
      }
    }
    final results = List<DiscoverTrack>.of(sourceTracks);
    final selectedIndex = results.indexWhere((item) => item.videoId == track.videoId);
    final queueTracks = selectedIndex < 0 ? <DiscoverTrack>[track] : results;
    final startIndex = selectedIndex < 0 ? 0 : selectedIndex;
    final player = PersistentAudioPlayer.instance;
    final provisionalItem = MediaQueueItem(
      title: track.title,
      path: track.videoId,
      artist: track.artist,
      artworkUrl: track.thumbnailUrl,
      lyricsVideoId: track.videoId,
      durationText: track.durationText,
      isDiscover: true,
    );
    final session = player.beginQueueSelection(
      api: widget.api,
      item: provisionalItem,
      isMusic: true,
    );

    // Publish the selected track and reveal Now Playing before resolving a
    // remote stream or asking media_kit to open it.
    NowPlayingOverlayController.open();

    try {
      final item = await _queueItem(queueTracks[startIndex]);
      if (request != _playRequestGeneration ||
          session != player.queueSession) return;

      await player.openQueue(
        api: widget.api,
        queue: [item],
        initialIndex: 0,
        isMusic: true,
        expectedSession: session,
      );
      if (request != _playRequestGeneration ||
          session != player.queueSession) return;

      _recordRecentlyPlayed(track);
      unawaited(_populateQueue(
        queueTracks,
        startIndex,
        session,
        _resolverGeneration,
      ).catchError((Object _) {}));
    } catch (error) {
      player.failQueueSelection(session);
      if (!mounted || request != _playRequestGeneration) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error is PlatformException
            ? error.message ?? 'Could not resolve this track.'
            : 'Could not start playback. Try again later.')),
      );
    } finally {
      if (request == _playRequestGeneration) _startingPlayback = false;
    }
  }

  Future<void> _playImportedPlaylist(ImportedPlaylist playlist) async {
    if (_resolvingImportedPlaylist || _startingPlayback) return;
    _resolvingImportedPlaylist = true;
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Preparing ${playlist.name}…')),
      );
    }
    try {
      final resolved = List<DiscoverTrack?>.filled(playlist.tracks.length, null);
      var next = 0;
      Future<void> worker() async {
        while (true) {
          final index = next++;
          if (index >= playlist.tracks.length) return;
          final source = playlist.tracks[index];
          if (source.videoId != null && source.videoId!.isNotEmpty &&
              source.title.trim().isNotEmpty && source.title != 'YouTube track') {
            resolved[index] = DiscoverTrack(
              videoId: source.videoId!,
              title: source.title,
              artist: source.artist.isEmpty ? 'YouTube' : source.artist,
            );
            continue;
          }
          try {
            final query = '${source.title} ${source.artist}'.trim();
            final candidates = await _service.search(query, limit: 10);
            for (final candidate in candidates) {
              if (PlaylistImportService.isSameTrack(
                source,
                ImportedTrack(title: candidate.title, artist: candidate.artist),
              )) {
                resolved[index] = candidate;
                break;
              }
            }
          } catch (_) {
            // Preserve playlist order and skip tracks that cannot be resolved.
          }
        }
      }
      await Future.wait(List.generate(3, (_) => worker()));
      final queue = resolved.whereType<DiscoverTrack>().toList(growable: false);
      if (queue.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('No tracks from this playlist could be matched in YouTube Music.')),
          );
        }
        return;
      }
      await _play(queue.first, queueOverride: queue);
    } finally {
      _resolvingImportedPlaylist = false;
    }
  }

  Future<MediaQueueItem> _queueItem(DiscoverTrack track) async {
    // Never block playback on a library refresh. Discover warms the server
    // index on screen entry; playback uses the latest cached snapshot and
    // falls back to NewPipe while a cold index is still loading.
    final local = AppSettings.instance.discoverLocalLossless
        ? DiscoverService.findLocalLosslessMatch(track, _localLibrary)
        : null;
    if (local != null) {
      return MediaQueueItem(
        title: track.title,
        path: local.path,
        volume: local.volume == 'internal' ? null : local.volume,
        size: local.size,
        artist: track.artist,
        artworkUrl: track.thumbnailUrl,
        lyricsVideoId: track.videoId,
        durationText: track.durationText,
      );
    }
    return _remoteQueueItem(track);
  }

  Future<void> _populateQueue(
    List<DiscoverTrack> tracks,
    int selectedIndex,
    int session,
    int resolverGeneration,
  ) async {
    final player = PersistentAudioPlayer.instance;
    Future<MediaQueueItem?> resolveAt(int index) async {
      if (!_canContinueQueueResolution(resolverGeneration, session, player)) {
        return null;
      }
      try {
        final item = await _queueItem(tracks[index]);
        return _canContinueQueueResolution(resolverGeneration, session, player)
            ? item
            : null;
      } catch (_) {
        return null;
      }
    }

    if (!_canContinueQueueResolution(resolverGeneration, session, player)) return;

    // Resolve the immediate neighbours concurrently, then fill the rest
    // in a deterministic order without blocking initial playback.
    final order = DiscoverService.progressiveQueueOrder(tracks.length, selectedIndex);
    final immediateCount = (selectedIndex > 0 ? 1 : 0) +
        (selectedIndex + 1 < tracks.length ? 1 : 0);
    final immediate = order.take(immediateCount).toList(growable: false);
    final immediateItems = await Future.wait(immediate.map(resolveAt));
    if (!_canContinueQueueResolution(resolverGeneration, session, player)) return;
    for (var offset = 0; offset < immediate.length; offset++) {
      final item = immediateItems[offset];
      if (item == null ||
          !_canContinueQueueResolution(resolverGeneration, session, player)) {
        continue;
      }
      await player.enqueue(
        item,
        insertAtStart: immediate[offset] < selectedIndex,
        expectedSession: session,
      );
    }
    if (!_canContinueQueueResolution(resolverGeneration, session, player)) return;

    // Keep at most two upcoming remote streams resolved ahead of playback.
    // The first next track is in the immediate batch above; only resolve the
    // second next track here instead of walking the entire recommendation list.
    if (AppSettings.instance.discoverAutoQueue &&
        selectedIndex + 2 < tracks.length) {
      final nextItem = await resolveAt(selectedIndex + 2);
      if (nextItem != null &&
          _canContinueQueueResolution(resolverGeneration, session, player)) {
        await player.enqueue(nextItem, expectedSession: session);
      }
    }

    // Optional lossless matching must not compete with Discover's initial
    // feed or first stream resolution. Warm the local index only after the
    // selected track and immediate queue neighbours have been prepared.
    if (_canContinueQueueResolution(resolverGeneration, session, player) &&
        AppSettings.instance.discoverLocalLossless &&
        _localLibrary.isEmpty) {
      unawaited(_loadLocalLibrary());
    }
  }

  Future<MediaQueueItem> _remoteQueueItem(DiscoverTrack track) async {
    final stream = await _service.resolve(track);
    return MediaQueueItem(
      title: track.title,
      path: track.videoId,
      streamUrl: stream.url,
      artist: track.artist,
      artworkUrl: track.thumbnailUrl,
      lyricsVideoId: track.videoId,
      durationText: track.durationText,
      isDiscover: true,
      streamCodec: stream.codec,
      streamResolver: stream.resolver,
      streamBitrateBps: stream.bitrateBps,
      httpHeaders: {
        'User-Agent': stream.userAgent,
        'Accept': '*/*',
      },
    );
  }

  Future<DiscoverLyrics?> _readSidecarLyrics(IndexedFile audio) async {
    final api = widget.api;
    if (api == null) return null;
    try {
      final separator = audio.path.lastIndexOf('/');
      final parent = separator < 0 ? '' : audio.path.substring(0, separator);
      final baseName = audio.name.replaceFirst(RegExp(r'\.[^.]+$'), '');
      final listing = audio.volume == 'internal'
          ? await api.listDirectory(parent)
          : await api.listStorageDirectory(audio.volume, parent);
      FileEntry? sidecar;
      for (final item in listing.items) {
        final name = item.name.toLowerCase();
        if (!item.isDirectory &&
            (name == (baseName + '.lrc').toLowerCase() || name == 'lyrics.lrc')) {
          sidecar = item;
          break;
        }
      }
      if (sidecar == null || sidecar.size <= 0 || sidecar.size > 512 * 1024) {
        return null;
      }
      final sidecarPath = parent.isEmpty ? sidecar.name : parent + '/' + sidecar.name;
      final bytes = audio.volume == 'internal'
          ? await api.downloadFile(sidecarPath)
          : await api.downloadStorageFile(audio.volume, sidecarPath);
      final content = utf8.decode(bytes, allowMalformed: true).trim();
      if (content.isEmpty) return null;
      final syncedLines = DiscoverService.parseLrc(content);
      final lines = syncedLines.isNotEmpty
          ? syncedLines
          : content.split(RegExp(r'\r?\n'))
              .map((line) => line.trim())
              .where((line) => line.isNotEmpty)
              .map((line) => DiscoverLyricsLine(timeMs: 0, text: line))
              .toList(growable: false);
      if (lines.isEmpty) return null;
      return DiscoverLyrics(
        lines: List.unmodifiable(lines),
        isSynced: syncedLines.isNotEmpty,
        source: 'Sidecar',
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> _showLyrics(DiscoverTrack track, {IndexedFile? local}) async {
    if (!AppSettings.instance.discoverLyrics) return;
    try {
      final lyrics = (local == null ? null : await _readSidecarLyrics(local)) ??
          await _service.lyrics(track);
      if (!mounted) return;
      final currentItem = PersistentAudioPlayer.instance.currentItem;
      final showActiveLine = currentItem?.path == track.videoId ||
          (local != null && currentItem?.path == local.path);
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Theme.of(context).colorScheme.surface,
        builder: (context) => SafeArea(
          child: SizedBox(
            height: MediaQuery.sizeOf(context).height * 0.72,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 18, 20, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(track.title, style: Theme.of(context).textTheme.titleLarge),
                      const SizedBox(height: 4),
                      Text(track.artist, style: Theme.of(context).textTheme.bodyMedium),
                      const SizedBox(height: 8),
                      Text(
                        lyrics == null
                            ? 'Lyrics not found'
                            : (lyrics.isSynced ? 'Synced lyrics' : 'Plain lyrics') + ' · ' + lyrics.source,
                        style: Theme.of(context).textTheme.labelSmall,
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: lyrics == null
                      ? const Center(child: Text('No matching lyrics were found.'))
                      : StreamBuilder<Duration>(
                          stream: PersistentAudioPlayer.instance.player.stream.position,
                          initialData: PersistentAudioPlayer.instance.player.state.position,
                          builder: (context, snapshot) {
                            final positionMs = snapshot.data?.inMilliseconds ?? 0;
                            var activeIndex = -1;
                            if (lyrics.isSynced && showActiveLine) {
                              for (var index = 0; index < lyrics.lines.length; index++) {
                                if (lyrics.lines[index].timeMs > positionMs) break;
                                activeIndex = index;
                              }
                            }
                            return ListView.builder(
                              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                              itemCount: lyrics.lines.length,
                              itemBuilder: (context, index) {
                                final active = index == activeIndex;
                                return AnimatedContainer(
                                  duration: const Duration(milliseconds: 160),
                                  padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 8),
                                  decoration: BoxDecoration(
                                    color: active
                                        ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.10)
                                        : Colors.transparent,
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Text(
                                    lyrics.lines[index].text,
                                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                                      color: active ? Theme.of(context).colorScheme.primary : null,
                                      fontWeight: active ? FontWeight.w700 : FontWeight.normal,
                                    ),
                                  ),
                                );
                              },
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not retrieve lyrics.')),
      );
    }
  }

  Widget _art(
    DiscoverTrack track, {
    double size = 56,
    double radius = 7,
    BoxFit fit = BoxFit.cover,
  }) {
    final show = AppSettings.instance.discoverArtwork && track.thumbnailUrl.isNotEmpty;
    final placeholder = Container(
      width: size.isFinite ? size : null,
      height: size.isFinite ? size : null,
      color: const Color(0xFF1A1B20),
    );
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: SizedBox(
        width: size.isFinite ? size : null,
        height: size.isFinite ? size : null,
        child: show
            ? DiscoverThumbnail(
                url: DiscoverThumbnailCache.urlForSize(
                  track.thumbnailUrl,
                  size <= 60 ? 160 : 544,
                ),
                cacheWidth: size <= 60 ? 160 : 544,
                fit: fit,
                fallback: placeholder,
                errorFallback: _artFallback(size),
              )
            : _artFallback(size),
      ),
    );
  }

  Widget _skeletonBlock({
    double? width,
    double? height,
    double radius = 8,
  }) {
    return AnimatedBuilder(
      animation: _shimmerController,
      builder: (context, child) {
        final shift = -1.4 + (_shimmerController.value * 2.8);
        return ShaderMask(
          blendMode: BlendMode.srcATop,
          shaderCallback: (bounds) => LinearGradient(
            begin: Alignment(shift, 0),
            end: Alignment(shift + 1.2, 0),
            colors: const [
              Color(0xFF1A1A1E),
              Color(0xFF2A2A30),
              Color(0xFF1A1A1E),
            ],
            stops: const [0.25, 0.5, 0.75],
          ).createShader(bounds),
          child: child,
        );
      },
      child: Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          color: const Color(0xFF1A1A1E),
          borderRadius: BorderRadius.circular(radius),
        ),
      ),
    );
  }

  Widget _skeletonLine({required double width, double height = 10}) =>
      _skeletonBlock(width: width, height: height, radius: 6);

  Widget _discoverHomeSkeleton() {
    final screenWidth = MediaQuery.sizeOf(context).width;
    final heroHeight = MediaQuery.sizeOf(context).height * .60;
    return SliverToBoxAdapter(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            height: heroHeight,
            child: Stack(
              fit: StackFit.expand,
              children: [
                _skeletonBlock(width: screenWidth, height: heroHeight, radius: 0),
                Positioned(
                  left: 36,
                  bottom: 62,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _skeletonLine(width: 112, height: 10),
                      const SizedBox(height: 12),
                      _skeletonLine(width: screenWidth * .62, height: 27),
                      const SizedBox(height: 8),
                      _skeletonLine(width: screenWidth * .36, height: 12),
                      const SizedBox(height: 18),
                      _skeletonBlock(width: 88, height: 36, radius: 18),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 26),
          for (var shelf = 0; shelf < 4; shelf++) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(36, 0, 28, 10),
              child: _skeletonLine(width: 118 + shelf * 12, height: 14),
            ),
            SizedBox(
              height: 190,
              child: ListView.separated(
                padding: const EdgeInsets.symmetric(horizontal: 36),
                scrollDirection: Axis.horizontal,
                itemCount: 4,
                separatorBuilder: (_, __) => const SizedBox(width: 15),
                itemBuilder: (_, __) => SizedBox(
                  width: 137,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _skeletonBlock(width: 137, height: 137, radius: 14),
                      const SizedBox(height: 8),
                      _skeletonLine(width: 112, height: 10),
                      const SizedBox(height: 6),
                      _skeletonLine(width: 76, height: 8),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 22),
          ],
        ],
      ),
    );
  }

  Widget _artFallback(double size) => Container(
    width: size.isFinite ? size : null,
    height: size.isFinite ? size : null,
    color: Theme.of(context).colorScheme.surfaceContainerHighest,
    alignment: Alignment.center,
    child: Icon(Icons.music_note_rounded, size: size.isFinite ? size * .42 : 44),
  );

  Widget _feedCard(
    DiscoverTrack track, {
    List<DiscoverTrack>? queueOverride,
    double cardWidth = 137,
  }) {
    final theme = Theme.of(context);
    final local = AppSettings.instance.discoverLocalLossless
        ? DiscoverService.findLocalLosslessMatch(track, _localLibrary) : null;
    return SizedBox(
      width: cardWidth,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => _play(track, queueOverride: queueOverride),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AspectRatio(
              aspectRatio: 1,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  _art(track, size: double.infinity, radius: 14),
                  if (local != null)
                    Positioned(
                      left: 7,
                      bottom: 7,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.black87,
                          borderRadius: BorderRadius.circular(5),
                        ),
                        child: const Text(
                          'LOSSLESS',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 9,
                            fontWeight: FontWeight.w800,
                            letterSpacing: .4,
                          ),
                        ),
                      ),
                    ),
                  Positioned(
                    right: 5,
                    top: 5,
                    child: Material(
                      color: Colors.black54,
                      shape: const CircleBorder(),
                      child: PopupMenuButton<String>(
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
                        iconSize: 20,
                        icon: const Icon(Icons.more_horiz_rounded, color: Colors.white),
                        onSelected: (v) {
                          if (v == 'speed_dial') _toggleSpeedDial(track);
                          if (v == 'play') _play(track, queueOverride: queueOverride);
                          if (v == 'radio') _loadRadio(track);
                          if (v == 'lyrics') _showLyrics(track, local: local);
                        },
                        itemBuilder: (_) => [
                          const PopupMenuItem(value: 'play', child: Text('Play')),
                          PopupMenuItem(
                            value: 'speed_dial',
                            child: Text(_isSpeedDialPinned(track)
                                ? 'Remove from Speed Dial'
                                : 'Add to Speed Dial'),
                          ),
                          const PopupMenuItem(value: 'radio', child: Text('Start radio')),
                          if (AppSettings.instance.discoverLyrics)
                            const PopupMenuItem(value: 'lyrics', child: Text('Lyrics')),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              track.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              track.artist,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: .5),
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _shelfHeading(String title, {VoidCallback? onSeeAll}) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 28, 6),
        child: Row(
          children: [
            Expanded(
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -.35,
                ),
              ),
            ),
            if (onSeeAll != null)
              TextButton(
                onPressed: onSeeAll,
                child: const Text('See all'),
              ),
          ],
        ),
      );

  void _showShelf(_DiscoverShelf shelf) {
    _requestGeneration++;
    setState(() {
      _tracks = shelf.tracks;
      _sectionTitle = shelf.title;
      _homeShelves = const [];
      _homeContinuation = '';
    });
  }

  List<DiscoverTrack> get _spotlightTracks =>
      buildDiscoverSpotlightTracks(
        shelves: _homeShelves
            .map((shelf) => DiscoverHomeShelf(
                  title: shelf.title,
                  tracks: shelf.tracks,
                  items: shelf.items,
                ))
            .toList(growable: false),
        recentlyPlayed: _recentlyPlayed,
      );

  void _playRandomSpotlight() {
    final tracks = _spotlightTracks;
    if (tracks.isEmpty) return;
    final selected = tracks[math.Random().nextInt(tracks.length)];
    _play(selected, queueOverride: tracks);
  }

  int get _spotlightPageCount =>
      _spotlightTracks.length + (_speedDial.isEmpty ? 0 : 1);

  void _playRandomSpeedDial() {
    if (_speedDial.isEmpty) return;
    final selected = _speedDial[math.Random().nextInt(_speedDial.length)];
    _play(selected, queueOverride: _speedDial);
  }

  void _openSpeedDialSheet() {
    final tracks = List<DiscoverTrack>.of(_speedDial);
    if (tracks.isEmpty) return;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => DraggableScrollableSheet(
        initialChildSize: .84,
        minChildSize: .5,
        maxChildSize: .95,
        expand: false,
        builder: (context, scrollController) => Material(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.only(top: 12, bottom: 14),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: .35),
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(22, 0, 16, 12),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Speed Dial',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    Text(
                      '${tracks.length} saved',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      tooltip: 'Shuffle Speed Dial',
                      onPressed: () {
                        Navigator.of(sheetContext).pop();
                        _playRandomSpeedDial();
                      },
                      icon: const Icon(Icons.shuffle_rounded),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView.separated(
                  controller: scrollController,
                  padding: const EdgeInsets.only(bottom: 24),
                  itemCount: tracks.length,
                  separatorBuilder: (_, __) => const Divider(height: 1, indent: 78),
                  itemBuilder: (context, index) {
                    final track = tracks[index];
                    return ListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 3),
                      leading: _art(track, size: 48, radius: 10),
                      title: Text(track.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                      subtitle: Text(track.artist, maxLines: 1, overflow: TextOverflow.ellipsis),
                      onTap: () {
                        Navigator.of(sheetContext).pop();
                        _play(track, queueOverride: tracks);
                      },
                      trailing: IconButton(
                        tooltip: 'Remove from Speed Dial',
                        onPressed: () {
                          _toggleSpeedDial(track);
                          Navigator.of(sheetContext).pop();
                        },
                        icon: const Icon(Icons.remove_circle_outline_rounded),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  bool _spotlightUserDragging = false;

  void _startSpotlightAutoAdvance() {
    _spotlightAutoAdvanceTimer?.cancel();
    if (!mounted || !_appResumed) return;
    _spotlightAutoAdvanceTimer = Timer.periodic(
      const Duration(milliseconds: 5500),
      (_) {
        final pageCount = _spotlightPageCount;
        if (!mounted ||
            !_appResumed ||
            ModalRoute.of(context)?.isCurrent == false ||
            _spotlightUserDragging ||
            pageCount < 2 ||
            !_spotlightPageController.hasClients ||
            (_scrollController.hasClients && _scrollController.offset > 48)) {
          return;
        }
        final next = _spotlightPage + 1;
        _spotlightPageController.animateToPage(
          next,
          duration: const Duration(milliseconds: 1150),
          curve: Curves.easeInOutCubic,
        );
      },
    );
  }

  Widget _speedDialHeroPage() {
    final tracks = _speedDial;
    final cover = tracks.first;
    return Material(
      color: const Color(0xFF08090C),
      child: Stack(
        fit: StackFit.expand,
        children: [
          _art(cover, size: double.infinity, radius: 0, fit: BoxFit.cover),
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Color(0xB8000000),
                  Color(0x20000000),
                  Color(0x3A000000),
                  Color(0xF0000000),
                ],
                stops: [0, .30, .52, 1],
              ),
            ),
          ),
          Positioned(
            top: 84,
            right: 30,
            child: Row(
              children: [
                for (final track in tracks.take(3))
                  Padding(
                    padding: const EdgeInsets.only(left: 8),
                    child: Container(
                      width: 58,
                      height: 58,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.white.withValues(alpha: .7), width: 1.2),
                        boxShadow: const [
                          BoxShadow(color: Colors.black45, blurRadius: 14, offset: Offset(0, 5)),
                        ],
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: _art(track, size: 58, radius: 0, fit: BoxFit.cover),
                    ),
                  ),
              ],
            ),
          ),
          Positioned(
            left: 36,
            right: 28,
            bottom: 62,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'YOUR SPEED DIAL',
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: Colors.white.withValues(alpha: .72),
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.35,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  'Your saved tracks',
                  maxLines: 2,
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    height: 1.04,
                    letterSpacing: -.7,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  '${tracks.length} pinned songs, ready when you are',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Colors.white.withValues(alpha: .68),
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 15),
                Row(
                  children: [
                    FilledButton.icon(
                      onPressed: _openSpeedDialSheet,
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.white.withValues(alpha: .88),
                        foregroundColor: const Color(0xFF202124),
                        minimumSize: const Size(0, 36),
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        shape: const StadiumBorder(),
                      ),
                      icon: const Icon(Icons.queue_music_rounded, size: 18),
                      label: const Text('Open Speed Dial', style: TextStyle(fontWeight: FontWeight.w700)),
                    ),
                    const SizedBox(width: 10),
                    IconButton(
                      tooltip: 'Shuffle Speed Dial',
                      onPressed: _playRandomSpeedDial,
                      style: IconButton.styleFrom(
                        backgroundColor: Colors.white.withValues(alpha: .16),
                        foregroundColor: Colors.white,
                        fixedSize: const Size(38, 38),
                      ),
                      icon: const Icon(Icons.shuffle_rounded, size: 18),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _spotlightHero() {
    final tracks = _spotlightTracks;
    final pageCount = _spotlightPageCount;
    if (pageCount == 0) return const SliverToBoxAdapter();

    final activePage = ((_spotlightPage - _spotlightInitialPage) % pageCount + pageCount) % pageCount;
    final heroHeight = MediaQuery.sizeOf(context).height * .60;
    return SliverToBoxAdapter(
      child: SizedBox(
        height: heroHeight,
        child: ValueListenableBuilder<double>(
          valueListenable: _heroScrollProgress,
          child: NotificationListener<ScrollNotification>(
            onNotification: (notification) {
              if (notification is ScrollStartNotification &&
                  notification.dragDetails != null) {
                _spotlightUserDragging = true;
                _spotlightAutoAdvanceTimer?.cancel();
                _spotlightAutoAdvanceTimer = null;
              } else if (notification is ScrollEndNotification &&
                  _spotlightUserDragging) {
                _spotlightUserDragging = false;
                _startSpotlightAutoAdvance();
              }
              return false;
            },
            child: PageView.builder(
            controller: _spotlightPageController,
            physics: pageCount <= 1
                ? const NeverScrollableScrollPhysics()
                : const PageScrollPhysics(),
            onPageChanged: (index) {
              if (!mounted) return;
              if (index != _spotlightPage) {
                setState(() => _spotlightPage = index);
              }
              if (!_spotlightUserDragging) _startSpotlightAutoAdvance();
            },
            itemBuilder: (context, index) {
              final pageIndex =
                  ((index - _spotlightInitialPage) % pageCount + pageCount) % pageCount;
              if (_speedDial.isNotEmpty && pageIndex == tracks.length) {
                return _speedDialHeroPage();
              }
              final track = tracks[pageIndex];
              return Material(
                color: const Color(0xFF08090C),
                child: InkWell(
                  onTap: () => _play(track, queueOverride: tracks),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      _art(
                        track,
                        size: double.infinity,
                        radius: 0,
                        fit: BoxFit.cover,
                      ),
                      const DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Color(0xB8000000),
                              Color(0x17000000),
                              Color(0x28000000),
                              Color(0xF0000000),
                            ],
                            stops: [0, .30, .52, 1],
                          ),
                        ),
                      ),
                      Positioned(
                        left: 36,
                        right: 28,
                        bottom: 62,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              'PICKED FOR YOU',
                              maxLines: 1,
                              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                                color: Colors.white.withValues(alpha: .72),
                                fontWeight: FontWeight.w700,
                                letterSpacing: 1.35,
                              ),
                            ),
                            const SizedBox(height: 10),
                            Text(
                              track.title,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                                color: Colors.white,
                                fontWeight: FontWeight.w800,
                                height: 1.04,
                                letterSpacing: -.7,
                              ),
                            ),
                            const SizedBox(height: 5),
                            Text(
                              track.artist,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                color: Colors.white.withValues(alpha: .68),
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            const SizedBox(height: 15),
                            Row(
                              children: [
                                FilledButton.icon(
                                  onPressed: () => _play(track, queueOverride: tracks),
                                  style: FilledButton.styleFrom(
                                    backgroundColor: Colors.white.withValues(alpha: .88),
                                    foregroundColor: const Color(0xFF202124),
                                    minimumSize: const Size(0, 36),
                                    padding: const EdgeInsets.symmetric(horizontal: 20),
                                    shape: const StadiumBorder(),
                                  ),
                                  icon: const Icon(Icons.play_arrow_rounded, size: 19),
                                  label: const Text(
                                    'Play',
                                    style: TextStyle(fontWeight: FontWeight.w700),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                if (tracks.length > 1)
                                  IconButton(
                                    tooltip: 'Shuffle featured tracks',
                                    onPressed: _playRandomSpotlight,
                                    style: IconButton.styleFrom(
                                      backgroundColor: Colors.white.withValues(alpha: .16),
                                      foregroundColor: Colors.white,
                                      fixedSize: const Size(38, 38),
                                    ),
                                    icon: const Icon(Icons.shuffle_rounded, size: 18),
                                  ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      if (pageCount > 1)
                        Positioned(
                          top: 18,
                          right: 20,
                          child: Row(
                            children: List.generate(pageCount, (dotIndex) {
                              final selected = dotIndex == activePage;
                              return AnimatedContainer(
                                duration: const Duration(milliseconds: 220),
                                curve: Curves.easeOutCubic,
                                margin: const EdgeInsets.only(left: 4),
                                width: selected ? 18 : 5,
                                height: 4,
                                decoration: BoxDecoration(
                                  color: selected
                                      ? Colors.white.withValues(alpha: .9)
                                      : Colors.white.withValues(alpha: .38),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                              );
                            }),
                          ),
                        ),
                    ],
                  ),
                ),
              );
            },
            ),
          ),
          builder: (context, progress, child) {
            final blur = progress * 8;
            return ClipRect(
              child: Transform.translate(
                offset: Offset(0, -heroHeight * .14 * progress),
                child: Transform.scale(
                  alignment: Alignment.topCenter,
                  scale: 1 + progress * .08,
                  child: Opacity(
                    opacity: 1 - progress * .35,
                    child: ImageFiltered(
                      imageFilter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
                      child: child!,
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _listeningPicksShelf() {
    if (_listeningPicks.isEmpty) return const SliverToBoxAdapter();
    return SliverToBoxAdapter(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _shelfHeading('Top Picks for You'),
          SizedBox(
            height: 190,
            child: ListView.separated(
              padding: const EdgeInsets.only(left: 20, right: 36),
              scrollDirection: Axis.horizontal,
              itemCount: _listeningPicks.length,
              separatorBuilder: (_, __) => const SizedBox(width: 15),
              itemBuilder: (context, index) => _feedCard(
                _listeningPicks[index],
                queueOverride: _listeningPicks,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _recentlyPlayedShelf() {
    if (_recentlyPlayed.isEmpty) return const SliverToBoxAdapter();
    return SliverToBoxAdapter(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _shelfHeading('Recently Played'),
          SizedBox(
            height: 190,
            child: ListView.separated(
              padding: const EdgeInsets.only(left: 20, right: 36),
              scrollDirection: Axis.horizontal,
              itemCount: _recentlyPlayed.length,
              separatorBuilder: (_, __) => const SizedBox(width: 15),
              itemBuilder: (context, index) => _feedCard(
                _recentlyPlayed[index],
                queueOverride: _recentlyPlayed,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _showTrackMenu(DiscoverTrack track) {
    final local = AppSettings.instance.discoverLocalLossless
        ? DiscoverService.findLocalLosslessMatch(track, _localLibrary) : null;
    return PopupMenuButton<String>(
      onSelected: (value) {
        if (value == 'speed_dial') _toggleSpeedDial(track);
        if (value == 'play') _play(track);
        if (value == 'radio') _loadRadio(track);
        if (value == 'lyrics') _showLyrics(track, local: local);
      },
      itemBuilder: (_) => [
        const PopupMenuItem(value: 'play', child: Text('Play')),
        PopupMenuItem(
          value: 'speed_dial',
          child: Text(_isSpeedDialPinned(track)
              ? 'Remove from Speed Dial'
              : 'Add to Speed Dial'),
        ),
        const PopupMenuItem(value: 'radio', child: Text('Start radio')),
        if (AppSettings.instance.discoverLyrics)
          const PopupMenuItem(value: 'lyrics', child: Text('Lyrics')),
      ],
      icon: const Icon(Icons.more_horiz_rounded),
    );
  }


  Widget _trackPager(_DiscoverShelf shelf) {
    final tracks = shelf.tracks.take(20).toList(growable: false);
    if (tracks.isEmpty) return const SliverToBoxAdapter(child: SizedBox.shrink());
    final width = MediaQuery.sizeOf(context).width * .86;
    final pageCount = (tracks.length / 4).ceil();
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.only(top: 24),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _shelfHeading(shelf.title, onSeeAll: () => _showShelf(shelf)),
          SizedBox(
            height: 4 * 66,
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              scrollDirection: Axis.horizontal,
              itemCount: pageCount,
              separatorBuilder: (_, __) => const SizedBox(width: 10),
              itemBuilder: (context, page) {
                final start = page * 4;
                final end = (start + 4).clamp(0, tracks.length).toInt();
                return SizedBox(
                  width: width,
                  child: Column(children: [
                    for (var index = start; index < end; index++)
                      Expanded(child: _compactTrackRow(tracks[index])),
                  ]),
                );
              },
            ),
          ),
        ]),
      ),
    );
  }

  Widget _compactTrackRow(DiscoverTrack track) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: () => _play(track),
      child: Row(children: [
        _art(track, size: 50),
        const SizedBox(width: 10),
        Expanded(child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(track.title, maxLines: 1, overflow: TextOverflow.ellipsis,
              style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 2),
            Text(track.artist, maxLines: 1, overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          ],
        )),
        SizedBox(width: 36, child: _showTrackMenu(track)),
      ]),
    );
  }

  bool _isMoodOrGenreShelf(_DiscoverShelf shelf) {
    final title = shelf.title.trim().toLowerCase();
    return title.contains('genre') ||
        title.contains('mood') ||
        title.contains('moment');
  }

  bool _isRecentHomeShelf(_DiscoverShelf shelf) {
    final normalized = shelf.title.trim().toLowerCase();
    return normalized == 'recent' ||
        normalized == 'recents' ||
        normalized == 'recently played' ||
        normalized == 'recently played tracks';
  }

  bool _isListLayoutShelf(_DiscoverShelf shelf) {
    final title = shelf.title.toLowerCase();
    return title.contains('recents') ||
        title.contains('quick picks') ||
        title.contains('listen again') ||
        title.contains('your music') ||
        title.contains('top songs');
  }

  void _openHomeItem(DiscoverHomeItem item, List<DiscoverHomeItem> shelfItems) {
    if (item.isPlayableTrack) {
      final queue = shelfItems.where((entry) => entry.isPlayableTrack)
          .map((entry) => entry.toTrack()).toList(growable: false);
      _play(item.toTrack(), queueOverride: queue.isEmpty ? null : queue);
      return;
    }
    if (item.browseId.isNotEmpty) {
      _openMood(DiscoverMood(
        title: item.title,
        browseId: item.browseId,
        params: item.params,
      ));
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('This collection cannot be opened right now.')),
    );
  }

  Widget _homeItemCard(
    DiscoverHomeItem item,
    List<DiscoverHomeItem> shelfItems, {
    double cardWidth = 137,
  }) {
    final track = item.toTrack();
    final isArtist = item.type == DiscoverHomeItemType.artist;
    return SizedBox(
      width: cardWidth,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => _openHomeItem(item, shelfItems),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AspectRatio(
              aspectRatio: 1,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(isArtist ? 84 : 14),
                child: _art(track, size: double.infinity, radius: isArtist ? 84 : 14),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              item.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              item.subtitle.isNotEmpty
                  ? item.subtitle
                  : switch (item.type) {
                      DiscoverHomeItemType.playlist => 'Playlist',
                      DiscoverHomeItemType.album => 'Album',
                      DiscoverHomeItemType.artist => 'Artist',
                      DiscoverHomeItemType.collection => 'Collection',
                      DiscoverHomeItemType.track => 'Song',
                    },
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurface.withValues(alpha: .5),
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }

  bool _isCommunityShelf(_DiscoverShelf shelf) {
    final title = shelf.title.toLowerCase();
    return title.contains('community') &&
        shelf.items.any((item) => item.type == DiscoverHomeItemType.playlist);
  }

  Widget _communityHomeShelf(_DiscoverShelf shelf) {
    final items = shelf.items.take(4).toList(growable: false);
    if (items.isEmpty) return _homeShelf(shelf);
    final width = (MediaQuery.sizeOf(context).width - 52) / 2;
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.only(top: 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _shelfHeading(shelf.title),
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              padding: const EdgeInsets.symmetric(horizontal: 20),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                crossAxisSpacing: 12,
                mainAxisSpacing: 14,
                mainAxisExtent: width + 52,
              ),
              itemCount: items.length,
              itemBuilder: (context, index) =>
                  _homeItemCard(items[index], items, cardWidth: width),
            ),
          ],
        ),
      ),
    );
  }

  bool _isArtistShelf(_DiscoverShelf shelf) =>
      AppSettings.instance.discoverArtistGrid &&
      shelf.items.length >= 4 &&
      shelf.items.every((item) => item.type == DiscoverHomeItemType.artist);

  Widget _artistHomeShelf(_DiscoverShelf shelf) {
    final items = shelf.items.take(8).toList(growable: false);
    final width = (MediaQuery.sizeOf(context).width - 52) / 2;
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.only(top: 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _shelfHeading(shelf.title),
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              padding: const EdgeInsets.symmetric(horizontal: 20),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                crossAxisSpacing: 12,
                mainAxisSpacing: 14,
                mainAxisExtent: width + 52,
              ),
              itemCount: items.length,
              itemBuilder: (context, index) =>
                  _homeItemCard(items[index], items, cardWidth: width),
            ),
          ],
        ),
      ),
    );
  }

  Widget _homeShelf(_DiscoverShelf shelf) {
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.only(top: 24),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _shelfHeading(
            shelf.title,
            onSeeAll: shelf.tracks.isEmpty ? null : () => _showShelf(shelf),
          ),
          SizedBox(
            height: 190,
            child: ListView.separated(
              padding: const EdgeInsets.only(left: 20, right: 36),
              scrollDirection: Axis.horizontal,
              itemCount: (shelf.items.isNotEmpty
                      ? shelf.items.length
                      : shelf.tracks.length).clamp(0, 12),
              separatorBuilder: (_, __) => const SizedBox(width: 15),
              itemBuilder: (context, index) {
                if (shelf.items.isNotEmpty) {
                  return _homeItemCard(shelf.items[index], shelf.items);
                }
                return _feedCard(shelf.tracks[index]);
              },
            ),
          ),
        ]),
      ),
    );
  }

  Widget _feedRow(DiscoverTrack track) {
    final local = AppSettings.instance.discoverLocalLossless
        ? DiscoverService.findLocalLosslessMatch(track, _localLibrary) : null;
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 3),
      leading: _art(track, size: 54),
      title: Text(track.title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text('${track.artist}${track.durationText.isEmpty ? '' : ' · ${track.durationText}'}${local == null ? '' : ' · LOSSLESS'}',
        maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: PopupMenuButton<String>(
        onSelected: (v) {
          if (v == 'speed_dial') _toggleSpeedDial(track);
          if (v == 'play') _play(track);
          if (v == 'radio') _loadRadio(track);
          if (v == 'lyrics') _showLyrics(track, local: local);
        },
        itemBuilder: (_) => [
          const PopupMenuItem(value: 'play', child: Text('Play')),
          PopupMenuItem(
            value: 'speed_dial',
            child: Text(_isSpeedDialPinned(track)
                ? 'Remove from Speed Dial'
                : 'Add to Speed Dial'),
          ),
          const PopupMenuItem(value: 'radio', child: Text('Start radio')),
          if (AppSettings.instance.discoverLyrics)
            const PopupMenuItem(value: 'lyrics', child: Text('Lyrics')),
        ],
      ),
      onTap: () => _play(track),
    );
  }

  Future<void> _refreshDiscover() async {
    await Future.wait([
      _loadHome(forceRefresh: true),
      _loadLocalLibrary(forceRefresh: true),
    ]);
    if (mounted && _error != null && _tracks.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not refresh Discover. Showing saved results.')),
      );
    }
  }

  Future<void> _openMusicLibrary() async {
    final api = widget.api;
    if (api == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Connect to a PocketLink server to open your music library.')),
      );
      return;
    }
    await Navigator.of(context).push<void>(MaterialPageRoute<void>(
      builder: (_) => MusicLibraryScreen(
        api: api,
        onOpenGenres: _openMoodsAndMoments,
        onOpenImported: () async {
          await Navigator.of(context).push<void>(MaterialPageRoute<void>(
            builder: (_) => ImportedPlaylistManagerScreen(
              api: widget.api!,
              onPlay: _playImportedPlaylist,
            ),
          ));
        },
      ),
    ));
  }
  @override
  Widget build(BuildContext context) {
    super.build(context);
    final top = LayoutInsetsScope.of(context).topClearance;
    final bottom = LayoutInsetsScope.of(context).bottomClearance;
    final hasTracks = _tracks.isNotEmpty;
    final hasPersonalContent = _recentlyPlayed.isNotEmpty ||
        _listeningPicks.isNotEmpty;
    final hasHomeContent = hasTracks || _homeShelves.isNotEmpty || hasPersonalContent;
    final showSpotlightHero = AppSettings.instance.discoverSpotlight &&
        (_spotlightTracks.isNotEmpty || _speedDial.isNotEmpty) &&
        (_homeShelves.isNotEmpty ||
            _sectionTitle == 'Top charts in India' ||
            _sectionTitle.startsWith('Discover in '));
    final showSpotlightSkeleton = _loading && !hasHomeContent &&
        AppSettings.instance.discoverSpotlight;
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: PocketLinkAppBar(
        feathered: true, showHome: false, automaticallyImplyLeading: true,
        title: TitleDropdownPopover<String>(
          tooltip: 'Discover navigation',
          items: const [
            SmokedGlassPopoverMenuItem(value: 'discover', label: 'Discover', icon: Icons.explore_rounded),
            SmokedGlassPopoverMenuItem(value: 'library', label: 'Library', icon: Icons.library_music_rounded),
          ],
          onSelected: (value) {
            if (value == 'library') _openMusicLibrary();
          },
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            const Text('Discover'),
            const SizedBox(width: 2),
            const Icon(Icons.keyboard_arrow_down_rounded, size: 20),
          ]),
        ),
        actionsBeforeHome: [
          IconButton(
            tooltip: 'Search moods and genres',
            onPressed: _openMoodsAndMoments,
            icon: const Icon(Icons.search_rounded),
          ),
        ],
        actions: [PocketLinkAppBarAction(
          label: 'Refresh Discover', icon: Icons.refresh_rounded,
          onPressed: _loading ? null : _refreshDiscover,
        )],
      ),
      body: RefreshIndicator(
        onRefresh: _refreshDiscover,
        child: CustomScrollView(
          controller: _scrollController,
          cacheExtent: 600,
          physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          // Keep the scrollable behind the transparent shared app bar so
          // content can feather through it exactly like the other sections.
          SliverToBoxAdapter(
            child: SizedBox(height: showSpotlightHero || showSpotlightSkeleton ? 0 : top),
          ),
          if (_localLibraryLoading && AppSettings.instance.discoverLocalLossless && widget.api != null)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 10),
                child: Row(
                  children: [
                    const SizedBox(
                      width: 13,
                      height: 13,
                      child: CircularProgressIndicator(strokeWidth: 1.6),
                    ),
                    const SizedBox(width: 9),
                    Text(
                      'Checking server music library…',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (_loading && !hasHomeContent)
              _discoverHomeSkeleton()
            else if (_error != null && !hasHomeContent)
              SliverFillRemaining(hasScrollBody: false, child: Center(child: Padding(
                padding: const EdgeInsets.all(28),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.cloud_off_rounded, size: 38),
                  const SizedBox(height: 12),
                  Text(_error!, textAlign: TextAlign.center),
                  const SizedBox(height: 14),
                  FilledButton.icon(onPressed: _loadHome, icon: const Icon(Icons.refresh_rounded), label: const Text('Try again')),
                ]),
              )))
            else if (hasHomeContent) ...[
              if (_loading) const SliverToBoxAdapter(child: LinearProgressIndicator(minHeight: 2)),
              if (_homeShelves.isNotEmpty) ...[
                // BitChord Home order: Top Picks, Recents, then the live
                // upstream shelves. Find Your Mood is inserted after the
                // lead feed shelf rather than before the feed.
                if (AppSettings.instance.discoverSpotlight) _spotlightHero(),
                _recentlyPlayedShelf(),
                _listeningPicksShelf(),
                for (var index = 0; index < _homeShelves.length; index++) ...[
                  if (!_isMoodOrGenreShelf(_homeShelves[index]) &&
                      (_recentlyPlayed.isEmpty ||
                          !_isRecentHomeShelf(_homeShelves[index]))) ...[
                  _isCommunityShelf(_homeShelves[index])
                      ? _communityHomeShelf(_homeShelves[index])
                      : _isArtistShelf(_homeShelves[index])
                          ? _artistHomeShelf(_homeShelves[index])
                          : _isListLayoutShelf(_homeShelves[index]) &&
                              _homeShelves[index].tracks.isNotEmpty &&
                              (_homeShelves[index].items.isEmpty ||
                                  _homeShelves[index].items.every((item) => item.isPlayableTrack))
                          ? _trackPager(_homeShelves[index])
                          : _homeShelf(_homeShelves[index]),
                  ],
                ],
              ] else ...[
                if (_sectionTitle == 'Top charts in India' ||
                    _sectionTitle.startsWith('Discover in ')) ...[
                  if (AppSettings.instance.discoverSpotlight) _spotlightHero(),
                  _recentlyPlayedShelf(),
                ],
                _listeningPicksShelf(),
                if (_tracks.isNotEmpty) ...[
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 18, 20, 10),
                      child: PocketLinkSectionHeader(_sectionTitle),
                    ),
                  ),
                  SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, index) => _feedRow(_tracks[index]),
                      childCount: _tracks.length,
                    ),
                  ),
                ],
                if (_error != null)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              'Online recommendations are unavailable. Your saved and local content is still available.',
                              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: Theme.of(context).colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                          TextButton(
                            onPressed: _loadHome,
                            child: const Text('Retry'),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ],
          if (_loadingMore)
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: 22),
                child: Center(child: SizedBox.square(
                  dimension: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )),
              ),
            ),
          SliverToBoxAdapter(child: SizedBox(height: bottom + 16)),
          ],
        ),
      ),
    );
  }
}
