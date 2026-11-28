import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/physics.dart';
import 'package:flutter/foundation.dart' show ValueListenable;

import 'package:material_ui/material_ui.dart';

import '../../core/navigation/pocketlink_navigation.dart';
import '../../core/network/server_api.dart';
import '../../core/settings/app_settings.dart';
import '../../core/widgets/pocketlink_scaffold.dart';
import 'global_mini_player_bar.dart';
import 'now_playing_screen.dart';
import 'now_playing_artwork_palette.dart';
import 'track_artwork_view.dart';
import 'persistent_audio_player.dart';
import 'now_playing_overlay_controller.dart';

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
  bool _nowPlayingOpen = false;
  bool _closingNowPlaying = false;
  Rect? _nowPlayingOriginRect;
  Rect? _miniArtworkOriginRect;
  double _nowPlayingOriginRadius = 20;
  bool _nowPlayingUsesMiniAnchor = true;
  final ValueNotifier<Uint8List?> _sharedArtwork = ValueNotifier(null);
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
      duration: const Duration(milliseconds: 360),
      reverseDuration: const Duration(milliseconds: 300),
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
    _nowPlayingController.stop();
    _sharedArtwork.dispose();
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
    _prepareNowPlaying(fromMiniPlayer: true);
  }

  void _captureNowPlayingOrigin({
    required bool preferMiniPlayer,
    bool compensateDockTranslation = false,
  }) {
    final overlayObject = PocketLinkNavigation.mediaOverlayKey.currentContext
        ?.findRenderObject();
    final overlaySize = overlayObject is RenderBox && overlayObject.hasSize
        ? overlayObject.size
        : MediaQuery.sizeOf(context);
    final useMini = preferMiniPlayer && _shouldShowMiniPlayer();
    final anchorKey = useMini
        ? PocketLinkNavigation.miniPlayerAnchorKey
        : PocketLinkNavigation.nowPlayingDockButtonKey;
    final measured = PocketLinkNavigation.resolveMediaRect(anchorKey);
    final safeBottom = MediaQuery.paddingOf(context).bottom;
    final fallback = useMini
        ? Rect.fromLTWH(
            16,
            overlaySize.height - safeBottom - _homeDockHeight - _miniPlayerHeight,
            math.max(1.0, overlaySize.width - 32).toDouble(),
            _miniPlayerHeight,
          )
        : Rect.fromLTWH(
            math.max(0.0, overlaySize.width - 14 - 64).toDouble(),
            math.max(0.0, overlaySize.height - safeBottom - 10 - 64),
            64,
            64,
          );
    final dockProgress = (_nowPlayingController.value / 0.42)
        .clamp(0.0, 1.0)
        .toDouble();
    _nowPlayingOriginRect = measured == null
        ? fallback
        : (!useMini && compensateDockTranslation
            ? measured.shift(Offset(0, -(82.0 + safeBottom) * dockProgress))
            : measured);
    _nowPlayingUsesMiniAnchor = useMini;
    _miniArtworkOriginRect = useMini
        ? PocketLinkNavigation.resolveMediaRect(PocketLinkNavigation.miniArtworkKey)
        : null;
    _nowPlayingOriginRadius =
        useMini ? 20 : _nowPlayingOriginRect!.shortestSide / 2;
  }

  void _prepareNowPlaying({bool fromMiniPlayer = false}) {
    if (_nowPlayingOpen || _openingNowPlaying) return;
    final player = _player;
    if (!player.isMusic || !player.isActive || player.currentItem == null) {
      return;
    }

    _captureNowPlayingOrigin(
      preferMiniPlayer: fromMiniPlayer || _shouldShowMiniPlayer(),
    );
    _openingNowPlaying = true;
    _nowPlayingController.value = 0;
    setState(() => _nowPlayingOpen = true);
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
    if (velocity.abs() < 0.01) {
      await _nowPlayingController.animateTo(
        target,
        duration: Duration(milliseconds: target > _nowPlayingController.value ? 360 : 300),
        curve: target > _nowPlayingController.value
            ? Curves.easeOutCubic
            : Curves.easeInOutCubicEmphasized,
      );
      return;
    }
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
    _captureNowPlayingOrigin(
      preferMiniPlayer: _nowPlayingUsesMiniAnchor,
      compensateDockTranslation: true,
    );
    _closingNowPlaying = true;
    try {
      await _animateNowPlayingTo(0, velocity: velocity);
    } on TickerCanceled {
      // A close gesture can interrupt the opening animation.
    }

    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) return;
    _nowPlayingController.value = 0;
    _openingNowPlaying = false;
    _closingNowPlaying = false;
    _nowPlayingOriginRect = null;
    _miniArtworkOriginRect = null;
    setState(() => _nowPlayingOpen = false);
  }

  void _updateMiniPlayerDrag(double delta) {
    if (!_nowPlayingOpen && delta < 0) _prepareNowPlaying(fromMiniPlayer: true);
    if (!_nowPlayingOpen) return;
    _applyMiniPlayerDrag(delta);
  }

  double _morphTravelExtent({required double fallback}) =>
      math.max(1.0, fallback).toDouble();

  void _applyMiniPlayerDrag(double delta) {
    if (!_nowPlayingOpen) return;
    _openingNowPlaying = false;
    if (MediaQuery.of(context).disableAnimations) {
      _nowPlayingController.value = 1;
      return;
    }
    final height = MediaQuery.sizeOf(context).height;
    final travelDistance = _morphTravelExtent(
      fallback: height,
    );
    _nowPlayingController.value = PocketLinkNavigation.updateMorphProgress(
      current: _nowPlayingController.value,
      dragDelta: delta,
      extent: travelDistance,
    );
  }

  void _endMiniPlayerDrag(double velocity) {
    if (!_nowPlayingOpen) {
      if (!_player.player.state.playing && velocity > 300) {
        _player.dismissMiniPlayer();
      }
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

  void _onNowPlayingDragStart() {
    if (!_nowPlayingOpen) return;
    _captureNowPlayingOrigin(
      preferMiniPlayer: _nowPlayingUsesMiniAnchor,
      compensateDockTranslation: true,
    );
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
    // Clear the gesture state even if another close path removed the route
    // before the recognizer delivered its end/cancel callback.
    if (!_nowPlayingOpen) return;
    final extent = _morphTravelExtent(
      fallback: math.max(1.0, MediaQuery.sizeOf(context).height),
    );
    final collapse = PocketLinkNavigation.shouldCollapseNowPlaying(
      progress: _nowPlayingController.value,
      downwardVelocity: velocity,
    );
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
          final morphProgress =
              _nowPlayingController.value.clamp(0.0, 1.0).toDouble();
          final miniPlayerOpacity =
              (1.0 - morphProgress / 0.18).clamp(0.0, 1.0).toDouble();
          final visible = shouldRenderMiniPlayer &&
              !observer.isNowPlayingVisible &&
              !observer.isModalRouteOnTop &&
              miniPlayerOpacity > 0.01;
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
                    ignoring: morphProgress > 0.05 || !visible,
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
                        reduceMotion: reduceMotion || _nowPlayingOpen,
                        player: player,
                        artworkBytes: _sharedArtwork,
                        surfaceIntensity: _nowPlayingOpen ? 0.0 : 1.0,
                        opacity: visible ? miniPlayerOpacity : 0.0,
                        onOpen: _openNowPlaying,
                        onDismiss: player.dismissMiniPlayer,
                        onExpandDragStart: _onMiniPlayerDragStart,
                        onExpandDragUpdate: _updateMiniPlayerDrag,
                        onExpandDragEnd: _endMiniPlayerDrag,
                      ),
                    ),
                  ),
                ),
              if (player.isMusic && player.isActive && player.currentItem != null)
                Positioned.fill(
                  child: AnimatedBuilder(
                    animation: _nowPlayingController,
                    child: RepaintBoundary(
                      child: _NowPlayingMorphOverlay(
                        animation: _nowPlayingController,
                        media: media,
                        onArtworkChanged: _publishSharedArtwork,
                        player: player,
                        api: player.api,
                        onDismiss: () => _closeNowPlaying(),
                        originRect: _nowPlayingOriginRect,
                        originRadius: _nowPlayingOriginRadius,
                        miniArtworkRect: _miniArtworkOriginRect,
                        sharedArtwork: _sharedArtwork,
                        onDragStart: _onNowPlayingDragStart,
                        onDragUpdate: _updateNowPlayingDrag,
                        onDragEnd: _endNowPlayingDrag,
                      ),
                    ),
                    builder: (context, child) => Offstage(
                      offstage: !_nowPlayingOpen,
                      child: TickerMode(
                        enabled: _nowPlayingOpen && _nowPlayingController.value > 0.01,
                        child: child!,
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
    required this.onArtworkChanged,
    required this.player,
    required this.api,
    required this.onDismiss,
    required this.originRect,
    required this.originRadius,
    required this.miniArtworkRect,
    required this.sharedArtwork,
    required this.onDragStart,
    required this.onDragUpdate,
    required this.onDragEnd,
  });

  final Animation<double> animation;
  final MediaQueryData media;
  final ValueChanged<Uint8List?> onArtworkChanged;
  final PersistentAudioPlayer player;
  final ServerApi? api;
  final VoidCallback onDismiss;
  final Rect? originRect;
  final double originRadius;
  final Rect? miniArtworkRect;
  final ValueListenable<Uint8List?> sharedArtwork;
  final VoidCallback onDragStart;
  final ValueChanged<double> onDragUpdate;
  final ValueChanged<double> onDragEnd;

  @override
  Widget build(BuildContext context) {
    final screenHeight = media.size.height;
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
            useSharedArtwork: miniArtworkRect != null,
            artworkTargetKey: PocketLinkNavigation.nowPlayingArtworkKey,
            onArtworkChanged: onArtworkChanged,
            onDismiss: onDismiss,
            onDismissDragStart: onDragStart,
            onDismissDragUpdate: onDragUpdate,
            onDismissDragEnd: onDragEnd,
          ),
        ),
        builder: (context, screen) {
          final t = animation.value.clamp(0.0, 1.0).toDouble();
          // The controller is eased for programmatic motion; pointer drags set
          // its value directly, keeping geometry 1:1 with the finger.
          final curvedT = t;
          final fullScreen = Offset.zero & media.size;
          final source = originRect ?? Rect.fromLTWH(
            media.size.width - 78,
            media.size.height - media.padding.bottom - 74,
            56,
            56,
          );
          final rect = Rect.lerp(source, fullScreen, curvedT)!;
          final radius = originRadius * (1.0 - curvedT);
          final foregroundOpacity =
              ((t - 0.32) / 0.50).clamp(0.0, 1.0).toDouble();
          final track = player.currentItem;
          final folderName = track == null || !track.path.contains('/')
              ? 'Internal storage'
              : track.path.substring(0, track.path.lastIndexOf('/')).split('/').last;
          final palette = track == null
              ? const <Color>[Color(0xFF252832), Color(0xFF17181B)]
              : NowPlayingArtworkPalette.fallback(
                  title: track.title,
                  folderName: folderName,
                  path: track.path,
                );
          final ambientColor = Color.lerp(palette[0], palette[1], 0.32)!;
          final surfaceColor = Color.lerp(
            const Color(0xFF17181B),
            ambientColor,
            (curvedT / 0.30).clamp(0.0, 1.0),
          )!;

          final heroArtworkRect = Rect.fromLTWH(
            0,
            0,
            media.size.width,
            media.size.height * 0.56,
          );
          final movingArtworkRect = miniArtworkRect == null
              ? null
              : Rect.lerp(miniArtworkRect!, heroArtworkRect, curvedT);

          return Stack(
            fit: StackFit.expand,
            children: [
              Positioned.fill(
                child: IgnorePointer(
                  child: ColoredBox(
                    color: Colors.black.withValues(alpha: 0.45 * curvedT),
                  ),
                ),
              ),
              if (movingArtworkRect != null && t < 1)
                ValueListenableBuilder<Uint8List?>(
                  valueListenable: sharedArtwork,
                  builder: (context, bytes, _) => Positioned.fromRect(
                    rect: movingArtworkRect,
                    child: IgnorePointer(
                      child: Opacity(
                        opacity: (1.0 - ((t - 0.75) / 0.25))
                            .clamp(0.0, 1.0)
                            .toDouble(),
                        child: TrackArtworkView(
                          bytes: bytes,
                          artworkUrl: track?.artworkUrl,
                          fallbackColors: palette,
                          fallbackIconSize: 92,
                          fit: BoxFit.cover,
                          borderRadius: BorderRadius.circular(
                            AppSettings.instance.thumbnailCornerRadius * (1 - curvedT),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              Positioned.fromRect(
                rect: rect,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(radius),
                  child: DecoratedBox(
                    decoration: BoxDecoration(color: surfaceColor),
                    child: OverflowBox(
                      alignment: Alignment.topLeft,
                      minWidth: media.size.width,
                      maxWidth: media.size.width,
                      minHeight: screenHeight,
                      maxHeight: screenHeight,
                      child: IgnorePointer(
                        ignoring: t < 0.38,
                        child: Opacity(
                          opacity: foregroundOpacity,
                          child: Transform.scale(
                            alignment: Alignment.topLeft,
                            scale: 0.92 + 0.08 * curvedT,
                            child: RepaintBoundary(child: screen!),
                          ),
                        ),
                      ),
                    ),
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
    required this.opacity,
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
  final double opacity;
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
              opacity: opacity,
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
