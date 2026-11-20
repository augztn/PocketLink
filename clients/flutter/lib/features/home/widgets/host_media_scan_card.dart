import 'package:material_ui/material_ui.dart';

import '../../../core/network/server_api.dart';

/// Presents host media-index status and scan controls.
///
/// Scan execution, polling, persistence, and report generation remain owned by
/// the dashboard; this widget only renders the supplied state.
class HostMediaScanCard extends StatelessWidget {
  const HostMediaScanCard({
    required this.status,
    required this.scanError,
    required this.savingSettings,
    required this.startingScan,
    required this.serverOnline,
    required this.checking,
    required this.volumes,
    required this.cardDecoration,
    required this.formatTimestamp,
    required this.formatInterval,
    required this.formatBytes,
    required this.onShowHistory,
    required this.onShowSkippedItems,
    required this.onUpdateAutomaticScanning,
    required this.onStartScan,
    required this.onRetryScan,
    required this.onShareReport,
    super.key,
  });

  final MediaIndexStatus? status;
  final String? scanError;
  final bool savingSettings;
  final bool startingScan;
  final bool serverOnline;
  final bool checking;
  final List<StorageVolume> volumes;
  final BoxDecoration cardDecoration;
  final String Function(int, {int? timezoneOffsetMinutes}) formatTimestamp;
  final String Function(int) formatInterval;
  final String Function(int) formatBytes;
  final ValueChanged<MediaIndexStatus> onShowHistory;
  final ValueChanged<MediaIndexStatus> onShowSkippedItems;
  final void Function({
    required bool enabled,
    required int intervalMinutes,
    required bool scanOnStartup,
    required bool scanOnStorageChange,
  }) onUpdateAutomaticScanning;
  final VoidCallback onStartScan;
  final VoidCallback onRetryScan;
  final ValueChanged<MediaIndexStatus> onShareReport;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final status = this.status;
    final scanning = status?.isScanning ?? false;
    final source = status?.currentSource;
    final elapsed = ((status?.elapsedMs ?? 0) / 1000).floor();
    final sourceLabel = source == 'internal'
        ? 'Internal storage'
        : source == null ? 'Preparing storage' : 'External storage';
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: _dashboardCardDecoration(theme),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.manage_search_rounded, color: colors.primary, size: 20),
          const SizedBox(width: 9),
          Expanded(child: Text('Host media library', style: theme.textTheme.titleSmall?.copyWith(
            color: colors.onSurface, fontWeight: FontWeight.w800,
          ))),
          Text(scanning ? 'Scanning' : scanError != null ? 'Unavailable' : status == null ? 'Checking' : status.state == 'failed' ? 'Failed' : status.state == 'interrupted' ? 'Interrupted' : status.state == 'partial' ? 'Partial' : status.state == 'complete' ? 'Up to date' : 'Ready',
            style: theme.textTheme.labelSmall?.copyWith(
              color: scanning || scanError != null
                  ? (theme.brightness == Brightness.dark ? const Color(0xFFFBBF24) : const Color(0xFFB45309))
                  : colors.onSurfaceVariant,
              fontWeight: FontWeight.w700,
            )),
        ]),
        const SizedBox(height: 7),
        Text(
          scanning
              ? 'Scanning $sourceLabel · ${elapsed}s elapsed'
              : status == null
                  ? 'Refresh the host device media and file index remotely.'
                  : '${status.regularFileCount} files · ${status.mediaCount} media · Last successful ${formatTimestamp(status.lastSuccessfulAt, timezoneOffsetMinutes: status.timezoneOffsetMinutes)}',
          style: theme.textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant),
        ),
        if (scanError != null) ...[
          const SizedBox(height: 7),
          Text(scanError!, style: theme.textTheme.bodySmall?.copyWith(color: colors.error)),
        ],
        if (status != null) ...[
          ExpansionTile(
            tilePadding: EdgeInsets.zero,
            childrenPadding: EdgeInsets.zero,
            title: Text('Scan details', style: theme.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700)),
            subtitle: Text(
              '${status.regularFileCount} files · ${status.mediaCount} media · ${status.skipped} skipped',
              style: theme.textTheme.labelSmall?.copyWith(color: colors.onSurfaceVariant),
            ),
            children: [
          const SizedBox(height: 7),
          Text(
            '${status.regularFileCount} files · ${status.directoryCount} folders · ${status.mediaCount} media',
            style: theme.textTheme.labelSmall?.copyWith(color: colors.onSurfaceVariant),
          ),
          Text(
            '${formatBytes(status.indexedBytes)} indexed · ${formatBytes(status.mediaBytes)} media',
            style: theme.textTheme.labelSmall?.copyWith(color: colors.onSurfaceVariant),
          ),
          Text(
            'Photos ${status.photoCount} · Videos ${status.videoCount} · Music ${status.musicCount} · Other ${status.otherFileCount}',
            style: theme.textTheme.labelSmall?.copyWith(color: colors.onSurfaceVariant),
          ),
          if (status.averageDurationMs > 0)
            Text(
              'Average successful scan: ${(status.averageDurationMs / 1000).toStringAsFixed(1)}s',
              style: theme.textTheme.labelSmall?.copyWith(color: colors.onSurfaceVariant),
            ),
          if (status.durationTrendPercent != 0)
            Text(
              'Latest scan ${status.durationTrendPercent.abs()}% ${status.durationTrendPercent > 0 ? 'slower' : 'faster'} than recent baseline',
              style: theme.textTheme.labelSmall?.copyWith(color: colors.onSurfaceVariant),
            ),
          const SizedBox(height: 6),
          const SizedBox(height: 6),
          Text(
            scanning || status.state == 'interrupted'
                ? '${status.state == 'interrupted' ? 'Interrupted' : 'Started'} ${formatTimestamp(status.lastAttemptStartedAt, timezoneOffsetMinutes: status.timezoneOffsetMinutes)} · ${status.scanTrigger == 'manual' ? 'Manual' : 'Automatic'}'
                : 'Last attempt: ${formatTimestamp(status.lastAttemptFinishedAt, timezoneOffsetMinutes: status.timezoneOffsetMinutes)} · ${status.scanTrigger == 'manual' ? 'Manual' : 'Automatic'}',
            style: theme.textTheme.labelSmall?.copyWith(color: colors.onSurfaceVariant),
          ),
          Text(
            'Last successful: ${formatTimestamp(status.lastSuccessfulAt, timezoneOffsetMinutes: status.timezoneOffsetMinutes)}',
            style: theme.textTheme.labelSmall?.copyWith(color: colors.onSurfaceVariant),
          ),
          if (status.lastAutomaticScanAt > 0)
            Text(
              'Last automatic: ${formatTimestamp(status.lastAutomaticScanAt, timezoneOffsetMinutes: status.timezoneOffsetMinutes)}',
              style: theme.textTheme.labelSmall?.copyWith(color: colors.onSurfaceVariant),
            ),
          if (!scanning && status.lastCompletedAt > 0)
            Text(
              'Duration: ${(status.elapsedMs / 1000).toStringAsFixed(1)}s · ${status.newFiles} new · ${status.updatedFiles} updated',
              style: theme.textTheme.labelSmall?.copyWith(color: colors.onSurfaceVariant),
            ),
          if (status.scannedBytes > 0)
            Text(
              '${formatBytes(status.scannedBytes)} traversed',
              style: theme.textTheme.labelSmall?.copyWith(color: colors.onSurfaceVariant),
            ),
          if (status.volumes.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text('STORAGE SOURCES', style: theme.textTheme.labelSmall?.copyWith(
              color: colors.onSurfaceVariant, fontWeight: FontWeight.w800, letterSpacing: 0.5,
            )),
            ...status.volumes.map((volume) => Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Row(children: [
                Expanded(child: Text(volume.volume == 'internal' ? 'Internal storage' : volume.volume,
                  style: theme.textTheme.labelSmall?.copyWith(color: colors.onSurfaceVariant))),
                Text(volume.stale ? 'Unavailable · stale index' : volume.state == 'complete' ? 'Scanned' : volume.state == 'scanning' ? 'Scanning' : volume.state,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: volume.state == 'complete' ? colors.onSurfaceVariant : const Color(0xFFFBBF24),
                  )),
                if (volume.skipped > 0)
                  Text(' · ${volume.skipped} skipped', style: theme.textTheme.labelSmall?.copyWith(color: const Color(0xFFFBBF24))),
              ]),
            )),
            ...volumes.where((volume) => !volume.available).map((volume) => Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Row(children: [
                Expanded(child: Text(volume.name, style: theme.textTheme.labelSmall?.copyWith(color: colors.onSurfaceVariant))),
                Text('Unavailable · index may be stale', style: theme.textTheme.labelSmall?.copyWith(color: const Color(0xFFFBBF24))),
              ]),
            )),
          ],
          if (status.scanHistory.isNotEmpty) ...[
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: () => onShowHistory(status),
                child: Text('View all ${status.scanHistory.length} scans'),
              ),
            ),
            const SizedBox(height: 8),
            Text('RECENT SCANS', style: theme.textTheme.labelSmall?.copyWith(
              color: colors.onSurfaceVariant, fontWeight: FontWeight.w800, letterSpacing: 0.5,
            )),
            ...status.scanHistory.take(3).map((entry) => Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Row(children: [
                Expanded(child: Text(
                  '${formatTimestamp(entry.completedAt, timezoneOffsetMinutes: entry.timezoneOffsetMinutes)} · ${entry.trigger == 'manual' ? 'Manual' : 'Automatic'}',
                  style: theme.textTheme.labelSmall?.copyWith(color: colors.onSurfaceVariant),
                )),
                Text(entry.state == 'complete' ? 'Complete' : entry.state,
                  style: theme.textTheme.labelSmall?.copyWith(color: entry.state == 'complete' ? colors.onSurfaceVariant : const Color(0xFFFBBF24))),
              ]),
            )),
          ],
          const SizedBox(height: 7),
          Wrap(
            spacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                '${status.scanned} checked',
                style: theme.textTheme.labelSmall?.copyWith(color: colors.onSurfaceVariant),
              ),
              if (status.skipped > 0)
                Material(
                  color: const Color(0xFFF59E0B).withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(20),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(20),
                    onTap: () => onShowSkippedItems(status),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            '${status.skipped} skipped',
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: const Color(0xFFFBBF24),
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(width: 2),
                          const Icon(Icons.chevron_right_rounded, size: 15, color: Color(0xFFFBBF24)),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
          if (status.lastError != null && status.lastError!.isNotEmpty) ...[
            const SizedBox(height: 5),
            Text(status.lastError!, style: theme.textTheme.bodySmall?.copyWith(color: colors.error)),
          ],
          const Divider(height: 18),
          Row(children: [
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Automatic scanning', style: theme.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700)),
              Text(
                status.automaticScanning.enabled
                    ? 'Every ${formatInterval(status.automaticScanning.intervalMinutes)} · startup and storage changes'
                    : 'Disabled',
                style: theme.textTheme.labelSmall?.copyWith(color: colors.onSurfaceVariant),
              ),
              if (status.automaticScanning.enabled && status.automaticScanning.nextScanAt > 0)
                Text('Next check: ${formatTimestamp(status.automaticScanning.nextScanAt, timezoneOffsetMinutes: status.timezoneOffsetMinutes)}',
                  style: theme.textTheme.labelSmall?.copyWith(color: colors.onSurfaceVariant)),
            ])),
            Switch.adaptive(
              value: status.automaticScanning.enabled,
              onChanged: scanning || savingSettings ? null : (enabled) =>
                  onUpdateAutomaticScanning(
                    enabled: enabled,
                    intervalMinutes: status.automaticScanning.intervalMinutes,
                    scanOnStartup: status.automaticScanning.scanOnStartup,
                    scanOnStorageChange: status.automaticScanning.scanOnStorageChange,
                  ),
            ),
          ]),
          Wrap(
            spacing: 6,
            runSpacing: 2,
            children: [
              FilterChip(
                label: const Text('On startup'),
                selected: status.automaticScanning.scanOnStartup,
                onSelected: scanning || savingSettings ? null : (selected) =>
                    onUpdateAutomaticScanning(
                      enabled: status.automaticScanning.enabled,
                      intervalMinutes: status.automaticScanning.intervalMinutes,
                      scanOnStartup: selected,
                      scanOnStorageChange: status.automaticScanning.scanOnStorageChange,
                    ),
              ),
              FilterChip(
                label: const Text('On storage connect'),
                selected: status.automaticScanning.scanOnStorageChange,
                onSelected: scanning || savingSettings ? null : (selected) =>
                    onUpdateAutomaticScanning(
                      enabled: status.automaticScanning.enabled,
                      intervalMinutes: status.automaticScanning.intervalMinutes,
                      scanOnStartup: status.automaticScanning.scanOnStartup,
                      scanOnStorageChange: selected,
                    ),
              ),
            ],
          ),
          if (status.automaticScanning.enabled)
            Align(
              alignment: Alignment.centerRight,
              child: DropdownButton<int>(
                value: status.automaticScanning.intervalMinutes,
                isDense: true,
                underline: const SizedBox.shrink(),
                items: const [15, 30, 60, 180, 360, 720, 1440]
                    .map((minutes) => DropdownMenuItem<int>(
                      value: minutes,
                      child: Text('Every ${minutes < 60 ? '$minutes minutes' : minutes == 1440 ? '24 hours' : '${minutes ~/ 60} hours'}'),
                    )).toList(),
                onChanged: scanning || savingSettings ? null : (minutes) {
                  if (minutes != null) onUpdateAutomaticScanning(
                    enabled: true,
                    intervalMinutes: minutes,
                    scanOnStartup: status.automaticScanning.scanOnStartup,
                    scanOnStorageChange: status.automaticScanning.scanOnStorageChange,
                  );
                },
              ),
            ),

            ],
          ),
        ],
        if (scanning) ...[
          const SizedBox(height: 10),
          const LinearProgressIndicator(),
        ],
        const SizedBox(height: 10),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: scanning || startingScan || checking || serverOnline != true
                ? null
                : onStartScan,
            style: TextButton.styleFrom(
              foregroundColor: const Color(0xFF8C9EFF),
              backgroundColor: const Color(0xFF536DFE).withValues(alpha: 0.16),
              padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              shape: const StadiumBorder(),
            ),
            icon: startingScan || scanning
                ? const SizedBox(width: 15, height: 15, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.refresh_rounded, size: 17),
            label: Text(scanning ? 'Scanning…' : startingScan ? 'Starting…' : 'Scan host now'),
          ),
        ),
        if (status != null && (status.state == 'partial' || status.state == 'failed' || status.state == 'interrupted' || status.skipped > 0))
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: scanning || startingScan || serverOnline != true ? null : onRetryScan,
              icon: const Icon(Icons.replay_rounded, size: 16),
              label: const Text('Retry failed scan'),
            ),
          ),
        if (status != null && status.lastScanStartedAt > 0)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => onShareReport(status),
              icon: const Icon(Icons.ios_share_rounded, size: 16),
              label: const Text('Share scan report'),
              style: TextButton.styleFrom(
                foregroundColor: colors.onSurfaceVariant,
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
          ),
      ]),
    );
  }
}
