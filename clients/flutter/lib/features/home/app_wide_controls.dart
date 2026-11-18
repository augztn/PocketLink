import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';

import '../../core/logging/diagnostic_observer.dart';
import '../../core/settings/app_settings.dart';
import '../media/persistent_audio_player.dart';
import '../media/persistent_mini_player.dart';
import 'floating_quick_shortcut.dart';

/// The HomeScreen supplies navigation actions while this widget stays above
/// the root Navigator, so controls remain available on pushed content routes.
class AppWideControlsController extends ChangeNotifier {
  AppWideControlsController._();

  static final instance = AppWideControlsController._();

  Object? _owner;
  final LayerLink musicButtonLink = LayerLink();
  VoidCallback? _openNowPlaying;
  ValueChanged<String>? _selectShortcut;
  VoidCallback? _expandShortcuts;

  VoidCallback? get openNowPlaying => _openNowPlaying;
  ValueChanged<String>? get selectShortcut => _selectShortcut;
  bool get isAttached => _owner != null;

  void registerShortcutExpander(VoidCallback callback) {
    _expandShortcuts = callback;
  }

  void unregisterShortcutExpander(VoidCallback callback) {
    if (_expandShortcuts == callback) _expandShortcuts = null;
  }

  void openShortcuts() => _expandShortcuts?.call();

  void attach({
    required Object owner,
    required VoidCallback openNowPlaying,
    required ValueChanged<String> selectShortcut,
  }) {
    _owner = owner;
    _openNowPlaying = openNowPlaying;
    _selectShortcut = selectShortcut;
    notifyListeners();
  }

  void detach(Object owner) {
    if (!identical(_owner, owner)) return;
    _owner = null;
    _openNowPlaying = null;
    _selectShortcut = null;
    notifyListeners();
  }
}

class AppWideControls extends StatefulWidget {
  const AppWideControls({super.key});

  @override
  State<AppWideControls> createState() => _AppWideControlsState();
}

class _AppWideControlsState extends State<AppWideControls> {
  final _settings = AppSettings.instance;
  final _player = PersistentAudioPlayer.instance;
  final _controller = AppWideControlsController.instance;
  bool _shortcutsExpanded = false;
  bool _miniPlayerDismissed = false;
  late bool _lastPlaying;

  @override
  void initState() {
    super.initState();
    _controller.registerShortcutExpander(_expandShortcuts);
    _lastPlaying = _player.isPlaying;
    _player.addListener(_playerChanged);
  }

  void _playerChanged() {
    final playing = _player.isPlaying;
    if (playing && !_lastPlaying && _miniPlayerDismissed && mounted) {
      setState(() => _miniPlayerDismissed = false);
    }
    _lastPlaying = playing;
  }

  @override
  void dispose() {
    _controller.unregisterShortcutExpander(_expandShortcuts);
    _player.removeListener(_playerChanged);
    super.dispose();
  }

  void _expandShortcuts() {
    HapticFeedback.lightImpact();
    setState(() => _shortcutsExpanded = true);
  }

  void _selectShortcut(String id) {
    setState(() => _shortcutsExpanded = false);
    _controller.selectShortcut?.call(id);
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([
        _settings,
        _player,
        _controller,
        DiagnosticNavigatorObserver.instance.controlsVisible,
        DiagnosticNavigatorObserver.instance.dashboardVisible,
      ]),
      builder: (context, _) {
        final observer = DiagnosticNavigatorObserver.instance;
        if (!observer.controlsVisible.value || !_controller.isAttached) {
          return const SizedBox.shrink();
        }

        final safeBottom = MediaQuery.paddingOf(context).bottom;
        final showMiniPlayer = _settings.showMiniPlayer &&
            _player.showMiniPlayer &&
            !_miniPlayerDismissed &&
            _controller.openNowPlaying != null;
        // Shortcuts are opened exclusively by long-pressing the Music dock button.
        final showShortcut = _shortcutsExpanded && _controller.selectShortcut != null;
        final dashboardVisible = observer.dashboardVisible.value;

        if (!showMiniPlayer && !showShortcut) {
          return const SizedBox.shrink();
        }

        // When opened from the dock, align the menu with the Music button.
        final controlsBottom = dashboardVisible ? 82.0 + safeBottom : 8.0 + safeBottom;

        return Stack(
          fit: StackFit.expand,
          children: [
            if (_shortcutsExpanded)
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => setState(() => _shortcutsExpanded = false),
                  child: const SizedBox.expand(),
                ),
              ),
            Positioned(
              left: 14,
              right: 16,
              bottom: controlsBottom,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  if (showMiniPlayer)
                    Expanded(
                      child: PersistentMiniPlayer(
                        player: _player,
                        onOpen: () => _controller.openNowPlaying?.call(),
                        onDismiss: () {
                          if (!_player.isPlaying) {
                            setState(() => _miniPlayerDismissed = true);
                          }
                        },
                      ),
                    ),
                ],
              ),
            ),
            if (showShortcut)
              Positioned(
                left: 0,
                top: 0,
                child: CompositedTransformFollower(
                  link: _controller.musicButtonLink,
                  showWhenUnlinked: false,
                  targetAnchor: Alignment.topCenter,
                  followerAnchor: Alignment.bottomCenter,
                  offset: const Offset(0, -8),
                  child: FloatingQuickShortcut(
                    shortcuts: _settings.floatingShortcuts,
                    expanded: true,
                    showButton: false,
                    onTap: _expandShortcuts,
                    onLongPress: _expandShortcuts,
                    longPressEnabled: false,
                    onSelect: _selectShortcut,
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}
