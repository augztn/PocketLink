import 'package:material_ui/material_ui.dart';

const double pocketLinkMiniPlayerHeight = 74.0;
const double pocketLinkHeaderFadeTailHeight = 112.0;
const double pocketLinkTopContentGap = 14.0;

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
  final void Function(Object routeIdentity, double height) reportHeaderHeight;

  static void reportRenderedHeader(
    BuildContext context,
    Object routeIdentity,
    double height,
  ) =>
      context
          .getInheritedWidgetOfExactType<LayoutInsetsScope>()
          ?.reportHeaderHeight(routeIdentity, height);

  static LayoutInsetsScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<LayoutInsetsScope>();

  static LayoutInsetsScope of(BuildContext context) {
    final scope = maybeOf(context);
    if (scope != null) return scope;
    final media = MediaQuery.maybeOf(context);
    final safeTop = media?.padding.top ?? 0.0;
    final safeBottom = media?.padding.bottom ?? 0.0;
    return LayoutInsetsScope(
      topClearance: safeTop + kToolbarHeight + pocketLinkTopContentGap,
      bottomClearance: safeBottom + 12,
      hasFloatingNavBar: false,
      hasActiveMiniPlayer: false,
      reportHeaderHeight: (_, __) {},
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
    this.activeRouteIdentities,
    super.key,
  });

  final Widget child;
  final bool hasFloatingNavBar;
  final bool hasActiveMiniPlayer;
  final Object? routeIdentity;
  final List<Object>? activeRouteIdentities;

  @override
  State<PocketLinkScaffold> createState() => _PocketLinkScaffoldState();
}

class _PocketLinkScaffoldState extends State<PocketLinkScaffold> {
  final Map<Object, double> _renderedHeaderHeights = <Object, double>{};

  @override
  void didUpdateWidget(covariant PocketLinkScaffold oldWidget) {
    super.didUpdateWidget(oldWidget);
    final activeRoutes = widget.activeRouteIdentities;
    if (activeRoutes != null) {
      _renderedHeaderHeights.removeWhere(
        (route, _) => !activeRoutes.contains(route),
      );
    }
  }

  void reportHeaderHeight(Object routeIdentity, double height) {
    if (!height.isFinite || height <= 0) return;
    final storedHeight = _renderedHeaderHeights[routeIdentity];
    if (storedHeight != null && (storedHeight - height).abs() < 0.5) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final activeRoutes = widget.activeRouteIdentities;
      if (activeRoutes != null && !activeRoutes.contains(routeIdentity)) {
        return;
      }
      final currentHeight = _renderedHeaderHeights[routeIdentity];
      if (currentHeight != null && (currentHeight - height).abs() < 0.5) {
        return;
      }
      setState(() => _renderedHeaderHeights[routeIdentity] = height);
    });
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final statusBarHeight = media.padding.top;
    final renderedHeaderHeight = widget.routeIdentity == null
        ? null
        : _renderedHeaderHeights[widget.routeIdentity];
    // The header reporter includes the feathered fade tail. Remove that
    // decorative tail, then add the one shared resting content gap.
    final topClearance = renderedHeaderHeight == null
        ? statusBarHeight + kToolbarHeight + pocketLinkTopContentGap
        : renderedHeaderHeight -
            pocketLinkHeaderFadeTailHeight +
            pocketLinkTopContentGap;
    final bottomClearance = media.padding.bottom +
        (widget.hasFloatingNavBar ? 84.0 : 12.0) +
        (widget.hasActiveMiniPlayer ? pocketLinkMiniPlayerHeight : 0.0);

    return LayoutInsetsScope(
      topClearance: topClearance,
      bottomClearance: bottomClearance,
      hasFloatingNavBar: widget.hasFloatingNavBar,
      hasActiveMiniPlayer: widget.hasActiveMiniPlayer,
      reportHeaderHeight: reportHeaderHeight,
      child: RepaintBoundary(child: widget.child),
    );
  }
}
