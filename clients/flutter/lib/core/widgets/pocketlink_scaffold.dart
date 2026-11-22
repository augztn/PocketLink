import 'package:flutter/foundation.dart' show ValueListenable;
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

/// Single source of truth for the floating dock and mini-player geometry.
abstract final class PocketLinkLayoutMetrics {
  static const double topBarHeight = 64;
  static const double dockHeight = 84;
  static const double miniPlayerHeight = 62;
  static const double miniPlayerGap = 10;
  static const double bottomClearance = 24;

  static double bottomOverlayHeight({
    required double bottomInset,
    required bool hasDock,
    required bool hasMiniPlayer,
  }) =>
      bottomInset +
      (hasDock ? dockHeight : 0) +
      (hasMiniPlayer ? miniPlayerHeight + miniPlayerGap : 0) +
      bottomClearance;
}

/// Shared background fade behind the persistent mini-player and bottom dock.
class PocketLinkBottomScrim extends StatelessWidget {
  const PocketLinkBottomScrim({required this.height, super.key});

  final double height;

  @override
  Widget build(BuildContext context) => IgnorePointer(
        child: SizedBox(
          height: height,
          child: const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.transparent,
                  Color(0x66000000),
                  Color(0xFF000000),
                ],
                stops: [0.0, 0.48, 1.0],
              ),
            ),
          ),
        ),
      );
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
    final safeBottom = media?.viewPadding.bottom ?? 0.0;
    return LayoutInsetsScope(
      topClearance: safeTop + PocketLinkLayoutMetrics.topBarHeight + 8,
      bottomClearance: PocketLinkLayoutMetrics.bottomOverlayHeight(
        bottomInset: safeBottom,
        hasDock: false,
        hasMiniPlayer: false,
      ),
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
    if (notification.depth != 0 || notification.metrics.axis != Axis.vertical) return false;
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
            ? PocketLinkLayoutMetrics.topBarHeight
            : (_renderedHeaderHeight! - statusBarHeight - 32).clamp(
                PocketLinkLayoutMetrics.topBarHeight,
                200.0,
              ).toDouble();
    final topClearance = statusBarHeight + headerContentHeight + 8;
    final bottomClearance = PocketLinkLayoutMetrics.bottomOverlayHeight(
      bottomInset: media.viewPadding.bottom,
      hasDock: widget.hasFloatingNavBar,
      hasMiniPlayer: widget.hasActiveMiniPlayer,
    );

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
