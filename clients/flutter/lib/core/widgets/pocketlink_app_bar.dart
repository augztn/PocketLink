import 'package:material_ui/material_ui.dart';

import '../navigation/pocketlink_navigation.dart';
import 'feathered_glass_header.dart';
import 'pocketlink_scaffold.dart';
import 'smoked_glass_popover_menu.dart';

class PocketLinkAppBarAction {
  const PocketLinkAppBarAction({
    required this.label,
    required this.icon,
    required this.onPressed,
    this.enabled = true,
    this.dividerBefore = false,
  });

  final String label;
  final IconData icon;
  final VoidCallback? onPressed;
  final bool enabled;
  final bool dividerBefore;
}

/// Shared navigation and action surface for every secondary screen.
class PocketLinkTopBar extends StatelessWidget implements PreferredSizeWidget {
  const PocketLinkTopBar({
    required this.title,
    this.actions = const [],
    this.onHome,
    this.leading,
    this.leadingWidth,
    this.titleSpacing,
    this.centerTitle,
    this.backgroundColor,
    this.foregroundColor,
    this.elevation,
    this.showHome = false,
    this.showMoreMenu = true,
    this.automaticallyImplyLeading = true,
    this.actionsBeforeHome = const [],
    this.feathered = false,
    super.key,
  });

  final Widget title;
  final List<PocketLinkAppBarAction> actions;
  final VoidCallback? onHome;
  final Widget? leading;
  final double? leadingWidth;
  final double? titleSpacing;
  final bool? centerTitle;
  final Color? backgroundColor;
  final Color? foregroundColor;
  final double? elevation;
  final bool showHome;
  final bool showMoreMenu;
  final bool automaticallyImplyLeading;
  final List<Widget> actionsBeforeHome;
  final bool feathered;

  static const dashboardRouteName = PocketLinkRouteNames.dashboard;

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
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final safeLeft = MediaQuery.paddingOf(context).left;
    final navigator = Navigator.maybeOf(context);
    final scaffold = Scaffold.maybeOf(context);
    final effectiveLeading = leading ??
        (automaticallyImplyLeading && scaffold?.hasDrawer == true
            ? IconButton(
                tooltip: 'Open navigation menu',
                onPressed: () => scaffold?.openDrawer(),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints.tightFor(width: 40, height: 40),
                icon: const Icon(Icons.menu_rounded),
              )
            : automaticallyImplyLeading && (navigator?.canPop() ?? false)
                ? IconButton(
                    tooltip: 'Back',
                    onPressed: () => navigator?.maybePop(),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints.tightFor(width: 40, height: 40),
                    icon: const Icon(Icons.arrow_back_rounded),
                  )
                : null);
    final alignedLeading = effectiveLeading == null
        ? null
        : Padding(
            padding: EdgeInsets.only(left: safeLeft + 16),
            child: effectiveLeading,
          );
    final effectiveLeadingWidth = effectiveLeading == null
        ? null
        : (leadingWidth ?? kToolbarHeight) + safeLeft;
    return AppBar(
      title: title,
      leading: alignedLeading,
      leadingWidth: effectiveLeadingWidth,
      titleSpacing: effectiveLeading == null ? (titleSpacing ?? 16) + safeLeft : titleSpacing,
      automaticallyImplyLeading: false,
      centerTitle: centerTitle,
      backgroundColor: backgroundColor ?? Colors.transparent,
      toolbarHeight: PocketLinkLayoutMetrics.topBarHeight,
      flexibleSpace: const FeatheredGlassHeaderBackground(
        contentHeight: PocketLinkLayoutMetrics.topBarHeight,
      ),
      // Extends the header's progressive blur/scrim below the toolbar.
      // The fade reaches zero alpha at this boundary, so no seam is visible.
      bottom: const PreferredSize(
        preferredSize: Size.fromHeight(32),
        child: IgnorePointer(child: SizedBox.expand()),
      ),
      foregroundColor: foregroundColor,
      elevation: elevation ?? 0,
      scrolledUnderElevation: 0,
      surfaceTintColor: Colors.transparent,
      shadowColor: Colors.transparent,
      titleTextStyle: theme.textTheme.titleLarge?.copyWith(
        color: foregroundColor ?? theme.colorScheme.onSurface,
        fontSize: 26,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.5,
      ),
      actionsPadding: EdgeInsets.only(
        right: PocketLinkHorizontalGutter.padding(context).right,
      ),
      actions: [
      ...actionsBeforeHome,
      if (showHome)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: SizedBox.square(
            dimension: 40,
            child: GlassCircleButton(
              size: 40,
              tooltip: 'Home',
              onPressed: () => _goHome(context),
              child: const Icon(Icons.home_rounded),
            ),
          ),
        ),
      if (showMoreMenu)
        SmokedGlassPopoverMenu<PocketLinkAppBarAction>(
          tooltip: 'More actions',
          items: [
            if (!actions.any((action) => action.label.toLowerCase().contains('home')))
              SmokedGlassPopoverMenuItem<PocketLinkAppBarAction>(
              value: PocketLinkAppBarAction(
                label: 'Return to Home',
                icon: Icons.home_rounded,
                onPressed: () => _goHome(context),
              ),
              label: 'Return to Home',
              icon: Icons.home_rounded,
            ),
            ...actions.map((action) => SmokedGlassPopoverMenuItem<PocketLinkAppBarAction>(
              value: action,
              label: action.label,
              icon: action.icon,
              enabled: action.enabled && action.onPressed != null,
              dividerBefore: action.dividerBefore,
            )),
          ],
          onSelected: (action) => action.onPressed?.call(),
          child: const Padding(
            padding: EdgeInsets.symmetric(vertical: 4),
            child: SizedBox.square(
              dimension: 40,
              child: GlassCircleButton(
                size: 40,
                tooltip: 'Open overflow menu',
                onPressed: null,
                child: Icon(Icons.more_vert_rounded, size: 18),
              ),
            ),
          ),
        ),
      ],
    );
  }

  @override
  Size get preferredSize => const Size.fromHeight(PocketLinkLayoutMetrics.topBarHeight + 32);
}


/// Backwards-compatible name while screens migrate to the unified top bar.
typedef PocketLinkAppBar = PocketLinkTopBar;

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