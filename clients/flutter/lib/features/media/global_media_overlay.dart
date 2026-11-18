import 'dart:async';
import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import '../../core/navigation/pocketlink_navigation.dart';
import '../../core/settings/app_settings.dart';
import 'now_playing_screen.dart';
import 'persistent_audio_player.dart';

class GlobalMediaOverlay extends StatefulWidget {
  const GlobalMediaOverlay({required this.child, super.key});

  final Widget child;

  @override
  State<GlobalMediaOverlay> createState() => _GlobalMediaOverlayState();
}

class _GlobalMediaOverlayState extends State<GlobalMediaOverlay> {
  static const double _miniPlayerHeight = 62;
  static const double _homeDockHeight = 82;
  static const Duration _trackPopupDuration = Duration(milliseconds: 2300);

  bool _openingNowPlaying = false;
  MediaQueueItem? _lastTrack;
  MediaQueueItem? _trackPopup;
  Offset? _trackPopupOffset;
  Timer? _trackPopupTimer;

  PersistentAudioPlayer get _player => PersistentAudioPlayer.instance;

  @override
  void initState() {
    super.initState();
    _lastTrack = _player.currentItem;
    _player.addListener(_onPlayerChanged);
  }

  @override
  void dispose() {
    _player.removeListener(_onPlayerChanged);
    _trackPopupTimer?.cancel();
    super.dispose();
  }

  void _onPlayerChanged() {
    final current = _player.currentItem;
    final previous = _lastTrack;
    final changed = current?.path != previous?.path ||
        current?.volume != previous?.volume;
    _lastTrack = current;
    if (!changed || previous == null || current == null || !_player.isMusic) {
      return;
    }

    _trackPopupTimer?.cancel();
    setState(() {
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
    final overlay = context.findRenderObject();
    if (button is! RenderBox || overlay is! RenderBox ||
        !button.attached || !overlay.attached) {
      return;
    }

    final buttonPosition = button.localToGlobal(Offset.zero, ancestor: overlay);
    final size = overlay.size;
    const popupWidth = 248.0;
    const popupHeight = 56.0;
    final left = (buttonPosition.dx + button.size.width / 2 - popupWidth / 2)
        .clamp(12.0, math.max(12.0, size.width - popupWidth - 12.0));
    final top = (buttonPosition.dy - popupHeight - 10)
        .clamp(12.0, math.max(12.0, size.height - popupHeight - 12.0));
    if (mounted) setState(() => _trackPopupOffset = Offset(left, top));
  }

  bool _shouldShowMiniPlayer() {
    final player = _player;
    return AppSettings.instance.showMiniPlayer && player.shouldShowMiniPlayer;
  }

  Future<void> _openNowPlaying() async {
    if (_openingNowPlaying) return;
    final player = _player;
    final item = player.currentItem;
    final api = player.api;
    final navigator = PocketLinkNavigation.navigatorKey.currentState;
    if (!player.isMusic || !player.isActive || item == null || api == null ||
        navigator == null) {
      return;
    }

    _openingNowPlaying = true;
    try {
      await navigator.push<void>(
        MaterialPageRoute<void>(
          settings: const RouteSettings(
            name: PocketLinkRouteNames.nowPlaying,
          ),
          builder: (_) => NowPlayingScreen(
            api: api,
            queue: player.queue,
            initialIndex: player.currentIndex,
            resumeExisting: true,
          ),
        ),
      );
    } finally {
      _openingNowPlaying = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final player = _player;
    final settings = AppSettings.instance;
    final observer = PocketLinkNavigation.observer;

    return AnimatedBuilder(
      animation: Listenable.merge(<Listenable>[player, settings]),
      builder: (context, _) => ValueListenableBuilder<List<Route<dynamic>>>(
        valueListenable: observer.routeStack,
        builder: (context, _, __) {
          final visible = _shouldShowMiniPlayer() &&
              !observer.isNowPlayingVisible &&
              !observer.isModalRouteOnTop;
          final onDashboard = observer.isDashboardVisible;
          final showTrackPopup = _trackPopup != null &&
              _trackPopupOffset != null &&
              onDashboard &&
              !observer.isNowPlayingVisible &&
              !observer.isModalRouteOnTop;
          final media = MediaQuery.of(context);
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
            fit: StackFit.expand,
            children: [
              Positioned.fill(child: navigatorContent),
              if (visible)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: bottomInset + (onDashboard ? _homeDockHeight : 0),
                  child: _GlobalMiniPlayerBar(
                    player: player,
                    onOpen: _openNowPlaying,
                    onDismiss: player.dismissMiniPlayer,
                  ),
                ),
              Positioned(
                left: _trackPopupOffset?.dx ?? 0,
                top: _trackPopupOffset?.dy ?? 0,
                child: IgnorePointer(
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 260),
                    reverseDuration: const Duration(milliseconds: 180),
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

class _TrackChangePopup extends StatelessWidget {
  const _TrackChangePopup({required this.item, super.key});

  final MediaQueueItem item;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Material(
      elevation: 8,
      color: colors.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        width: 248,
        height: 56,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: colors.outlineVariant.withValues(alpha: 0.55)),
        ),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: colors.primary.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(11),
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
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12),
                  ),
                  Text(
                    'NOW PLAYING',
                    style: TextStyle(
                      color: colors.onSurfaceVariant,
                      fontSize: 9,
                      letterSpacing: 1.1,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GlobalMiniPlayerBar extends StatelessWidget {
  const _GlobalMiniPlayerBar({
    required this.player,
    required this.onOpen,
    required this.onDismiss,
  });

  final PersistentAudioPlayer player;
  final VoidCallback onOpen;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final item = player.currentItem;
    if (item == null) return const SizedBox.shrink();

    return Align(
      alignment: Alignment.centerLeft,
      child: Padding(
        // Match the Home/Explore/Files capsule and leave the separate Music
        // button's 64 px circle plus its 10 px gap outside this bar.
        padding: const EdgeInsets.fromLTRB(14, 4, 88, 0),
        child: Material(
          color: Theme.of(context).colorScheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(16),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onVerticalDragEnd: (details) {
              final velocity = details.primaryVelocity ?? 0;
              if (!player.isPlaying && velocity > 300) onDismiss();
            },
            child: InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: onOpen,
              child: SizedBox(
                height: 58,
                child: Row(
                  children: [
                    const SizedBox(width: 14),
                    Icon(
                      Icons.music_note_rounded,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            item.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          const Text(
                            'NOW PLAYING',
                            style: TextStyle(fontSize: 9, letterSpacing: 1.1),
                          ),
                        ],
                      ),
                    ),
                    StreamBuilder<bool>(
                      stream: player.player.stream.playing,
                      initialData: player.player.state.playing,
                      builder: (context, snapshot) => IconButton(
                        tooltip: (snapshot.data ?? false) ? 'Pause' : 'Play',
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
    );
  }
}
