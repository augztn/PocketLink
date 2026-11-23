import 'package:material_ui/material_ui.dart';

/// Shared typography for section headings across PocketLink screens.
class PocketLinkSectionHeader extends StatelessWidget {
  const PocketLinkSectionHeader(
    this.title, {
    this.uppercase = false,
    this.color,
    super.key,
  });

  final String title;
  final bool uppercase;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Text(
      uppercase ? title.toUpperCase() : title,
      style: theme.textTheme.titleMedium?.copyWith(
        color: color ?? theme.colorScheme.onSurface,
        fontSize: 18,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.2,
      ),
    );
  }
}
