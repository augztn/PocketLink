import 'package:material_ui/material_ui.dart';

import '../../../core/network/server_api.dart';

/// Renders host hardware and mounted-volume telemetry on the Home dashboard.
class HostDeviceMetricsCard extends StatelessWidget {
  const HostDeviceMetricsCard({
    required this.telemetry,
    required this.telemetryError,
    required this.serverOnline,
    required this.volumes,
    required this.cardDecoration,
    required this.formatBytes,
    super.key,
  });

  final HostSystemTelemetry? telemetry;
  final String? telemetryError;
  final bool serverOnline;
  final List<StorageVolume> volumes;
  final BoxDecoration cardDecoration;
  final String Function(int bytes) formatBytes;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final telemetry = this.telemetry;
    final telemetryError = this.telemetryError;
    final serverOnline = this.serverOnline;
    final volumes = this.volumes;
    final cardDecoration = this.cardDecoration;
    final formatBytes = this.formatBytes;
    final colors = theme.colorScheme;
    final muted = colors.onSurfaceVariant;
    final foreground = colors.onSurface;

    String percentLabel(double? value) =>
        value == null ? '—' : '${value.clamp(0, 100).toStringAsFixed(0)}%';

    String cpuDetail() => telemetry?.cpuUsagePercent != null
        ? 'Live device usage'
        : 'Waiting for next sample';

    Widget metric(
      String label,
      String value,
      double? progress,
      String detail,
      IconData icon,
    ) {
      return Expanded(
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: colors.surfaceContainer,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: colors.outlineVariant.withValues(alpha: 0.62)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Icon(icon, size: 15, color: muted),
                const SizedBox(width: 6),
                Text(label, style: theme.textTheme.labelSmall?.copyWith(
                  color: muted, letterSpacing: 0.55, fontWeight: FontWeight.w700,
                )),
              ]),
              const SizedBox(height: 7),
              Text(value, style: theme.textTheme.titleMedium?.copyWith(
                color: foreground, fontWeight: FontWeight.w800,
              )),
              if (progress != null) ...[
                const SizedBox(height: 7),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: (progress / 100).clamp(0.0, 1.0),
                    minHeight: 4,
                    backgroundColor: colors.surfaceContainerHighest,
                    color: icon == Icons.battery_charging_full_rounded
                        ? const Color(0xFF4ADE80)
                        : const Color(0xFF60A5FA),
                  ),
                ),
              ],
              const SizedBox(height: 5),
              Text(detail, maxLines: 1, overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelSmall?.copyWith(color: muted)),
            ],
          ),
        ),
      );
    }

    final memoryDetail = telemetry?.memoryUsedBytes != null &&
            telemetry?.memoryTotalBytes != null
        ? '${formatBytes(telemetry!.memoryUsedBytes!)} / ${formatBytes(telemetry.memoryTotalBytes!)} used'
        : '';
    final storageDetail = telemetry?.storageUsedBytes != null &&
            telemetry?.storageTotalBytes != null
        ? '${formatBytes(telemetry!.storageUsedBytes!)} / ${formatBytes(telemetry.storageTotalBytes!)} used'
        : '';
    final batteryDetail = telemetry == null
        ? 'Battery status unavailable'
        : switch (telemetry.batteryStatus) {
            'charging' => 'Charging',
            'not_charging' => 'Not charging',
            _ => 'Status unavailable',
          };
    final deviceName = [
      telemetry?.manufacturer,
      telemetry?.deviceModel,
    ].whereType<String>().where((part) => part.isNotEmpty).join(' ');
    final cpuName = telemetry?.cpuModel;
    final hasCpu = telemetry?.cpuUsagePercent != null ||
        telemetry?.cpuUsageStatus == 'sampling';
    final hasMemory = telemetry?.memoryUsagePercent != null &&
        memoryDetail.isNotEmpty;
    final hasStorage = telemetry?.storageUsagePercent != null &&
        storageDetail.isNotEmpty;
    final hasBattery = telemetry?.batteryPercent != null;
    final sampledAt = telemetry?.sampledAtMs == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(telemetry!.sampledAtMs!).toLocal();

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: cardDecoration,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(Icons.memory_rounded, size: 18, color: muted),
            const SizedBox(width: 8),
            Expanded(child: Text('HOST DEVICE HEALTH',
              style: theme.textTheme.labelMedium?.copyWith(
                color: foreground, fontWeight: FontWeight.w800, letterSpacing: 0.65,
              ))),
            if (sampledAt != null)
              Text(
                '${serverOnline == true ? 'Updated' : 'Last known'} ${sampledAt.hour.toString().padLeft(2, '0')}:${sampledAt.minute.toString().padLeft(2, '0')}',
                style: theme.textTheme.labelSmall?.copyWith(color: muted),
              ),
          ]),
          const SizedBox(height: 11),
          if (telemetry == null)
            Text(
              serverOnline != true
                  ? 'System information appears when the host is connected.'
                  : telemetryError ?? 'Reading system information from the host…',
              style: theme.textTheme.bodySmall?.copyWith(
                color: telemetryError == null ? muted : const Color(0xFFFBBF24),
              ),
            )
          else ...[
            if (hasCpu || hasMemory)
              Row(children: [
                if (hasCpu)
                  metric(
                    'CPU',
                    telemetry.cpuUsagePercent == null
                        ? 'Sampling'
                        : percentLabel(telemetry.cpuUsagePercent),
                    telemetry.cpuUsagePercent,
                    cpuDetail(),
                    Icons.speed_rounded,
                  ),
                if (hasCpu && hasMemory) const SizedBox(width: 9),
                if (hasMemory)
                  metric('MEMORY', percentLabel(telemetry.memoryUsagePercent),
                      telemetry.memoryUsagePercent, memoryDetail, Icons.memory_rounded),
              ]),
            if (hasStorage || hasBattery) ...[
              if (hasCpu || hasMemory) const SizedBox(height: 9),
              Row(children: [
                if (hasStorage)
                  metric('STORAGE', percentLabel(telemetry.storageUsagePercent),
                      telemetry.storageUsagePercent, storageDetail, Icons.storage_rounded),
                if (hasStorage && hasBattery) const SizedBox(width: 9),
                if (hasBattery)
                  metric(
                    'BATTERY',
                    '${telemetry.batteryPercent}%',
                    telemetry.batteryPercent!.toDouble(),
                    batteryDetail,
                    Icons.battery_charging_full_rounded,
                  ),
              ]),
            ],
            if (!hasCpu && !hasMemory && !hasStorage && !hasBattery)
              Text(
                'No system readings are currently available.',
                style: theme.textTheme.bodySmall?.copyWith(color: muted),
              ),
            const SizedBox(height: 12),
            if (deviceName.isNotEmpty)
              _deviceDetailRow(theme, muted, Icons.phone_android_rounded,
                  deviceName, telemetry.androidVersion == null
                      ? null : 'Android ${telemetry.androidVersion}'),
            if (cpuName != null || telemetry.cpuCores != null)
              _deviceDetailRow(
                theme, muted, Icons.memory_rounded,
                cpuName ?? 'CPU',
                telemetry.cpuCores == null ? null : '${telemetry.cpuCores} cores',
              ),
          ],
          if (volumes.isNotEmpty) ...[
            const SizedBox(height: 5),
            Text('EXTERNAL STORAGE', style: theme.textTheme.labelSmall?.copyWith(
              color: muted, letterSpacing: 0.65, fontWeight: FontWeight.w800,
            )),
            const SizedBox(height: 7),
            for (final volume in volumes) ...[
              Padding(
                padding: const EdgeInsets.only(bottom: 9),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Icon(Icons.usb_rounded, size: 15, color: muted),
                    const SizedBox(width: 8),
                    Expanded(child: Text(volume.name, maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: foreground, fontWeight: FontWeight.w700,
                      ))),
                    Text(
                      !volume.available ? 'Disconnected' : volume.writable ? 'Writable' : 'Read only',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: !volume.available ? muted : volume.writable
                            ? const Color(0xFF4ADE80) : const Color(0xFFFBBF24),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ]),
                  if (volume.available &&
                      volume.totalBytes != null &&
                      volume.usedBytes != null &&
                      volume.availableBytes != null &&
                      volume.usagePercent != null) ...[
                    const SizedBox(height: 5),
                    Row(children: [
                      Expanded(child: Text(
                        '${formatBytes(volume.usedBytes!)} of ${formatBytes(volume.totalBytes!)} used',
                        style: theme.textTheme.labelSmall?.copyWith(color: muted),
                      )),
                      Text('${formatBytes(volume.availableBytes!)} free',
                        style: theme.textTheme.labelSmall?.copyWith(color: muted)),
                    ]),
                    const SizedBox(height: 5),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: (volume.usagePercent!.clamp(0, 100)) / 100,
                        minHeight: 4,
                        backgroundColor: colors.surfaceContainerHighest,
                        color: const Color(0xFF60A5FA),
                      ),
                    ),
                  ] else if (volume.available) ...[
                    const SizedBox(height: 3),
                    Text('Capacity unavailable on this Android version or storage provider',
                      style: theme.textTheme.labelSmall?.copyWith(color: muted)),
                  ],
                ]),
              ),
            ],
          ],
        ],
      ),
    );
  }

  Widget _deviceDetailRow(
    ThemeData theme,
    Color muted,
    IconData icon,
    String title,
    String? trailing,
  ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 7),
      child: Row(children: [
        Icon(icon, size: 15, color: muted),
        const SizedBox(width: 8),
        Expanded(child: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis,
          style: theme.textTheme.labelMedium?.copyWith(color: muted))),
        if (trailing != null)
          Text(trailing, style: theme.textTheme.labelSmall?.copyWith(color: muted)),
      ]),
    );
  }
}
