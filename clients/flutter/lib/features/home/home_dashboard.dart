import 'dart:async';
import 'package:material_ui/material_ui.dart';
import 'package:file_picker/file_picker.dart';
import 'package:share_plus/share_plus.dart';

import 'quick_actions_store.dart';
import 'network_route_classifier.dart';
import '../../core/settings/app_settings.dart';
import '../../core/navigation/pocketlink_navigation.dart';
import '../../core/storage/home_activity_store.dart';
import '../../core/widgets/liquid_glass_pill.dart';
import '../settings/settings_screen.dart';
import 'explore_search_screens.dart';
import '../media/now_playing_screen.dart';
import '../media/persistent_audio_player.dart';
import '../../core/network/server_api.dart';
import '../library/photo_gallery_screen.dart';
import '../transfers/transfer_manager_screen.dart';
import '../transfers/transfer_manager.dart';
import '../search/search_screen.dart';

class HomeDashboard extends StatefulWidget {
  const HomeDashboard({
    required this.api,
    required this.serverName,
    required this.onOpenExplore,
    required this.onOpenFiles,
    required this.onOpenExternalStorage,
    required this.onOpenHostSetup,
    required this.onOpenFileLocation,
    this.onReturnToConnection,
  });

  final ServerApi api;
  final String? serverName;
  final void Function(ExploreCategory category, {String? fileCategory}) onOpenExplore;
  final VoidCallback onOpenFiles;
  final VoidCallback onOpenExternalStorage;
  final VoidCallback onOpenHostSetup;
  final void Function(String? volume, String path) onOpenFileLocation;
  final VoidCallback? onReturnToConnection;

  @override
  State<HomeDashboard> createState() => HomeDashboardState();
}

class HomeDashboardState extends State<HomeDashboard> with WidgetsBindingObserver {
  bool _checking = false;
  bool? _serverOnline;
  Duration? _latency;
  DateTime? _lastCheckedAt;
  List<StorageVolume> _volumes = const [];
  List<RecentFile> _recentFiles = const [];
  MediaIndexStatus? _mediaScanStatus;
  bool _startingMediaScan = false;
  bool _watchingMediaScan = false;
  HostSystemTelemetry? _hostTelemetry;
  String? _telemetryError;
  String? _mediaScanError;
  String? _volumeError;
  String? _recentFilesError;
  int _refreshGeneration = 0;
  Timer? _telemetryTimer;
  Future<void>? _telemetryRequest;
  final QuickActionsStore _quickActionsStore = QuickActionsStore();
  List<String> _quickActions = List.of(QuickActionsStore.defaults);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadQuickActions();
    HomeActivityStore.instance.load();
    _refreshStatus();
    _startTelemetryPolling();
  }

  @override
  void dispose() {
    _telemetryTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _startTelemetryPolling();
      if (_serverOnline == true) unawaited(_refreshHostTelemetry());
    } else {
      _telemetryTimer?.cancel();
      _telemetryTimer = null;
    }
  }

  void _startTelemetryPolling() {
    _telemetryTimer?.cancel();
    if (WidgetsBinding.instance.lifecycleState != AppLifecycleState.resumed) return;
    _telemetryTimer = Timer.periodic(const Duration(seconds: 20), (_) {
      if (!mounted || _serverOnline != true || _checking) return;
      unawaited(_refreshHostTelemetry());
    });
  }

  static const _quickActionDetails = <String, ({String label, IconData icon})>{
    'files': (label: 'Files', icon: Icons.folder_open_rounded),
    'upload': (label: 'Upload', icon: Icons.cloud_upload_rounded),
    'favorites': (label: 'Favorites', icon: Icons.favorite_rounded),
    'photos': (label: 'Photos', icon: Icons.photo_library_rounded),
    'music': (label: 'Music', icon: Icons.headphones_rounded),
    'videos': (label: 'Videos', icon: Icons.movie_rounded),
    'drives': (label: 'Drives', icon: Icons.usb_rounded),
    'documents': (label: 'Documents', icon: Icons.description_rounded),
    'transfers': (label: 'Transfers', icon: Icons.swap_vert_rounded),
  };

  Future<void> _loadQuickActions() async {
    final actions = await _quickActionsStore.load();
    if (mounted) setState(() => _quickActions = actions);
  }

  Future<void> _editQuickActions() async {
    var draft = List<String>.of(_quickActions);
    final result = await showDialog<List<String>>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Customize quick actions'),
          content: SizedBox(
            width: 420,
            height: 440,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Drag to rearrange. Select the actions you want on Home.',
                    style: Theme.of(context).textTheme.bodySmall),
                const SizedBox(height: 12),
                Expanded(
                  child: ReorderableListView.builder(
                    itemCount: draft.length,
                    onReorderItem: (oldIndex, newIndex) {
                      setDialogState(() {
                        final item = draft.removeAt(oldIndex);
                        draft.insert(newIndex, item);
                      });
                    },
                    itemBuilder: (context, index) {
                      final id = draft[index];
                      final detail = _quickActionDetails[id]!;
                      return CheckboxListTile(
                        key: ValueKey(id),
                        value: true,
                        controlAffinity: ListTileControlAffinity.leading,
                        secondary: const Icon(Icons.drag_handle_rounded),
                        title: Text(detail.label),
                        onChanged: (checked) {
                          if (checked == false) {
                            setDialogState(() => draft.remove(id));
                          }
                        },
                      );
                    },
                  ),
                ),
                const Divider(),
                Text('Add actions', style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: QuickActionsStore.available
                      .where((id) => !draft.contains(id))
                      .map((id) => ActionChip(
                            avatar: Icon(_quickActionDetails[id]!.icon, size: 17),
                            label: Text(_quickActionDetails[id]!.label),
                            onPressed: () => setDialogState(() => draft.add(id)),
                          ))
                      .toList(),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => setDialogState(
                () => draft = List.of(QuickActionsStore.defaults),
              ),
              child: const Text('Reset'),
            ),
            FilledButton(
              onPressed: draft.isEmpty
                  ? null
                  : () => Navigator.pop(dialogContext, draft),
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
    if (result == null || !mounted) return;
    await _quickActionsStore.save(result);
    if (mounted) setState(() => _quickActions = result);
  }

  void _runQuickAction(String id) {
    switch (id) {
      case 'upload':
        _quickUpload();
        return;
      case 'files':
        widget.onOpenFiles();
        return;
      case 'favorites':
        Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => PhotoGalleryScreen(api: widget.api, initialTab: 3)));
        return;
      case 'photos':
        widget.onOpenExplore(ExploreCategory.photos);
        return;
      case 'music':
        widget.onOpenExplore(ExploreCategory.music);
        return;
      case 'videos':
        widget.onOpenExplore(ExploreCategory.videos);
        return;
      case 'drives':
        widget.onOpenExternalStorage();
        return;
      case 'documents':
        widget.onOpenExplore(ExploreCategory.files, fileCategory: 'Documents');
        return;
      case 'transfers':
        Navigator.of(context).push(MaterialPageRoute<void>(
          builder: (_) => const TransferManagerScreen(),
        ));
        return;
    }
  }


  IconData _recentIcon(FileEntry file) {
    if (file.isDirectory) return Icons.folder_outlined;
    final dot = file.name.lastIndexOf('.');
    final extension = dot < 0 ? '' : file.name.substring(dot + 1).toLowerCase();
    if (const {'jpg','jpeg','png','gif','webp','heic','heif','bmp','avif'}.contains(extension)) return Icons.image_outlined;
    if (const {'mp4','mkv','mov','avi','webm','m4v','3gp'}.contains(extension)) return Icons.video_file_outlined;
    if (const {'mp3','m4a','aac','wav','flac','ogg','opus','wma','aiff','alac'}.contains(extension)) return Icons.audio_file_outlined;
    if (const {'pdf','doc','docx','xls','xlsx','ppt','pptx','txt','rtf','odt'}.contains(extension)) return Icons.description_outlined;
    return Icons.insert_drive_file_outlined;
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    const units = ['KB', 'MB', 'GB', 'TB'];
    var value = bytes / 1024;
    var unit = 0;
    while (value >= 1024 && unit < units.length - 1) {
      value /= 1024;
      unit++;
    }
    return '${value.toStringAsFixed(1)} ${units[unit]}';
  }

  String _relativeTime(DateTime date) {
    final difference = DateTime.now().difference(date);
    if (difference.isNegative || difference.inMinutes < 1) return 'Just now';
    if (difference.inHours < 1) return '${difference.inMinutes}m ago';
    if (difference.inDays < 1) return '${difference.inHours}h ago';
    if (difference.inDays < 7) return '${difference.inDays}d ago';
    return '${date.day}/${date.month}/${date.year}';
  }

  Future<void> _handleRecentAction(RecentFile recent, String action) async {
    final path = recent.path;
    try {
      switch (action) {
        case 'download':
          if (recent.volume == null) {
            final bytes = await widget.api.downloadFile(path);
            final saved = await FilePicker.saveFile(
              dialogTitle: 'Save ${recent.file.name}',
              fileName: recent.file.name,
              bytes: bytes,
            );
            if (saved == null) return;
          } else {
            final bytes = await widget.api.downloadStorageFile(recent.volume!, path);
            final saved = await FilePicker.saveFile(
              dialogTitle: 'Save ${recent.file.name}',
              fileName: recent.file.name,
              bytes: bytes,
            );
            if (saved == null) return;
          }
          break;
        case 'share':
          if (recent.file.size > 50 * 1024 * 1024) {
            if (mounted) ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Sharing from Home is limited to 50 MB. Use Download for larger files.')),
            );
            return;
          }
          final shareBytes = recent.volume == null
              ? await widget.api.downloadFile(path)
              : await widget.api.downloadStorageFile(recent.volume!, path);
          await SharePlus.instance.share(
            ShareParams(
              files: [XFile.fromData(shareBytes, name: recent.file.name)],
              text: recent.file.name,
            ),
          );
          break;
        case 'rename':
          final controller = TextEditingController(text: recent.file.name);
          final name = await showDialog<String>(
            context: context,
            builder: (dialogContext) => AlertDialog(
              title: const Text('Rename file'),
              content: TextField(controller: controller, autofocus: true),
              actions: [
                TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancel')),
                FilledButton(onPressed: () => Navigator.pop(dialogContext, controller.text.trim()), child: const Text('Save')),
              ],
            ),
          );
          controller.dispose();
          if (name == null || name.isEmpty || name == recent.file.name) return;
          if (recent.volume == null) {
            await widget.api.renameItem(path, name);
          } else {
            await widget.api.renameStorageItem(recent.volume!, path, name);
          }
          await _refreshStatus();
          break;
        case 'delete':
          final confirmed = await showDialog<bool>(
            context: context,
            builder: (dialogContext) => AlertDialog(
              title: const Text('Delete file?'),
              content: Text('Delete "${recent.file.name}"? This cannot be undone.'),
              actions: [
                TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancel')),
                FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Delete')),
              ],
            ),
          );
          if (confirmed != true) return;
          if (recent.volume == null) {
            await widget.api.deleteItem(path);
          } else {
            await widget.api.deleteStorageItem(recent.volume!, path);
          }
          await _refreshStatus();
          break;
      }
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not complete that file action.')),
      );
    }
  }

  Future<void> _showServerSwitcherSheet() async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => SafeArea(
        child: Container(
          padding: const EdgeInsets.fromLTRB(18, 12, 18, 22),
          decoration: const BoxDecoration(
            color: Color(0xFF161618),
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            border: Border(top: BorderSide(color: Color(0x22FFFFFF))),
          ),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Center(child: Container(width: 36, height: 4, decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(4)))),
            const SizedBox(height: 18),
            const Text('Server switcher & Native host', style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.swap_horiz_rounded, color: Colors.white70),
              title: const Text('Switch server', style: TextStyle(color: Colors.white)),
              subtitle: const Text('Choose or manage saved servers', style: TextStyle(color: Colors.white60)),
              onTap: widget.onReturnToConnection == null ? null : () {
                Navigator.pop(sheetContext);
                widget.onReturnToConnection!.call();
              },
            ),
            const Divider(color: Color(0x22FFFFFF)),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.dns_outlined, color: Colors.white70),
              title: const Text('Host PocketLink on this phone', style: TextStyle(color: Colors.white)),
              subtitle: const Text('Set up this device as a PocketLink server', style: TextStyle(color: Colors.white60)),
              onTap: () {
                Navigator.pop(sheetContext);
                widget.onOpenHostSetup();
              },
            ),
          ]),
        ),
      ),
    );
  }

  String _networkRouteLabel(Uri? base) =>
      networkRouteLabel(base?.host ?? '');

  Future<void> _quickUpload() async {
    try {
      final file = await FilePicker.pickFile();
      if (file == null) return;
      final bytes = await file.readAsBytes();
      final completed = await TransferManager.instance.run(
        name: file.name,
        direction: 'Upload',
        location: 'Internal storage · Root',
        operation: (token, progress) => widget.api.uploadFile(
          '',
          file.name,
          bytes,
          cancelToken: token,
          onSendProgress: progress,
        ),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(completed ? 'Uploaded ${file.name}' : 'Upload did not complete. Check Transfers.'),
      ));
      if (completed) await _refreshStatus();
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not upload the selected file.')),
      );
    }
  }


  Future<void> _refreshHostTelemetry() {
    final pending = _telemetryRequest;
    if (pending != null) return pending;

    late final Future<void> request;
    request = () async {
      try {
        final telemetry = await widget.api.systemTelemetry();
        if (mounted) setState(() {
          _hostTelemetry = telemetry;
          _telemetryError = null;
        });
      } catch (_) {
        if (mounted) setState(() => _telemetryError = 'Could not read host device health. Pull to refresh and try again.');
      } finally {
        if (identical(_telemetryRequest, request)) _telemetryRequest = null;
      }
    }();
    _telemetryRequest = request;
    return request;
  }

  Widget _buildHostDeviceMetrics(ThemeData theme) {
    final telemetry = _hostTelemetry;
    final muted = Colors.white.withValues(alpha: 0.58);
    final foreground = Colors.white;

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
            color: Colors.white.withValues(alpha: 0.035),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.white.withValues(alpha: 0.055)),
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
                    backgroundColor: Colors.white.withValues(alpha: 0.10),
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
        ? '${_formatBytes(telemetry!.memoryUsedBytes!)} / ${_formatBytes(telemetry.memoryTotalBytes!)} used'
        : '';
    final storageDetail = telemetry?.storageUsedBytes != null &&
            telemetry?.storageTotalBytes != null
        ? '${_formatBytes(telemetry!.storageUsedBytes!)} / ${_formatBytes(telemetry.storageTotalBytes!)} used'
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
      decoration: BoxDecoration(
        color: const Color(0xFF1E2025),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Icon(Icons.memory_rounded, size: 18, color: Colors.white70),
            const SizedBox(width: 8),
            Expanded(child: Text('HOST DEVICE HEALTH',
              style: theme.textTheme.labelMedium?.copyWith(
                color: foreground, fontWeight: FontWeight.w800, letterSpacing: 0.65,
              ))),
            if (sampledAt != null)
              Text(
                '${_serverOnline == true ? 'Updated' : 'Last known'} ${sampledAt.hour.toString().padLeft(2, '0')}:${sampledAt.minute.toString().padLeft(2, '0')}',
                style: theme.textTheme.labelSmall?.copyWith(color: muted),
              ),
          ]),
          const SizedBox(height: 11),
          if (telemetry == null)
            Text(
              _serverOnline != true
                  ? 'System information appears when the host is connected.'
                  : _telemetryError ?? 'Reading system information from the host…',
              style: theme.textTheme.bodySmall?.copyWith(
                color: _telemetryError == null ? muted : const Color(0xFFFBBF24),
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
          if (_volumes.isNotEmpty) ...[
            const SizedBox(height: 5),
            Text('EXTERNAL STORAGE', style: theme.textTheme.labelSmall?.copyWith(
              color: muted, letterSpacing: 0.65, fontWeight: FontWeight.w800,
            )),
            const SizedBox(height: 7),
            for (final volume in _volumes) ...[
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
                        '${_formatBytes(volume.usedBytes!)} of ${_formatBytes(volume.totalBytes!)} used',
                        style: theme.textTheme.labelSmall?.copyWith(color: muted),
                      )),
                      Text('${_formatBytes(volume.availableBytes!)} free',
                        style: theme.textTheme.labelSmall?.copyWith(color: muted)),
                    ]),
                    const SizedBox(height: 5),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: (volume.usagePercent!.clamp(0, 100)) / 100,
                        minHeight: 4,
                        backgroundColor: Colors.white.withValues(alpha: 0.10),
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
          style: theme.textTheme.labelMedium?.copyWith(color: Colors.white70))),
        if (trailing != null)
          Text(trailing, style: theme.textTheme.labelSmall?.copyWith(color: muted)),
      ]),
    );
  }

  Widget _buildServerTelemetry(BuildContext context, ThemeData theme, ColorScheme colors) {
    final transfers = TransferManager.instance;
    final base = Uri.tryParse(widget.api.baseUrl);
    final host = base == null ? widget.api.baseUrl : '${base.host}:${base.hasPort ? base.port : (base.scheme == 'https' ? 443 : 80)}';
    final displayName = (widget.serverName ?? '').trim().isNotEmpty ? widget.serverName!.trim() : host;
    final route = _networkRouteLabel(base);
    final online = _serverOnline == true;
    final statusColor = _checking ? Colors.amber : online ? const Color(0xFF4ADE80) : const Color(0xFFF59E0B);
    final cardColor = const Color(0xFF1E2025);
    final foreground = Colors.white;
    final muted = Colors.white.withValues(alpha: 0.62);
    final mountedVolumes = _volumes.where((volume) => volume.available).toList(growable: false);
    return AnimatedBuilder(
      animation: transfers,
      builder: (context, _) {
        final activeTransfers = transfers.tasks.where((task) => task.status == TransferStatus.running).length;
        return Container(
          padding: const EdgeInsets.all(15),
          decoration: BoxDecoration(
            color: cardColor,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: online ? Colors.white.withValues(alpha: 0.075) : statusColor.withValues(alpha: 0.42),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: _showServerSwitcherSheet,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Padding(
                      padding: EdgeInsets.only(top: 2),
                      child: Icon(Icons.dns_rounded, color: Colors.white70, size: 19),
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
                      decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.075), borderRadius: BorderRadius.circular(20)),
                      child: Text(route, style: theme.textTheme.labelSmall?.copyWith(color: foreground, fontWeight: FontWeight.w700)),
                    ),
                    const SizedBox(width: 2),
                    const Icon(Icons.expand_more_rounded, color: Colors.white54, size: 19),
                  ]),
                ),
              ),
              const SizedBox(height: 8),
              Row(children: [
                Container(width: 7, height: 7, decoration: BoxDecoration(color: statusColor, shape: BoxShape.circle)),
                const SizedBox(width: 7),
                Expanded(
                  child: Text(
                    _checking ? 'Checking server' : online
                        ? 'Online${_latency == null ? '' : ' • ${_latency!.inMilliseconds} ms'}'
                        : 'Offline',
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
                    onPressed: online ? _quickUpload : null,
                    icon: const Icon(Icons.arrow_upward_rounded, color: Colors.white, size: 18),
                  ),
                ),
              ]),
              if (_lastCheckedAt != null) ...[
                const SizedBox(height: 4),
                Text(
                  'Last checked ${_lastCheckedAt!.hour.toString().padLeft(2, '0')}:${_lastCheckedAt!.minute.toString().padLeft(2, '0')}',
                  style: theme.textTheme.labelSmall?.copyWith(color: muted),
                ),
              ],
              if (!online && !_checking) ...[
                const SizedBox(height: 8),
                Row(children: [
                  Expanded(child: Text('Server is unreachable. Check the network or server service.',
                    style: theme.textTheme.bodySmall?.copyWith(color: Colors.white70))),
                  TextButton(onPressed: () => _refreshStatus(forceRefresh: true), child: const Text('Reconnect')),
                  TextButton(onPressed: widget.onReturnToConnection, child: const Text('Switch')),
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
                  Text(_checking ? 'Checking' : (_latency == null ? '—' : '${_latency!.inMilliseconds} ms'),
                    style: theme.textTheme.labelMedium?.copyWith(color: foreground, fontWeight: FontWeight.w600)),
                ])),
              ]),
              const SizedBox(height: 11),
              InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: () => widget.onOpenExplore(ExploreCategory.drives),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Text('MOUNTED PARTITIONS', style: theme.textTheme.labelSmall?.copyWith(color: muted, letterSpacing: 0.65)),
                    const Spacer(),
                    Text('${mountedVolumes.length + 1} mounted', style: theme.textTheme.labelSmall?.copyWith(color: foreground, fontWeight: FontWeight.w600)),
                    const SizedBox(width: 3),
                    const Icon(Icons.chevron_right_rounded, color: Colors.white70, size: 17),
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
                  if (_volumeError != null) ...[
                    const SizedBox(height: 5),
                    Text(_volumeError!, style: theme.textTheme.labelSmall?.copyWith(color: const Color(0xFFFBBF24))),
                  ],
                ]),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildContinueStrip(BuildContext context, ThemeData theme, ColorScheme colors) {
    final player = PersistentAudioPlayer.instance;
    final items = HomeActivityStore.instance.itemsForServer(widget.api.baseUrl).take(8).toList();
    if (items.isEmpty) {
      return Container(
        height: 72,
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(color: colors.surfaceContainerLow, borderRadius: BorderRadius.circular(18)),
        child: Row(children: [
          Icon(Icons.history_rounded, color: colors.onSurfaceVariant),
          const SizedBox(width: 10),
          Expanded(child: Text('Your recent tracks, folders and files will appear here.',
            style: theme.textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant))),
        ]),
      );
    }
    return SizedBox(
      height: 92,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: items.length,
        separatorBuilder: (_, __) => const SizedBox(width: 10),
        itemBuilder: (context, index) {
          final recent = items[index];
          final isTrack = recent.kind == 'track';
          final isFolder = recent.kind == 'folder';
          final icon = isTrack ? Icons.music_note_rounded : isFolder ? Icons.folder_rounded : Icons.insert_drive_file_rounded;
          return SizedBox(
            width: 250,
            child: Material(
              color: colors.surfaceContainerLow,
              borderRadius: BorderRadius.circular(18),
              child: InkWell(
                borderRadius: BorderRadius.circular(18),
                onTap: () async {
                  if (isTrack) {
                    final queueItem = MediaQueueItem(
                      title: recent.title,
                      path: recent.path,
                      volume: recent.volume,
                    );
                    await player.openQueue(
                      api: widget.api,
                      queue: [queueItem],
                      initialIndex: 0,
                      isMusic: true,
                    );
                    await Navigator.of(context, rootNavigator: true).push<void>(
                      MaterialPageRoute<void>(
                        settings: const RouteSettings(
                          name: PocketLinkRouteNames.nowPlaying,
                        ),
                        builder: (_) => NowPlayingScreen(
                          api: widget.api,
                          queue: player.queue,
                          initialIndex: player.currentIndex,
                          resumeExisting: true,
                        ),
                      ),
                    );
                  } else {
                    final path = isFolder ? recent.path : recent.parentPath;
                    widget.onOpenFileLocation(recent.volume, path);
                  }
                },
                child: Padding(
                  padding: const EdgeInsets.all(13),
                  child: Row(children: [
                    Container(width: 48, height: 48, decoration: BoxDecoration(
                      color: colors.primaryContainer, borderRadius: BorderRadius.circular(14)),
                      child: Icon(icon, color: colors.primary)),
                    const SizedBox(width: 11),
                    Expanded(child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(isTrack ? 'Continue listening' : isFolder ? 'Recent folder' : 'Recent file',
                        style: theme.textTheme.labelSmall?.copyWith(color: colors.onSurfaceVariant)),
                      const SizedBox(height: 3),
                      Text(recent.title, maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                    ])),
                    Icon(isTrack ? Icons.play_arrow_rounded : Icons.chevron_right_rounded),
                  ]),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildGlobalSearchEntry(ThemeData theme, ColorScheme colors) {
    return Material(
      color: const Color(0xFF1E2025),
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
          builder: (_) => SearchScreen(api: widget.api),
        )),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(children: [
            Icon(Icons.search_rounded, color: colors.primary),
            const SizedBox(width: 12),
            Expanded(child: Text('Search files, folders and media',
              style: theme.textTheme.bodyMedium?.copyWith(color: Colors.white70))),
            const Icon(Icons.arrow_forward_rounded, color: Colors.white54, size: 18),
          ]),
        ),
      ),
    );
  }

  Widget _buildActiveTransfersPreview(ThemeData theme, ColorScheme colors) {
    final manager = TransferManager.instance;
    return AnimatedBuilder(
      animation: manager,
      builder: (context, _) {
        final active = manager.tasks
            .where((task) => task.status == TransferStatus.running)
            .take(2)
            .toList(growable: false);
        if (active.isEmpty) return const SizedBox.shrink();
        return Material(
          color: const Color(0xFF1E2025),
          borderRadius: BorderRadius.circular(18),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
              builder: (_) => const TransferManagerScreen(),
            )),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Expanded(child: Text('Active transfers',
                    style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800))),
                  Text('View all', style: theme.textTheme.labelMedium?.copyWith(color: colors.primary)),
                ]),
                const SizedBox(height: 10),
                for (var index = 0; index < active.length; index++) ...[
                  if (index > 0) const SizedBox(height: 12),
                  Row(children: [
                    Icon(active[index].direction == 'Upload'
                        ? Icons.cloud_upload_outlined : Icons.download_rounded,
                      color: colors.primary, size: 19),
                    const SizedBox(width: 9),
                    Expanded(child: Text(active[index].name, maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600))),
                    Text(active[index].progress == null
                        ? 'In progress'
                        : '${(active[index].progress! * 100).round()}%',
                      style: theme.textTheme.labelSmall?.copyWith(color: Colors.white70)),
                  ]),
                  const SizedBox(height: 7),
                  LinearProgressIndicator(value: active[index].progress, minHeight: 4),
                  const SizedBox(height: 4),
                  Text(active[index].total > 0
                      ? '${_formatBytes(active[index].transferred)} of ${_formatBytes(active[index].total)}'
                      : 'Transfer in progress',
                    style: theme.textTheme.labelSmall?.copyWith(color: Colors.white60)),
                ],
              ]),
            ),
          ),
        );
      },
    );
  }

  Future<void> _watchHostMediaScan() async {
    if (_watchingMediaScan) return;
    _watchingMediaScan = true;
    try {
      while (mounted && (_mediaScanStatus?.isScanning ?? false)) {
        await Future<void>.delayed(const Duration(seconds: 2));
        if (!mounted) return;
        final status = await widget.api.mediaIndexStatus();
        if (!mounted) return;
        setState(() => _mediaScanStatus = status);
      }
      if (mounted) await _refreshStatus();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not update host scan progress.')),
        );
      }
    } finally {
      _watchingMediaScan = false;
    }
  }

  Future<void> _startHostMediaScan() async {
    if (_startingMediaScan || (_mediaScanStatus?.isScanning ?? false)) return;
    setState(() {
      _startingMediaScan = true;
      _mediaScanError = null;
    });
    try {
      final status = await widget.api.startMediaIndexScan();
      if (!mounted) return;
      setState(() {
        _mediaScanStatus = status;
        _mediaScanError = status.state == 'failed' ? (status.lastError ?? 'The host scan failed.') : null;
      });
      if (status.isScanning) unawaited(_watchHostMediaScan());
      else if (status.state == 'failed' || status.state == 'partial') {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(status.lastError ?? 'The host scan did not complete fully.')),
        );
      }
    } catch (_) {
      if (mounted) {
        setState(() => _mediaScanError = 'Could not start the host scan. Check the host connection and storage permissions.');
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not start a scan on the host device. Check the server connection.')),
        );
      }
    } finally {
      if (mounted) setState(() => _startingMediaScan = false);
    }
  }

  Widget _buildHostMediaScanCard(ThemeData theme, ColorScheme colors) {
    final status = _mediaScanStatus;
    final scanning = status?.isScanning ?? false;
    final source = status?.currentSource;
    final elapsed = ((status?.elapsedMs ?? 0) / 1000).floor();
    final sourceLabel = source == 'internal'
        ? 'Internal storage'
        : source == null ? 'Preparing storage' : 'External storage';
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: const Color(0xFF1E2025),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.manage_search_rounded, color: colors.primary, size: 20),
          const SizedBox(width: 9),
          Expanded(child: Text('Host media library', style: theme.textTheme.titleSmall?.copyWith(
            color: Colors.white, fontWeight: FontWeight.w800,
          ))),
          Text(scanning ? 'Scanning' : _mediaScanError != null ? 'Unavailable' : status == null ? 'Checking' : status.state == 'failed' ? 'Failed' : status.state == 'partial' ? 'Partial' : status.state == 'complete' ? 'Up to date' : 'Ready',
            style: theme.textTheme.labelSmall?.copyWith(
              color: scanning || _mediaScanError != null ? const Color(0xFFFBBF24) : Colors.white70,
              fontWeight: FontWeight.w700,
            )),
        ]),
        const SizedBox(height: 7),
        Text(
          scanning
              ? 'Scanning $sourceLabel · ${elapsed}s elapsed'
              : 'Refresh the host device media and file index remotely.',
          style: theme.textTheme.bodySmall?.copyWith(color: Colors.white60),
        ),
        if (_mediaScanError != null) ...[
          const SizedBox(height: 7),
          Text(_mediaScanError!, style: theme.textTheme.bodySmall?.copyWith(color: const Color(0xFFFBBF24))),
        ],
        if (status != null) ...[
          const SizedBox(height: 7),
          Text(
            '${status.mediaCount} media · ${status.fileCount} files · '
            '${status.scanned} checked · ${status.skipped} skipped',
            style: theme.textTheme.labelSmall?.copyWith(color: Colors.white70),
          ),
          if (status.lastError != null && status.lastError!.isNotEmpty) ...[
            const SizedBox(height: 5),
            Text(status.lastError!, style: theme.textTheme.bodySmall?.copyWith(color: colors.error)),
          ],
        ],
        if (scanning) ...[
          const SizedBox(height: 10),
          const LinearProgressIndicator(),
        ],
        const SizedBox(height: 10),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: scanning || _startingMediaScan || _checking || _serverOnline != true
                ? null
                : _startHostMediaScan,
            icon: _startingMediaScan || scanning
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.refresh_rounded, size: 18),
            label: Text(scanning ? 'Scanning on host…' : _startingMediaScan ? 'Starting…' : 'Scan host now'),
          ),
        ),
      ]),
    );
  }

  Future<void> _refreshMediaIndexStatus(int generation) async {
    try {
      final status = await widget.api.mediaIndexStatus();
      if (!mounted || generation != _refreshGeneration) return;
      setState(() {
        _mediaScanStatus = status;
        _mediaScanError = null;
      });
      if (status.isScanning) unawaited(_watchHostMediaScan());
    } catch (_) {
      if (mounted && generation == _refreshGeneration) {
        setState(() => _mediaScanError = 'Host media index is unavailable. Check the native host service.');
      }
    }
  }

  Future<void> _refreshVolumesAndRecentFiles(int generation) async {
    List<StorageVolume> volumes;
    try {
      volumes = await widget.api.listStorageVolumes();
      if (!mounted || generation != _refreshGeneration) return;
      setState(() {
        _volumes = volumes;
        _volumeError = null;
      });
    } catch (_) {
      if (!mounted || generation != _refreshGeneration) return;
      setState(() => _volumeError = 'Could not load mounted storage from the host.');
      return;
    }

    try {
      final recentFiles = await widget.api.listRecentFiles(volumes: volumes);
      if (!mounted || generation != _refreshGeneration) return;
      setState(() {
        _recentFiles = recentFiles;
        _recentFilesError = null;
      });
    } catch (_) {
      if (mounted && generation == _refreshGeneration) {
        setState(() => _recentFilesError = 'Could not load recent files from the host.');
      }
    }
  }

  Future<void> _refreshStatus({bool forceRefresh = false}) async {
    if (_checking) return;
    if (forceRefresh) widget.api.invalidateDirectoryCache();
    final generation = ++_refreshGeneration;
    if (mounted) setState(() => _checking = true);
    final stopwatch = Stopwatch()..start();
    try {
      // Only the authenticated root request determines whether the host is online.
      // Optional panels load independently so slow storage scans cannot keep the
      // entire dashboard stuck in the "Checking" state.
      await widget.api.authenticate();
      stopwatch.stop();
      if (!mounted || generation != _refreshGeneration) return;
      setState(() {
        _serverOnline = true;
        _latency = stopwatch.elapsed;
        _lastCheckedAt = DateTime.now();
        _checking = false;
      });

      unawaited(_refreshHostTelemetry());
      unawaited(_refreshMediaIndexStatus(generation));
      unawaited(_refreshVolumesAndRecentFiles(generation));
    } catch (_) {
      stopwatch.stop();
      if (!mounted || generation != _refreshGeneration) return;
      setState(() {
        _serverOnline = false;
        _latency = null;
        _lastCheckedAt = DateTime.now();
        _checking = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final availableVolumes = _volumes.where((volume) => volume.available).length;
    final appSettings = AppSettings.instance;


    Widget sectionTitle(String title, {String? action, VoidCallback? onAction}) {
      return Row(
        children: [
          Expanded(
            child: Text(title, style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w800,
              letterSpacing: -0.4,
            )),
          ),
          if (action != null)
            TextButton(onPressed: onAction, child: Text(action)),
        ],
      );
    }

    Widget quickAction(IconData icon, String label, VoidCallback onTap) {
      return Material(
        color: colors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(18),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 23, color: colors.primary),
                const SizedBox(height: 8),
                Text(label, maxLines: 1, overflow: TextOverflow.visible, softWrap: false,
                  style: theme.textTheme.labelLarge?.copyWith(fontSize: 11.5, fontWeight: FontWeight.w600)),
              ],
            ),
          ),
        ),
      );
    }

    final sectionBuilders = <String, Widget Function()>{
      'search': () => appSettings.showGlobalSearch
          ? Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: _buildGlobalSearchEntry(theme, colors),
            )
          : const SizedBox.shrink(),
      'quick': () => appSettings.showQuickActions
          ? Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                sectionTitle('Quick actions', action: 'Edit', onAction: _editQuickActions),
                const SizedBox(height: 9),
                if (_quickActions.isEmpty)
                  OutlinedButton.icon(
                    onPressed: _editQuickActions,
                    icon: const Icon(Icons.add_rounded),
                    label: const Text('Add quick actions'),
                  )
                else
                  GridView.count(
                    crossAxisCount: 4,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    crossAxisSpacing: 9,
                    mainAxisSpacing: 9,
                    childAspectRatio: 0.88,
                    children: _quickActions.map((id) {
                      final detail = _quickActionDetails[id]!;
                      return quickAction(detail.icon, detail.label, () => _runQuickAction(id));
                    }).toList(),
                  ),
              ]),
            )
          : const SizedBox.shrink(),
      'transfers': () => appSettings.showActiveTransfers
          ? Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: _buildActiveTransfersPreview(theme, colors),
            )
          : const SizedBox.shrink(),
      'continue': () => appSettings.showLibrary
          ? Padding(
              padding: const EdgeInsets.only(bottom: 18),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                sectionTitle('Continue'),
                const SizedBox(height: 10),
                AnimatedBuilder(
                  animation: HomeActivityStore.instance,
                  builder: (context, _) => _buildContinueStrip(context, theme, colors),
                ),
              ]),
            )
          : const SizedBox.shrink(),
      'recent': () => appSettings.showRecentFiles
          ? Padding(
              padding: const EdgeInsets.only(bottom: 18),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                sectionTitle(
                  'Recent files',
                  action: 'Browse',
                  onAction: () => widget.onOpenExplore(ExploreCategory.files),
                ),
                const SizedBox(height: 10),
                if (_recentFiles.isEmpty)
                  Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: colors.surfaceContainerLow,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(children: [
                      Icon(Icons.history_rounded, color: colors.onSurfaceVariant),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          _recentFilesError ?? (_checking
                              ? 'Checking your folders for recent files…'
                              : 'No recent files found in the scanned folders.'),
                          style: theme.textTheme.bodyMedium?.copyWith(color: colors.onSurfaceVariant),
                        ),
                      ),
                    ]),
                  )
                else
                  Material(
                    color: colors.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(20),
                    clipBehavior: Clip.antiAlias,
                    child: Column(children: [
                      for (var index = 0; index < _recentFiles.take(8).length; index++) ...[
                        if (index > 0) const Divider(height: 1, indent: 68),
                        ListTile(
                          dense: true,
                          minVerticalPadding: 8,
                          leading: Container(
                            width: 42,
                            height: 42,
                            decoration: BoxDecoration(
                              color: colors.secondaryContainer,
                              borderRadius: BorderRadius.circular(13),
                            ),
                            child: Icon(_recentIcon(_recentFiles[index].file), color: colors.onSecondaryContainer),
                          ),
                          title: Text(
                            _recentFiles[index].file.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                          ),
                          subtitle: Text(
                            '${_formatBytes(_recentFiles[index].file.size)} · ${_relativeTime(_recentFiles[index].modifiedAt)} · ${_recentFiles[index].volumeName}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          trailing: PopupMenuButton<String>(
                            tooltip: 'File actions',
                            onSelected: (action) => _handleRecentAction(_recentFiles[index], action),
                            itemBuilder: (_) => const [
                              PopupMenuItem(value: 'download', child: Text('Download')),
                              PopupMenuItem(value: 'share', child: Text('Share')),
                              PopupMenuItem(value: 'rename', child: Text('Rename')),
                              PopupMenuItem(value: 'delete', child: Text('Delete')),
                            ],
                          ),
                          onTap: () {
                            final recent = _recentFiles[index];
                            HomeActivityStore.instance.recordFile(
                              serverUrl: widget.api.baseUrl,
                              title: recent.file.name,
                              path: recent.path,
                              volume: recent.volume,
                            );
                            widget.onOpenFileLocation(recent.volume, recent.parentPath);
                          },
                        ),
                      ],
                    ]),
                  ),
              ]),
            )
          : const SizedBox.shrink(),
    };



    return Scaffold(
      backgroundColor: Colors.black,
      drawer: Drawer(
        child: SafeArea(
          child: ListView(
            padding: EdgeInsets.zero,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: colors.primaryContainer,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Icon(Icons.cloud_rounded, color: colors.onPrimaryContainer),
                    ),
                    const SizedBox(height: 14),
                    Text('PocketLink', style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
                    const SizedBox(height: 3),
                    Text('Storage & locations', style: theme.textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant)),
                  ],
                ),
              ),
              const Divider(height: 1),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 18, 16, 8),
                child: Text('STORAGE', style: theme.textTheme.labelSmall?.copyWith(
                  color: colors.primary, fontWeight: FontWeight.w800, letterSpacing: 1.1,
                )),
              ),
              ListTile(
                leading: const Icon(Icons.phone_android_rounded),
                title: const Text('Internal storage'),
                subtitle: const Text('Browse server folders'),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () {
                  Navigator.pop(context);
                  widget.onOpenExplore(ExploreCategory.files);
                },
              ),
              ListTile(
                leading: const Icon(Icons.usb_rounded),
                title: const Text('USB & external drives'),
                subtitle: Text(_checking ? 'Checking connected drives…' : '$availableVolumes of ${_volumes.length} available'),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () {
                  Navigator.pop(context);
                  widget.onOpenExplore(ExploreCategory.drives);
                },
              ),
              ListTile(
                leading: const Icon(Icons.add_to_drive_rounded),
                title: const Text('Connect a drive'),
                subtitle: const Text('Set up USB / SSD / OTG access'),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () {
                  Navigator.pop(context);
                  widget.onOpenHostSetup();
                },
              ),
              const Divider(height: 24),
              ListTile(
                leading: const Icon(Icons.switch_account_rounded),
                title: const Text('Connection / Switch server'),
                subtitle: const Text('Return to the server login screen'),
                onTap: () {
                  Navigator.pop(context);
                  widget.onReturnToConnection?.call();
                },
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 16, 8),
                child: Text('TOOLS', style: theme.textTheme.labelSmall?.copyWith(
                  color: colors.primary, fontWeight: FontWeight.w800, letterSpacing: 1.1,
                )),
              ),
              ListTile(
                leading: const Icon(Icons.swap_vert_rounded),
                title: const Text('Transfers'),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.of(context).push(MaterialPageRoute<void>(
                    builder: (_) => const TransferManagerScreen(),
                  ));
                },
              ),
              ListTile(
                leading: const Icon(Icons.settings_outlined),
                title: const Text('Settings'),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.of(context).push(MaterialPageRoute<void>(
                    builder: (_) => SettingsScreen(
                      onOpenSavedServers: widget.onReturnToConnection,
                    ),
                  ));
                },
              ),
            ],
          ),
        ),
      ),
      appBar: AppBar(
        // Let Scaffold's drawer provide the standard Material hamburger button.
        backgroundColor: Colors.black,
        surfaceTintColor: Colors.transparent,
        titleSpacing: 20,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('PocketLink', style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w900,
              letterSpacing: -0.6,
            )),
            Text('Your private space', style: theme.textTheme.labelSmall?.copyWith(
              color: colors.onSurfaceVariant,
              fontWeight: FontWeight.w500,
            )),
          ],
        ),
        actions: [
          LiquidGlassPill(
            radius: BorderRadius.circular(14),
            child: IconButton(
              tooltip: 'Transfers',
              onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
                builder: (_) => const TransferManagerScreen(),
              )),
              icon: const Icon(Icons.swap_vert_rounded),
            ),
          ),
          IconButton(
            tooltip: 'Refresh server status',
            onPressed: _checking ? null : () => _refreshStatus(forceRefresh: true),
            icon: const Icon(Icons.refresh_rounded),
          ),
          const SizedBox(width: 6),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => _refreshStatus(forceRefresh: true),
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: EdgeInsets.fromLTRB(18, 6, 18, 104 + MediaQuery.paddingOf(context).bottom),
          children: [
            _buildServerTelemetry(context, theme, colors),
            const SizedBox(height: 12),
            _buildHostDeviceMetrics(theme),
            const SizedBox(height: 12),
            _buildHostMediaScanCard(theme, colors),
            const SizedBox(height: 18),
            for (final section in appSettings.homeSectionOrder)
              if (sectionBuilders.containsKey(section)) sectionBuilders[section]!(),
          ],
        ),
      ),
    );
  }
}