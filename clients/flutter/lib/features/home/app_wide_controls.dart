import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';

import '../../core/settings/app_settings.dart';
import '../../core/logging/diagnostic_observer.dart';
import 'floating_quick_shortcut.dart';

/// HomeScreen supplies navigation while this widget owns only the shortcut
/// surface. Mini-player visibility and lifecycle live in GlobalMiniPlayer.
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
  final _controller = AppWideControlsController.instance;
  bool _shortcutsExpanded = false;

  @override
  void initState() {
    super.initState();
    _controller.registerShortcutExpander(_expandShortcuts);
  }

  @override
  void dispose() {
    _controller.unregisterShortcutExpander(_expandShortcuts);
    super.dispose();
  }

  void _expandShortcuts() {
    HapticFeedback.lightImpact();
    if (mounted) setState(() => _shortcutsExpanded = true);
  }

  void _selectShortcut(String id) {
    setState(() => _shortcutsExpanded = false);
    _controller.selectShortcut?.call(id);
  }

  @override
  Widget build(BuildContext context) {
    final observer = DiagnosticNavigatorObserver.instance;
    return AnimatedBuilder(
      animation: Listenable.merge([
        _settings,
        _controller,
        observer.controlsVisible,
      ]),
      builder: (context, _) {
        if (!observer.controlsVisible.value || !_controller.isAttached) {
          return const SizedBox.shrink();
        }

        final showShortcut =
            _shortcutsExpanded && _controller.selectShortcut != null;
        if (!showShortcut) return const SizedBox.shrink();

        return Stack(
          fit: StackFit.expand,
          children: [
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => setState(() => _shortcutsExpanded = false),
                child: ColoredBox(
                  color: Colors.black.withValues(alpha: 0.45),
                  child: const SizedBox.expand(),
                ),
              ),
            ),
            Positioned(
              left: 0,
              top: 0,
              child: CompositedTransformFollower(
                link: _controller.musicButtonLink,
                showWhenUnlinked: false,
                targetAnchor: Alignment.topRight,
                followerAnchor: Alignment.bottomRight,
                offset: const Offset(0, -8),
                child: FloatingQuickShortcut(
                  shortcuts: _settings.floatingShortcuts,
                  expanded: true,
                  showButton: false,
                  onTap: () => setState(() => _shortcutsExpanded = false),
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
