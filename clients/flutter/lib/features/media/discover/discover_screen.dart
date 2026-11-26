import 'dart:async';
import 'dart:convert';

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
import 'discover_home_feed_store.dart';
import 'discover_moods_screen.dart';

class _DiscoverShelf {
  const _DiscoverShelf(this.title, this.tracks);
  final String title;
  final List<DiscoverTrack> tracks;
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

class _DiscoverScreenState extends State<DiscoverScreen> with SingleTickerProviderStateMixin {
  static final Map<String, List<IndexedFile>> _localLibraryCache = {};
  static final Map<String, DateTime> _localLibraryCacheUpdated = {};
  final DiscoverService _service = DiscoverService();
  late final AnimationController _shimmerController;
  List<DiscoverTrack> _tracks = const [];
  List<DiscoverTrack> _recentlyPlayed = const [];
  List<DiscoverTrack> _listeningPicks = const [];
  String _listeningPicksSeed = '';
  int _listeningPicksGeneration = 0;
  int _recentlyPlayedGeneration = 0;
  int _moodsGeneration = 0;
  List<DiscoverMoodSection> _moodSections = const [];
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
  String _homeContinuation = '';
  bool _loadingMore = false;
  Future<void>? _homeRequest;
  final ScrollController _scrollController = ScrollController();
  late String _lastRegion;

  @override
  void initState() {
    super.initState();
    AppLogger.event('screen.opened', category: 'screen', component: 'discover');
    _shimmerController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat();
    _lastRegion = AppSettings.instance.discoverRegion;
    _scrollController.addListener(_onDiscoverScroll);
    AppSettings.instance.addListener(_onSettingsChanged);
    _loadLocalLibrary();
    _loadHome();
    unawaited(_loadRecentlyPlayed());
    unawaited(_loadMoods());
  }

  Future<void> _loadRecentlyPlayed() async {
    final generation = _recentlyPlayedGeneration;
    final recent = await DiscoverRecentlyPlayedStore.read();
    if (!mounted || generation != _recentlyPlayedGeneration) return;
    setState(() => _recentlyPlayed = recent);
    if (recent.isNotEmpty) unawaited(_loadListeningPicks(recent.first));
  }

  Future<void> _loadMoods({String? region}) async {
    final targetRegion = region ?? AppSettings.instance.discoverRegion;
    final generation = ++_moodsGeneration;
    try {
      final sections = await _service.moodsAndGenres(region: targetRegion);
      if (mounted && generation == _moodsGeneration &&
          targetRegion == AppSettings.instance.discoverRegion) {
        setState(() => _moodSections = sections);
      }
    } catch (error) {
      AppLogger.warning('Discover mood shelf loading failed', category: 'discover',
        component: 'discover_screen',
        fields: {'failure_type': error.runtimeType.toString()});
    }
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
    final region = AppSettings.instance.discoverRegion;
    if (region == _lastRegion) return;
    _lastRegion = region;
    if (!mounted) return;
    _requestGeneration++;
    _listeningPicksSeed = '';
    final pendingHome = _homeRequest;
    if (pendingHome == null) {
      unawaited(_loadHome(forceRefresh: true));
    } else {
      unawaited(_reloadHomeAfterPending(region, pendingHome));
    }
    unawaited(_loadMoods(region: region));
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
    AppSettings.instance.removeListener(_onSettingsChanged);
    _scrollController.removeListener(_onDiscoverScroll);
    _scrollController.dispose();
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
            (shelf) => _DiscoverShelf(shelf.title, shelf.tracks),
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
          .map((shelf) => _DiscoverShelf(shelf.title, shelf.tracks))
          .where((shelf) => shelf.tracks.isNotEmpty)
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
                ))
            .toList(growable: false),
        feed.shelves,
      );
      final merged = mergedFeed
          .map((shelf) => _DiscoverShelf(shelf.title, shelf.tracks))
          .toList(growable: false);
      if (merged.length == _homeShelves.length &&
          merged.every((shelf) => _homeShelves.any((old) =>
              old.title == shelf.title && old.tracks.length == shelf.tracks.length))) {
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
              title: shelf.title, tracks: shelf.tracks,
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
            title: shelf.title, tracks: shelf.tracks,
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
      unawaited(_populateQueue(queueTracks, startIndex, session)
          .catchError((Object _) {}));
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
  ) async {
    final player = PersistentAudioPlayer.instance;
    Future<MediaQueueItem?> resolveAt(int index) async {
      if (session != player.queueSession) return null;
      try {
        return await _queueItem(tracks[index]);
      } catch (_) {
        return null;
      }
    }

    // Resolve the immediate neighbours concurrently, then fill the rest
    // in a deterministic order without blocking initial playback.
    final order = DiscoverService.progressiveQueueOrder(tracks.length, selectedIndex);
    final immediateCount = (selectedIndex > 0 ? 1 : 0) +
        (selectedIndex + 1 < tracks.length ? 1 : 0);
    final immediate = order.take(immediateCount).toList(growable: false);
    final immediateItems = await Future.wait(immediate.map(resolveAt));
    for (var offset = 0; offset < immediate.length; offset++) {
      final item = immediateItems[offset];
      if (item == null || session != player.queueSession) continue;
      await player.enqueue(
        item,
        insertAtStart: immediate[offset] < selectedIndex,
        expectedSession: session,
      );
    }
    if (session != player.queueSession || !AppSettings.instance.discoverAutoQueue) return;

    for (final index in order.skip(immediate.length)) {
      if (session != player.queueSession) return;
      final item = await resolveAt(index);
      if (item != null) {
        await player.enqueue(
          item,
          insertAtStart: index < selectedIndex,
          expectedSession: session,
        );
      }
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
    return SliverList(
      delegate: SliverChildListDelegate([
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _skeletonLine(width: 142, height: 26),
              const SizedBox(height: 8),
              _skeletonLine(width: 178, height: 10),
            ],
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 238,
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            scrollDirection: Axis.horizontal,
            itemCount: 3,
            separatorBuilder: (_, __) => const SizedBox(width: 12),
            itemBuilder: (_, __) => SizedBox(
              width: 168,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _skeletonBlock(width: 168, height: 168, radius: 14),
                  const SizedBox(height: 9),
                  _skeletonLine(width: 132, height: 10),
                  const SizedBox(height: 6),
                  _skeletonLine(width: 88, height: 8),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 24),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
          child: _skeletonLine(width: 132, height: 12),
        ),
        SizedBox(
          height: 4 * 66,
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            scrollDirection: Axis.horizontal,
            itemCount: 2,
            separatorBuilder: (_, __) => const SizedBox(width: 10),
            itemBuilder: (_, __) => SizedBox(
              width: screenWidth * .86,
              child: Column(
                children: List.generate(4, (_) => Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Row(children: [
                      _skeletonBlock(width: 50, height: 50, radius: 10),
                      const SizedBox(width: 10),
                      Expanded(child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _skeletonLine(width: 150, height: 11),
                          const SizedBox(height: 7),
                          _skeletonLine(width: 92, height: 8),
                        ],
                      )),
                      _skeletonBlock(width: 22, height: 22, radius: 11),
                    ]),
                  ),
                )),
              ),
            ),
          ),
        ),
        const SizedBox(height: 24),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
          child: _skeletonLine(width: 112, height: 12),
        ),
        SizedBox(
          height: 112,
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            scrollDirection: Axis.horizontal,
            itemCount: 4,
            separatorBuilder: (_, __) => const SizedBox(width: 10),
            itemBuilder: (_, __) => _skeletonBlock(
              width: (screenWidth - 50) / 2,
              height: 112,
              radius: 14,
            ),
          ),
        ),
        for (var shelf = 0; shelf < 3; shelf++) ...[
          const SizedBox(height: 24),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
            child: _skeletonLine(width: 118 + shelf * 12, height: 12),
          ),
          SizedBox(
            height: 214,
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              scrollDirection: Axis.horizontal,
              itemCount: 4,
              separatorBuilder: (_, __) => const SizedBox(width: 12),
              itemBuilder: (_, __) => SizedBox(
                width: 148,
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Expanded(child: _skeletonBlock(width: 148, radius: 14)),
                  const SizedBox(height: 9),
                  _skeletonLine(width: 112, height: 10),
                  const SizedBox(height: 6),
                  _skeletonLine(width: 76, height: 8),
                ]),
              ),
            ),
          ),
        ],
      ]),
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
    double cardWidth = 168,
  }) {
    final theme = Theme.of(context);
    final local = AppSettings.instance.discoverLocalLossless
        ? DiscoverService.findLocalLosslessMatch(track, _localLibrary) : null;
    return SizedBox(
      width: cardWidth,
      child: InkWell(
        borderRadius: BorderRadius.circular(7),
        onTap: () => _play(track, queueOverride: queueOverride),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AspectRatio(
              aspectRatio: 1,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  _art(track, size: double.infinity, radius: 7),
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
                          if (v == 'play') _play(track, queueOverride: queueOverride);
                          if (v == 'radio') _loadRadio(track);
                          if (v == 'lyrics') _showLyrics(track, local: local);
                        },
                        itemBuilder: (_) => [
                          const PopupMenuItem(value: 'play', child: Text('Play')),
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
                color: theme.colorScheme.onSurfaceVariant,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _shelfHeading(String title, {VoidCallback? onSeeAll}) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
        child: Row(children: [
          Expanded(child: PocketLinkSectionHeader(title)),
          if (onSeeAll != null)
            TextButton(onPressed: onSeeAll, child: const Text('See all')),
        ]),
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

  Widget _topPickCard(DiscoverTrack track) {
    final screenWidth = MediaQuery.sizeOf(context).width;
    final width = (screenWidth * .60).clamp(190.0, 280.0).toDouble();
    final local = AppSettings.instance.discoverLocalLossless
        ? DiscoverService.findLocalLosslessMatch(track, _localLibrary)
        : null;
    return SizedBox(
      width: width,
      child: AspectRatio(
        aspectRatio: .75,
        child: Material(
          color: const Color(0xFF1A1B20),
          borderRadius: BorderRadius.circular(12),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () => _play(track, queueOverride: _listeningPicks),
            child: Stack(
              fit: StackFit.expand,
              children: [
                _art(track, size: double.infinity, radius: 0),
                const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      stops: [.34, .66, 1],
                      colors: [
                        Color(0x00000000),
                        Color(0x52000000),
                        Color(0xE6000000),
                      ],
                    ),
                  ),
                ),
                if (local != null)
                  Positioned(
                    left: 14,
                    top: 14,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                      decoration: BoxDecoration(
                        color: Colors.black54,
                        borderRadius: BorderRadius.circular(5),
                      ),
                      child: const Text(
                        'LOSSLESS',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 9,
                          fontWeight: FontWeight.w800,
                          letterSpacing: .5,
                        ),
                      ),
                    ),
                  ),
                Positioned(
                  top: 5,
                  right: 5,
                  child: Material(
                    color: Colors.black45,
                    shape: const CircleBorder(),
                    child: PopupMenuButton<String>(
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
                      iconSize: 20,
                      icon: const Icon(Icons.more_horiz_rounded, color: Colors.white),
                      onSelected: (value) {
                        if (value == 'play') _play(track, queueOverride: _listeningPicks);
                        if (value == 'radio') _loadRadio(track);
                        if (value == 'lyrics') _showLyrics(track, local: local);
                      },
                      itemBuilder: (_) => [
                        const PopupMenuItem(value: 'play', child: Text('Play')),
                        const PopupMenuItem(value: 'radio', child: Text('Start radio')),
                        if (AppSettings.instance.discoverLyrics)
                          const PopupMenuItem(value: 'lyrics', child: Text('Lyrics')),
                      ],
                    ),
                  ),
                ),
                Positioned(
                  left: 16,
                  right: 16,
                  bottom: 16,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'BASED ON YOUR RECENT LISTENING',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: themeTextStyle(context, eyebrow: true),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        track.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          color: Colors.white,
                          fontSize: 17,
                          height: 1.2,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        track.artist,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Colors.white.withValues(alpha: .86),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  TextStyle themeTextStyle(BuildContext context, {bool eyebrow = false}) {
    return (eyebrow
        ? Theme.of(context).textTheme.bodySmall
        : Theme.of(context).textTheme.bodyMedium)!.copyWith(
      color: eyebrow ? const Color(0xFFFFD2DA) : Colors.white,
      fontSize: eyebrow ? 10 : 13,
      fontWeight: eyebrow ? FontWeight.w600 : FontWeight.normal,
      letterSpacing: eyebrow ? .65 : 0,
    );
  }

  Widget _listeningPicksShelf() {
    if (_listeningPicks.isEmpty) return const SliverToBoxAdapter();
    final cardWidth = (MediaQuery.sizeOf(context).width * .60).clamp(190.0, 280.0).toDouble();
    return SliverToBoxAdapter(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _shelfHeading('Top Picks for You'),
        SizedBox(
          height: cardWidth / .75,
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            scrollDirection: Axis.horizontal,
            itemCount: _listeningPicks.length,
            separatorBuilder: (_, __) => const SizedBox(width: 14),
            itemBuilder: (context, index) => _topPickCard(_listeningPicks[index]),
          ),
        ),
        const SizedBox(height: 22),
      ]),
    );
  }

  Widget _recentlyPlayedShelf() {
    if (_recentlyPlayed.isEmpty) return const SliverToBoxAdapter();
    final columns = <List<DiscoverTrack>>[
      for (var index = 0; index < _recentlyPlayed.length; index += 4)
        _recentlyPlayed.skip(index).take(4).toList(growable: false),
    ];
    return SliverToBoxAdapter(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _shelfHeading('Recents'),
        SizedBox(
          height: 4 * 58,
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            scrollDirection: Axis.horizontal,
            itemCount: columns.length,
            separatorBuilder: (_, __) => const SizedBox(width: 14),
            itemBuilder: (context, index) => SizedBox(
              width: MediaQuery.sizeOf(context).width * .78,
              child: Column(
                children: [
                  for (final track in columns[index])
                    SizedBox(
                      height: 58,
                      child: InkWell(
                        onTap: () => _play(track, queueOverride: _recentlyPlayed),
                        child: Row(children: [
                          _art(track, size: 46),
                          const SizedBox(width: 11),
                          Expanded(child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(track.title, maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.titleSmall),
                              Text(track.artist, maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                                )),
                            ],
                          )),
                          PopupMenuButton<String>(
                            tooltip: 'More actions',
                            onSelected: (value) {
                              if (value == 'play') _play(track, queueOverride: _recentlyPlayed);
                              if (value == 'radio') _loadRadio(track);
                              if (value == 'lyrics') _showLyrics(track);
                            },
                            itemBuilder: (_) => [
                              const PopupMenuItem(value: 'play', child: Text('Play')),
                              const PopupMenuItem(value: 'radio', child: Text('Start radio')),
                              if (AppSettings.instance.discoverLyrics)
                                const PopupMenuItem(value: 'lyrics', child: Text('Lyrics')),
                            ],
                          ),
                        ]),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 22),
      ]),
    );
  }

  Widget _moodHomeShelf() {
    final sections = _moodSections.where((item) => item.items.isNotEmpty).toList();
    if (sections.isEmpty) return const SliverToBoxAdapter();
    final section = sections.first;
    return SliverToBoxAdapter(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _shelfHeading(section.title, onSeeAll: _openMoodsAndMoments),
        SizedBox(
          height: 116,
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            scrollDirection: Axis.horizontal,
            itemCount: section.items.length.clamp(0, 12),
            separatorBuilder: (_, __) => const SizedBox(width: 10),
            itemBuilder: (context, index) {
              final mood = section.items[index];
              final base = mood.stripeColor == 0
                  ? Theme.of(context).colorScheme.surfaceContainerHighest
                  : Color(mood.stripeColor);
              return SizedBox(
                width: 148,
                child: Material(
                  borderRadius: BorderRadius.circular(12),
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: () => _openMood(mood),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [
                                Color.lerp(base, Colors.white, .12)!,
                                base,
                                Color.lerp(base, Colors.black, .28)!,
                              ],
                            ),
                          ),
                        ),
                        Positioned(
                          right: -18,
                          top: -28,
                          child: Container(
                            width: 112,
                            height: 112,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: Colors.white.withValues(alpha: .18),
                                width: 1.2,
                              ),
                            ),
                          ),
                        ),
                        Positioned(
                          right: 6,
                          top: 12,
                          child: Icon(
                            Icons.graphic_eq_rounded,
                            size: 42,
                            color: Colors.white.withValues(alpha: .22),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(13, 12, 13, 12),
                          child: Align(
                            alignment: Alignment.bottomLeft,
                            child: Text(
                              mood.title,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.w700,
                                color: Colors.white,
                                height: 1.15,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 22),
      ]),
    );
  }

  Widget _showTrackMenu(DiscoverTrack track) {
    final local = AppSettings.instance.discoverLocalLossless
        ? DiscoverService.findLocalLosslessMatch(track, _localLibrary) : null;
    return PopupMenuButton<String>(
      onSelected: (value) {
        if (value == 'play') _play(track);
        if (value == 'radio') _loadRadio(track);
        if (value == 'lyrics') _showLyrics(track, local: local);
      },
      itemBuilder: (_) => [
        const PopupMenuItem(value: 'play', child: Text('Play')),
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

  bool _isListLayoutShelf(_DiscoverShelf shelf) {
    final title = shelf.title.toLowerCase();
    return title.contains('recents') ||
        title.contains('quick picks') ||
        title.contains('listen again') ||
        title.contains('your music') ||
        title.contains('top songs');
  }

  Widget _homeShelf(_DiscoverShelf shelf) {
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.only(top: 24),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _shelfHeading(shelf.title, onSeeAll: () => _showShelf(shelf)),
          SizedBox(
            height: 214,
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              scrollDirection: Axis.horizontal,
              itemCount: shelf.tracks.length.clamp(0, 12),
              separatorBuilder: (_, __) => const SizedBox(width: 12),
              itemBuilder: (context, index) => _feedCard(shelf.tracks[index]),
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
          if (v == 'play') _play(track);
          if (v == 'radio') _loadRadio(track);
          if (v == 'lyrics') _showLyrics(track, local: local);
        },
        itemBuilder: (_) => [
          const PopupMenuItem(value: 'play', child: Text('Play')),
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
      _loadMoods(),
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
    final top = LayoutInsetsScope.of(context).topClearance;
    final bottom = LayoutInsetsScope.of(context).bottomClearance;
    final hasTracks = _tracks.isNotEmpty;
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
          SliverToBoxAdapter(child: SizedBox(height: top)),
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
            if (_loading && !hasTracks)
              _discoverHomeSkeleton()
            else if (_error != null && !hasTracks)
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
            else if (hasTracks) ...[
              if (_loading) const SliverToBoxAdapter(child: LinearProgressIndicator(minHeight: 2)),
              if (_homeShelves.isNotEmpty) ...[
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Listen now',
                          style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.7,
                          ),
                        ),
                        const SizedBox(height: 5),
                        Text(
                          'Picked for you in $_regionName',
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                // BitChord Home order: Top Picks, Recents, then the live
                // upstream shelves. Find Your Mood is inserted after the
                // lead feed shelf rather than before the feed.
                _listeningPicksShelf(),
                _recentlyPlayedShelf(),
                for (var index = 0; index < _homeShelves.length; index++) ...[
                  _isListLayoutShelf(_homeShelves[index])
                      ? _trackPager(_homeShelves[index])
                      : _homeShelf(_homeShelves[index]),
                  if (index == 0) _moodHomeShelf(),
                ],
              ] else ...[
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
