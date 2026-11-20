import 'package:material_ui/material_ui.dart';

import '../../transfers/transfer_manager.dart';

/// Displays the currently running transfers without owning transfer state.
class HomeActiveTransfersPreview extends StatelessWidget {
  const HomeActiveTransfersPreview({
    required this.tasks,
    required this.formatBytes,
    required this.onOpen,
    super.key,
  });

  final List<TransferTask> tasks;
  final String Function(int bytes) formatBytes;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    if (tasks.isEmpty) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: colors.surfaceContainer,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: colors.outlineVariant.withValues(alpha: 0.55)),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(18),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: onOpen,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Active transfers',
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    Text(
                      'View all',
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: colors.primary,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                for (var index = 0; index < tasks.length; index++) ...[
                  if (index > 0) const SizedBox(height: 12),
                  Row(
                    children: [
                      Icon(
                        tasks[index].direction == 'Upload'
                            ? Icons.cloud_upload_outlined
                            : Icons.download_rounded,
                        color: colors.primary,
                        size: 19,
                      ),
                      const SizedBox(width: 9),
                      Expanded(
                        child: Text(
                          tasks[index].name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      Text(
                        tasks[index].progress == null
                            ? 'In progress'
                            : '${(tasks[index].progress! * 100).round()}%',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 7),
                  LinearProgressIndicator(
                    value: tasks[index].progress,
                    minHeight: 4,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    tasks[index].total > 0
                        ? '${formatBytes(tasks[index].transferred)} of ${formatBytes(tasks[index].total)}'
                        : 'Transfer in progress',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
