import 'dart:async';
import 'dart:math' as math;

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

class GlobalMediaOverlay extends StatefulWidget {
  const GlobalMediaOverlay({required this.child, super.key});

  final Widget child;

  @override
  State<GlobalMediaOverlay> createState() => _GlobalMediaOverlayState();
}

class _GlobalMediaOverlayState extends State<GlobalMediaOverlay>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  static const Duration _trackPopupDuration = Duration(milliseconds: 2300);

  bool _openingNowPlaying = false;
  bool _nowPlayingOpen = false;
  final ValueNotifier<bool> _isNowPlayingDragging = ValueNotifier<bool>(false);
  bool _closingNowPlaying = false;
  Rect? _nowPlayingOriginRect;
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
    final miniPlayerOffset = _shouldShowMiniPlayer() ? PocketLinkLayoutMetrics.miniPlayerHeight : 0.0;
    final top = (buttonPosition.dy - popupHeight - 8 - miniPlayerOffset)
        .clamp(8.0, math.max(8.0, size.height - popupHeight - 8))
        .toDouble();
    if (mounted) setState(() => _trackPopupOffset = Offset(left, top));
  }

  bool _shouldShowMiniPlayer() {
    final player = _player;
    return AppSettings.instance.showMiniPlayer && player.shouldShowMiniPlayer;
  }

  Future<void> _openNowPlaying() async {
    if (_openingNowPlaying || _nowPlayingOpen) return;
    final player = _player;
    final item = player.currentItem;
    final api = player.api;
    final navigator = PocketLinkNavigation.navigatorKey.currentState;
    final overlay = navigator?.overlay;
    if (!player.isMusic || !player.isActive || item == null || api == null ||
        navigator == null || overlay == null) {
      return;
    }

    _openingNowPlaying = true;
    final media = MediaQuery.of(context);
    final globalOrigin = PocketLinkNavigation.resolveMediaOriginRect(
      preferMiniPlayer: _shouldShowMiniPlayer(),
    );
    final overlayBox = overlay.context.findRenderObject();
    _nowPlayingOriginRect = globalOrigin != null && overlayBox is RenderBox
        ? globalOrigin.shift(-overlayBox.localToGlobal(Offset.zero))
        : globalOrigin;
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
          player: player,
          api: api,
          onDismiss: _closeNowPlaying,
          isDragging: isDragging,
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
      setState(() {
        _nowPlayingOpen = false;
        _isNowPlayingDragging.value = false;
        _nowPlayingOriginRect = null;
      });
      _nowPlayingController.value = 0;
    }));

    try {
      await _nowPlayingController.animateTo(
        1,
        duration: const Duration(milliseconds: 380),
        curve: Curves.easeOutQuart,
      );
    } on TickerCanceled {
      // A close gesture can interrupt the opening animation.
    } finally {
      _openingNowPlaying = false;
    }
  }

  Future<void> _closeNowPlaying() async {
    if (!_nowPlayingOpen || _closingNowPlaying) return;
    _closingNowPlaying = true;
    try {
      await _nowPlayingController.animateBack(
        0,
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeOutQuart,
      );
    } on TickerCanceled {
      // The route is already being removed.
    }

    final navigator = PocketLinkNavigation.navigatorKey.currentState;
    final route = _nowPlayingRoute;
    if (navigator != null && route != null &&
        PocketLinkNavigation.observer.currentPageRoute == route) {
      navigator.pop();
    } else if (route != null) {
      navigator?.removeRoute(route);
    }
  }

  void _updateNowPlayingDrag(double delta) {
    if (!_nowPlayingOpen) return;
    final height = MediaQuery.sizeOf(context).height;
    _nowPlayingController.value =
        (_nowPlayingController.value - delta / (height * 0.65))
            .clamp(0.0, 1.0)
            .toDouble();
  }

  void _endNowPlayingDrag(double velocity) {
    if (_nowPlayingController.value < 0.85 || velocity > 280) {
      unawaited(_closeNowPlaying());
    } else {
      _isNowPlayingDragging.value = false;
      unawaited(_nowPlayingController.animateTo(
        1,
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutQuart,
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
        PocketLinkNavigation.bottomDockVisible,
        PocketLinkScrollOffsetScope.dockCollapsed,
        _nowPlayingController,
      ]),
      builder: (context, _) => ValueListenableBuilder<List<Route<dynamic>>>(
        valueListenable: observer.routeStack,
        builder: (context, _, __) {
          final drawerOpen = PocketLinkNavigation.drawerOpen.value;
          final visible = _shouldShowMiniPlayer() &&
              !_nowPlayingOpen &&
              !drawerOpen &&
              !PocketLinkNavigation.quickShortcutsOpen.value &&
              !observer.isNowPlayingVisible &&
              !observer.isModalRouteOnTop &&
              _nowPlayingController.value <= 0.0;
          final onDashboard = observer.isDashboardVisible;
          final dockVisible = onDashboard && PocketLinkNavigation.bottomDockVisible.value;
          final compactDock = dockVisible &&
              visible &&
              PocketLinkScrollOffsetScope.dockCollapsed.value;
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
          final bottomInset = media.viewPadding.bottom;

          // Keep the navigator at full height. Every route reads the same
          // measured header and mounted-overlay geometry from this scope.
          final navigatorContent = PocketLinkScaffold(
            routeIdentity: observer.currentPageRoute,
            hasFloatingNavBar: dockVisible,
            hasActiveMiniPlayer: visible,
            child: widget.child,
          );

          return Stack(
            key: PocketLinkNavigation.mediaOverlayKey,
            fit: StackFit.expand,
            children: [
              Positioned.fill(child: navigatorContent),
              if (!dockVisible && visible)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: PocketLinkBottomScrim(
                    height: PocketLinkLayoutMetrics.bottomOverlayHeight(
                      bottomInset: bottomInset,
                      hasDock: false,
                      hasMiniPlayer: true,
                    ),
                  ),
                ),
              if (visible)
                Positioned(
                  left: compactDock
                      ? PocketLinkHorizontalGutter.padding(context).left + 76
                      : 0,
                  right: compactDock
                      ? PocketLinkHorizontalGutter.padding(context).right + 76
                      : 0,
                  bottom: bottomInset + (compactDock
                      ? 12
                      : dockVisible
                          ? PocketLinkLayoutMetrics.dockHeight +
                              PocketLinkLayoutMetrics.miniPlayerGap
                          : 0),
                  child: AnimatedSlide(
                    offset: Offset.zero,
                    duration: reduceMotion || drawerOpen
                        ? Duration.zero
                        : const Duration(milliseconds: 280),
                    curve: Curves.easeOutCubic,
                    child: _GlobalMiniPlayerBar(
                      visible: true,
                      reduceMotion: reduceMotion,
                      compact: compactDock,
                      player: player,
                      onOpen: _openNowPlaying,
                      onDismiss: player.dismissMiniPlayer,
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
  final bool isDragging;
  final PersistentAudioPlayer player;
  final ServerApi api;
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

    return MediaQuery(
      data: media,
      child: AnimatedBuilder(
      animation: animation,
      child: NowPlayingScreen(
        api: api,
        queue: player.queue,
        initialIndex: player.currentIndex,
        resumeExisting: true,
        onDismiss: onDismiss,
        onDismissDragStart: onDragStart,
        onDismissDragUpdate: onDragUpdate,
        onDismissDragEnd: onDragEnd,
      ),
      builder: (context, animatedChild) {
        final t = animation.value.clamp(0.0, 1.0).toDouble();
        final rect = Rect.lerp(origin, destination, t)!;
        final radius = BorderRadius.lerp(
          BorderRadius.circular(22),
          BorderRadius.circular(isDragging ? 32 : 0),
          t,
        )!;
        // Finish the source mini-player fade before the full player starts fading in.
        final miniOpacity = (1.0 - t / 0.25).clamp(0.0, 1.0).toDouble();
        final fullOpacity = ((t - 0.25) / 0.75).clamp(0.0, 1.0).toDouble();

        return Material(
          type: MaterialType.transparency,
          child: Stack(
            fit: StackFit.expand,
            children: [
              Positioned.fill(
                child: AbsorbPointer(
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
                  const ColoredBox(color: Color(0xFF0A0B0E)),
                  Positioned.fill(
                    child: IgnorePointer(
                      ignoring: fullOpacity < 1,
                      child: Opacity(
                        opacity: fullOpacity,
                        child: animatedChild,
                      ),
                    ),
                  ),
                  Positioned.fromRect(
                    rect: rect,
                    child: IgnorePointer(
                      ignoring: miniOpacity <= 0,
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
    return Align(
      alignment: Alignment.center,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: colors.primary.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(Icons.graphic_eq_rounded, color: colors.primary, size: 21),
            ),
            const SizedBox(width: 10),
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
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const Text(
                    'NOW PLAYING',
                    style: TextStyle(
                      color: Colors.white54,
                      fontSize: 8,
                      letterSpacing: 1,
                    ),
                  ),
                ],
              ),
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
                        color: Colors.white,
                        icon: Icon((playingSnapshot.data ?? false)
                            ? Icons.pause_rounded
                            : Icons.play_arrow_rounded),
                      ),
                    );
                  },
                ),
              ),
            ),
            IconButton(
              visualDensity: VisualDensity.compact,
              onPressed: player.skipToNext,
              color: Colors.white,
              icon: const Icon(Icons.skip_next_rounded),
            ),
          ],
        ),
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
    required this.visible,
    required this.reduceMotion,
    required this.compact,
    required this.player,
    required this.onOpen,
    required this.onDismiss,
  });

  final bool visible;
  final bool reduceMotion;
  final bool compact;
  final PersistentAudioPlayer player;
  final VoidCallback onOpen;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final item = player.currentItem;
    if (item == null) return const SizedBox.shrink();

    return StreamBuilder<bool>(
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
            compact: compact,
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
          ),
        ),
      ),
    );
  }
}
