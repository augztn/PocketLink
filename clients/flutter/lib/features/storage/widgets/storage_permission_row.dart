import 'package:material_ui/material_ui.dart';

import '../../../core/widgets/shared/status_pill.dart';

class StoragePermissionRow extends StatelessWidget {
  const StoragePermissionRow({
    required this.icon,
    required this.title,
    required this.description,
    required this.status,
    required this.granted,
    required this.onTap,
    this.recommended = false,
    this.neutral = false,
  });

  final IconData icon;
  final String title;
  final String description;
  final String status;
  final bool granted;
  final bool recommended;
  final bool neutral;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final statusColor = granted
        ? Colors.green
        : recommended
            ? colors.tertiary
            : neutral
                ? colors.onSurfaceVariant
                : colors.error;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 2),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, size: 20, color: statusColor),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 2),
                    Text(description, style: theme.textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant, height: 1.3)),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  PocketLinkStatusPill(label: status, granted: granted),
                  if (onTap != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 3),
                      child: Icon(Icons.chevron_right_rounded, size: 18, color: colors.onSurfaceVariant),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
