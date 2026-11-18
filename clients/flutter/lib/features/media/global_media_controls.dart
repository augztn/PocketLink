import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';

import '../../core/settings/app_settings.dart';
import '../home/floating_quick_shortcut.dart';
import 'persistent_audio_player.dart';

class GlobalMediaControlsController extends ChangeNotifier {
  GlobalMediaControlsController._();

  static final instance = GlobalMediaControlsController._();

  VoidCallback? _onOpenNowPlaying;
  ValueChanged<String>? _onShortcut;
  bool _expanded = false;
  bool _miniPlayerDismissed = false;
  bool _nowPlayingRouteOpen = false;

  bool get expanded => _expanded;
  bool get miniPlayerDismissed => _miniPlayerDismissed;
  bool get nowPlayingRouteOpen => _nowPlayingRouteOpen;

  void attach({
    required VoidCallback onOpenNowPlaying,
    required ValueChanged<String> onShortcut,
  }) {
    _onOpenNowPlaying = onOpenNowPlaying;
    _onShortcut = onShortcut;
    notifyListeners();
  }

  void detach() {
    _onOpenNowPlaying = null;
    _onShortcut = null;
    _expanded = false;
    notifyListeners();
  }

  void expandShortcuts() {
    HapticFeedback.lightImpact();
    _expanded = true;
    notifyListeners();
  }

  void collapseShortcuts() {
    if (!_expanded) return;
    _expanded = false;
    notifyListeners();
  }

  void selectShortcut(String id) {
    _expanded = false;
    notifyListeners();
    _onShortcut?.call(id);
  }

  void openNowPlaying() => _onOpenNowPlaying?.call();

  void dismissMiniPlayer() {
    final player = PersistentAudioPlayer.instance;
    if (player.isPlaying || _miniPlayerDismissed) return;
    _miniPlayerDismissed = true;
    notifyListeners();
  }

  void restoreMiniPlayer() {
    if (!_miniPlayerDismissed) return;
    _miniPlayerDismissed = false;
    notifyListeners();
  }

  void setNowPlayingRouteOpen(bool value) {
    if (_nowPlayingRouteOpen == value) return;
    _nowPlayingRouteOpen = value;
    notifyListeners();
  }
}

class GlobalMediaControlsOverlay extends StatelessWidget {
  const GlobalMediaControlsOverlay({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final controller = GlobalMediaControlsController.instance;
    final player = PersistentAudioPlayer.instance;
    return AnimatedBuilder(
      animation: AppSettings.instance,
      builder: (context, _) => AnimatedBuilder(
        animation: player,
        builder: (context, __) => AnimatedBuilder(
          animation: controller,
          builder: (context, ___) {
            final settings = AppSettings.instance;
            final showMiniPlayer = settings.showMiniPlayer &&
                player.isMusic &&
                player.isActive &&
                player.currentItem != null &&
                !controller.miniPlayerDismissed &&
                !controller.nowPlayingRouteOpen;
            final bottom = MediaQuery.paddingOf(context).bottom + 90.0;
            return PopScope(
              canPop: !controller.expanded,
              onPopInvokedWithResult: (didPop, result) {
                if (!didPop && controller.expanded) {
                  controller.collapseShortcuts();
                }
              },
              child: Stack(
                fit: StackFit.expand,
                children: [
                  child,
                  if (controller.expanded)
                    Positioned.fill(
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: controller.collapseShortcuts,
                        child: const SizedBox.expand(),
                      ),
                    ),
                  if (showMiniPlayer)
                    Positioned(
                      left: 14,
                      right: 14,
                      bottom: bottom,
                      child: _GlobalMiniPlayerBar(
                        player: player,
                        onOpen: controller.openNowPlaying,
                        onDismiss: controller.dismissMiniPlayer,
                      ),
                    ),
                  if (settings.floatingShortcutEnabled)
                    AnimatedPositioned(
                      duration: const Duration(milliseconds: 220),
                      curve: Curves.easeInOutCubic,
                      right: 16,
                      bottom: bottom + (showMiniPlayer ? 66.0 : 0.0),
                      child: FloatingQuickShortcut(
                        shortcuts: settings.floatingShortcuts,
                        expanded: controller.expanded,
                        useLiquidGlass: settings.useLiquidGlass,
                        onTap: () {
                          if (settings.floatingShortcutTapAction == 'menu') {
                            controller.expandShortcuts();
                          } else if (settings.floatingShortcuts.isNotEmpty) {
                            controller.selectShortcut(settings.floatingShortcuts.first);
                          }
                        },
                        onLongPress: controller.expandShortcuts,
                        longPressEnabled: settings.floatingShortcutLongPressEnabled,
                        onSelect: controller.selectShortcut,
                      ),
                    ),
                ],
              ),
            );
          },
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
    final item = player.currentItem!;
    return Material(
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
                Icon(Icons.music_note_rounded,
                    color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(item.title,
                          maxLines: 1, overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w700)),
                      const Text('NOW PLAYING',
                          style: TextStyle(fontSize: 9, letterSpacing: 1.1)),
                    ],
                  ),
                ),
                StreamBuilder<bool>(
                  stream: player.player.stream.playing,
                  initialData: player.player.state.playing,
                  builder: (context, snapshot) => IconButton(
                    tooltip: (snapshot.data ?? false) ? 'Pause' : 'Play',
                    onPressed: player.togglePlayback,
                    icon: Icon((snapshot.data ?? false)
                        ? Icons.pause_rounded
                        : Icons.play_arrow_rounded),
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
    );
  }
}
