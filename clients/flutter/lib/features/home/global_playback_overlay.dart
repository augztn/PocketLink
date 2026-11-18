import 'package:material_ui/material_ui.dart';

/// Hosts controls above the root Navigator so they remain visible on pushed
/// screens such as Photos, Documents, Files, Music and Videos.
class GlobalPlaybackOverlay extends ChangeNotifier {
  GlobalPlaybackOverlay._();

  static final GlobalPlaybackOverlay instance = GlobalPlaybackOverlay._();

  WidgetBuilder? _builder;
  bool _suppressed = false;

  void setBuilder(WidgetBuilder builder) {
    _builder = builder;
    notifyListeners();
  }

  void clearBuilder(WidgetBuilder builder) {
    if (_builder != builder) return;
    _builder = null;
    notifyListeners();
  }

  void setSuppressed(bool value) {
    if (_suppressed == value) return;
    _suppressed = value;
    notifyListeners();
  }

  void refresh() => notifyListeners();

  Widget build(BuildContext context) => _suppressed
      ? const SizedBox.shrink()
      : _builder?.call(context) ?? const SizedBox.shrink();
}
