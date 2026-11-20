import 'package:material_ui/material_ui.dart';

/// Compact status label shared by PocketLink surfaces.
class PocketLinkStatusPill extends StatelessWidget {
  const PocketLinkStatusPill({
    required this.label,
    required this.foreground,
    required this.background,
    required this.padding,
    required this.radius,
    required this.textStyle,
    this.icon,
    this.iconSize = 13,
    this.iconSpacing = 5,
    super.key,
  });

  final String label;
  final Color foreground;
  final Color background;
  final EdgeInsetsGeometry padding;
  final double radius;
  final TextStyle? textStyle;
  final IconData? icon;
  final double iconSize;
  final double iconSpacing;

  @override
  Widget build(BuildContext context) => Container(
        padding: padding,
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(radius),
        ),
        child: icon == null
            ? Text(label, style: textStyle)
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: iconSize, color: foreground),
                  SizedBox(width: iconSpacing),
                  Text(label, style: textStyle),
                ],
              ),
      );
}
