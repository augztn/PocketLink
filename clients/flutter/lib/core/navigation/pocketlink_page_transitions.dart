import 'package:material_ui/material_ui.dart';

import '../settings/app_settings.dart';

/// A subtle shared-axis transition that keeps the incoming route fully opaque.
class PocketLinkPageTransitionsBuilder extends PageTransitionsBuilder {
  const PocketLinkPageTransitionsBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    if (MediaQuery.of(context).disableAnimations ||
        !AppSettings.instance.animationsEnabled ||
        !AppSettings.instance.pageTransitionsEnabled) {
      return child;
    }

    final eased = CurvedAnimation(
      parent: animation,
      curve: Curves.easeOutCubic,
      // Keep reverse progress linear. Predictive-back gestures drive this
      // animation interactively; easing it can distort the finger-tracked
      // progress and make a partially completed pop feel hesitant on release.
      reverseCurve: Curves.linear,
    );

    // Do not fade the route: Settings pages use layered/glass surfaces, and
    // fading exposes the previous route through them during push and pop.
    return SlideTransition(
      position: Tween<Offset>(
        begin: const Offset(0.035, 0),
        end: Offset.zero,
      ).animate(eased),
      child: ScaleTransition(
        scale: Tween<double>(begin: 0.99, end: 1).animate(eased),
        child: child,
      ),
    );
  }
}
