import 'package:material_ui/material_ui.dart';

import '../../../core/network/server_api.dart';
import '../../../core/widgets/liquid_glass_pill.dart';
import '../../transfers/transfer_manager.dart';
import '../../transfers/transfer_manager_screen.dart';

/// Displays the active server connection and its storage/transfer summary.
class ServerTelemetryCard extends StatelessWidget {
  const ServerTelemetryCard({
    required this.apiBaseUrl,
    required this.serverName,
    required this.routeLabel,
    required this.checking,
    required this.serverOnline,
    required this.latency,
    required this.lastCheckedAt,
    required this.volumes,
    required this.volumeError,
    required this.onShowServerSwitcher,
    required this.onQuickUpload,
    required this.onRefresh,
    required this.onReturnToConnection,
    required this.onOpenFiles,
    super.key,
  });

  final String apiBaseUrl;
  final String? serverName;
  final String routeLabel;
  final bool checking;
  final bool serverOnline;
  final Duration? latency;
  final DateTime? lastCheckedAt;
  final List<StorageVolume> volumes;
  final String? volumeError;
  final VoidCallback onShowServerSwitcher;
  final VoidCallback onQuickUpload;
  final VoidCallback onRefresh;
  final VoidCallback? onReturnToConnection;
  final VoidCallback onOpenFiles;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final transfers = TransferManager.instance;
    final base = Uri.tryParse(apiBaseUrl);
    final host = base == null ? apiBaseUrl : '${base.host}:${base.hasPort ? base.port : (base.scheme == 'https' ? 443 : 80)}';
    final displayName = (serverName ?? '').trim().isNotEmpty ? serverName!.trim() : host;
    final route = routeLabel;
    final online = serverOnline;
    final muted = colors.onSurfaceVariant;
    final statusColor = checking
        ? (theme.brightness == Brightness.dark ? const Color(0xFFFBBF24) : const Color(0xFFB45309))
        : online
            ? (theme.brightness == Brightness.dark ? const Color(0xFF4ADE80) : const Color(0xFF059669))
            : (theme.brightness == Brightness.dark ? const Color(0xFFF59E0B) : const Color(0xFFB45309));
    final latencyMs = latency?.inMilliseconds;
    final latencyColor = latencyMs == null
        ? muted
        : latencyMs <= 150
            ? (theme.brightness == Brightness.dark ? const Color(0xFF4ADE80) : const Color(0xFF15803D))
            : latencyMs <= 300
                ? (theme.brightness == Brightness.dark ? const Color(0xFFFBBF24) : const Color(0xFFB45309))
                : latencyMs <= 600
                    ? (theme.brightness == Brightness.dark ? const Color(0xFFFB923C) : const Color(0xFFC2410C))
                    : (theme.brightness == Brightness.dark ? const Color(0xFFF87171) : const Color(0xFFB91C1C));
    final cardColor = colors.surfaceContainerLow;
    final foreground = colors.onSurface;
    final mountedVolumes = volumes.where((volume) => volume.available).toList(growable: false);
    return AnimatedBuilder(
      animation: transfers,
      builder: (context, _) {
        final activeTransfers = transfers.tasks.where((task) => task.status == TransferStatus.running).length;
        return Container(
          padding: const EdgeInsets.all(15),
          decoration: BoxDecoration(
            color: theme.brightness == Brightness.dark ? null : cardColor,
            gradient: theme.brightness == Brightness.dark
                ? const LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Color(0xFF1B1D24), Color(0xFF131419)],
                  )
                : null,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: online
                  ? theme.brightness == Brightness.dark
                      ? Colors.white.withValues(alpha: 0.07)
                      : colors.outlineVariant.withValues(alpha: 0.62)
                  : statusColor.withValues(alpha: 0.42),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: onShowServerSwitcher,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Icon(Icons.dns_rounded, color: colors.onSurfaceVariant, size: 19),
                    ),
                    const SizedBox(width: 9),
                    Expanded(
                      child: Text(
                        displayName,
                        softWrap: true,
                        style: theme.textTheme.titleSmall?.copyWith(color: foreground, fontWeight: FontWeight.w800, height: 1.2),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                      decoration: BoxDecoration(color: colors.surfaceContainerHighest, borderRadius: BorderRadius.circular(20)),
                      child: Text(route, style: theme.textTheme.labelSmall?.copyWith(color: foreground, fontWeight: FontWeight.w700)),
                    ),
                    const SizedBox(width: 2),
                    Icon(Icons.expand_more_rounded, color: colors.onSurfaceVariant, size: 19),
                  ]),
                ),
              ),
              const SizedBox(height: 8),
              Row(children: [
                Container(width: 7, height: 7, decoration: BoxDecoration(color: statusColor, shape: BoxShape.circle)),
                const SizedBox(width: 7),
                Expanded(
                  child: Text.rich(
                    checking
                        ? const TextSpan(text: 'Checking server')
                        : !online
                            ? const TextSpan(text: 'Offline')
                            : TextSpan(
                                children: [
                                  const TextSpan(text: 'Online'),
                                  if (latencyMs != null)
                                    TextSpan(
                                      text: ' • $latencyMs ms',
                                      style: TextStyle(color: latencyColor),
                                    ),
                                ],
                              ),
                    maxLines: 1,
                    overflow: TextOverflow.visible,
                    style: theme.textTheme.labelMedium?.copyWith(color: statusColor, fontWeight: FontWeight.w700),
                  ),
                ),
                LiquidGlassPill(
                  radius: BorderRadius.circular(13),
                  child: IconButton(
                    visualDensity: VisualDensity.compact,
                    tooltip: 'Quick upload',
                    onPressed: online ? onQuickUpload : null,
                    icon: Icon(Icons.arrow_upward_rounded, color: colors.onSurface, size: 18),
                  ),
                ),
              ]),
              if (lastCheckedAt != null) ...[
                const SizedBox(height: 4),
                Text(
                  'Last checked ${lastCheckedAt!.hour.toString().padLeft(2, '0')}:${lastCheckedAt!.minute.toString().padLeft(2, '0')}',
                  style: theme.textTheme.labelSmall?.copyWith(color: muted),
                ),
              ],
              if (!online && !checking) ...[
                const SizedBox(height: 8),
                Row(children: [
                  Expanded(child: Text('Server is unreachable. Check the network or server service.',
                    style: theme.textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant))),
                  TextButton(onPressed: () => onRefresh, child: const Text('Reconnect')),
                  TextButton(onPressed: onReturnToConnection, child: const Text('Switch')),
                ]),
              ],
              const SizedBox(height: 13),
              Row(children: [
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('STORAGE', style: theme.textTheme.labelSmall?.copyWith(color: muted, letterSpacing: 0.7)),
                  const SizedBox(height: 5),
                  Text(
                    '${mountedVolumes.length + 1} volume${mountedVolumes.isEmpty ? '' : 's'} mounted',
                    maxLines: 1,
                    overflow: TextOverflow.visible,
                    style: theme.textTheme.labelMedium?.copyWith(color: foreground, fontWeight: FontWeight.w600),
                  ),
                ])),
                const SizedBox(width: 10),
                Expanded(child: InkWell(
                  borderRadius: BorderRadius.circular(10),
                  onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const TransferManagerScreen())),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('TRANSFERS', style: theme.textTheme.labelSmall?.copyWith(color: muted, letterSpacing: 0.7)),
                    const SizedBox(height: 5),
                    Text('$activeTransfers active', style: theme.textTheme.labelMedium?.copyWith(color: foreground, fontWeight: FontWeight.w600)),
                  ]),
                )),
                const SizedBox(width: 10),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('LATENCY', style: theme.textTheme.labelSmall?.copyWith(color: muted, letterSpacing: 0.7)),
                  const SizedBox(height: 5),
                  Text(checking ? 'Checking' : (latencyMs == null ? '—' : '$latencyMs ms'),
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: latencyMs == null ? muted : latencyColor,
                      fontWeight: FontWeight.w700,
                    )),
                ])),
              ]),
              const SizedBox(height: 11),
              InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: onOpenFiles,
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Text('MOUNTED PARTITIONS', style: theme.textTheme.labelSmall?.copyWith(color: muted, letterSpacing: 0.65)),
                    const Spacer(),
                    Text('${mountedVolumes.length + 1} mounted', style: theme.textTheme.labelSmall?.copyWith(color: foreground, fontWeight: FontWeight.w600)),
                    const SizedBox(width: 3),
                    Icon(Icons.chevron_right_rounded, color: colors.onSurfaceVariant, size: 17),
                  ]),
                  const SizedBox(height: 7),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(5),
                    child: SizedBox(height: 5, child: Row(children: [
                      Expanded(child: Container(color: const Color(0xFF60A5FA))),
                      for (var i = 0; i < mountedVolumes.length; i++) ...[
                        const SizedBox(width: 2),
                        Expanded(child: Container(color: const Color(0xFF2DD4BF))),
                      ],
                    ])),
                  ),
                  const SizedBox(height: 5),
                  Text('Internal storage${mountedVolumes.isEmpty ? '' : ' · ${mountedVolumes.map((volume) => volume.name).join(' · ')}'}',
                    maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelSmall?.copyWith(color: muted)),
                  if (volumeError != null) ...[
                    const SizedBox(height: 5),
                    Text(volumeError!, style: theme.textTheme.labelSmall?.copyWith(color: const Color(0xFFFBBF24))),
                  ],
                ]),
              ),
            ],
          ),
        );
      },
    );
  }
}
