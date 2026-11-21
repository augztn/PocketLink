import 'package:material_ui/material_ui.dart';

class HostServiceStatusRow extends StatelessWidget {
  const HostServiceStatusRow({
    super.key,
    required this.label,
    required this.value,
    required this.ready,
    this.neutral = false,
  });

  final String label;
  final String value;
  final bool ready;
  final bool neutral;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final statusColor = ready
        ? Colors.green
        : neutral
            ? colors.onSurfaceVariant
            : colors.tertiary;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        children: [
          Icon(
            ready
                ? Icons.check_circle_rounded
                : neutral
                    ? Icons.remove_circle_outline_rounded
                    : Icons.info_outline_rounded,
            size: 18,
            color: statusColor,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              label,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.end,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                color: statusColor,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
