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
    super.key,
  });

  final Widget title;
  final List<HomeServerAppBarAction> actions;
  final VoidCallback? onHome;
  final Widget? leading;
  final bool? centerTitle;

  void _goHome(BuildContext context) {
    if (onHome != null) {
      onHome!();
      return;
    }
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  @override
  Widget build(BuildContext context) => AppBar(
    title: title,
    leading: leading,
    centerTitle: centerTitle,
    actions: [
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
