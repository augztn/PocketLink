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

  bool _openingNowPlaying = false;

  PersistentAudioPlayer get _player => PersistentAudioPlayer.instance;

  bool _shouldShowMiniPlayer() {
    final player = _player;
    return AppSettings.instance.showMiniPlayer &&
        player.isMusic &&
        player.isActive &&
        player.currentItem != null &&
        !player.isMiniPlayerDismissed;
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
          final media = MediaQuery.of(context);
          final bottomInset = media.padding.bottom;

          final Widget navigatorContent;
          if (visible && !onDashboard) {
            navigatorContent = MediaQuery(
              data: media.copyWith(
                padding: media.padding.copyWith(bottom: 0),
                viewPadding: media.viewPadding.copyWith(bottom: 0),
              ),
              child: Padding(
                padding: EdgeInsets.only(
                  bottom: _miniPlayerHeight + bottomInset,
                ),
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
            ],
          );
        },
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

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 4, 14, 0),
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
                    tooltip: 'Dismiss mini-player',
                    onPressed: onDismiss,
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
