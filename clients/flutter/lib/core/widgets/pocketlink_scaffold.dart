import 'package:material_ui/material_ui.dart';

/// Route-level layout geometry shared by every PocketLink screen.
class LayoutInsetsScope extends InheritedWidget {
  const LayoutInsetsScope({
    required this.topClearance,
    required this.bottomClearance,
    required this.hasFloatingNavBar,
    required this.hasActiveMiniPlayer,
    required this.reportHeaderHeight,
    required super.child,
    super.key,
  });

  final double topClearance;
  final double bottomClearance;
  final bool hasFloatingNavBar;
  final bool hasActiveMiniPlayer;
  final ValueChanged<double> reportHeaderHeight;

  static void reportRenderedHeader(BuildContext context, double height) =>
      maybeOf(context)?.reportHeaderHeight(height);

  static LayoutInsetsScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<LayoutInsetsScope>();

  static LayoutInsetsScope of(BuildContext context) {
    final scope = maybeOf(context);
    if (scope != null) return scope;
    final media = MediaQuery.maybeOf(context);
    final safeTop = media?.padding.top ?? 0.0;
    final safeBottom = media?.padding.bottom ?? 0.0;
    return LayoutInsetsScope(
      topClearance: safeTop + kToolbarHeight + 10,
      bottomClearance: safeBottom + 12,
      hasFloatingNavBar: false,
      hasActiveMiniPlayer: false,
      reportHeaderHeight: (_) {},
      child: const SizedBox.shrink(),
    );
  }

  @override
  bool updateShouldNotify(LayoutInsetsScope oldWidget) =>
      topClearance != oldWidget.topClearance ||
      bottomClearance != oldWidget.bottomClearance ||
      hasFloatingNavBar != oldWidget.hasFloatingNavBar ||
      hasActiveMiniPlayer != oldWidget.hasActiveMiniPlayer;
}

/// Installs the shared layout scope around the active navigator route tree.
///
/// Header clearance is reported by the rendered FeatheredGlassHeaderBackground;
/// bottom clearance follows the overlays that are currently mounted.
class PocketLinkScaffold extends StatefulWidget {
  const PocketLinkScaffold({
    required this.child,
    required this.hasFloatingNavBar,
    required this.hasActiveMiniPlayer,
    this.routeIdentity,
    super.key,
  });

  final Widget child;
  final bool hasFloatingNavBar;
  final bool hasActiveMiniPlayer;
  final Object? routeIdentity;

  @override
  State<PocketLinkScaffold> createState() => _PocketLinkScaffoldState();
}

class _PocketLinkScaffoldState extends State<PocketLinkScaffold> {
  double? _renderedHeaderHeight;

  @override
  void didUpdateWidget(covariant PocketLinkScaffold oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.routeIdentity != widget.routeIdentity) {
      _renderedHeaderHeight = null;
    }
  }

  void reportHeaderHeight(double height) {
    if (!height.isFinite || height <= 0 ||
        (_renderedHeaderHeight != null &&
            (_renderedHeaderHeight! - height).abs() < 0.5)) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && (_renderedHeaderHeight == null ||
          (_renderedHeaderHeight! - height).abs() >= 0.5)) {
        setState(() => _renderedHeaderHeight = height);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final statusBarHeight = media.padding.top;
    final headerContentHeight =
        _renderedHeaderHeight == null
            ? kToolbarHeight
            : (_renderedHeaderHeight! - statusBarHeight - 16).clamp(
                kToolbarHeight,
                200.0,
              ).toDouble();
    final topClearance = statusBarHeight + headerContentHeight + 10;
    final bottomClearance = media.padding.bottom +
        (widget.hasFloatingNavBar ? 84.0 : 12.0) +
        (widget.hasActiveMiniPlayer ? 74.0 : 0.0);

    return LayoutInsetsScope(
      topClearance: topClearance,
      bottomClearance: bottomClearance,
      hasFloatingNavBar: widget.hasFloatingNavBar,
      hasActiveMiniPlayer: widget.hasActiveMiniPlayer,
      reportHeaderHeight: reportHeaderHeight,
      child: widget.child,
    );
  }
}
