import 'package:material_ui/material_ui.dart';

import '../../../core/widgets/shared/status_pill.dart';
import 'host_media_metric.dart';

class HostMediaScanCard extends StatelessWidget {
  const HostMediaScanCard({
    required this.status,
    required this.scanning,
    required this.skippedItems,
    required this.completedAt,
    required this.busy,
    required this.onScan,
    super.key,
  });

  final Map<String, dynamic> status;
  final bool scanning;
  final int skippedItems;
  final String? completedAt;
  final bool busy;
  final VoidCallback onScan;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final scanState = status['state'];

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: colors.outlineVariant.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                scanning ? Icons.sync_rounded : Icons.perm_media_outlined,
                color: colors.primary,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  switch (scanState) {
                    'scanning' => 'Scanning device storage',
                    'complete' => 'Media and files indexed',
                    'partial' => 'Scan completed with skipped items',
                    'failed' => 'Scan failed',
                    _ => 'Media scan ready',
                  },
                  style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
                ),
              ),
              if (scanState == 'complete')
                const PocketLinkStatusPill(label: 'Complete', granted: true),
            ],
          ),
          const SizedBox(height: 8),
          const SizedBox(height: 4),
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
            childAspectRatio: 2.7,
            children: [
              HostMediaMetric(label: 'Photos', value: status['photo_count'] ?? 0, icon: Icons.photo_outlined),
              HostMediaMetric(label: 'Videos', value: status['video_count'] ?? 0, icon: Icons.video_library_outlined),
              HostMediaMetric(label: 'Music', value: status['music_count'] ?? 0, icon: Icons.music_note_rounded),
              HostMediaMetric(label: 'Files', value: status['file_count'] ?? 0, icon: Icons.insert_drive_file_outlined),
            ],
          ),
          Text(
            '${status['scanned'] ?? 0} items checked in this scan',
            style: theme.textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant),
          ),
          if (scanning && status['current_source'] != null) ...[
            const SizedBox(height: 4),
            Text(
              'Scanning ${status['current_source'] == 'internal' ? 'internal storage' : 'external storage'} · ${((status['elapsed_ms'] as num?)?.toInt() ?? 0) ~/ 1000}s elapsed',
              style: theme.textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant),
            ),
          ],
          if (skippedItems > 0) ...[
            const SizedBox(height: 4),
            Text('$skippedItems items skipped', style: theme.textTheme.bodySmall?.copyWith(color: colors.error)),
          ],
          if (!scanning && completedAt != null) ...[
            const SizedBox(height: 4),
            Text('Last completed: $completedAt', style: theme.textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant)),
          ],
          if (scanning) ...[
            const SizedBox(height: 10),
            const LinearProgressIndicator(),
          ],
          if (status['last_error'] != null) ...[
            const SizedBox(height: 8),
            Text(
              status['last_error'].toString(),
              style: theme.textTheme.bodySmall?.copyWith(color: colors.error),
            ),
          ],
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: scanning || busy ? null : onScan,
              icon: scanning
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.refresh_rounded, size: 18),
              label: Text(scanning ? 'Scanning…' : 'Scan media & files now'),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'The scan runs on the host in the background. Existing indexed results remain available while it updates.',
            style: theme.textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant, height: 1.35),
          ),
        ],
      ),
    );
  }
}
