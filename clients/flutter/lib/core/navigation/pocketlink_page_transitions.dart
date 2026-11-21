import 'package:material_ui/material_ui.dart';

/// A subtle shared-axis transition for pushed routes and reverse pops.
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
    if (MediaQuery.of(context).disableAnimations) return child;

    final eased = CurvedAnimation(
      parent: animation,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );
    final opacity = CurvedAnimation(
      parent: animation,
      curve: Curves.easeOut,
      reverseCurve: Curves.easeIn,
    );

    return FadeTransition(
      opacity: opacity,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0.035, 0),
          end: Offset.zero,
        ).animate(eased),
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.99, end: 1).animate(eased),
          child: child,
        ),
      ),
    );
  }
}
