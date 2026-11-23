import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/network/server_api.dart';
import '../../../core/settings/app_settings.dart';
import '../../../core/widgets/pocketlink_app_bar.dart';
import '../../../core/widgets/pocketlink_scaffold.dart';
import '../../../core/widgets/pocketlink_section_header.dart';
import '../data/media_library_repository.dart';
import '../media_library_catalog.dart';
import '../now_playing_overlay_controller.dart';
import '../persistent_audio_player.dart';
import 'discover_models.dart';
import 'discover_service.dart';

class _DiscoverShelf {
  const _DiscoverShelf(this.title, this.tracks);
  final String title;
  final List<DiscoverTrack> tracks;
}

class DiscoverScreen extends StatefulWidget {
  const DiscoverScreen({this.api, this.embedded = false, super.key});

  final ServerApi? api;
  final bool embedded;

  @override
  State<DiscoverScreen> createState() => _DiscoverScreenState();
}

class _DiscoverScreenState extends State<DiscoverScreen> {
  final DiscoverService _service = DiscoverService();
  final TextEditingController _searchController = TextEditingController();
  List<DiscoverTrack> _tracks = const [];
  List<_DiscoverShelf> _homeShelves = const [];
  List<IndexedFile> _localLibrary = const [];
  bool _loading = false;
  bool _loadingLibrary = false;
  String? _error;
  String _sectionTitle = 'Top charts in India';
  int _requestGeneration = 0;
  late String _lastRegion;

  @override
  void initState() {
    super.initState();
    _lastRegion = AppSettings.instance.discoverRegion;
    AppSettings.instance.addListener(_onSettingsChanged);
    _loadLocalLibrary();
    _loadHome();
  }

  void _onSettingsChanged() {
    final region = AppSettings.instance.discoverRegion;
    if (region == _lastRegion) return;
    _lastRegion = region;
    if (mounted) unawaited(_loadHome());
  }

  String get _regionName =>
      AppSettings.discoverRegions[AppSettings.instance.discoverRegion] ?? 'India';

  @override
  void dispose() {
    AppSettings.instance.removeListener(_onSettingsChanged);
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadLocalLibrary() async {
    if (_loadingLibrary || widget.api == null) return;
    setState(() => _loadingLibrary = true);
    try {
      final result = await MediaLibraryRepository(
        api: widget.api!,
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

  Future<void> _loadHome() async {
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
      setState(() {
        _homeShelves = shelves;
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

  Future<void> _search(String query) async {
    if (query.trim().length < 2) return;
    final generation = ++_requestGeneration;
    setState(() {
      _loading = true;
      _error = null;
      _sectionTitle = query.trim();
      _homeShelves = const [];
    });
    try {
      final results = await _service.search(query);
      if (!mounted || generation != _requestGeneration) return;
      setState(() {
        _tracks = results;
        if (results.isEmpty) _error = 'No tracks found. Try another search.';
      });
    } on PlatformException catch (error) {
      if (!mounted || generation != _requestGeneration) return;
      setState(() => _error = error.message ?? 'Discover is unavailable on this device.');
    } catch (_) {
      if (!mounted || generation != _requestGeneration) return;
      setState(() => _error = 'Could not load Discover results. Check your connection and try again.');
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

  Widget _quickSearchChip(String label, String query) => Padding(
        padding: const EdgeInsets.only(right: 8),
        child: ActionChip(
          label: Text(label),
          onPressed: () {
            _searchController.text = query;
            _search(query);
          },
        ),
      );

  Widget _art(DiscoverTrack track, {double size = 56}) {
    final show = AppSettings.instance.discoverArtwork && track.thumbnailUrl.isNotEmpty;
    return ClipRRect(
      borderRadius: BorderRadius.circular(13),
      child: SizedBox(
        width: size.isFinite ? size : null,
        height: size.isFinite ? size : null,
        child: show
          ? Image.network(track.thumbnailUrl, fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => _artFallback(size))
          : _artFallback(size)),
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

  Widget _moodTiles() {
    const moods = <({String title, String query, Color color, IconData icon})>[
      (title: 'Energy', query: 'high energy dance workout songs', color: Color(0xFF236B50), icon: Icons.bolt_rounded),
      (title: 'Relax', query: 'calm relaxing acoustic music', color: Color(0xFF315F91), icon: Icons.water_drop_outlined),
      (title: 'Heartbreak', query: 'sad heartbreak songs', color: Color(0xFF9A5938), icon: Icons.cloud_outlined),
      (title: 'Love', query: 'romantic love songs', color: Color(0xFF9A426C), icon: Icons.favorite_border_rounded),
    ];
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.only(top: 24),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _shelfHeading('Find your mood'),
          SizedBox(
            height: 112,
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              scrollDirection: Axis.horizontal,
              itemCount: moods.length,
              separatorBuilder: (_, __) => const SizedBox(width: 10),
              itemBuilder: (context, index) {
                final mood = moods[index];
                return SizedBox(
                  width: (MediaQuery.sizeOf(context).width - 50) / 2,
                  child: Material(
                    color: mood.color,
                    borderRadius: BorderRadius.circular(14),
                    clipBehavior: Clip.antiAlias,
                    child: InkWell(
                      onTap: () {
                        _searchController.text = mood.query;
                        _search(mood.query);
                      },
                      child: Stack(children: [
                        Positioned(right: 12, top: 8,
                          child: Icon(mood.icon, size: 42, color: Colors.white24)),
                        Positioned(left: 14, bottom: 13,
                          child: Text(mood.title, style: const TextStyle(
                            color: Colors.white, fontSize: 17, fontWeight: FontWeight.w800))),
                        Positioned(right: 10, top: 9,
                          child: Text('PL', style: TextStyle(
                            color: Colors.white.withValues(alpha: .55),
                            fontSize: 9, fontWeight: FontWeight.w900))),
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final top = LayoutInsetsScope.of(context).topClearance;
    final bottom = LayoutInsetsScope.of(context).bottomClearance;
    final hasTracks = _tracks.isNotEmpty;
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: PocketLinkAppBar(
        feathered: true, showHome: false, automaticallyImplyLeading: true,
        title: const Text('Discover'),
        actions: [PocketLinkAppBarAction(
          label: 'Refresh Discover', icon: Icons.refresh_rounded,
          onPressed: _loading ? null : _loadHome,
        )],
      ),
      body: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          // Keep the scrollable behind the transparent shared app bar so
          // content can feather through it exactly like the other sections.
          SliverToBoxAdapter(child: SizedBox(height: top)),
          SliverToBoxAdapter(child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const SizedBox(height: 4),
                TextField(
                  controller: _searchController, textInputAction: TextInputAction.search,
                  onSubmitted: _search,
                  decoration: InputDecoration(
                    hintText: 'Songs, artists and albums',
                    prefixIcon: const Icon(Icons.search_rounded),
                    suffixIcon: IconButton(
                      tooltip: 'Search',
                      onPressed: () => _search(_searchController.text),
                      icon: const Icon(Icons.arrow_forward_rounded),
                    ),
                    filled: true,
                    fillColor: theme.colorScheme.surfaceContainerHighest.withValues(alpha: .72),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(18), borderSide: BorderSide.none),
                  ),
                ),
                const SizedBox(height: 14),
                SizedBox(height: 38, child: ListView(scrollDirection: Axis.horizontal, children: [
                  _quickSearchChip('India', 'top songs India'),
                  _quickSearchChip('Malayalam', 'popular Malayalam songs'),
                  _quickSearchChip('Hindi', 'top Hindi songs'),
                  _quickSearchChip('Tamil', 'popular Tamil songs'),
                  _quickSearchChip('English', 'top English songs'),
                ])),
              ]),
            )),
            if (_loading && !hasTracks)
              const SliverFillRemaining(hasScrollBody: false, child: Center(child: CircularProgressIndicator()))
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
                _moodTiles(),
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
    );
  }
}
