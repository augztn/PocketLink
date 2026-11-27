import 'package:material_ui/material_ui.dart';

/// Provides a stable Overlay above app-level surfaces mounted outside the
/// root Navigator, such as the persistent media player.
class PersistentOverlayHost extends StatefulWidget {
  const PersistentOverlayHost({required this.child, super.key});

  final Widget child;

  @override
  State<PersistentOverlayHost> createState() => _PersistentOverlayHostState();
}

class _PersistentOverlayHostState extends State<PersistentOverlayHost> {
  late final OverlayEntry _entry;

  @override
  void initState() {
    super.initState();
    _entry = OverlayEntry(builder: (_) => widget.child);
  }

  @override
  void didUpdateWidget(covariant PersistentOverlayHost oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.child != widget.child) _entry.markNeedsBuild();
  }

  @override
  void dispose() {
    _entry.remove();
    _entry.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Overlay(
        initialEntries: <OverlayEntry>[_entry],
      );
}
