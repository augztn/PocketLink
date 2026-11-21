import 'package:material_ui/material_ui.dart';

class HostQuickActionsCard extends StatelessWidget {
  const HostQuickActionsCard({
    required this.onManageStorage,
    required this.onSecuritySettings,
    required this.onDiagnostics,
    super.key,
  });

  final VoidCallback onManageStorage;
  final VoidCallback onSecuritySettings;
  final VoidCallback onDiagnostics;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: colors.outlineVariant.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Quick actions',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Jump directly to the controls you need.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: colors.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: onManageStorage,
                icon: const Icon(Icons.storage_outlined, size: 18),
                label: const Text('Manage storage'),
              ),
              OutlinedButton.icon(
                onPressed: onSecuritySettings,
                icon: const Icon(Icons.lock_outline_rounded, size: 18),
                label: const Text('Security settings'),
              ),
              OutlinedButton.icon(
                onPressed: onDiagnostics,
                icon: const Icon(Icons.article_outlined, size: 18),
                label: const Text('Diagnostics'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
