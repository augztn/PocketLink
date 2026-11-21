import 'package:material_ui/material_ui.dart';

import '../../../core/widgets/shared/status_pill.dart';
import 'storage_permission_row.dart';

class HostDevicePermissionsCard extends StatelessWidget {
  const HostDevicePermissionsCard({
    required this.statusLoaded,
    required this.requiredAccessReady,
    required this.internalGranted,
    required this.backgroundGranted,
    required this.busy,
    required this.refreshingStatus,
    required this.onRequestInternalStorageAccess,
    required this.onRequestBackgroundAccess,
    required this.onRefresh,
    super.key,
  });

  final bool statusLoaded;
  final bool requiredAccessReady;
  final bool internalGranted;
  final bool backgroundGranted;
  final bool busy;
  final bool refreshingStatus;
  final VoidCallback onRequestInternalStorageAccess;
  final VoidCallback onRequestBackgroundAccess;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(22),
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
                  color: colors.primaryContainer,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(
                  Icons.shield_outlined,
                  color: colors.onPrimaryContainer,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Device permissions',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      !statusLoaded
                          ? 'Checking Android access…'
                          : requiredAccessReady
                              ? 'Required access is ready'
                              : 'Internal storage access is not enabled',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              PocketLinkStatusPill(
                label: !statusLoaded
                    ? 'Checking'
                    : requiredAccessReady
                        ? 'Ready'
                        : 'Needs access',
                granted: requiredAccessReady,
              ),
            ],
          ),
          const SizedBox(height: 14),
          Divider(
            height: 1,
            color: colors.outlineVariant.withValues(alpha: 0.45),
          ),
          const SizedBox(height: 4),
          StoragePermissionRow(
            icon: Icons.folder_open_rounded,
            title: 'All-files access',
            description:
                'Direct access to shared and supported removable storage. Some drives may still need folder approval.',
            status: !statusLoaded
                ? 'Checking'
                : internalGranted
                    ? 'Enabled'
                    : 'Needs access',
            granted: statusLoaded && internalGranted,
            neutral: !statusLoaded,
            onTap: !statusLoaded || internalGranted || busy
                ? null
                : onRequestInternalStorageAccess,
          ),
          StoragePermissionRow(
            icon: Icons.battery_charging_full_rounded,
            title: 'Background activity',
            description: 'Battery exemption may reduce background restrictions',
            status: !statusLoaded
                ? 'Checking'
                : backgroundGranted
                    ? 'Exempt'
                    : 'Recommended',
            granted: statusLoaded && backgroundGranted,
            recommended: statusLoaded && !backgroundGranted,
            onTap: !statusLoaded || backgroundGranted || busy
                ? null
                : onRequestBackgroundAccess,
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: TextButton.icon(
              onPressed: busy || refreshingStatus ? null : onRefresh,
              icon: refreshingStatus
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.refresh_rounded, size: 18),
              label: Text(
                refreshingStatus
                    ? 'Checking permissions…'
                    : 'Refresh permission status',
              ),
              style: TextButton.styleFrom(
                minimumSize: const Size.fromHeight(42),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(13),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
