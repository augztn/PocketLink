import 'package:material_ui/material_ui.dart';

/// Shared 16dp content gutter plus the current horizontal system safe area.
class PocketLinkHorizontalGutter {
  const PocketLinkHorizontalGutter._();

  static const double base = 16;

  static EdgeInsets padding(
    BuildContext context, {
    double top = 0,
    double bottom = 0,
  }) {
    final safe = MediaQuery.paddingOf(context);
    return EdgeInsets.fromLTRB(
      base + safe.left,
      top,
      base + safe.right,
      bottom,
    );
  }
}

/// Shared adaptive column count for card grids across phones and larger displays.
class PocketLinkResponsiveLayout {
  const PocketLinkResponsiveLayout._();

  static int gridColumns(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    if (width < 600) return 2;
    if (width < 840) return 3;
    if (width < 1200) return 4;
    return 5;
  }
}

/// Scroll position shared by the active route tree so every top bar reacts
/// consistently to the same scroll activity.
class PocketLinkScrollOffsetScope extends InheritedNotifier<ValueNotifier<double>> {
  const PocketLinkScrollOffsetScope({
    required ValueNotifier<double> offset,
    required super.child,
    super.key,
  }) : super(notifier: offset);

  static final ValueNotifier<double> _zero = ValueNotifier<double>(0);

  static ValueListenable<double> listenableOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<PocketLinkScrollOffsetScope>()?.notifier ?? _zero;
}

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
      bottomClearance: safeBottom + 12 + 24,
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
  final ValueNotifier<double> _scrollOffset = ValueNotifier<double>(0);

  @override
  void didUpdateWidget(covariant PocketLinkScaffold oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.routeIdentity != widget.routeIdentity) {
      _renderedHeaderHeight = null;
      _scrollOffset.value = 0;
    }
  }

  @override
  void dispose() {
    _scrollOffset.dispose();
    super.dispose();
  }

  bool _handleScrollNotification(ScrollNotification notification) {
    if (notification.depth != 0) return false;
    final next = notification.metrics.pixels.clamp(0.0, double.infinity).toDouble();
    if ((_scrollOffset.value - next).abs() >= 0.5) {
      _scrollOffset.value = next;
    }
    return false;
  }

  void reportHeaderHeight(double height) {
    if (!height.isFinite || height <= 0 ||
        (_renderedHeaderHeight != null &&
            (_renderedHeaderHeight! - height).abs() < 0.5)) {
      return;
    }
    final routeIdentity = widget.routeIdentity;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && widget.routeIdentity == routeIdentity &&
          (_renderedHeaderHeight == null ||
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
        (widget.hasActiveMiniPlayer ? 74.0 : 0.0) +
        24.0;

    return LayoutInsetsScope(
      topClearance: topClearance,
      bottomClearance: bottomClearance,
      hasFloatingNavBar: widget.hasFloatingNavBar,
      hasActiveMiniPlayer: widget.hasActiveMiniPlayer,
      reportHeaderHeight: reportHeaderHeight,
      child: NotificationListener<ScrollNotification>(
        onNotification: _handleScrollNotification,
        child: PocketLinkScrollOffsetScope(
          offset: _scrollOffset,
          child: widget.child,
        ),
      ),
    );
  }
}
