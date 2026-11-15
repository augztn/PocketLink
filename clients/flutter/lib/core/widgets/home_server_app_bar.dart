import 'package:flutter/material.dart';

class HomeServerAppBarAction {
  const HomeServerAppBarAction({
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
class HomeServerAppBar extends StatelessWidget implements PreferredSizeWidget {
  const HomeServerAppBar({
    required this.title,
    this.actions = const [],
    this.onHome,
    this.leading,
    this.centerTitle,
    this.backgroundColor,
    this.foregroundColor,
    this.elevation,
    this.showHome = true,
    super.key,
  });

  final Widget title;
  final List<HomeServerAppBarAction> actions;
  final VoidCallback? onHome;
  final Widget? leading;
  final bool? centerTitle;
  final Color? backgroundColor;
  final Color? foregroundColor;
  final double? elevation;
  final bool showHome;

  static const dashboardRouteName = '/homeserver-dashboard';

  static void goToDashboard(BuildContext context) {
    Navigator.of(context).popUntil(
      (route) => route.settings.name == dashboardRouteName,
    );
  }

  void _goHome(BuildContext context) {
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
      if (showHome)
        IconButton(
          tooltip: 'Home',
          onPressed: () => _goHome(context),
          icon: const Icon(Icons.home_rounded),
        ),
      PopupMenuButton<HomeServerAppBarAction>(
        tooltip: 'More actions',
        icon: const Icon(Icons.more_vert_rounded),
        onSelected: (action) => action.onPressed?.call(),
        itemBuilder: (context) => actions.map((action) =>
          PopupMenuItem<HomeServerAppBarAction>(
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
