import 'package:material_ui/material_ui.dart';

abstract final class PocketLinkRouteNames {
  static const dashboard = '/pocketlink-dashboard';
  static const nowPlaying = '/pocketlink-now-playing';
}

/// Tracks the root navigator stack so app-level UI can react to route changes.
class PocketLinkNavigationObserver extends NavigatorObserver {
  final List<Route<dynamic>> _routes = <Route<dynamic>>[];

  final ValueNotifier<List<Route<dynamic>>> routeStack =
      ValueNotifier<List<Route<dynamic>>>(const <Route<dynamic>>[]);

  Route<dynamic>? get currentPageRoute {
    for (final route in _routes.reversed) {
      if (route is PageRoute<dynamic>) return route;
    }
    return null;
  }

  bool get isDashboardVisible =>
      currentPageRoute?.settings.name == PocketLinkRouteNames.dashboard;

  bool get isNowPlayingVisible =>
      currentPageRoute?.settings.name == PocketLinkRouteNames.nowPlaying;

  bool get isModalRouteOnTop =>
      _routes.isNotEmpty && _routes.last is PopupRoute<dynamic>;

  void _publish() {
    routeStack.value = List<Route<dynamic>>.unmodifiable(_routes);
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _routes.remove(route);
    _routes.add(route);
    _publish();
    super.didPush(route, previousRoute);
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _routes.remove(route);
    if (previousRoute != null && !_routes.contains(previousRoute)) {
      _routes.add(previousRoute);
    }
    _publish();
    super.didPop(route, previousRoute);
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _routes.remove(route);
    if (previousRoute != null && !_routes.contains(previousRoute)) {
      _routes.add(previousRoute);
    }
    _publish();
    super.didRemove(route, previousRoute);
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    final index = oldRoute == null ? -1 : _routes.indexOf(oldRoute);
    if (index >= 0) {
      _routes.removeAt(index);
      if (newRoute != null) _routes.insert(index, newRoute);
    } else if (newRoute != null) {
      _routes.add(newRoute);
    }
    _publish();
    super.didReplace(newRoute: newRoute, oldRoute: oldRoute);
  }
}

abstract final class PocketLinkNavigation {
  static final navigatorKey = GlobalKey<NavigatorState>();
  static final musicButtonKey = GlobalKey();
  static final miniPlayerKey = GlobalKey();
  static final mediaOverlayKey = GlobalKey();
  static final drawerOpen = ValueNotifier<bool>(false);
  static final observer = PocketLinkNavigationObserver();

  /// Captures the visible source surface for the Now Playing container transform.
  static Rect? resolveMediaOriginRect({required bool preferMiniPlayer}) {
    final keys = preferMiniPlayer
        ? <GlobalKey>[miniPlayerKey, musicButtonKey]
        : <GlobalKey>[musicButtonKey, miniPlayerKey];
    for (final key in keys) {
      final renderObject = key.currentContext?.findRenderObject();
      if (renderObject is! RenderBox || !renderObject.hasSize) continue;
      final rect = renderObject.localToGlobal(Offset.zero) & renderObject.size;
      if (rect.width > 0 && rect.height > 0) return rect;
    }
    return null;
  }

  /// Expands a full-screen media route from the mini-player or Music dock pill.
  static Widget mediaContainerTransformTransition({
    required BuildContext context,
    required Animation<double> animation,
    required Widget child,
    required Rect? originRect,
  }) {
    final media = MediaQuery.of(context);
    if (media.disableAnimations) return child;
    final size = media.size;
    final destination = Offset.zero & size;
    final origin = originRect ?? Rect.fromLTWH(
      size.width - 72,
      size.height - media.padding.bottom - 76,
      56,
      56,
    );

    return AnimatedBuilder(
      animation: animation,
      child: child,
      builder: (context, animatedChild) {
        final progress = animation.status == AnimationStatus.reverse
            ? Curves.easeInCubic.transform(animation.value)
            : Curves.easeOutCubic.transform(animation.value);
        final rect = Rect.lerp(origin, destination, progress)!;
        final radius = 22 * (1 - progress);
        return Align(
          alignment: Alignment.topLeft,
          widthFactor: 1,
          heightFactor: 1,
          child: Transform.translate(
            offset: rect.topLeft,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(radius),
              child: SizedBox(
                width: rect.width,
                height: rect.height,
                child: FittedBox(
                  fit: BoxFit.fill,
                  child: SizedBox(
                    width: size.width,
                    height: size.height,
                    child: animatedChild,
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
