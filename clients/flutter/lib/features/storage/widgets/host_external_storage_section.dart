import 'package:material_ui/material_ui.dart';

import 'storage_permission_row.dart';
import 'storage_volume_tile.dart';

class HostExternalStorageSection extends StatelessWidget {
  const HostExternalStorageSection({
    required this.volumes,
    required this.selectedVolumeCount,
    required this.detectedVolumeCount,
    required this.busy,
    required this.refreshing,
    required this.onRefresh,
    required this.onChooseFolder,
    required this.onSelectVolume,
    super.key,
  });

  final List<Map<String, dynamic>> volumes;
  final int selectedVolumeCount;
  final int detectedVolumeCount;
  final bool busy;
  final bool refreshing;
  final VoidCallback onRefresh;
  final VoidCallback onChooseFolder;
  final ValueChanged<String> onSelectVolume;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 24),
        Row(
          children: [
            const Expanded(
              child: HostSetupSectionTitle(
                title: 'USB / External Storage',
                subtitle: 'PocketLink detects mounted SD cards and USB drives automatically. Direct access is preferred; folder approval is the fallback.',
              ),
            ),
            IconButton(
              tooltip: 'Refresh connected storage',
              onPressed: busy || refreshing ? null : onRefresh,
              icon: refreshing
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.refresh_rounded),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
          decoration: BoxDecoration(
            color: colors.surfaceContainerLow,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: colors.outlineVariant.withValues(alpha: 0.35)),
          ),
          child: StoragePermissionRow(
            icon: Icons.usb_rounded,
            title: 'USB folder access',
            description: selectedVolumeCount > 0
                ? '$selectedVolumeCount drive permission(s) saved'
                : volumes.isEmpty
                    ? 'Connect a drive or choose a folder manually'
                    : '$detectedVolumeCount drive(s) detected · approve access to use',
            status: selectedVolumeCount > 0
                ? 'Granted'
                : volumes.isEmpty
                    ? 'Not connected'
                    : 'Needs approval',
            granted: selectedVolumeCount > 0,
            neutral: volumes.isEmpty,
            onTap: null,
          ),
        ),
        const SizedBox(height: 10),
        if (volumes.isEmpty)
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: colors.surfaceContainerLow,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: colors.outlineVariant.withValues(alpha: 0.35)),
            ),
            child: Column(
              children: [
                Icon(Icons.usb_rounded, size: 34, color: colors.onSurfaceVariant),
                const SizedBox(height: 10),
                Text('No removable drive detected', style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                Text(
                  'Connect or reconnect your USB drive. You can also choose its folder manually.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant, height: 1.4),
                ),
                const SizedBox(height: 14),
                OutlinedButton.icon(
                  onPressed: busy ? null : onChooseFolder,
                  icon: const Icon(Icons.folder_open_rounded, size: 18),
                  label: const Text('Choose storage folder'),
                ),
              ],
            ),
          ),
        ...volumes.map((volume) {
          final selected = volume['selected'] == true;
          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: StorageVolumeTile(
              title: volume['name']?.toString() ?? 'USB storage',
              value: volume['access'] == 'direct'
                  ? (volume['writable'] == true ? 'Direct access · read and write' : 'Direct access · read-only')
                  : volume['access'] == 'saf'
                      ? 'Folder permission saved · ready to use'
                      : 'Detected · tap to approve folder access',
              selected: selected,
              onTap: busy || selected ? null : () => onSelectVolume(volume['id'].toString()),
              accessType: volume['access']?.toString() ?? 'not_granted',
            ),
          );
        }),
        if (volumes.isNotEmpty) ...[
          const SizedBox(height: 2),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: busy ? null : onChooseFolder,
              icon: const Icon(Icons.folder_open_rounded, size: 18),
              label: const Text('Choose a folder manually'),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Use this if Android does not expose the drive directly or you need to select a specific folder.',
            style: theme.textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant, height: 1.35),
          ),
        ],
      ],
    );
  }
}
