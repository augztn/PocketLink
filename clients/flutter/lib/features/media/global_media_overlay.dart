import 'dart:async';
import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import '../../core/navigation/pocketlink_navigation.dart';
import '../../core/network/server_api.dart';
import '../../core/settings/app_settings.dart';
import '../../core/widgets/liquid_glass_pill.dart';
import 'now_playing_screen.dart';
import 'persistent_audio_player.dart';

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
  bool _isNowPlayingDragging = false;
  bool _closingNowPlaying = false;
  Rect? _nowPlayingOriginRect;
  OverlayEntry? _nowPlayingEntry;
  late final AnimationController _nowPlayingController;

  static VoidCallback? _openNowPlayingHandler;

  static void openNowPlaying() => _openNowPlayingHandler?.call();
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
    _openNowPlayingHandler = _openNowPlaying;
    WidgetsBinding.instance.addObserver(this);
    _player.addListener(_onPlayerChanged);
  }

  @override
  void dispose() {
    _player.removeListener(_onPlayerChanged);
    _trackPopupTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _openNowPlayingHandler = null;
    _nowPlayingEntry?.remove();
    _nowPlayingEntry = null;
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
    final miniPlayerOffset = _shouldShowMiniPlayer() ? _miniPlayerHeight : 0.0;
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
    final overlay = PocketLinkNavigation.navigatorKey.currentState?.overlay;
    if (!player.isMusic || !player.isActive || item == null || api == null ||
        overlay == null) {
      return;
    }

    _openingNowPlaying = true;
    _nowPlayingOriginRect = PocketLinkNavigation.resolveMediaOriginRect(
      preferMiniPlayer: _shouldShowMiniPlayer(),
    );
    setState(() => _nowPlayingOpen = true);
    _nowPlayingEntry = OverlayEntry(
      builder: (context) => _NowPlayingMorphOverlay(
        animation: _nowPlayingController,
        originRect: _nowPlayingOriginRect,
        player: player,
        api: api,
        onDismiss: _closeNowPlaying,
        isDragging: _isNowPlayingDragging,
        onDragStart: () {
          _isNowPlayingDragging = true;
          _nowPlayingEntry?.markNeedsBuild();
        },
        onDragUpdate: _updateNowPlayingDrag,
        onDragEnd: _endNowPlayingDrag,
      ),
    );
    overlay.insert(_nowPlayingEntry!);
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
    _isNowPlayingDragging = false;
    _nowPlayingEntry?.markNeedsBuild();
    try {
      await _nowPlayingController.animateBack(
        0,
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeOutQuart,
      );
    } on TickerCanceled {
      // The overlay is already being removed.
    }
    _nowPlayingEntry?.remove();
    _nowPlayingEntry = null;
    if (mounted) {
      setState(() {
        _nowPlayingOpen = false;
        _nowPlayingOriginRect = null;
      });
    }
    _closingNowPlaying = false;
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
    _isNowPlayingDragging = false;
    _nowPlayingEntry?.markNeedsBuild();
    if (_nowPlayingController.value < 0.85 || velocity > 280) {
      unawaited(_closeNowPlaying());
    } else {
      unawaited(_nowPlayingController.animateTo(
        1,
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutQuart,
      ));
    }
  }

  @override
  Future<bool> didPopRoute() async {
    if (!_nowPlayingOpen) return false;
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
        _nowPlayingController,
      ]),
      builder: (context, _) => ValueListenableBuilder<List<Route<dynamic>>>(
        valueListenable: observer.routeStack,
        builder: (context, _, __) {
          final drawerOpen = PocketLinkNavigation.drawerOpen.value;
          final visible = _shouldShowMiniPlayer() &&
              !_nowPlayingOpen &&
              !drawerOpen &&
              !observer.isNowPlayingVisible &&
              !observer.isModalRouteOnTop;
          final onDashboard = observer.isDashboardVisible;
          final showTrackPopup = _trackPopup != null &&
              _trackPopupOffset != null &&
              onDashboard &&
              !drawerOpen &&
              !_nowPlayingOpen &&
              !observer.isNowPlayingVisible &&
              !observer.isModalRouteOnTop;
          final media = MediaQuery.of(context);
          final reduceMotion = media.disableAnimations;
          final bottomInset = media.padding.bottom;

          final Widget navigatorContent;
          if (visible && !onDashboard) {
            final reservedHeight = _miniPlayerHeight + bottomInset;
            navigatorContent = MediaQuery(
              data: media.copyWith(
                size: Size(
                  media.size.width,
                  (media.size.height - reservedHeight)
                      .clamp(0.0, double.infinity)
                      .toDouble(),
                ),
                padding: media.padding.copyWith(bottom: 0),
                viewPadding: media.viewPadding.copyWith(bottom: 0),
              ),
              child: Padding(
                padding: EdgeInsets.only(bottom: reservedHeight),
                child: widget.child,
              ),
            );
          } else {
            navigatorContent = widget.child;
          }

          return Stack(
            key: PocketLinkNavigation.mediaOverlayKey,
            fit: StackFit.expand,
            children: [
              Positioned.fill(child: navigatorContent),
              if (visible)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: bottomInset + (onDashboard ? _homeDockHeight : 0),
                  child: AnimatedSlide(
                    offset: Offset.zero,
                    duration: reduceMotion || drawerOpen
                        ? Duration.zero
                        : const Duration(milliseconds: 280),
                    curve: Curves.easeOutCubic,
                    child: _GlobalMiniPlayerBar(
                      visible: true,
                      reduceMotion: reduceMotion,
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
    final size = MediaQuery.sizeOf(context);
    final destination = Offset.zero & size;
    final origin = originRect ??
        Rect.fromLTWH(size.width - 292, size.height - 142, 278, 62);

    return AnimatedBuilder(
      animation: animation,
      builder: (context, _) {
        final t = animation.value.clamp(0.0, 1.0).toDouble();
        final rect = Rect.lerp(origin, destination, t)!;
        final radius = BorderRadius.lerp(
          BorderRadius.circular(22),
          BorderRadius.circular(isDragging ? 32 : 0),
          t,
        )!;
        final miniOpacity = (1.0 - t * 2.5).clamp(0.0, 1.0).toDouble();
        final fullOpacity = ((t - 0.25) / 0.75).clamp(0.0, 1.0).toDouble();

        return Stack(
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
        );
      },
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
              stream: player.player.stream.playing,
              initialData: player.player.state.playing,
              builder: (context, snapshot) => IconButton(
                visualDensity: VisualDensity.compact,
                onPressed: player.togglePlayback,
                color: Colors.white,
                icon: Icon((snapshot.data ?? false)
                    ? Icons.pause_rounded
                    : Icons.play_arrow_rounded),
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
    required this.player,
    required this.onOpen,
    required this.onDismiss,
  });

  final bool visible;
  final bool reduceMotion;
  final PersistentAudioPlayer player;
  final VoidCallback onOpen;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final item = player.currentItem;
    if (item == null) return const SizedBox.shrink();

    final colors = Theme.of(context).colorScheme;
    return Align(
      alignment: Alignment.centerLeft,
      child: Padding(
        // Same horizontal footprint as the Home / Explore / Files capsule.
        padding: const EdgeInsets.fromLTRB(14, 4, 88, 0),
        child: LiquidGlassPill(
          key: PocketLinkNavigation.miniPlayerKey,
          radius: BorderRadius.circular(22),
          child: AnimatedOpacity(
            opacity: visible ? 1 : 0,
            duration: reduceMotion
                ? Duration.zero
                : const Duration(milliseconds: 220),
            curve: Curves.easeOut,
            child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onVerticalDragEnd: (details) {
              final velocity = details.primaryVelocity ?? 0;
              if (!player.isPlaying && velocity > 300) onDismiss();
            },
            child: InkWell(
              borderRadius: BorderRadius.circular(22),
              onTap: onOpen,
              child: SizedBox(
                height: 58,
                child: Row(
                  children: [
                    const SizedBox(width: 12),
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: colors.primary.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        Icons.graphic_eq_rounded,
                        color: colors.primary,
                        size: 21,
                      ),
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
                                  fontWeight: FontWeight.w800,
                                ),
                          ),
                          Text(
                            'NOW PLAYING',
                            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                  fontSize: 8,
                                  letterSpacing: 1.0,
                                  color: colors.onSurfaceVariant,
                                ),
                          ),
                        ],
                      ),
                    ),
                    StreamBuilder<bool>(
                      stream: player.player.stream.playing,
                      initialData: player.player.state.playing,
                      builder: (context, snapshot) => IconButton(
                        tooltip: (snapshot.data ?? false) ? 'Pause' : 'Play',
                        visualDensity: VisualDensity.compact,
                        onPressed: player.togglePlayback,
                        icon: Icon(
                          (snapshot.data ?? false)
                              ? Icons.pause_rounded
                              : Icons.play_arrow_rounded,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Next track',
                      visualDensity: VisualDensity.compact,
                      onPressed: player.skipToNext,
                      icon: const Icon(Icons.skip_next_rounded),
                    ),
                    const SizedBox(width: 4),
                  ],
                ),
              ),
            ),
          ),
          ),
        ),
      ),
    );
  }
}
