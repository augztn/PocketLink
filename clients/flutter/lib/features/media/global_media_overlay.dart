import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/physics.dart';
import 'package:flutter/foundation.dart' show ValueListenable;

import 'package:material_ui/material_ui.dart';
import 'package:flutter/scheduler.dart' show TickerCanceled;

import '../../core/navigation/pocketlink_navigation.dart';
import '../../core/network/server_api.dart';
import '../../core/settings/app_settings.dart';
import '../../core/widgets/pocketlink_scaffold.dart';
import '../../core/widgets/liquid_glass_pill.dart';
import 'global_mini_player_bar.dart';
import 'now_playing_screen.dart';
import 'persistent_audio_player.dart';
import 'now_playing_overlay_controller.dart';
import 'now_playing_scrubber.dart';

class GlobalMediaOverlay extends StatefulWidget {
  const GlobalMediaOverlay({required this.child, super.key});

  final Widget child;

  @override
  State<GlobalMediaOverlay> createState() => _GlobalMediaOverlayState();
}

class _GlobalMediaOverlayState extends State<GlobalMediaOverlay>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  static const double _miniPlayerHeight = 62;
  static const double _homeDockHeight = 82;
  static const Duration _trackPopupDuration = Duration(milliseconds: 2300);

  bool _openingNowPlaying = false;
  bool _nowPlayingOpen = false;
  final ValueNotifier<bool> _isNowPlayingDragging = ValueNotifier<bool>(false);
  bool _closingNowPlaying = false;
  bool _snapMiniPlayerVisibility = false;
  Rect? _nowPlayingOriginRect;
  Rect? _miniArtworkOriginRect;
  final ValueNotifier<Uint8List?> _sharedArtwork = ValueNotifier(null);
  Route<void>? _nowPlayingRoute;
  late final AnimationController _nowPlayingController;
  MediaQueueItem? _lastTrack;
  int _lastTrackIndex = 0;
  MediaQueueItem? _trackPopup;
  int _trackDirection = 1;
  Offset? _trackPopupOffset;
  Timer? _trackPopupTimer;

  PersistentAudioPlayer get _player => PersistentAudioPlayer.instance;

  @override
  void initState() {
    super.initState();
    _lastTrack = _player.currentItem;
    _lastTrackIndex = _player.currentIndex;
    _nowPlayingController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 380),
      reverseDuration: const Duration(milliseconds: 320),
    );
    NowPlayingOverlayController.register(_openNowPlaying);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) WidgetsBinding.instance.addObserver(this);
    });
    _player.addListener(_onPlayerChanged);
  }

  @override
  void dispose() {
    _player.removeListener(_onPlayerChanged);
    _trackPopupTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    NowPlayingOverlayController.unregister();
    _nowPlayingRoute = null;
    _nowPlayingController.stop();
    _isNowPlayingDragging.dispose();
    _sharedArtwork.dispose();
    _nowPlayingController.dispose();
    super.dispose();
  }

  void _onPlayerChanged() {
    final current = _player.currentItem;
    final previous = _lastTrack;
    final changed = current?.path != previous?.path ||
        current?.volume != previous?.volume;
    final currentIndex = _player.currentIndex;
    final previousIndex = _lastTrackIndex;
    _lastTrack = current;
    _lastTrackIndex = currentIndex;
    if (changed) _sharedArtwork.value = null;
    if (!changed || previous == null || current == null || !_player.isMusic) {
      return;
    }

    final queueLength = _player.queue.length;
    final requestedDirection = _player.takePendingTrackDirection();
    final wrappedBackward = queueLength > 1 &&
        previousIndex == 0 &&
        currentIndex == queueLength - 1;
    final movedForward = requestedDirection != null
        ? requestedDirection > 0
        : !wrappedBackward &&
            (currentIndex > previousIndex ||
                (previousIndex == queueLength - 1 && currentIndex == 0));
    _trackPopupTimer?.cancel();
    setState(() {
      _trackDirection = movedForward ? 1 : -1;
      _trackPopup = current;
      _trackPopupOffset = null;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _positionTrackPopup());
    _trackPopupTimer = Timer(_trackPopupDuration, () {
      if (mounted) setState(() => _trackPopup = null);
    });
  }

  void _positionTrackPopup() {
    if (!mounted || _trackPopup == null) return;
    final buttonContext = PocketLinkNavigation.musicButtonKey.currentContext;
    final button = buttonContext?.findRenderObject();
    final overlay = PocketLinkNavigation.mediaOverlayKey.currentContext
        ?.findRenderObject();
    if (button is! RenderBox || overlay is! RenderBox ||
        !button.attached || !overlay.attached) {
      return;
    }

    final buttonPosition = button.localToGlobal(Offset.zero, ancestor: overlay);
    final size = overlay.size;
    const popupWidth = 184.0;
    const popupHeight = 44.0;
    final left = 14.0.clamp(0.0, math.max(0.0, size.width - popupWidth)).toDouble();
    final miniPlayerOffset = _shouldShowMiniPlayer() ? _miniPlayerHeight : 0.0;
    final top = (buttonPosition.dy - popupHeight - 8 - miniPlayerOffset)
        .clamp(8.0, math.max(8.0, size.height - popupHeight - 8))
        .toDouble();
    if (mounted) setState(() => _trackPopupOffset = Offset(left, top));
  }

  bool _shouldShowMiniPlayer() {
    final player = _player;
    final standaloneDiscover =
        PocketLinkNavigation.observer.isStandaloneDiscoverFlow;
    return player.shouldShowMiniPlayer &&
        (standaloneDiscover || AppSettings.instance.showMiniPlayer);
  }

  void _prepareNowPlaying() {
    if (_nowPlayingOpen || _openingNowPlaying) return;
    final player = _player;
    final item = player.currentItem;
    final navigator = PocketLinkNavigation.navigatorKey.currentState;
    if (!player.isMusic || !player.isActive || item == null || navigator == null) {
      return;
    }

    _openingNowPlaying = true;
    final media = MediaQuery.of(context);
    final mediaOverlayBox =
        PocketLinkNavigation.mediaOverlayKey.currentContext?.findRenderObject();
    final globalOrigin = PocketLinkNavigation.resolveMediaOriginRect(
      preferMiniPlayer: _shouldShowMiniPlayer(),
    );
    _nowPlayingOriginRect =
        globalOrigin != null && mediaOverlayBox is RenderBox
            ? globalOrigin.shift(
                -mediaOverlayBox.localToGlobal(Offset.zero),
              )
            : globalOrigin;
    _miniArtworkOriginRect =
        PocketLinkNavigation.resolveMediaRect(PocketLinkNavigation.miniArtworkKey);
    _nowPlayingController.value = 0;
    setState(() {
      _nowPlayingOpen = true;
      _isNowPlayingDragging.value = false;
    });

    final route = PageRouteBuilder<void>(
      opaque: false,
      barrierColor: Colors.transparent,
      maintainState: true,
      settings: const RouteSettings(name: PocketLinkRouteNames.nowPlaying),
      transitionDuration: Duration.zero,
      reverseTransitionDuration: Duration.zero,
      pageBuilder: (_, __, ___) => ValueListenableBuilder<bool>(
        valueListenable: _isNowPlayingDragging,
        builder: (context, isDragging, _) => _NowPlayingMorphOverlay(
          animation: _nowPlayingController,
          media: media,
          originRect: _nowPlayingOriginRect,
          sourceArtworkRect: _miniArtworkOriginRect,
          artworkBytes: _sharedArtwork,
          artworkTargetKey: PocketLinkNavigation.nowPlayingArtworkKey,
          player: player,
          api: player.api,
          isDragging: isDragging,
          onDismiss: () => _closeNowPlaying(),
          onDragStart: () => _isNowPlayingDragging.value = true,
          onDragUpdate: _updateNowPlayingDrag,
          onDragEnd: _endNowPlayingDrag,
        ),
      ),
    );
    _nowPlayingRoute = route;
    unawaited(navigator.push<void>(route).then((_) {
      if (!mounted || !identical(_nowPlayingRoute, route)) return;
      _nowPlayingRoute = null;
      _closingNowPlaying = false;
      _openingNowPlaying = false;
      _nowPlayingController.value = 0;
      _snapMiniPlayerVisibility = true;
      setState(() {
        _nowPlayingOpen = false;
        _isNowPlayingDragging.value = false;
        _nowPlayingOriginRect = null;
        _miniArtworkOriginRect = null;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_snapMiniPlayerVisibility) return;
        setState(() => _snapMiniPlayerVisibility = false);
      });
    }));
  }

  Future<void> _openNowPlaying() async {
    if (_openingNowPlaying || _nowPlayingOpen) return;
    _prepareNowPlaying();
    if (!_nowPlayingOpen) return;
    try {
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted || !_nowPlayingOpen) return;
      if (MediaQuery.of(context).disableAnimations) {
        _nowPlayingController.value = 1;
      } else {
        await _animateNowPlayingTo(1);
      }
    } on TickerCanceled {
      // A close gesture can interrupt the opening animation.
    } finally {
      _openingNowPlaying = false;
    }
  }

  Future<void> _animateNowPlayingTo(
    double target, {
    double velocity = 0,
  }) async {
    if (MediaQuery.of(context).disableAnimations) {
      _nowPlayingController.value = target;
      return;
    }
    final spring = SpringDescription.withDampingRatio(
      mass: 1,
      stiffness: 520,
      ratio: 0.90,
    );
    await _nowPlayingController.animateWith(
      SpringSimulation(
        spring,
        _nowPlayingController.value,
        target,
        velocity,
      ),
    );
  }

  Future<void> _closeNowPlaying({double velocity = 0}) async {
    if (!_nowPlayingOpen || _closingNowPlaying) return;
    _closingNowPlaying = true;
    try {
      await _animateNowPlayingTo(0, velocity: velocity);
    } on TickerCanceled {
      // The route is already being removed.
    }

    _isNowPlayingDragging.value = false;
    final navigator = PocketLinkNavigation.navigatorKey.currentState;
    final route = _nowPlayingRoute;
    if (navigator != null && route != null) {
      // Remove only after the shared controller has completed its reverse spring.
      navigator.removeRoute(route);
    }
  }

  void _updateMiniPlayerDrag(double delta) {
    // Only an upward drag expands. A downward swipe retains the paused-player
    // dismiss shortcut and never opens an intermediate route.
    if (!_nowPlayingOpen && delta < 0) _prepareNowPlaying();
    if (!_nowPlayingOpen) return;
    _openingNowPlaying = false;
    if (MediaQuery.of(context).disableAnimations) {
      _nowPlayingController.value = 1;
      return;
    }
    final height = MediaQuery.sizeOf(context).height;
    _nowPlayingController.value =
        PocketLinkNavigation.updateMorphProgress(
      current: _nowPlayingController.value,
      dragDelta: delta,
      extent: height,
    );
  }

  void _endMiniPlayerDrag(double velocity) {
    if (!_nowPlayingOpen) {
      if (!_player.player.state.playing && velocity > 300) {
        _player.dismissMiniPlayer();
      }
      return;
    }
    _openingNowPlaying = false;
    final height = math.max(1.0, MediaQuery.sizeOf(context).height);
    final expand = PocketLinkNavigation.shouldExpandFromMiniPlayer(
      progress: _nowPlayingController.value,
      upwardVelocity: velocity,
    );
    if (expand) {
      unawaited(_animateNowPlayingTo(
        1,
        velocity: -velocity / height,
      ));
    } else {
      unawaited(_closeNowPlaying(velocity: -velocity / height));
    }
  }

  void _updateNowPlayingDrag(double delta) {
    if (!_nowPlayingOpen) return;
    if (MediaQuery.of(context).disableAnimations) {
      _nowPlayingController.value = delta > 0 ? 0 : 1;
      return;
    }
    final height = MediaQuery.sizeOf(context).height;
    _nowPlayingController.value =
        PocketLinkNavigation.updateMorphProgress(
      current: _nowPlayingController.value,
      dragDelta: delta,
      extent: height,
    );
  }

  void _endNowPlayingDrag(double velocity) {
    if (!_nowPlayingOpen) return;
    final height = math.max(1.0, MediaQuery.sizeOf(context).height);
    final collapse = PocketLinkNavigation.shouldCollapseNowPlaying(
      progress: _nowPlayingController.value,
      downwardVelocity: velocity,
    );
    _isNowPlayingDragging.value = false;
    if (collapse) {
      unawaited(_closeNowPlaying(velocity: -velocity / height));
    } else {
      unawaited(_animateNowPlayingTo(
        1,
        velocity: -velocity / height,
      ));
    }
  }

  @override
  Future<bool> didPopRoute() async {
    if (!_nowPlayingOpen ||
        PocketLinkNavigation.observer.isModalRouteOnTop ||
        !PocketLinkNavigation.observer.isNowPlayingVisible) {
      return false;
    }
    await _closeNowPlaying();
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final player = _player;
    final settings = AppSettings.instance;
    final observer = PocketLinkNavigation.observer;

    return AnimatedBuilder(
      animation: Listenable.merge(<Listenable>[
        player,
        settings,
        PocketLinkNavigation.drawerOpen,
        PocketLinkNavigation.quickShortcutsOpen,
      ]),
      builder: (context, _) => ValueListenableBuilder<List<Route<dynamic>>>(
        valueListenable: observer.routeStack,
        builder: (context, routes, __) {
          final drawerOpen = PocketLinkNavigation.drawerOpen.value;
          final miniPlayerAvailable = _shouldShowMiniPlayer() &&
              !drawerOpen &&
              !PocketLinkNavigation.quickShortcutsOpen.value;
          final shouldRenderMiniPlayer = miniPlayerAvailable &&
              (_nowPlayingOpen ||
                  (!observer.isNowPlayingVisible &&
                      !observer.isModalRouteOnTop));
          final visible = shouldRenderMiniPlayer &&
              !_nowPlayingOpen &&
              !observer.isNowPlayingVisible &&
              !observer.isModalRouteOnTop &&
              _nowPlayingController.value <= 0.0;
          final onDashboard = observer.isDashboardVisible;
          final showTrackPopup = _trackPopup != null &&
              _trackPopupOffset != null &&
              onDashboard &&
              !_shouldShowMiniPlayer() &&
              !drawerOpen &&
              !_nowPlayingOpen &&
              !observer.isNowPlayingVisible &&
              !observer.isModalRouteOnTop;
          final media = MediaQuery.of(context);
          final reduceMotion = media.disableAnimations;
          final bottomInset = media.padding.bottom;

          // Keep the navigator at full height. Every route reads the same
          // measured header and mounted-overlay geometry from this scope.
          final navigatorContent = PocketLinkScaffold(
            routeIdentity: observer.currentPageRoute,
            activeRouteIdentities: routes
                .whereType<PageRoute<dynamic>>()
                .cast<Object>()
                .toList(growable: false),
            hasFloatingNavBar: onDashboard,
            hasActiveMiniPlayer: shouldRenderMiniPlayer,
            child: widget.child,
          );

          return Stack(
            key: PocketLinkNavigation.mediaOverlayKey,
            fit: StackFit.expand,
            children: [
              Positioned.fill(child: navigatorContent),
              if (onDashboard)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  height: math.max(64.0, bottomInset + 48.0),
                  child: const IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.transparent,
                          Color(0xA6000000),
                        ],
                      ),
                    ),
                    ),
                  ),
                ),
              if (shouldRenderMiniPlayer)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: bottomInset + (onDashboard ? _homeDockHeight : 0),
                  child: IgnorePointer(
                    ignoring: !visible,
                    child: AnimatedSlide(
                      offset: Offset.zero,
                      duration: reduceMotion || drawerOpen
                          ? Duration.zero
                          : const Duration(milliseconds: 280),
                      curve: Curves.easeOutCubic,
                      child: _GlobalMiniPlayerBar(
                        visible: visible,
                        hasFloatingNavBar: onDashboard,
                        reduceMotion: reduceMotion ||
                            _nowPlayingOpen ||
                            _snapMiniPlayerVisibility,
                        player: player,
                        artworkBytes: _sharedArtwork,
                        surfaceIntensity: visible ? 1.0 : 0.0,
                        onOpen: _openNowPlaying,
                        onDismiss: player.dismissMiniPlayer,
                        onExpandDragUpdate: _updateMiniPlayerDrag,
                        onExpandDragEnd: _endMiniPlayerDrag,
                      ),
                    ),
                  ),
                ),
              Positioned(
                left: _trackPopupOffset?.dx ?? 0,
                top: _trackPopupOffset?.dy ?? 0,
                child: IgnorePointer(
                  child: AnimatedSwitcher(
                    duration: reduceMotion || drawerOpen
                        ? Duration.zero
                        : const Duration(milliseconds: 260),
                    reverseDuration: reduceMotion || drawerOpen
                        ? Duration.zero
                        : const Duration(milliseconds: 180),
                    switchInCurve: Curves.easeOutBack,
                    switchOutCurve: Curves.easeInCubic,
                    transitionBuilder: (child, animation) => FadeTransition(
                      opacity: animation,
                      child: SlideTransition(
                        position: Tween<Offset>(
                          begin: const Offset(0, 0.16),
                          end: Offset.zero,
                        ).animate(animation),
                        child: ScaleTransition(
                          scale: Tween<double>(begin: 0.92, end: 1).animate(animation),
                          child: child,
                        ),
                      ),
                    ),
                    child: showTrackPopup
                        ? _TrackChangePopup(
                            key: ValueKey('${_trackPopup!.volume}:${_trackPopup!.path}'),
                            item: _trackPopup!,
                            direction: _trackDirection,
                          )
                        : const SizedBox.shrink(),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _NowPlayingMorphOverlay extends StatelessWidget {
  const _NowPlayingMorphOverlay({
    required this.animation,
    required this.media,
    required this.originRect,
    required this.sourceArtworkRect,
    required this.artworkBytes,
    required this.artworkTargetKey,
    required this.isDragging,
    required this.player,
    required this.api,
    required this.onDismiss,
    required this.onDragStart,
    required this.onDragUpdate,
    required this.onDragEnd,
  });

  final Animation<double> animation;
  final MediaQueryData media;
  final Rect? originRect;
  final Rect? sourceArtworkRect;
  final ValueNotifier<Uint8List?> artworkBytes;
  final GlobalKey artworkTargetKey;
  final bool isDragging;
  final PersistentAudioPlayer player;
  final ServerApi? api;
  final VoidCallback onDismiss;
  final VoidCallback onDragStart;
  final ValueChanged<double> onDragUpdate;
  final ValueChanged<double> onDragEnd;

  @override
  Widget build(BuildContext context) {
    final size = media.size;
    final destination = Offset.zero & size;
    final origin = originRect ??
        Rect.fromLTWH(size.width - 292, size.height - 142, 278, 62);
    final sourceArt = sourceArtworkRect ??
        Rect.fromLTWH(origin.left + 10, origin.top + 10, 34, 34);

    return MediaQuery(
      data: media,
      child: AnimatedBuilder(
        animation: animation,
        child: NowPlayingScreen(
          api: api,
          queue: player.queue,
          initialIndex: player.currentIndex,
          resumeExisting: true,
          morphAnimation: animation,
          useSharedArtwork: true,
          artworkTargetKey: artworkTargetKey,
          onArtworkChanged: (bytes) => artworkBytes.value = bytes,
          onDismiss: onDismiss,
          onDismissDragStart: onDragStart,
          onDismissDragUpdate: onDragUpdate,
          onDismissDragEnd: onDragEnd,
        ),
        builder: (context, animatedChild) {
          final t = animation.value.clamp(0.0, 1.0).toDouble();
          final rect = Rect.lerp(origin, destination, t)!;
          final radiusValue = t < 0.5
              ? 22 + (24 - 22) * (t * 2)
              : 24 * (1 - (t - 0.5) * 2);
          final radius = BorderRadius.circular(
            radiusValue + (isDragging ? 4 * (1 - t) : 0),
          );
          final glassIntensity =
              1.0 - (t * 2.5).clamp(0.0, 1.0).toDouble();
          final miniOpacity =
              (1.0 - t / 0.35).clamp(0.0, 1.0).toDouble();
          final targetArt = PocketLinkNavigation.resolveMediaRect(
                artworkTargetKey,
              ) ??
              Rect.fromCenter(
                center: Offset(size.width / 2, size.height * 0.34),
                width: 260,
                height: 260,
              );
          final artworkRect = Rect.lerp(sourceArt, targetArt, t)!;
          final artworkRadius = BorderRadius.lerp(
            BorderRadius.circular(11),
            BorderRadius.circular(26),
            t,
          )!;

          return PopScope<void>(
            canPop: false,
            onPopInvokedWithResult: (didPop, result) {
              if (!didPop) onDismiss();
            },
            child: Material(
              type: MaterialType.transparency,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Positioned.fill(
                    child: IgnorePointer(
                      child: ColoredBox(
                        color: Colors.black.withValues(alpha: 0.55 * t),
                      ),
                    ),
                  ),
                  ClipPath(
                    clipper: _NowPlayingMorphClipper(
                      rect: rect,
                      radius: radius,
                    ),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        Positioned.fill(
                          child: IgnorePointer(
                            ignoring: t < 0.35,
                            child: animatedChild!,
                          ),
                        ),
                        Positioned.fromRect(
                          rect: rect,
                          child: IgnorePointer(
                            child: SmokedGlassSurface(
                              radius: radius,
                              intensity: glassIntensity,
                              child: const SizedBox.expand(),
                            ),
                          ),
                        ),
                        Positioned.fromRect(
                          rect: artworkRect,
                          child: ValueListenableBuilder<Uint8List?>(
                            valueListenable: artworkBytes,
                            builder: (context, bytes, _) =>
                                _SharedMorphArtwork(
                              item: player.currentItem,
                              bytes: bytes,
                              radius: artworkRadius,
                            ),
                          ),
                        ),
                        Positioned.fromRect(
                          rect: rect,
                          child: IgnorePointer(
                            ignoring: t > 0.1,
                            child: Opacity(
                              opacity: miniOpacity,
                              child: _MiniPlayerMorphContents(player: player),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _SharedMorphArtwork extends StatelessWidget {
  const _SharedMorphArtwork({
    required this.item,
    required this.bytes,
    required this.radius,
  });

  final MediaQueueItem? item;
  final Uint8List? bytes;
  final BorderRadius radius;

  @override
  Widget build(BuildContext context) {
    final artworkUrl = item?.artworkUrl;
    Widget fallback() => DecoratedBox(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF6559A8), Color(0xFF24243D)],
            ),
          ),
          child: const Center(
            child: Icon(Icons.music_note_rounded, color: Colors.white, size: 30),
          ),
        );

    return ClipRRect(
      borderRadius: radius,
      child: bytes != null
          ? Image.memory(bytes!, fit: BoxFit.cover, gaplessPlayback: true)
          : artworkUrl?.isNotEmpty == true
              ? Image.network(
                  artworkUrl!,
                  fit: BoxFit.cover,
                  gaplessPlayback: true,
                  errorBuilder: (_, __, ___) => fallback(),
                )
              : fallback(),
    );
  }
}

class _NowPlayingMorphClipper extends CustomClipper<Path> {
  const _NowPlayingMorphClipper({
    required this.rect,
    required this.radius,
  });

  final Rect rect;
  final BorderRadius radius;

  @override
  Path getClip(Size size) => Path()..addRRect(radius.toRRect(rect));

  @override
  bool shouldReclip(_NowPlayingMorphClipper oldClipper) =>
      oldClipper.rect != rect || oldClipper.radius != radius;
}

class _MiniPlayerMorphContents extends StatelessWidget {
  const _MiniPlayerMorphContents({required this.player});

  final PersistentAudioPlayer player;

  @override
  Widget build(BuildContext context) {
    final item = player.currentItem;
    if (item == null) return const SizedBox.shrink();
    final colors = Theme.of(context).colorScheme;
    final isLight = Theme.of(context).brightness == Brightness.light;
    final foreground =
        isLight ? const Color(0xFF0F172A) : Colors.white;
    final secondaryForeground =
        isLight ? const Color(0xFF475569) : Colors.white54;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          height: 55,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Row(
              children: [
                const SizedBox(width: 34, height: 34),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.labelLarge?.copyWith(
                              color: foreground,
                              fontWeight: FontWeight.w800,
                            ),
                      ),
                      Text(
                        'NOW PLAYING · SWIPE TO SKIP',
                        style: TextStyle(
                          color: secondaryForeground,
                          fontSize: 8,
                          letterSpacing: 0.45,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  onPressed: player.queue.length > 1
                      ? player.skipToPrevious
                      : null,
                  color: foreground,
                  icon: const Icon(Icons.skip_previous_rounded),
                ),
                StreamBuilder<bool>(
                  stream: player.player.stream.buffering,
                  initialData: player.player.state.buffering,
                  builder: (context, bufferingSnapshot) =>
                      StreamBuilder<Duration>(
                    stream: player.player.stream.duration,
                    initialData: player.player.state.duration,
                    builder: (context, durationSnapshot) =>
                        StreamBuilder<bool>(
                      stream: player.player.stream.playing,
                      initialData: player.player.state.playing,
                      builder: (context, playingSnapshot) {
                        final loading =
                            (bufferingSnapshot.data ?? false) ||
                            (durationSnapshot.data ?? Duration.zero) <=
                                Duration.zero;
                        return PlaybackLoadingIndicator(
                          loading: loading,
                          size: 40,
                          child: IconButton(
                            visualDensity: VisualDensity.compact,
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints.tightFor(
                              width: 36,
                              height: 36,
                            ),
                            onPressed: player.togglePlayback,
                            color: foreground,
                            icon: Icon(
                              (playingSnapshot.data ?? false)
                                  ? Icons.pause_rounded
                                  : Icons.play_arrow_rounded,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  onPressed:
                      player.queue.length > 1 ? player.skipToNext : null,
                  color: foreground,
                  icon: const Icon(Icons.skip_next_rounded),
                ),
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(19, 0, 19, 3),
          child: StreamBuilder<Duration>(
            stream: player.player.stream.position,
            initialData: player.player.state.position,
            builder: (context, positionSnapshot) =>
                StreamBuilder<Duration>(
              stream: player.player.stream.duration,
              initialData: player.player.state.duration,
              builder: (context, durationSnapshot) {
                final duration = durationSnapshot.data ?? Duration.zero;
                final position = positionSnapshot.data ?? Duration.zero;
                final progress = duration > Duration.zero
                    ? (position.inMilliseconds / duration.inMilliseconds)
                        .clamp(0.0, 1.0)
                        .toDouble()
                    : 0.0;
                return ClipRRect(
                  borderRadius: BorderRadius.circular(2),
                  child: LinearProgressIndicator(
                    value: progress,
                    minHeight: 2.5,
                    backgroundColor:
                        colors.onSurface.withValues(alpha: 0.07),
                    valueColor: AlwaysStoppedAnimation<Color>(
                      colors.primary.withValues(alpha: 0.92),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}

class _TrackChangePopup extends StatelessWidget {
  const _TrackChangePopup({required this.item, required this.direction, super.key});

  final MediaQueueItem item;
  final int direction;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Material(
      elevation: 6,
      color: colors.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(15),
      child: Container(
        width: 184,
        height: 44,
        padding: const EdgeInsets.symmetric(horizontal: 9),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(15),
          border: Border.all(color: colors.outlineVariant.withValues(alpha: 0.5)),
        ),
        child: Row(
          children: [
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: colors.primary.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(9),
              ),
              child: Icon(Icons.graphic_eq_rounded, color: colors.primary, size: 17),
            ),
            const SizedBox(width: 7),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 10.5),
                  ),
                  Text(
                    'NOW PLAYING',
                    style: TextStyle(
                      color: colors.onSurfaceVariant,
                      fontSize: 8,
                      letterSpacing: 0.9,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 5),
            _AnimatedTrackDirection(direction: direction, color: colors.primary),
          ],
        ),
      ),
    );
  }
}

class _AnimatedTrackDirection extends StatelessWidget {
  const _AnimatedTrackDirection({required this.direction, required this.color});

  final int direction;
  final Color color;

  @override
  Widget build(BuildContext context) => AnimatedSwitcher(
        duration: const Duration(milliseconds: 220),
        transitionBuilder: (child, animation) => FadeTransition(
          opacity: animation,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: Offset(direction > 0 ? -0.45 : 0.45, 0),
              end: Offset.zero,
            ).animate(animation),
            child: child,
          ),
        ),
        child: Icon(
          direction > 0 ? Icons.arrow_forward_rounded : Icons.arrow_back_rounded,
          key: ValueKey(direction),
          color: color,
          size: 19,
        ),
      );
}

class _GlobalMiniPlayerBar extends StatelessWidget {
  const _GlobalMiniPlayerBar({
    required this.visible,
    required this.hasFloatingNavBar,
    required this.reduceMotion,
    required this.player,
    required this.artworkBytes,
    required this.surfaceIntensity,
    required this.onOpen,
    required this.onDismiss,
    required this.onExpandDragUpdate,
    required this.onExpandDragEnd,
  });

  final bool visible;
  final bool hasFloatingNavBar;
  final bool reduceMotion;
  final PersistentAudioPlayer player;
  final ValueListenable<Uint8List?> artworkBytes;
  final double surfaceIntensity;
  final VoidCallback onOpen;
  final VoidCallback onDismiss;
  final ValueChanged<double> onExpandDragUpdate;
  final ValueChanged<double> onExpandDragEnd;

  @override
  Widget build(BuildContext context) {
    final item = player.currentItem;
    if (item == null) return const SizedBox.shrink();

    return ValueListenableBuilder<Uint8List?>(
      valueListenable: artworkBytes,
      builder: (context, artwork, _) => StreamBuilder<bool>(
        stream: player.player.stream.playing,
        initialData: player.player.state.playing,
        builder: (context, playingSnapshot) => StreamBuilder<Duration>(
          stream: player.player.stream.position,
          initialData: player.player.state.position,
          builder: (context, positionSnapshot) => StreamBuilder<Duration>(
            stream: player.player.stream.duration,
            initialData: player.player.state.duration,
            builder: (context, durationSnapshot) => GlobalMiniPlayerBar(
              item: item,
              visible: visible,
              reduceMotion: reduceMotion,
              isPlaying: playingSnapshot.data ?? false,
              position: positionSnapshot.data ?? Duration.zero,
              duration: durationSnapshot.data ?? Duration.zero,
              canSkipPrevious: player.queue.length > 1,
              canSkipNext: player.queue.length > 1,
              onOpen: onOpen,
              onDismiss: onDismiss,
              onTogglePlayback: player.togglePlayback,
              onSkipPrevious: player.skipToPrevious,
              onSkipNext: player.skipToNext,
              surfaceKey: PocketLinkNavigation.miniPlayerKey,
              hasFloatingNavBar: hasFloatingNavBar,
              surfaceIntensity: surfaceIntensity,
              artworkBytes: artwork,
              artworkKey: PocketLinkNavigation.miniArtworkKey,
              onExpandDragUpdate: onExpandDragUpdate,
              onExpandDragEnd: onExpandDragEnd,
            ),
          ),
        ),
      ),
    );
  }
}
