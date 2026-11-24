import 'dart:io';

import 'package:material_ui/material_ui.dart';

import 'app_logger.dart';

/// Records navigation and app lifecycle without logging user content or paths.
class DiagnosticNavigatorObserver extends NavigatorObserver {
  DiagnosticNavigatorObserver._();

  static final instance = DiagnosticNavigatorObserver._();
  final List<Route<dynamic>> _routes = [];

  String _routeLabel(Route<dynamic>? route) =>
      route == null ? 'none' : route.runtimeType.toString();

  void _recordNavigation(String action, Route<dynamic>? route, Route<dynamic>? related) {
    AppLogger.event('navigation.$action', category: 'navigation', component: 'navigator',
      fields: {'route_type': _routeLabel(route), 'related_route_type': _routeLabel(related),
        'stack_depth': _routes.length});
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _routes.add(route);
    _recordNavigation('push', route, previousRoute);
    super.didPush(route, previousRoute);
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _routes.remove(route);
    _recordNavigation('pop', route, previousRoute);
    super.didPop(route, previousRoute);
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _routes.remove(route);
    _recordNavigation('remove', route, previousRoute);
    super.didRemove(route, previousRoute);
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    final index = oldRoute == null ? -1 : _routes.indexOf(oldRoute);
    if (index >= 0 && newRoute != null) {
      _routes[index] = newRoute;
    } else if (newRoute != null) {
      _routes.add(newRoute);
    }
    _recordNavigation('replace', newRoute, oldRoute);
    super.didReplace(newRoute: newRoute, oldRoute: oldRoute);
  }
}

/// Captures foreground/background transitions and a lightweight memory sample.
class DiagnosticLifecycleObserver with WidgetsBindingObserver {
  DiagnosticLifecycleObserver._();

  static final instance = DiagnosticLifecycleObserver._();
  bool _started = false;

  void start() {
    if (_started) return;
    _started = true;
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final fields = <String, Object?>{'state': state.name};
    try {
      fields['processRssMb'] =
          (ProcessInfo.currentRss / (1024 * 1024)).toStringAsFixed(1);
    } catch (_) {
      fields['processRssMb'] = 'unavailable';
    }
    AppLogger.info('App lifecycle changed', fields: fields);
  }
}
