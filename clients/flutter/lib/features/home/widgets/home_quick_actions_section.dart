import 'package:material_ui/material_ui.dart';

class HomeQuickAction {
  const HomeQuickAction({
    required this.id,
    required this.label,
    required this.icon,
  });

  final String id;
  final String label;
  final IconData icon;
}

/// Presentation-only Home quick actions section.
/// Persistence, editing state, and action routing remain owned by HomeDashboard.
class HomeQuickActionsSection extends StatelessWidget {
  const HomeQuickActionsSection({
    required this.actions,
    required this.cardDecoration,
    required this.onEdit,
    required this.onSelect,
    super.key,
  });

  final List<HomeQuickAction> actions;
  final BoxDecoration Function(ThemeData theme, {double radius}) cardDecoration;
  final VoidCallback onEdit;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Quick actions',
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.4,
                ),
              ),
            ),
            TextButton(onPressed: onEdit, child: const Text('Edit')),
          ],
        ),
        const SizedBox(height: 14),
        if (actions.isEmpty)
          OutlinedButton.icon(
            onPressed: onEdit,
            icon: const Icon(Icons.add_rounded),
            label: const Text('Add quick actions'),
          )
        else
          GridView.count(
            padding: EdgeInsets.zero,
            crossAxisCount: 4,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisSpacing: 9,
            mainAxisSpacing: 9,
            childAspectRatio: 0.88,
            children: actions.map((action) {
              return Container(
                decoration: cardDecoration(theme),
                child: Material(
                  color: Colors.transparent,
                  borderRadius: BorderRadius.circular(18),
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: () => onSelect(action.id),
                    borderRadius: BorderRadius.circular(18),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: 10,
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(action.icon, size: 23, color: colors.primary),
                          const SizedBox(height: 8),
                          Text(
                            action.label,
                            maxLines: 1,
                            overflow: TextOverflow.visible,
                            softWrap: false,
                            style: theme.textTheme.labelLarge?.copyWith(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            }).toList(growable: false),
          ),
      ],
    );
  }
}
