import 'dart:ui' as ui;

import 'package:material_ui/material_ui.dart';

class SmokedGlassPopoverMenuItem<T> {
  const SmokedGlassPopoverMenuItem({
    required this.value,
    required this.label,
    required this.icon,
    this.destructive = false,
    this.enabled = true,
    this.dividerBefore = false,
  });

  final T value;
  final String label;
  final IconData icon;
  final bool destructive;
  final bool enabled;
  final bool dividerBefore;
}

/// Root-navigator popover with a measured anchor and reversible glass bloom.
class SmokedGlassPopoverMenu<T> extends StatelessWidget {
  const SmokedGlassPopoverMenu({
    required this.items,
    required this.onSelected,
    required this.child,
    this.tooltip,
    this.gap = 8,
    super.key,
  });

  final List<SmokedGlassPopoverMenuItem<T>> items;
  final ValueChanged<T> onSelected;
  final Widget child;
  final String? tooltip;
  final double gap;

  Future<void> _open(BuildContext context) async {
    final renderObject = context.findRenderObject();
    if (renderObject is! RenderBox || !renderObject.hasSize) return;

    final anchor = renderObject.localToGlobal(Offset.zero) & renderObject.size;
    final result = await Navigator.of(context, rootNavigator: true).push<T>(
      _SmokedGlassPopoverRoute<T>(
        anchor: anchor,
        gap: gap,
        items: items,
      ),
    );
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
  });

  final Rect anchor;
  final double gap;
  final List<SmokedGlassPopoverMenuItem<T>> items;

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
    final right = (media.size.width - anchor.right).clamp(8.0, media.size.width - 8).toDouble();
    final top = (anchor.bottom + gap).clamp(
      media.padding.top + 8,
      media.size.height - media.padding.bottom - 54,
    ).toDouble();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final curved = CurvedAnimation(
      parent: animation,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );
    final foreground = isDark ? Colors.white : const Color(0xFF172033);
    final iconColor = isDark ? const Color(0xFFA1A7B3) : const Color(0xFF64748B);

    return Material(
      type: MaterialType.transparency,
      child: Stack(
        children: [
          Positioned(
            top: top,
            right: right,
            child: FadeTransition(
              opacity: curved,
              child: SlideTransition(
                position: Tween<Offset>(
                  begin: const Offset(0, -0.04),
                  end: Offset.zero,
                ).animate(curved),
                child: ScaleTransition(
                  alignment: Alignment.topRight,
                  scale: Tween<double>(begin: 0.84, end: 1).animate(curved),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      minWidth: 210,
                      maxWidth: mathMin(280, media.size.width - right - 8),
                      maxHeight: media.size.height - top - media.padding.bottom - 8,
                    ),
                    child: ClipRRect(
                borderRadius: BorderRadius.circular(22),
                child: BackdropFilter(
                  filter: ui.ImageFilter.blur(sigmaX: 24, sigmaY: 24),
                  child: Stack(
                    children: [
                      DecoratedBox(
                        decoration: BoxDecoration(
                          color: isDark
                              ? const Color(0xFF1C1E24).withValues(alpha: 0.76)
                              : Colors.white.withValues(alpha: 0.86),
                          borderRadius: BorderRadius.circular(22),
                          border: Border.all(
                            color: isDark
                                ? Colors.white.withValues(alpha: 0.16)
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
                            padding: const EdgeInsets.symmetric(vertical: 6),
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
                                        color: foreground.withValues(alpha: 0.12),
                                      ),
                                    ),
                                  SizedBox(
                                    height: 46,
                                    child: Material(
                                      color: Colors.transparent,
                                      child: InkWell(
                                        onTap: item.enabled
                                            ? () => Navigator.of(context).pop<T>(item.value)
                                            : null,
                                        borderRadius: BorderRadius.circular(12),
                                        child: Padding(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 16,
                                          ),
                                          child: Row(
                                            children: [
                                              Icon(
                                                item.icon,
                                                size: 20,
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
                                                  overflow: TextOverflow.ellipsis,
                                                  style: Theme.of(context)
                                                      .textTheme.bodyMedium
                                                      ?.copyWith(
                                                        fontSize: 15,
                                                        color: item.enabled
                                                            ? item.destructive
                                                                ? const Color(0xFFEF4444)
                                                                : foreground
                                                            : foreground.withValues(alpha: 0.38),
                                                      ),
                                                ),
                                              ),
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
                      Positioned(
                        top: 0,
                        left: 1,
                        right: 1,
                        child: IgnorePointer(
                          child: Container(
                            height: 1,
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [
                                  Colors.white.withValues(alpha: 0.02),
                                  Colors.white.withValues(alpha: 0.42),
                                  Colors.white.withValues(alpha: 0.02),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
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

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) => child;
}

double mathMin(double a, double b) => a < b ? a : b;
