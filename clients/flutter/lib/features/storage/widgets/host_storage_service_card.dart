import 'package:material_ui/material_ui.dart';

import '../../../core/widgets/shared/status_pill.dart';

class HostStorageServiceCard extends StatelessWidget {
  const HostStorageServiceCard({
    required this.running,
    required this.canStart,
    required this.busy,
    required this.onStart,
    required this.onStop,
    super.key,
  });

  final bool running;
  final bool canStart;
  final bool busy;
  final VoidCallback onStart;
  final VoidCallback onStop;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return Column(
      children: [
        const SizedBox(height: 22),
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: colors.surfaceContainerLow,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: colors.outlineVariant.withValues(alpha: 0.4)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: running ? colors.primaryContainer : colors.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(
                      Icons.dns_outlined,
                      color: running ? colors.onPrimaryContainer : colors.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Storage service',
                          style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          running
                              ? 'PocketLink storage access is running on this phone.'
                              : canStart
                                  ? 'Your storage setup is ready. Start the service when needed.'
                                  : 'Complete a storage permission above before starting.',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colors.onSurfaceVariant,
                            height: 1.35,
                          ),
                        ),
                      ],
                    ),
                  ),
                  PocketLinkStatusPill(
                    label: running ? 'Running' : 'Stopped',
                    granted: running,
                  ),
                ],
              ),
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: busy || (!running && !canStart)
                      ? null
                      : (running ? onStop : onStart),
                  icon: Icon(running ? Icons.stop_rounded : Icons.play_arrow_rounded),
                  label: Text(running ? 'Stop storage service' : 'Start storage service'),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(50),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                ),
              ),
              if (!running && !canStart) ...[
                const SizedBox(height: 8),
                Text(
                  'Enable All-files access or grant access to a USB folder to continue.',
                  style: theme.textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}
