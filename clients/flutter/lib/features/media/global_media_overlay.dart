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
import 'global_mini_player_bar.dart';
import 'now_playing_screen.dart';
import 'persistent_audio_player.dart';
import 'now_playing_overlay_controller.dart';
import 'now_playing_scrubber.dart';
import 'now_playing_artwork_palette.dart';
import 'track_artwork_view.dart';

class GlobalMediaOverlay extends StatefulWidget {
  const GlobalMediaOverlay({required this.child, super.key});

  final Widget child;

  @override
  State<GlobalMediaOverlay> createState() => _GlobalMediaOverlayState();
}

class _GlobalMediaOverlayState extends State<GlobalMediaOverlay>
    with TickerProviderStateMixin {
  static const double _miniPlayerHeight = 62;
  static const double _homeDockHeight = 82;
  static const Duration _trackPopupDuration = Duration(milliseconds: 2300);

  bool _openingNowPlaying = false;
  bool _miniPlayerGestureActive = false;
  bool _nowPlayingOpen = false;
  bool _morphLayoutReady = false;
  double _pendingMiniPlayerDragDelta = 0;
  double? _pendingMiniPlayerDragEndVelocity;
  final ValueNotifier<bool> _isNowPlayingDragging = ValueNotifier<bool>(false);
  bool _closingNowPlaying = false;
  bool _snapMiniPlayerVisibility = false;
  Rect? _nowPlayingOriginRect;
  Rect? _miniArtworkOriginRect;
  final ValueNotifier<Uint8List?> _sharedArtwork = ValueNotifier(null);
  final ValueNotifier<Rect?> _sharedArtworkTargetRect = ValueNotifier(null);
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
    NowPlayingOverlayController.register(
      _openNowPlaying,
      progress: _nowPlayingController,
      collapseHandler: _closeNowPlaying,
    );
    _player.addListener(_onPlayerChanged);
  }

  @override
  void dispose() {
    _player.removeListener(_onPlayerChanged);
    _trackPopupTimer?.cancel();
    NowPlayingOverlayController.unregister();
    _nowPlayingRoute = null;
    _nowPlayingController.stop();
    _isNowPlayingDragging.dispose();
    _sharedArtwork.dispose();
    _sharedArtworkTargetRect.dispose();
    _nowPlayingController.dispose();
    super.dispose();
  }

  void _publishSharedArtwork(Uint8List? bytes) {
    if (mounted) _sharedArtwork.value = bytes;
  }

  void _onPlayerChanged() {
    final current = _player.currentItem;
    final previous = _lastTrack;
    final changed = current?.stableTrackId != previous?.stableTrackId;
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

  void _onMiniPlayerDragStart() {
    if (!mounted) return;
    if (!_miniPlayerGestureActive) {
      setState(() => _miniPlayerGestureActive = true);
    }
    // Mount the morph sheet as soon as a vertical drag is recognized. Waiting
    // for the first update lets the source player disappear before the sheet
    // has had a frame to paint.
    _prepareNowPlaying();
  }

  void _prepareNowPlaying() {
    if (_nowPlayingOpen || _openingNowPlaying ||
        (_nowPlayingRoute?.isActive ?? false)) return;
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
    _sharedArtworkTargetRect.value = null;
    _nowPlayingController.value = 0;
    _morphLayoutReady = false;
    _pendingMiniPlayerDragDelta = 0;
    _pendingMiniPlayerDragEndVelocity = null;
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
          artworkTargetRect: _sharedArtworkTargetRect,
          artworkTargetKey: PocketLinkNavigation.nowPlayingArtworkKey,
          onArtworkChanged: _publishSharedArtwork,
          player: player,
          api: player.api,
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
      _morphLayoutReady = false;
      _pendingMiniPlayerDragDelta = 0;
      _pendingMiniPlayerDragEndVelocity = null;
      _snapMiniPlayerVisibility = true;
      setState(() {
        _nowPlayingOpen = false;
        _isNowPlayingDragging.value = false;
        _nowPlayingOriginRect = null;
        _miniArtworkOriginRect = null;
        _sharedArtworkTargetRect.value = null;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_snapMiniPlayerVisibility) return;
        setState(() => _snapMiniPlayerVisibility = false);
      });
    }));
    // Interactive expansion can begin before the new route has completed its
    // first layout. Hold those initial deltas until the artwork target has a
    // real RenderBox, otherwise the morph starts toward a guessed center rect.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_nowPlayingOpen) return;
      // Capture the expanded artwork target once, after the route has laid
      // out. Re-measuring it on every animation tick can shift the image while
      // the user is dragging, especially as Now Playing fades in.
      _sharedArtworkTargetRect.value = PocketLinkNavigation.resolveMediaRect(
        PocketLinkNavigation.nowPlayingArtworkKey,
      );
      _morphLayoutReady = true;
      final pendingDelta = _pendingMiniPlayerDragDelta;
      _pendingMiniPlayerDragDelta = 0;
      if (pendingDelta != 0) _applyMiniPlayerDrag(pendingDelta);
      final pendingVelocity = _pendingMiniPlayerDragEndVelocity;
      _pendingMiniPlayerDragEndVelocity = null;
      if (pendingVelocity != null) _finishMiniPlayerDrag(pendingVelocity);
    });
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

    // Paint the exact t == 0 source frame before revealing the static player.
    await WidgetsBinding.instance.endOfFrame;
    _isNowPlayingDragging.value = false;
    final navigator = PocketLinkNavigation.navigatorKey.currentState;
    final route = _nowPlayingRoute;
    if (navigator != null && route != null && route.isActive) {
      // Remove only after the shared controller has completed its reverse spring.
      navigator.removeRoute(route);
    }
  }

  void _updateMiniPlayerDrag(double delta) {
    // Only an upward drag expands. A downward swipe retains the paused-player
    // dismiss shortcut and never opens an intermediate route.
    if (!_nowPlayingOpen && delta < 0) _prepareNowPlaying();
    if (!_nowPlayingOpen) return;
    if (!_morphLayoutReady) {
      _pendingMiniPlayerDragDelta += delta;
      return;
    }
    _applyMiniPlayerDrag(delta);
  }

  double _morphTravelExtent({required double fallback}) {
    final source = _miniArtworkOriginRect;
    final target = _sharedArtworkTargetRect.value;
    if (source != null && target != null) {
      final measured = (source.center.dy - target.center.dy).abs();
      if (measured.isFinite && measured > 1) return measured;
    }
    return math.max(1.0, fallback).toDouble();
  }

  void _applyMiniPlayerDrag(double delta) {
    if (!_nowPlayingOpen) return;
    _openingNowPlaying = false;
    if (MediaQuery.of(context).disableAnimations) {
      _nowPlayingController.value = 1;
      return;
    }
    final height = MediaQuery.sizeOf(context).height;
    final travelDistance = _morphTravelExtent(
      fallback: height - (_nowPlayingOriginRect?.height ?? _miniPlayerHeight),
    );
    _nowPlayingController.value = PocketLinkNavigation.updateMorphProgress(
      current: _nowPlayingController.value,
      dragDelta: delta,
      extent: travelDistance,
    );
  }

  void _endMiniPlayerDrag(double velocity) {
    if (_miniPlayerGestureActive && mounted) {
      setState(() => _miniPlayerGestureActive = false);
    }
    if (!_nowPlayingOpen) {
      if (!_player.player.state.playing && velocity > 300) {
        _player.dismissMiniPlayer();
      }
      return;
    }
    if (!_morphLayoutReady) {
      _pendingMiniPlayerDragEndVelocity = velocity;
      return;
    }
    _finishMiniPlayerDrag(velocity);
  }

  void _finishMiniPlayerDrag(double velocity) {
    if (!_nowPlayingOpen) return;
    _openingNowPlaying = false;
    final extent = _morphTravelExtent(
      fallback: math.max(1.0, MediaQuery.sizeOf(context).height),
    );
    final expand = PocketLinkNavigation.shouldExpandFromMiniPlayer(
      progress: _nowPlayingController.value,
      upwardVelocity: velocity,
    );
    if (expand) {
      unawaited(_animateNowPlayingTo(1, velocity: -velocity / extent));
    } else {
      unawaited(_closeNowPlaying(velocity: -velocity / extent));
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
      extent: _morphTravelExtent(fallback: height),
    );
  }

  void _endNowPlayingDrag(double velocity) {
    if (!_nowPlayingOpen) return;
    final extent = _morphTravelExtent(
      fallback: math.max(1.0, MediaQuery.sizeOf(context).height),
    );
    final collapse = PocketLinkNavigation.shouldCollapseNowPlaying(
      progress: _nowPlayingController.value,
      downwardVelocity: velocity,
    );
    _isNowPlayingDragging.value = false;
    if (collapse) {
      unawaited(_closeNowPlaying(velocity: -velocity / extent));
    } else {
      unawaited(_animateNowPlayingTo(
        1,
        velocity: -velocity / extent,
      ));
    }
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
        PocketLinkNavigation.discoverSearchVisible,
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
          final compactDiscoverControls =
              PocketLinkNavigation.discoverSearchVisible.value && onDashboard;
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
                  left: compactDiscoverControls ? 14 : 0,
                  right: compactDiscoverControls ? 88 : 0,
                  bottom: bottomInset +
                      (onDashboard && !compactDiscoverControls ? _homeDockHeight : 10),
                  child: IgnorePointer(
                    ignoring: !visible && !_miniPlayerGestureActive,
                    child: AnimatedSlide(
                      offset: Offset.zero,
                      duration: reduceMotion || drawerOpen
                          ? Duration.zero
                          : const Duration(milliseconds: 280),
                      curve: Curves.easeOutCubic,
                      child: _GlobalMiniPlayerBar(
                        compact: compactDiscoverControls,
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
                        onExpandDragStart: _onMiniPlayerDragStart,
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
    required this.artworkTargetRect,
    required this.artworkTargetKey,
    required this.onArtworkChanged,
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
  final ValueListenable<Rect?> artworkTargetRect;
  final GlobalKey artworkTargetKey;
  final ValueChanged<Uint8List?> onArtworkChanged;
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
    final safeInsets = media.padding;
    final dockHeight = 82.0 + safeInsets.bottom;
    final miniBottom = size.height - dockHeight;
    final origin = originRect ??
        Rect.fromLTRB(
          safeInsets.left + 16.0,
          miniBottom - 60.0,
          size.width - safeInsets.right - 16.0,
          miniBottom,
        );
    final sourceArt = sourceArtworkRect ??
        Rect.fromLTWH(origin.left + 10, origin.top + 10, 34, 34);

    return MediaQuery(
      data: media,
      child: AnimatedBuilder(
        animation: animation,
        child: RepaintBoundary(
          child: NowPlayingScreen(
            api: api,
            queue: player.queue,
            initialIndex: player.currentIndex,
            resumeExisting: true,
            morphAnimation: animation,
            useSharedArtwork: true,
            artworkTargetKey: artworkTargetKey,
            onArtworkChanged: onArtworkChanged,
            onDismiss: onDismiss,
            onDismissDragStart: onDragStart,
            onDismissDragUpdate: onDragUpdate,
            onDismissDragEnd: onDragEnd,
          ),
        ),
        builder: (context, animatedChild) {
          final t = animation.value.clamp(0.0, 1.0).toDouble();
          final rect = Rect.lerp(origin, destination, t)!;
          const miniPlayerRadius = 22.0;
          final radius = BorderRadius.lerp(
            BorderRadius.zero,
            BorderRadius.circular(miniPlayerRadius),
            1.0 - t,
          )!;
          final currentItem = player.currentItem;
          final artworkPalette = currentItem == null
              ? const [Color(0xFF6559A8), Color(0xFF24243D), Color(0xFF171326)]
              : NowPlayingArtworkPalette.fallback(
                  title: currentItem.title,
                  folderName: currentItem.path.split('/').length > 1
                      ? currentItem.path.split('/')[currentItem.path.split('/').length - 2]
                      : 'Internal storage',
                  path: currentItem.path,
                );
          // Keep the morph surface fully opaque and consistently dark.
          // Artwork-derived ambient colors belong in the expanded player
          // content, not in the container being transformed; interpolating
          // them here can expose a pale panel during the reverse transition.
          const sheetFill = Color(0xFF0A0B0E);
          // Remove docked controls before expanded controls begin appearing.
          final miniOpacity = 1.0 -
              const Interval(
                0.0,
                0.22,
                curve: Curves.easeOutCubic,
              ).transform(t);
          final isGradientTheme =
              AppSettings.instance.nowPlayingTheme == 'gradient';
          final targetArt = isGradientTheme
              ? Rect.fromLTWH(0, 0, size.width, size.height * 0.64)
              : artworkTargetRect.value ??
                  Rect.fromCenter(
                    center: Offset(size.width / 2, size.height * 0.34),
                    width: 260,
                    height: 260,
                  );
          final artworkRect = Rect.lerp(sourceArt, targetArt, t)!;
          final artworkRadius = BorderRadius.lerp(
            BorderRadius.circular(11),
            isGradientTheme ? BorderRadius.zero : BorderRadius.circular(26),
            t,
          )!;

          return PopScope<void>(
            canPop: !PocketLinkNavigation.shouldCollapseNowPlayingOnBack(
              progress: animation.value,
            ),
            onPopInvokedWithResult: (didPop, result) {
              if (!didPop &&
                  PocketLinkNavigation.shouldCollapseNowPlayingOnBack(
                    progress: animation.value,
                  )) {
                onDismiss();
              }
            },
            child: Material(
              type: MaterialType.transparency,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Positioned.fill(
                    child: IgnorePointer(
                      child: ColoredBox(
                        color: Colors.black.withValues(alpha: 0.45 * t),
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
                        Positioned.fromRect(
                          rect: rect,
                          child: IgnorePointer(
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                color: sheetFill,
                                borderRadius: radius,
                              ),
                              child: const SizedBox.expand(),
                            ),
                          ),
                        ),
                        Positioned.fill(
                          child: IgnorePointer(
                            ignoring: t < 0.35,
                            child: Opacity(
                              opacity: const Interval(
                                0.50,
                                1.0,
                                curve: Curves.easeOutCubic,
                              ).transform(t),
                              child: animatedChild!,
                            ),
                          ),
                        ),
                        Positioned.fromRect(
                            rect: artworkRect,
                            child: ValueListenableBuilder<Uint8List?>(
                              valueListenable: artworkBytes,
                              builder: (context, bytes, _) => DecoratedBox(
                                decoration: BoxDecoration(
                                  borderRadius: artworkRadius,
                                  boxShadow: isGradientTheme
                                      ? const []
                                      : [
                                          BoxShadow(
                                            color: artworkPalette[0]
                                                .withValues(alpha: 0.28 * t),
                                            blurRadius: 38 * t,
                                            spreadRadius: 2 * t,
                                            offset: Offset(0, 16 * t),
                                          ),
                                          BoxShadow(
                                            color: Colors.black
                                                .withValues(alpha: 0.34 * t),
                                            blurRadius: 24 * t,
                                            offset: Offset(0, 12 * t),
                                          ),
                                        ],
                                ),
                                child: Stack(
                                  fit: StackFit.expand,
                                  children: [
                                    TrackArtworkView(
                                      bytes: bytes,
                                      artworkUrl: currentItem?.artworkUrl,
                                      fallbackColors: artworkPalette,
                                      fallbackIconSize: 19 + (73 * t),
                                      borderRadius: artworkRadius,
                                    ),
                                    if (bytes != null && !isGradientTheme)
                                      DecoratedBox(
                                        decoration: BoxDecoration(
                                          borderRadius: artworkRadius,
                                          gradient: RadialGradient(
                                            center: const Alignment(-0.55, -0.7),
                                            radius: 1.1,
                                            colors: [
                                              Colors.white.withValues(
                                                alpha: 0.18 * t,
                                              ),
                                              Colors.transparent,
                                            ],
                                          ),
                                        ),
                                      ),
                                    if (!isGradientTheme)
                                      DecoratedBox(
                                        decoration: BoxDecoration(
                                          borderRadius: artworkRadius,
                                          border: Border.all(
                                            color: Colors.white
                                                .withValues(alpha: 0.16 * t),
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
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
                        item.artist?.trim().isNotEmpty == true
                            ? item.artist!.trim()
                            : item.sourceLabel,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: secondaryForeground,
                          fontSize: 10,
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
                        final loading = player.isSelectionLoading ||
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
    required this.compact,
    required this.visible,
    required this.hasFloatingNavBar,
    required this.reduceMotion,
    required this.player,
    required this.artworkBytes,
    required this.surfaceIntensity,
    required this.onOpen,
    required this.onDismiss,
    required this.onExpandDragStart,
    required this.onExpandDragUpdate,
    required this.onExpandDragEnd,
  });

  final bool compact;
  final bool visible;
  final bool hasFloatingNavBar;
  final bool reduceMotion;
  final PersistentAudioPlayer player;
  final ValueListenable<Uint8List?> artworkBytes;
  final double surfaceIntensity;
  final VoidCallback onOpen;
  final VoidCallback onDismiss;
  final VoidCallback onExpandDragStart;
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
              isLoading: player.isSelectionLoading ||
                  player.player.state.buffering ||
                  (durationSnapshot.data ?? Duration.zero) <= Duration.zero,
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
              compact: compact,
              surfaceIntensity: surfaceIntensity,
              artworkBytes: artwork,
              artworkKey: PocketLinkNavigation.miniArtworkKey,
              onExpandDragStart: onExpandDragStart,
              onExpandDragUpdate: onExpandDragUpdate,
              onExpandDragEnd: onExpandDragEnd,
            ),
          ),
        ),
      ),
    );
  }
}
