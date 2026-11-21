import 'package:material_ui/material_ui.dart';

/// Presentation-only global search entry used on the Home dashboard.
class HomeGlobalSearchEntry extends StatelessWidget {
  const HomeGlobalSearchEntry({
    required this.cardDecoration,
    required this.onTap,
    super.key,
  });

  final BoxDecoration Function(ThemeData theme, {double radius}) cardDecoration;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return Container(
      decoration: cardDecoration(theme),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(18),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                Icon(Icons.search_rounded, color: colors.primary),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Search files, folders and media',
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(color: colors.onSurfaceVariant),
                  ),
                ),
                Icon(
                  Icons.arrow_forward_rounded,
                  color: colors.onSurfaceVariant,
                  size: 18,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
