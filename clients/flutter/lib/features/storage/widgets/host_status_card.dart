import 'package:material_ui/material_ui.dart';

import '../../../core/widgets/shared/status_pill.dart';
import 'host_service_status_row.dart';

class HostStatusCard extends StatelessWidget {
  const HostStatusCard({
    required this.statusLoaded,
    required this.running,
    required this.apiRunning,
    required this.serverPasswordConfigured,
    required this.bridgeRunning,
    required this.internalGranted,
    required this.usbStatus,
    required this.selectedVolumeCount,
    required this.detectedVolumeCount,
    required this.refreshing,
    required this.busy,
    required this.statusCheckedLabel,
    required this.onRefresh,
    super.key,
  });

  final bool statusLoaded;
  final bool running;
  final bool apiRunning;
  final bool serverPasswordConfigured;
  final bool bridgeRunning;
  final bool internalGranted;
  final String usbStatus;
  final int selectedVolumeCount;
  final int detectedVolumeCount;
  final bool refreshing;
  final bool busy;
  final String statusCheckedLabel;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.all(16),
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
              Expanded(
                child: Text(
                  'Host status',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              PocketLinkStatusPill(
                label: !statusLoaded
                    ? 'Checking'
                    : running
                        ? 'Running'
                        : 'Stopped',
                granted: running,
              ),
              const SizedBox(width: 2),
              IconButton(
                tooltip: 'Refresh host status',
                onPressed: refreshing || busy ? null : onRefresh,
                icon: refreshing
                    ? const SizedBox(
                        width: 19,
                        height: 19,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.refresh_rounded),
              ),
            ],
          ),
          Text(
            'Live status reported by the Android host service.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: colors.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          if (!statusLoaded)
            const LinearProgressIndicator()
          else ...[
            HostServiceStatusRow(
              label: 'Storage service',
              value: running ? 'Running' : 'Stopped',
              ready: running,
              neutral: !running,
            ),
            HostServiceStatusRow(
              label: 'Native server API',
              value: apiRunning
                  ? 'Running'
                  : serverPasswordConfigured
                      ? 'Stopped'
                      : 'Password not set',
              ready: apiRunning,
              neutral: !running && !serverPasswordConfigured,
            ),
            HostServiceStatusRow(
              label: 'Android storage bridge',
              value: bridgeRunning ? 'Running' : 'Stopped',
              ready: bridgeRunning,
              neutral: !running,
            ),
            HostServiceStatusRow(
              label: 'Internal storage',
              value: internalGranted ? 'Access granted' : 'Needs access',
              ready: internalGranted,
            ),
            HostServiceStatusRow(
              label: 'USB / external drives',
              value: usbStatus,
              ready: selectedVolumeCount > 0,
              neutral: detectedVolumeCount == 0,
            ),
          ],
          const SizedBox(height: 6),
          Text(
            statusCheckedLabel,
            style: theme.textTheme.labelSmall?.copyWith(
              color: colors.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
