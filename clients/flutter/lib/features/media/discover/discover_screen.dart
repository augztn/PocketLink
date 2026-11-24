import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/network/server_api.dart';
import '../../../core/settings/app_settings.dart';
import '../../../core/widgets/pocketlink_app_bar.dart';
import '../../../core/widgets/pocketlink_scaffold.dart';
import '../../../core/widgets/smoked_glass_popover_menu.dart';
import '../../../core/widgets/pocketlink_section_header.dart';
import '../data/media_library_repository.dart';
import '../media_library_catalog.dart';
import '../now_playing_overlay_controller.dart';
import '../music_library_screen.dart';
import '../persistent_audio_player.dart';
import 'discover_models.dart';
import 'discover_service.dart';

class _DiscoverShelf {
  const _DiscoverShelf(this.title, this.tracks);
  final String title;
  final List<DiscoverTrack> tracks;
}

class _DiscoverFeedSnapshot {
  const _DiscoverFeedSnapshot(this.shelves, this.sectionTitle);

  final List<_DiscoverShelf> shelves;
  final String sectionTitle;
}

class DiscoverScreen extends StatefulWidget {
  const DiscoverScreen({this.api, this.embedded = false, super.key});

  final ServerApi? api;
  final bool embedded;

  @override
  State<DiscoverScreen> createState() => _DiscoverScreenState();
}

class _DiscoverScreenState extends State<DiscoverScreen> with SingleTickerProviderStateMixin {
  static final Map<String, _DiscoverFeedSnapshot> _feedCache = {};
  static final Map<String, List<IndexedFile>> _localLibraryCache = {};
  final DiscoverService _service = DiscoverService();
  late final AnimationController _shimmerController;
  List<DiscoverTrack> _tracks = const [];
  List<_DiscoverShelf> _homeShelves = const [];
  List<IndexedFile> _localLibrary = const [];
  bool _loading = false;
  bool _loadingLibrary = false;
  bool _startingPlayback = false;
  String? _error;
  String _sectionTitle = 'Top charts in India';
  int _requestGeneration = 0;
  late String _lastRegion;

  @override
  void initState() {
    super.initState();
    _shimmerController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat();
    _lastRegion = AppSettings.instance.discoverRegion;
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
    AppSettings.instance.removeListener(_onSettingsChanged);
    _shimmerController.dispose();
    super.dispose();
  }


  Future<void> _openMoodsAndMoments() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => _MoodsAndMomentsScreen(
          service: _service,
          onOpenTracks: (title, tracks) {
            if (!mounted) return;
            setState(() {
              _tracks = tracks;
              _homeShelves = const [];
              _sectionTitle = title;
              _error = tracks.isEmpty ? 'No tracks found for this mood.' : null;
              _loading = false;
            });
          },
        ),
      ),
    );
  }

  Future<void> _loadLocalLibrary({bool forceRefresh = false}) async {
    final api = widget.api;
    if (_loadingLibrary || api == null) return;
    final cacheKey = api.baseUrl;
    final cached = _localLibraryCache[cacheKey];
    if (!forceRefresh && cached != null) {
      _localLibrary = cached;
      return;
    }
    setState(() => _loadingLibrary = true);
    try {
      final result = await MediaLibraryRepository(
        api: api,
        type: MediaLibraryType.music,
      ).readIndexedMedia();
      if (!mounted) return;
      setState(() {
        _localLibrary = result.items.map((item) => IndexedFile(
          volume: item.volume ?? 'internal',
          path: item.path,
          name: item.entry.name,
          type: item.entry.type,
          size: item.entry.size,
          modified: item.entry.modified,
          mime: '',
          category: 'music',
        )).toList(growable: false);
        _localLibraryCache[cacheKey] = _localLibrary;
      });
    } catch (_) {
      // Discovery remains usable when the host library is temporarily offline.
    } finally {
      if (mounted) {
        setState(() => _loadingLibrary = false);
      } else {
        _loadingLibrary = false;
      }
    }
  }

  Future<void> _loadHome({bool forceRefresh = false}) async {
    final region = AppSettings.instance.discoverRegion;
    final cached = _feedCache[region];
    if (!forceRefresh && cached != null) {
      _homeShelves = cached.shelves;
      _tracks = cached.shelves.isEmpty
          ? const []
          : cached.shelves.first.tracks;
      _sectionTitle = cached.sectionTitle;
      _error = null;
      _loading = false;
      return;
    }
    final generation = ++_requestGeneration;
    setState(() {
      _loading = true;
      _error = null;
      _sectionTitle = 'Top charts in $_regionName';
    });
    try {
      // Build a real discovery landing feed from independent editorial
      // shelves. These are public charts/search feeds, not fabricated
      // personalized recommendations.
      final responses = await Future.wait<List<DiscoverTrack>>([
        _service.home(limit: 24).catchError((Object _) => <DiscoverTrack>[]),
        _service.search('new music releases ${DateTime.now().year} $_regionName', limit: 18).catchError((Object _) => <DiscoverTrack>[]),
        _service.search('popular Malayalam songs', limit: 18).catchError((Object _) => <DiscoverTrack>[]),
        _service.search('popular Hindi songs', limit: 18).catchError((Object _) => <DiscoverTrack>[]),
        _service.search('popular Tamil songs', limit: 18).catchError((Object _) => <DiscoverTrack>[]),
        _service.search('chill relaxing songs playlist', limit: 18).catchError((Object _) => <DiscoverTrack>[]),
        _service.search('workout energetic songs playlist', limit: 18).catchError((Object _) => <DiscoverTrack>[]),
        _service.search('party hits playlist', limit: 18).catchError((Object _) => <DiscoverTrack>[]),
        _service.search('popular music mixes $_regionName', limit: 18).catchError((Object _) => <DiscoverTrack>[]),
      ]);
      if (!mounted || generation != _requestGeneration) return;
      final shelves = <_DiscoverShelf>[
        if (responses[0].isNotEmpty)
          _DiscoverShelf('Trending in $_regionName', responses[0]),
        if (responses[1].isNotEmpty)
          _DiscoverShelf('New releases', responses[1]),
        if (responses[2].isNotEmpty)
          _DiscoverShelf('Malayalam hits', responses[2]),
        if (responses[3].isNotEmpty)
          _DiscoverShelf('Hindi hits', responses[3]),
        if (responses[4].isNotEmpty)
          _DiscoverShelf('Tamil hits', responses[4]),
        if (responses[5].isNotEmpty)
          _DiscoverShelf('Chill & unwind', responses[5]),
        if (responses[6].isNotEmpty)
          _DiscoverShelf('Workout energy', responses[6]),
        if (responses[7].isNotEmpty)
          _DiscoverShelf('Party starters', responses[7]),
        if (responses[8].isNotEmpty)
          _DiscoverShelf('Popular mixes', responses[8]),
      ];
      if (shelves.isEmpty) {
        final fallback = await _service.search('top songs $_regionName');
        if (!mounted || generation != _requestGeneration) return;
        if (fallback.isEmpty) {
          setState(() => _error = 'No music recommendations are available right now.');
          return;
        }
        shelves.add(_DiscoverShelf('Popular in $_regionName', fallback));
      }
      final snapshot = _DiscoverFeedSnapshot(
        List.unmodifiable(shelves),
        'Top charts in $_regionName',
      );
      _feedCache[region] = snapshot;
      setState(() {
        _homeShelves = snapshot.shelves;
        _tracks = shelves.first.tracks;
        _error = null;
      });
    } on PlatformException catch (error) {
      if (!mounted || generation != _requestGeneration) return;
      setState(() => _error = error.message ?? 'YouTube Music home is unavailable.');
    } catch (_) {
      if (!mounted || generation != _requestGeneration) return;
      setState(() => _error = 'Could not load YouTube Music home. Check your connection and try again.');
    } finally {
      if (mounted && generation == _requestGeneration) setState(() => _loading = false);
    }
  }

  Future<void> _loadRadio(DiscoverTrack track) async {
    final generation = ++_requestGeneration;
    setState(() {
      _loading = true;
      _error = null;
      _sectionTitle = 'Radio · ${track.title}';
      _homeShelves = const [];
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

  Future<void> _play(DiscoverTrack track) async {
    // Ignore repeated taps while the first selection is resolving and opening.
    // Otherwise each tap replaces the queue and starts another auto-queue pass.
    if (_startingPlayback) return;
    _startingPlayback = true;
    var sourceTracks = _tracks;
    for (final shelf in _homeShelves) {
      if (shelf.tracks.any((item) => item.videoId == track.videoId)) {
        sourceTracks = shelf.tracks;
        break;
      }
    }
    final results = List<DiscoverTrack>.of(sourceTracks);
    final selectedIndex = results.indexWhere((item) => item.videoId == track.videoId);
    final queueTracks = selectedIndex < 0 ? <DiscoverTrack>[track] : results;
    final startIndex = selectedIndex < 0 ? 0 : selectedIndex;
    try {
      final item = await _queueItem(queueTracks[startIndex]);
      final player = PersistentAudioPlayer.instance;
      await player.openQueue(
        api: widget.api,
        queue: [item],
        initialIndex: 0,
        isMusic: true,
      );
      final session = player.queueSession;
      NowPlayingOverlayController.open();
      unawaited(_populateQueue(queueTracks, startIndex, session).catchError((Object _) {}));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error is PlatformException
            ? error.message ?? 'Could not resolve this track.'
            : 'Could not start playback. Try again later.')),
      );
    } finally {
      _startingPlayback = false;
    }
  }

  Future<MediaQueueItem> _queueItem(DiscoverTrack track) async {
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
    final placeholder = _skeletonBlock(
      width: size.isFinite ? size : null,
      height: size.isFinite ? size : null,
      radius: 13,
    );
    return ClipRRect(
      borderRadius: BorderRadius.circular(13),
      child: SizedBox(
        width: size.isFinite ? size : null,
        height: size.isFinite ? size : null,
        child: show
            ? Image.network(
                track.thumbnailUrl,
                fit: BoxFit.cover,
                frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
                  if (wasSynchronouslyLoaded) return child;
                  return AnimatedOpacity(
                    opacity: frame == null ? 0 : 1,
                    duration: const Duration(milliseconds: 220),
                    curve: Curves.easeOut,
                    child: frame == null
                        ? placeholder
                        : Stack(fit: StackFit.expand, children: [placeholder, child]),
                  );
                },
                errorBuilder: (_, __, ___) => _artFallback(size),
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
        onOpenImported: () {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Playlist import is not connected to the Library screen yet.')),
          );
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
          physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          // Keep the scrollable behind the transparent shared app bar so
          // content can feather through it exactly like the other sections.
          SliverToBoxAdapter(child: SizedBox(height: top)),
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
          SliverToBoxAdapter(child: SizedBox(height: bottom + 16)),
          ],
        ),
      ),
    );
  }
}


class _MoodsAndMomentsScreen extends StatefulWidget {
  const _MoodsAndMomentsScreen({
    required this.service,
    required this.onOpenTracks,
  });

  final DiscoverService service;
  final void Function(String title, List<DiscoverTrack> tracks) onOpenTracks;

  @override
  State<_MoodsAndMomentsScreen> createState() => _MoodsAndMomentsScreenState();
}

class _MoodsAndMomentsScreenState extends State<_MoodsAndMomentsScreen> {
  late Future<List<DiscoverMoodSection>> _sections;
  final TextEditingController _query = TextEditingController();
  bool _searching = false;

  @override
  void initState() {
    super.initState();
    _sections = widget.service.moodsAndGenres();
  }

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  Future<void> _submitSearch() async {
    final query = _query.text.trim();
    if (query.length < 2 || _searching) return;
    setState(() => _searching = true);
    try {
      final tracks = await widget.service.search(query);
      if (!mounted) return;
      Navigator.of(context).pop();
      widget.onOpenTracks(query, tracks);
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Search failed: $error')),
      );
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  Future<void> _openMood(DiscoverMood mood) async {
    if (_searching) return;
    setState(() => _searching = true);
    try {
      final tracks = await widget.service.browseMood(mood);
      if (!mounted) return;
      Navigator.of(context).pop();
      widget.onOpenTracks(mood.title, tracks);
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not load ${mood.title}: $error')),
      );
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: PocketLinkAppBar(
        feathered: true,
        title: const Text('Search'),
        actions: const [],
      ),
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.fromLTRB(20, MediaQuery.paddingOf(context).top + kToolbarHeight + 12, 20, 18),
              child: TextField(
                controller: _query,
                autofocus: false,
                textInputAction: TextInputAction.search,
                onSubmitted: (_) => _submitSearch(),
                decoration: InputDecoration(
                  hintText: 'Songs, artists and albums',
                  prefixIcon: const Icon(Icons.search_rounded),
                  suffixIcon: IconButton(
                    tooltip: 'Search',
                    onPressed: _submitSearch,
                    icon: _searching
                        ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.arrow_forward_rounded),
                  ),
                  filled: true,
                  fillColor: theme.colorScheme.surfaceContainerHighest.withValues(alpha: .72),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(18), borderSide: BorderSide.none),
                ),
              ),
            ),
          ),
          FutureBuilder<List<DiscoverMoodSection>>(
            future: _sections,
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(child: CircularProgressIndicator()),
                );
              }
              if (snapshot.hasError || !snapshot.hasData || snapshot.data!.isEmpty) {
                return SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text('Moods & Moments are unavailable right now.'),
                          const SizedBox(height: 12),
                          FilledButton(
                            onPressed: () => setState(() => _sections = widget.service.moodsAndGenres()),
                            child: const Text('Try again'),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }
              return SliverList(
                delegate: SliverChildListDelegate([
                  for (final section in snapshot.data!) ...[
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
                      child: Text(section.title, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: GridView.builder(
                        padding: EdgeInsets.zero,
                        shrinkWrap: true,
                        primary: false,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: section.items.length,
                        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2,
                          mainAxisExtent: 76,
                          crossAxisSpacing: 10,
                          mainAxisSpacing: 10,
                        ),
                        itemBuilder: (context, index) => _DiscoverMoodTile(
                          mood: section.items[index],
                          service: widget.service,
                          onTap: () => _openMood(section.items[index]),
                        ),
                      ),
                    ),
                    const SizedBox(height: 22),
                  ],
                ]),
              );
            },
          ),
          SliverToBoxAdapter(
            child: SizedBox(
              height: LayoutInsetsScope.of(context).bottomClearance + 24,
            ),
          ),
        ],
      ),
    );
  }
}

class _DiscoverMoodTile extends StatefulWidget {
  const _DiscoverMoodTile({
    required this.mood,
    required this.service,
    required this.onTap,
  });

  final DiscoverMood mood;
  final DiscoverService service;
  final VoidCallback onTap;

  @override
  State<_DiscoverMoodTile> createState() => _DiscoverMoodTileState();
}

class _DiscoverMoodTileState extends State<_DiscoverMoodTile> {
  late Future<List<DiscoverTrack>> _covers;

  @override
  void initState() {
    super.initState();
    _covers = widget.service.browseMood(widget.mood, limit: 2);
  }

  Color _tint(int argb) {
    final source = Color(argb);
    return Color.lerp(source, const Color(0xFF777782), .42) ?? const Color(0xFF454550);
  }

  @override
  Widget build(BuildContext context) {
    final tint = _tint(widget.mood.stripeColor);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: widget.onTap,
        borderRadius: BorderRadius.circular(14),
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            gradient: LinearGradient(
              colors: [
                Color.alphaBlend(tint.withValues(alpha: .55), const Color(0xFF24242A)),
                Color.alphaBlend(tint.withValues(alpha: .16), const Color(0xFF24242A)),
              ],
            ),
          ),
          child: Stack(
            clipBehavior: Clip.hardEdge,
            children: [
              Positioned(
                right: 4,
                top: 5,
                bottom: 5,
                width: 76,
                child: FutureBuilder<List<DiscoverTrack>>(
                  future: _covers,
                  builder: (context, snapshot) {
                    final covers = snapshot.data ?? const <DiscoverTrack>[];
                    return Stack(
                      alignment: Alignment.center,
                      children: [
                        if (covers.length > 1)
                          Transform.translate(
                            offset: const Offset(-12, 2),
                            child: Transform.rotate(
                              angle: -.34,
                              child: _cover(covers[1].thumbnailUrl, 43),
                            ),
                          ),
                        if (covers.isNotEmpty)
                          Transform.translate(
                            offset: const Offset(10, 5),
                            child: Transform.rotate(
                              angle: -.08,
                              child: _cover(covers[0].thumbnailUrl, 48),
                            ),
                          ),
                      ],
                    );
                  },
                ),
              ),
              Align(
                alignment: Alignment.centerLeft,
                child: Padding(
                  padding: const EdgeInsets.only(left: 14, right: 66),
                  child: Text(
                    widget.mood.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      height: 1.1,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _cover(String url, double size) => ClipRRect(
    borderRadius: BorderRadius.circular(8),
    child: SizedBox.square(
      dimension: size,
      child: url.isEmpty
          ? const ColoredBox(color: Color(0xFF393941))
          : Image.network(url, fit: BoxFit.cover, errorBuilder: (_, __, ___) =>
              const ColoredBox(color: Color(0xFF393941))),
    ),
  );
}
