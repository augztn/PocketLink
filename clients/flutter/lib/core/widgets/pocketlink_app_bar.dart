import 'package:flutter/material.dart';

class PocketLinkAppBarAction {
  const PocketLinkAppBarAction({
    required this.label,
    required this.icon,
    required this.onPressed,
    this.enabled = true,
  });

  final String label;
  final IconData icon;
  final VoidCallback? onPressed;
  final bool enabled;
}

/// Shared navigation and action surface for every secondary screen.
class PocketLinkAppBar extends StatelessWidget implements PreferredSizeWidget {
  const PocketLinkAppBar({
    required this.title,
    this.actions = const [],
    this.onHome,
    this.leading,
    this.centerTitle,
    this.backgroundColor,
    this.foregroundColor,
    this.elevation,
    this.showHome = true,
    this.actionsBeforeHome = const [],
    super.key,
  });

  final Widget title;
  final List<PocketLinkAppBarAction> actions;
  final VoidCallback? onHome;
  final Widget? leading;
  final bool? centerTitle;
  final Color? backgroundColor;
  final Color? foregroundColor;
  final double? elevation;
  final bool showHome;
  final List<Widget> actionsBeforeHome;

  static const dashboardRouteName = '/pocketlink-dashboard';

  static void goToDashboard(BuildContext context) {
    final scopedHome = PocketLinkNavigationScope.maybeOnHome(context);
    if (scopedHome != null) {
      scopedHome();
      return;
    }
    Navigator.of(context, rootNavigator: true).popUntil(
      (route) => route.settings.name == dashboardRouteName,
    );
  }

  void _goHome(BuildContext context) {
    final scopedHome = PocketLinkNavigationScope.maybeOnHome(context);
    if (scopedHome != null) {
      scopedHome();
      return;
    }
    if (onHome != null) {
      onHome!();
      return;
    }
    goToDashboard(context);
  }

  @override
  Widget build(BuildContext context) => AppBar(
    title: title,
    leading: leading,
    centerTitle: centerTitle,
    backgroundColor: backgroundColor,
    foregroundColor: foregroundColor,
    elevation: elevation,
    actions: [
      ...actionsBeforeHome,
      if (showHome)
        IconButton(
          tooltip: 'Home',
          onPressed: () => _goHome(context),
          icon: const Icon(Icons.home_rounded),
        ),
      PopupMenuButton<PocketLinkAppBarAction>(
        tooltip: 'More actions',
        icon: const Icon(Icons.more_vert_rounded),
        onSelected: (action) => action.onPressed?.call(),
        itemBuilder: (context) => actions.map((action) =>
          PopupMenuItem<PocketLinkAppBarAction>(
            value: action,
            enabled: action.enabled && action.onPressed != null,
            child: Row(
              children: [
                Icon(action.icon, size: 20),
                const SizedBox(width: 12),
                Text(action.label),
              ],
            ),
          ),
        ).toList(growable: false),
      ),
    ],
  );

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);
}


/// Supplies dashboard navigation to screens hosted inside nested navigators.
class PocketLinkNavigationScope extends InheritedWidget {
  const PocketLinkNavigationScope({
    required this.onHome,
    required super.child,
    super.key,
  });

  final VoidCallback onHome;

  static VoidCallback? maybeOnHome(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<PocketLinkNavigationScope>()?.onHome;

  @override
  bool updateShouldNotify(PocketLinkNavigationScope oldWidget) =>
      onHome != oldWidget.onHome;
}
