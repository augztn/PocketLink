import 'dart:ui' as ui;

import 'package:material_ui/material_ui.dart';

import '../settings/app_settings.dart';

class SmokedGlassPopoverMenuItem<T> {
  const SmokedGlassPopoverMenuItem({
    required this.value,
    required this.label,
    required this.icon,
    this.destructive = false,
    this.enabled = true,
    this.dividerBefore = false,
    this.trailing,
  });

  final T value;
  final String label;
  final IconData icon;
  final bool destructive;
  final bool enabled;
  final bool dividerBefore;
  final Widget? trailing;
}

/// Consistent left-anchored dropdown used by screen title selectors.
class TitleDropdownPopover<T> extends StatelessWidget {
  const TitleDropdownPopover({
    required this.items,
    required this.onSelected,
    required this.child,
    this.tooltip,
    this.onOpenChanged,
    super.key,
  });

  final List<SmokedGlassPopoverMenuItem<T>> items;
  final ValueChanged<T> onSelected;
  final Widget child;
  final String? tooltip;
  final ValueChanged<bool>? onOpenChanged;

  @override
  Widget build(BuildContext context) => SmokedGlassPopoverMenu<T>(
    items: items,
    onSelected: onSelected,
    child: child,
    tooltip: tooltip,
    onOpenChanged: onOpenChanged,
    titleMenu: true,
    itemHeight: 44,
    menuVerticalPadding: 6,
    itemHorizontalPadding: 14,
    trailingWidth: 48,
  );
}

/// Root-navigator popover with a measured anchor and reversible glass bloom.
class SmokedGlassPopoverMenu<T> extends StatelessWidget {
  const SmokedGlassPopoverMenu({
    required this.items,
    required this.onSelected,
    required this.child,
    this.tooltip,
    this.gap = 8,
    this.onOpenChanged,
    this.itemHeight = 44,
    this.menuVerticalPadding = 6,
    this.itemHorizontalPadding = 14,
    this.trailingWidth = 48,
    this.titleMenu = false,
    super.key,
  });

  final List<SmokedGlassPopoverMenuItem<T>> items;
  final ValueChanged<T> onSelected;
  final Widget child;
  final String? tooltip;
  final double gap;
  final ValueChanged<bool>? onOpenChanged;
  final double itemHeight;
  final double menuVerticalPadding;
  final double itemHorizontalPadding;
  final double trailingWidth;
  final bool titleMenu;

  Future<void> _open(BuildContext context) async {
    final renderObject = context.findRenderObject();
    if (renderObject is! RenderBox || !renderObject.hasSize) return;

    final anchor = renderObject.localToGlobal(Offset.zero) & renderObject.size;
    onOpenChanged?.call(true);
    T? result;
    try {
      result = await Navigator.of(context, rootNavigator: true).push<T>(
        _SmokedGlassPopoverRoute<T>(
          anchor: anchor,
          gap: gap,
          items: items,
          itemHeight: itemHeight,
          menuVerticalPadding: menuVerticalPadding,
          itemHorizontalPadding: itemHorizontalPadding,
          trailingWidth: trailingWidth,
          titleMenu: titleMenu,
        ),
      );
    } finally {
      onOpenChanged?.call(false);
    }
    if (result != null) onSelected(result);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (anchorContext, _) {
        final trigger = GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => _open(anchorContext),
          child: child,
        );
        return tooltip == null
            ? trigger
            : Tooltip(message: tooltip!, child: trigger);
      },
    );
  }
}

class _SmokedGlassPopoverRoute<T> extends PopupRoute<T> {
  _SmokedGlassPopoverRoute({
    required this.anchor,
    required this.gap,
    required this.items,
    required this.itemHeight,
    required this.menuVerticalPadding,
    required this.itemHorizontalPadding,
    required this.trailingWidth,
    required this.titleMenu,
  });

  final Rect anchor;
  final double gap;
  final List<SmokedGlassPopoverMenuItem<T>> items;
  final double itemHeight;
  final double menuVerticalPadding;
  final double itemHorizontalPadding;
  final double trailingWidth;
  final bool titleMenu;

  @override
  Color? get barrierColor => Colors.transparent;

  @override
  bool get barrierDismissible => true;

  @override
  String? get barrierLabel => 'Dismiss menu';

  @override
  Duration get transitionDuration => const Duration(milliseconds: 220);

  @override
  Duration get reverseTransitionDuration => const Duration(milliseconds: 170);

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) {
    final media = MediaQuery.of(context);
    final menuMaxWidth = mathMin(232, media.size.width - 32);
    final right = titleMenu
        ? 16.0
        : (media.size.width - anchor.right).clamp(16.0, media.size.width - menuMaxWidth - 16).toDouble();
    final menuWidth = menuMaxWidth;
    final minTop = media.padding.top + 8;
    final maxTop = mathMax(
      minTop,
      media.size.height - media.padding.bottom - 54,
    );
    final top = (anchor.bottom + (titleMenu ? 6 : gap)).clamp(minTop, maxTop).toDouble();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final useGlass = AppSettings.instance.useLiquidGlass;
    final curved = CurvedAnimation(
      parent: animation,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );
    final foreground = isDark ? Colors.white : const Color(0xFF172033);
    final iconColor = isDark ? const Color(0xFFD0D5DD) : const Color(0xFF475569);

    return Material(
      type: MaterialType.transparency,
      child: Stack(
        children: [
          if (useGlass)
            Positioned.fill(
              child: FadeTransition(
                opacity: curved,
                child: IgnorePointer(
                  child: ColoredBox(
                    color: Colors.black.withValues(alpha: 0.45),
                  ),
                ),
              ),
            ),
          Positioned(
            top: top,
            left: titleMenu ? 16 : null,
            right: titleMenu ? null : right,
            child: FadeTransition(
              opacity: curved,
              child: SlideTransition(
                position: Tween<Offset>(
                  begin: const Offset(0, -0.04),
                  end: Offset.zero,
                ).animate(curved),
                child: ScaleTransition(
                  alignment: titleMenu ? Alignment.topLeft : Alignment.topRight,
                  scale: Tween<double>(begin: 0.84, end: 1).animate(curved),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      minWidth: menuWidth,
                      maxWidth: menuWidth,
                      maxHeight: mathMin(
                        media.size.height * 0.55,
                        media.size.height - top - media.padding.bottom - 8,
                      ),
                    ),
                    child: ClipRRect(
                borderRadius: BorderRadius.circular(22),
                child: useGlass
                    ? BackdropFilter(
                        filter: ui.ImageFilter.blur(sigmaX: 30, sigmaY: 30),
                        child: _buildMenuCard(
                          context: context,
                          isDark: isDark,
                          useGlass: true,
                          foreground: foreground,
                          iconColor: iconColor,
                        ),
                      )
                    : _buildMenuCard(
                        context: context,
                        isDark: isDark,
                        useGlass: false,
                        foreground: foreground,
                        iconColor: iconColor,
                      ),
              ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildMenuCard({
    required BuildContext context,
    required bool isDark,
    required bool useGlass,
    required Color foreground,
    required Color iconColor,
  }) {
    return Stack(
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            color: isDark
                ? (useGlass
                    ? const Color(0xFF14151A).withValues(alpha: 0.72)
                    : const Color(0xFF1E2025))
                : (useGlass
                    ? Colors.white.withValues(alpha: 0.82)
                    : Colors.white),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(
              color: isDark
                  ? Colors.white.withValues(alpha: useGlass ? 0.20 : 0.12)
                  : const Color(0xFF94A3B8).withValues(alpha: 0.34),
            ),
            boxShadow: const [
              BoxShadow(
                color: Colors.black26,
                blurRadius: 24,
                offset: Offset(0, 10),
              ),
            ],
          ),
          child: Material(
                          color: Colors.transparent,
                          child: SingleChildScrollView(
                            primary: false,
                            physics: const BouncingScrollPhysics(),
                            padding: EdgeInsets.symmetric(vertical: menuVerticalPadding),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                for (final item in items) ...[
                                  if (item.dividerBefore)
                                    Padding(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 12,
                                        vertical: 4,
                                      ),
                                      child: Divider(
                                        height: 1,
                                        color: foreground.withValues(alpha: 0.08),
                                      ),
                                    ),
                                  SizedBox(
                                    height: itemHeight,
                                    child: Material(
                                      color: Colors.transparent,
                                      child: InkWell(
                                        onTap: item.enabled
                                            ? () => Navigator.of(context).pop<T>(item.value)
                                            : null,
                                        borderRadius: BorderRadius.circular(12),
                                        child: Padding(
                                          padding: EdgeInsets.symmetric(
                                            horizontal: itemHorizontalPadding,
                                          ),
                                          child: Row(
                                            children: [
                                              Icon(
                                                item.icon,
                                                size: 18,
                                                color: item.enabled
                                                    ? item.destructive
                                                        ? const Color(0xFFEF4444)
                                                        : iconColor
                                                    : iconColor.withValues(alpha: 0.38),
                                              ),
                                              const SizedBox(width: 12),
                                              Expanded(
                                                child: Text(
                                                  item.label,
                                                  maxLines: 1,
                                                  softWrap: false,
                                                  overflow: TextOverflow.fade,
                                                  style: Theme.of(context)
                                                      .textTheme.bodyMedium
                                                      ?.copyWith(
                                                        fontSize: 14.5,
                                                        fontWeight: FontWeight.w500,
                                                        color: item.enabled
                                                            ? item.destructive
                                                                ? const Color(0xFFEF4444)
                                                                : foreground
                                                            : foreground.withValues(alpha: 0.38),
                                                      ),
                                                ),
                                              ),
                                              if (item.trailing != null || titleMenu) ...[
                                                const SizedBox(width: 12),
                                                SizedBox(
                                                  width: trailingWidth,
                                                  child: Align(
                                                    alignment: Alignment.centerRight,
                                                    child: item.trailing,
                                                  ),
                                                ),
                                              ],
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                      ),
        if (useGlass)
          Positioned(
            top: 0,
            left: 1,
            right: 1,
            child: IgnorePointer(
              child: Container(
                height: 1,
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      Color(0x08FFFFFF),
                      Color(0x6BFFFFFF),
                      Color(0x08FFFFFF),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) => child;
}

double mathMin(double a, double b) => a < b ? a : b;
double mathMax(double a, double b) => a > b ? a : b;
