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
  }

  void _onSettingsChanged() {
    final region = AppSettings.instance.discoverRegion;
    if (region == _lastRegion) return;
    _lastRegion = region;
    if (mounted) unawaited(_loadHome(forceRefresh: true));
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
    final cached = DiscoverCache.instance.read<_DiscoverFeedSnapshot>(cacheKey);
    if (cached != null) {
      void restore() {
        _homeShelves = cached.value.shelves;
        _tracks = cached.value.shelves.isEmpty
            ? const []
            : cached.value.shelves.first.tracks;
        _sectionTitle = cached.value.sectionTitle;
        _homeContinuation = cached.value.continuation;
        _error = null;
        _loading = false;
      }

      if (mounted) {
        setState(restore);
      } else {
        restore();
      }
      AppLogger.event('discover.home_cache_restored', category: 'discover',
        component: 'discover_screen',
        fields: {'shelf_count': cached.value.shelves.length,
          'track_count': cached.value.shelves.fold<int>(0, (sum, shelf) => sum + shelf.tracks.length),
          'stale': DiscoverCache.instance.isStale(cached)});
      if (!forceRefresh && !DiscoverCache.instance.isStale(cached)) return;
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
    try {
      final feed = await _service.homeFeed(limit: 50);
      if (!mounted || generation != _requestGeneration) return;
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
    if (_loadingMore || continuation.isEmpty || _homeShelves.isEmpty) return;
    setState(() => _loadingMore = true);
    final generation = _requestGeneration;
    try {
      final feed = await _service.moreHome(continuation, limit: 50);
      if (!mounted || generation != _requestGeneration) return;
      final existingIds = _homeShelves
          .expand((shelf) => shelf.tracks)
          .map((track) => track.videoId)
          .toSet();
      final merged = _homeShelves.map((shelf) =>
          _DiscoverShelf(shelf.title, List<DiscoverTrack>.of(shelf.tracks))).toList();
      for (final pageShelf in feed.shelves) {
        final freshTracks = pageShelf.tracks
            .where((track) => existingIds.add(track.videoId))
            .toList(growable: false);
        if (freshTracks.isEmpty) continue;
        final index = merged.indexWhere((shelf) =>
            shelf.title.toLowerCase() == pageShelf.title.toLowerCase());
        if (index < 0) {
          merged.add(_DiscoverShelf(pageShelf.title, freshTracks));
        } else {
          merged[index] = _DiscoverShelf(
            merged[index].title,
            [...merged[index].tracks, ...freshTracks],
          );
        }
      }
      if (merged.length == _homeShelves.length &&
          merged.every((shelf) => _homeShelves.any((old) =>
              old.title == shelf.title && old.tracks.length == shelf.tracks.length))) {
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
      setState(() {
        _homeShelves = snapshot.shelves;
        _homeContinuation = snapshot.continuation;
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

  Widget _art(DiscoverTrack track, {double size = 56}) {
    final show = AppSettings.instance.discoverArtwork && track.thumbnailUrl.isNotEmpty;
    final placeholder = Container(
      width: size.isFinite ? size : null,
      height: size.isFinite ? size : null,
      color: const Color(0xFF1A1B20),
    );
    return ClipRRect(
      borderRadius: BorderRadius.circular(13),
      child: SizedBox(
        width: size.isFinite ? size : null,
        height: size.isFinite ? size : null,
        child: show
            ? DiscoverThumbnail(
                url: DiscoverThumbnailCache.urlForSize(
                  track.thumbnailUrl,
                  size <= 60 ? 160 : 400,
                ),
                cacheWidth: size <= 60 ? 160 : 400,
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
          padding: const EdgeInsets.fromLTRB(20, 2, 20, 12),
          child: _skeletonLine(width: 86, height: 12),
        ),
        SizedBox(
          height: 286,
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            scrollDirection: Axis.horizontal,
            itemCount: 2,
            separatorBuilder: (_, __) => const SizedBox(width: 12),
            itemBuilder: (_, __) => _skeletonBlock(
              width: screenWidth * .70,
              height: 286,
              radius: 18,
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

  Widget _feedCard(DiscoverTrack track) {
    final theme = Theme.of(context);
    final local = AppSettings.instance.discoverLocalLossless
        ? DiscoverService.findLocalLosslessMatch(track, _localLibrary) : null;
    return SizedBox(width: 148, child: InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () => _play(track),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        AspectRatio(aspectRatio: 1, child: Stack(fit: StackFit.expand, children: [
          _art(track, size: double.infinity),
          if (local != null) Positioned(left: 7, bottom: 7, child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
            decoration: BoxDecoration(color: Colors.black87, borderRadius: BorderRadius.circular(7)),
            child: const Text('LOSSLESS', style: TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w800)),
          )),
          Positioned(right: 4, top: 4, child: Material(
            color: Colors.black45, shape: const CircleBorder(),
            child: PopupMenuButton<String>(
              icon: const Icon(Icons.more_horiz_rounded, color: Colors.white),
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
          )),
        ])),
        const SizedBox(height: 9),
        Text(track.title, maxLines: 1, overflow: TextOverflow.ellipsis,
          style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
        const SizedBox(height: 3),
        Text(track.artist, maxLines: 1, overflow: TextOverflow.ellipsis,
          style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
      ]),
    ));
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
    setState(() {
      _tracks = shelf.tracks;
      _sectionTitle = shelf.title;
      _homeShelves = const [];
      _homeContinuation = '';
    });
  }

  Widget _heroShelf(List<_DiscoverShelf> shelves) {
    final cards = <({DiscoverTrack track, String eyebrow})>[
      for (final shelf in shelves.take(2))
        if (shelf.tracks.isNotEmpty)
          (track: shelf.tracks.first, eyebrow: shelf.title),
    ];
    if (cards.isEmpty) return const SizedBox.shrink();
    final width = MediaQuery.sizeOf(context).width * .70;
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.only(top: 10),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _shelfHeading('Featured'),
          SizedBox(
            height: 286,
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              scrollDirection: Axis.horizontal,
              itemCount: cards.length,
              separatorBuilder: (_, __) => const SizedBox(width: 12),
              itemBuilder: (context, index) {
                final card = cards[index];
                return SizedBox(
                  width: width,
                  child: Material(
                    color: Theme.of(context).colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(18),
                    clipBehavior: Clip.antiAlias,
                    child: InkWell(
                      onTap: () => _play(card.track),
                      child: Stack(fit: StackFit.expand, children: [
                        _art(card.track, size: double.infinity),
                        const DecoratedBox(decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [Colors.transparent, Color(0xE6000000)],
                            stops: [0.32, 1],
                          ),
                        )),
                        Positioned(left: 16, right: 16, bottom: 18, child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(card.eyebrow.toUpperCase(),
                              maxLines: 1, overflow: TextOverflow.ellipsis,
                              style: const TextStyle(color: Colors.white70,
                                fontSize: 10, fontWeight: FontWeight.w800,
                                letterSpacing: 1.1)),
                            const SizedBox(height: 7),
                            Text(card.track.title, maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                color: Colors.white, fontWeight: FontWeight.w900)),
                            const SizedBox(height: 3),
                            Text(card.track.artist, maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: Colors.white70)),
                          ],
                        )),
                        Positioned(right: 8, top: 8, child: Material(
                          color: Colors.black45, shape: const CircleBorder(),
                          child: Theme(
                            data: Theme.of(context).copyWith(
                              popupMenuTheme: const PopupMenuThemeData(
                                color: Color(0xFF24262B),
                              ),
                            ),
                            child: _showTrackMenu(card.track),
                          ),
                        )),
                      ]),
                    ),
                  ),
                );
              },
            ),
          ),
        ]),
      ),
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
                _heroShelf(_homeShelves),
                if (_homeShelves.isNotEmpty) _trackPager(_homeShelves.first),
                for (final shelf in _homeShelves.skip(1)) _homeShelf(shelf),
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
