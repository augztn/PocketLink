import 'package:material_ui/material_ui.dart';

/// Compact status label shared by PocketLink surfaces.
class PocketLinkStatusPill extends StatelessWidget {
  const PocketLinkStatusPill({
    required this.label,
    this.foreground,
    this.background,
    this.padding = const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
    this.radius = 30,
    this.textStyle,
    this.granted,
    this.icon,
    this.iconSize = 13,
    this.iconSpacing = 5,
    super.key,
  });

  final String label;
  final Color? foreground;
  final Color? background;
  final EdgeInsetsGeometry padding;
  final double radius;
  final TextStyle? textStyle;
  final bool? granted;
  final IconData? icon;
  final double iconSize;
  final double iconSpacing;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final resolvedForeground = foreground ??
        (granted == null
            ? colors.onSurface
            : granted!
                ? Colors.green
                : colors.tertiary);
    final resolvedBackground =
        background ?? resolvedForeground.withValues(alpha: 0.12);
    final resolvedTextStyle = textStyle ??
        Theme.of(context).textTheme.labelSmall?.copyWith(
              color: resolvedForeground,
              fontWeight: FontWeight.w700,
            );

    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: resolvedBackground,
        borderRadius: BorderRadius.circular(radius),
      ),
      child: icon == null
          ? Text(label, style: resolvedTextStyle)
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: iconSize, color: resolvedForeground),
                SizedBox(width: iconSpacing),
                Text(label, style: resolvedTextStyle),
              ],
            ),
    );
  }
}
