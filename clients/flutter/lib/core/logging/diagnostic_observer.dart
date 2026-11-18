import 'dart:io';

import 'package:material_ui/material_ui.dart';

import 'app_logger.dart';
import '../widgets/pocketlink_app_bar.dart';

/// Records navigation and app lifecycle without logging user content or paths.
class DiagnosticNavigatorObserver extends NavigatorObserver {
  DiagnosticNavigatorObserver._();

  static final instance = DiagnosticNavigatorObserver._();
  final List<Route<dynamic>> _routes = [];
  final ValueNotifier<bool> controlsVisible = ValueNotifier(false);
  final ValueNotifier<bool> dashboardVisible = ValueNotifier(false);

  void _updateControlVisibility() {
    final dashboardRoute = PocketLinkAppBar.dashboardRouteName;
    final hasDashboard = _routes.any((route) => route.settings.name == dashboardRoute);
    final currentRoute = _routes.isEmpty ? null : _routes.last;
    controlsVisible.value = hasDashboard && currentRoute is PageRoute;
    dashboardVisible.value = hasDashboard && currentRoute?.settings.name == dashboardRoute;
  }

  String _routeLabel(Route<dynamic>? route) =>
      route == null ? 'none' : route.runtimeType.toString();

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _routes.add(route);
    _updateControlVisibility();
    AppLogger.info('Navigation route pushed', fields: {
      'route': _routeLabel(route),
      'previousRoute': _routeLabel(previousRoute),
      'stackDepth': _routes.length,
    });
    super.didPush(route, previousRoute);
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _routes.remove(route);
    _updateControlVisibility();
    AppLogger.info('Navigation route popped', fields: {
      'route': _routeLabel(route),
      'revealedRoute': _routeLabel(previousRoute),
      'stackDepth': _routes.length,
    });
    super.didPop(route, previousRoute);
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _routes.remove(route);
    _updateControlVisibility();
    AppLogger.info('Navigation route removed', fields: {
      'route': _routeLabel(route),
      'stackDepth': _routes.length,
    });
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
    _updateControlVisibility();
    AppLogger.info('Navigation route replaced', fields: {
      'oldRoute': _routeLabel(oldRoute),
      'newRoute': _routeLabel(newRoute),
      'stackDepth': _routes.length,
    });
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
