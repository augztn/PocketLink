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
  static final mediaOverlayKey = GlobalKey();
  static final observer = PocketLinkNavigationObserver();
}
