import 'dart:async';
import 'package:material_ui/material_ui.dart';
import 'package:file_picker/file_picker.dart';
import 'package:share_plus/share_plus.dart';

import 'quick_actions_store.dart';
import 'widgets/host_device_metrics_card.dart';
import 'widgets/server_telemetry_card.dart';
import 'network_route_classifier.dart';
import '../../core/settings/app_settings.dart';
import '../../core/storage/home_activity_store.dart';
import '../../core/widgets/feathered_glass_header.dart';
import '../../core/widgets/smoked_glass_popover_menu.dart';
import '../../core/widgets/pocketlink_scaffold.dart';
import 'explore_search_screens.dart';
import '../media/persistent_audio_player.dart';
import '../media/now_playing_overlay_controller.dart';
import '../../core/network/server_api.dart';
import '../transfers/transfer_manager_screen.dart';
import '../transfers/transfer_manager.dart';
import '../search/search_screen.dart';

class HomeDashboard extends StatefulWidget {
  const HomeDashboard({
    required this.api,
    required this.serverName,
    required this.onOpenExplore,
    required this.onOpenLibrary,
    required this.onOpenFiles,
    required this.onOpenExternalStorage,
    required this.onOpenHostSetup,
    required this.onOpenFileLocation,
    required this.onOpenDrawer,
    this.onReturnToConnection,
  });

  final ServerApi api;
  final String? serverName;
  final void Function(ExploreCategory category, {String? fileCategory}) onOpenExplore;
  final ValueChanged<String> onOpenLibrary;
  final VoidCallback onOpenFiles;
  final VoidCallback onOpenExternalStorage;
  final VoidCallback onOpenHostSetup;
  final void Function(String? volume, String path) onOpenFileLocation;
  final VoidCallback onOpenDrawer;
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
  bool _savingMediaScanSettings = false;
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
        widget.onOpenLibrary('favorites');
        return;
      case 'photos':
        widget.onOpenLibrary('photos');
        return;
      case 'music':
        widget.onOpenLibrary('music');
        return;
      case 'videos':
        widget.onOpenLibrary('videos');
        return;
      case 'drives':
        widget.onOpenExternalStorage();
        return;
      case 'documents':
        widget.onOpenLibrary('documents');
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
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => SafeArea(
        child: Container(
          padding: const EdgeInsets.fromLTRB(18, 12, 18, 22),
          decoration: BoxDecoration(
            color: colors.surfaceContainerLow,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            border: Border(top: BorderSide(color: colors.outlineVariant)),
          ),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Center(child: Container(width: 36, height: 4, decoration: BoxDecoration(color: colors.outline, borderRadius: BorderRadius.circular(4)))),
            const SizedBox(height: 18),
            Text('Server switcher & Native host', style: theme.textTheme.titleLarge?.copyWith(color: colors.onSurface, fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.swap_horiz_rounded, color: colors.onSurfaceVariant),
              title: Text('Switch server', style: theme.textTheme.titleMedium?.copyWith(color: colors.onSurface)),
              subtitle: Text('Choose or manage saved servers', style: theme.textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant)),
              onTap: widget.onReturnToConnection == null ? null : () {
                Navigator.pop(sheetContext);
                widget.onReturnToConnection!.call();
              },
            ),
            const Divider(color: Color(0x22FFFFFF)),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.dns_outlined, color: colors.onSurfaceVariant),
              title: Text('Host PocketLink on this phone', style: theme.textTheme.titleMedium?.copyWith(color: colors.onSurface)),
              subtitle: Text('Set up this device as a PocketLink server', style: theme.textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant)),
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

  Widget _buildServerTelemetry() {
    return ServerTelemetryCard(
      apiBaseUrl: widget.api.baseUrl,
      serverName: widget.serverName,
      routeLabel: _networkRouteLabel(Uri.tryParse(widget.api.baseUrl)),
      checking: _checking,
      serverOnline: _serverOnline == true,
      latency: _latency,
      lastCheckedAt: _lastCheckedAt,
      volumes: _volumes,
      volumeError: _volumeError,
      onShowServerSwitcher: _showServerSwitcherSheet,
      onQuickUpload: _quickUpload,
      onRefresh: () => _refreshStatus(forceRefresh: true),
      onReturnToConnection: widget.onReturnToConnection,
      onOpenFiles: widget.onOpenFiles,
    );
  }

  BoxDecoration _dashboardCardDecoration(ThemeData theme, {double radius = 18}) {
    final dark = theme.brightness == Brightness.dark;
    final colors = theme.colorScheme;
    return BoxDecoration(
      color: dark ? null : colors.surfaceContainerLow,
      gradient: dark
          ? const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xFF1B1D24), Color(0xFF131419)],
            )
          : null,
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(
        color: dark
            ? Colors.white.withValues(alpha: 0.07)
            : colors.outlineVariant.withValues(alpha: 0.62),
      ),
    );
  }

  Future<void> _showSkippedItemsInfo(MediaIndexStatus status) async {
    final items = status.skippedItems;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('${status.skipped} skipped ${status.skipped == 1 ? 'item' : 'items'}'),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 360),
          child: SizedBox(
            width: 440,
            child: items.isEmpty
              ? const Text('The host reported skipped items but did not return their locations. Run Scan host again after checking storage permissions.')
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: ListView.separated(
                        shrinkWrap: true,
                        itemCount: items.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (context, index) {
                          final item = items[index];
                          final location = item.path.isEmpty ? item.volume : '${item.volume}/${item.path}';
                          return ListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            leading: const Icon(Icons.folder_off_outlined, color: Color(0xFFF59E0B)),
                            title: Text(location, maxLines: 2, overflow: TextOverflow.ellipsis),
                            subtitle: Text(item.reason, maxLines: 2, overflow: TextOverflow.ellipsis),
                          );
                        },
                      ),
                    ),
                    if (status.skipped > items.length) ...[
                      const SizedBox(height: 8),
                      Text('Showing ${items.length} of ${status.skipped}. Remaining entries are omitted to keep diagnostics lightweight.',
                        style: Theme.of(context).textTheme.bodySmall),
                    ],
                  ],
                ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Close')),
        ],
      ),
    );
  }

  Widget _buildContinueStrip(BuildContext context, ThemeData theme, ColorScheme colors) {
    final player = PersistentAudioPlayer.instance;
    final items = HomeActivityStore.instance.itemsForServer(widget.api.baseUrl).take(8).toList();
    if (items.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
        decoration: _dashboardCardDecoration(theme),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.history_rounded, color: colors.onSurfaceVariant, size: 22),
            const SizedBox(height: 7),
            Text(
              'Your recent tracks, folders and files will appear here.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant),
            ),
            const SizedBox(height: 10),
            TextButton.icon(
              onPressed: () => widget.onOpenExplore(ExploreCategory.music),
              style: TextButton.styleFrom(
                foregroundColor: const Color(0xFF8C9EFF),
                backgroundColor: const Color(0xFF536DFE).withValues(alpha: 0.16),
                padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                shape: const StadiumBorder(),
              ),
              icon: const Icon(Icons.play_arrow_rounded, size: 17),
              label: const Text('Browse media'),
            ),
          ],
        ),
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
            child: Container(
              decoration: _dashboardCardDecoration(theme),
              child: Material(
                color: Colors.transparent,
                borderRadius: BorderRadius.circular(18),
                clipBehavior: Clip.antiAlias,
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
                    NowPlayingOverlayController.open();
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
            ),
          );
        },
      ),
    );
  }

  Widget _buildGlobalSearchEntry(ThemeData theme, ColorScheme colors) {
    return Container(
      decoration: _dashboardCardDecoration(theme),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(18),
        clipBehavior: Clip.antiAlias,
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
              style: theme.textTheme.bodyMedium?.copyWith(color: colors.onSurfaceVariant))),
            Icon(Icons.arrow_forward_rounded, color: colors.onSurfaceVariant, size: 18),
          ]),
          ),
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
        return Container(
          decoration: _dashboardCardDecoration(theme),
          child: Material(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(18),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              borderRadius: BorderRadius.circular(18),
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
                      style: theme.textTheme.labelSmall?.copyWith(color: colors.onSurfaceVariant)),
                  ]),
                  const SizedBox(height: 7),
                  LinearProgressIndicator(value: active[index].progress, minHeight: 4),
                  const SizedBox(height: 4),
                  Text(active[index].total > 0
                      ? '${_formatBytes(active[index].transferred)} of ${_formatBytes(active[index].total)}'
                      : 'Transfer in progress',
                    style: theme.textTheme.labelSmall?.copyWith(color: colors.onSurfaceVariant)),
                ],
              ]),
              ),
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

  Future<void> _updateAutomaticMediaScanning({
    required bool enabled,
    required int intervalMinutes,
    required bool scanOnStartup,
    required bool scanOnStorageChange,
  }) async {
    if (_savingMediaScanSettings || _mediaScanStatus?.isScanning == true) return;
    setState(() => _savingMediaScanSettings = true);
    try {
      await widget.api.updateAutomaticMediaScanning(
        enabled: enabled,
        intervalMinutes: intervalMinutes,
        scanOnStartup: scanOnStartup,
        scanOnStorageChange: scanOnStorageChange,
      );
      final status = await widget.api.mediaIndexStatus();
      if (!mounted) return;
      setState(() { _mediaScanStatus = status; _mediaScanError = null; });
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not update automatic media scanning on the host.')),
      );
    } finally {
      if (mounted) setState(() => _savingMediaScanSettings = false);
    }
  }

  Future<void> _retryFailedMediaScan() async {
    if (_startingMediaScan || _mediaScanStatus?.isScanning == true) return;
    setState(() { _startingMediaScan = true; _mediaScanError = null; });
    try {
      final status = await widget.api.retryFailedMediaScan();
      if (!mounted) return;
      setState(() => _mediaScanStatus = status);
      if (status.isScanning) unawaited(_watchHostMediaScan());
    } catch (_) {
      if (mounted) setState(() => _mediaScanError = 'Could not retry the failed media scan.');
    } finally {
      if (mounted) setState(() => _startingMediaScan = false);
    }
  }

  String _formatScanInterval(int minutes) {
    if (minutes < 60) return '$minutes min';
    if (minutes % 60 == 0) return '${minutes ~/ 60} hr';
    return '${minutes ~/ 60}h ${minutes % 60}m';
  }

  String _formatScanTimestamp(int timestamp, {int? timezoneOffsetMinutes}) {
    if (timestamp <= 0) return 'Not yet scanned';
    final date = timezoneOffsetMinutes == null
        ? DateTime.fromMillisecondsSinceEpoch(timestamp).toLocal()
        : DateTime.fromMillisecondsSinceEpoch(timestamp, isUtc: true)
            .add(Duration(minutes: timezoneOffsetMinutes));
    final hour = date.hour % 12 == 0 ? 12 : date.hour % 12;
    final minute = date.minute.toString().padLeft(2, '0');
    final period = date.hour >= 12 ? 'PM' : 'AM';
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${date.day} ${months[date.month - 1]} ${date.year} · $hour:$minute $period';
  }

  Future<void> _showMediaScanHistory(MediaIndexStatus status) async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Media scan history'),
        content: SizedBox(
          width: 460,
          height: 360,
          child: ListView.separated(
            shrinkWrap: true,
            itemCount: status.scanHistory.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final entry = status.scanHistory[index];
              return ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text('${entry.trigger == 'manual' ? 'Manual' : 'Automatic'} · ${entry.state}'),
                leading: const Icon(Icons.history_rounded, size: 19),
                trailing: entry.runId == null
                    ? null
                    : Tooltip(message: entry.runId!, child: const Icon(Icons.fingerprint_rounded, size: 16)),
                subtitle: Text(
                  '${_formatScanTimestamp(entry.completedAt, timezoneOffsetMinutes: entry.timezoneOffsetMinutes)} · ${(entry.durationMs / 1000).toStringAsFixed(1)}s\n'
                  '${entry.scanned} checked · ${entry.newFiles} new · ${entry.updatedFiles} updated · ${entry.skipped} skipped'
                  '${entry.volumes.isEmpty ? '' : '\nVolumes: ${entry.volumes.map((volume) => '${volume.volume} ${volume.state}').join(' · ')}'}'
                  '${entry.lastError == null ? '' : '\n${entry.lastError}'}'
                  '${entry.skippedItems.isEmpty ? '' : '\n${entry.skippedItems.take(3).map((item) => '${item.volume}/${item.path}: ${item.reason}').join('\n')}'}',
                ),
                isThreeLine: true,
              );
            },
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Close')),
        ],
      ),
    );
  }

  Future<void> _shareMediaScanReport(MediaIndexStatus status) async {
    final lines = <String>[
      'PocketLink Media Library Scan Report',
      'Status: ${status.state}',
      'Scan run ID: ${status.scanRunId ?? 'unavailable'}',
      'Trigger: ${status.scanTrigger}',
      'Started: ${_formatScanTimestamp(status.lastScanStartedAt, timezoneOffsetMinutes: status.timezoneOffsetMinutes)}',
      'Last attempt completed: ${_formatScanTimestamp(status.lastAttemptFinishedAt, timezoneOffsetMinutes: status.timezoneOffsetMinutes)}',
      'Last successful scan: ${_formatScanTimestamp(status.lastSuccessfulAt, timezoneOffsetMinutes: status.timezoneOffsetMinutes)}',
      'Last automatic scan: ${_formatScanTimestamp(status.lastAutomaticScanAt, timezoneOffsetMinutes: status.timezoneOffsetMinutes)}',
      'Last manual scan: ${_formatScanTimestamp(status.lastManualScanAt, timezoneOffsetMinutes: status.timezoneOffsetMinutes)}',
      'Timezone: ${status.timezoneId ?? 'unknown'}',
      'Automatic scanning: ${status.automaticScanning.enabled ? 'enabled' : 'disabled'} · every ${status.automaticScanning.intervalMinutes} minutes',
      'Indexed bytes: ${status.indexedBytes}',
      'Media bytes: ${status.mediaBytes}',
      'Other files: ${status.otherFileCount}',
      'Average successful duration: ${status.averageDurationMs} ms',
      'Duration: ${(status.elapsedMs / 1000).toStringAsFixed(1)} seconds',
      'Checked: ${status.scanned}',
      'New files: ${status.newFiles}',
      'Updated files: ${status.updatedFiles}',
      'Skipped: ${status.skipped}',
      'Indexed file size: ${_formatBytes(status.scannedBytes)}',
      'Media: ${status.mediaCount} (Photos ${status.photoCount}, Videos ${status.videoCount}, Music ${status.musicCount})',
      if (status.lastError?.isNotEmpty == true) 'Error: ${status.lastError}',
      '',
      'Storage sources:',
      ...status.volumes.map((volume) => '${volume.volume}: ${volume.state}, ${volume.scanned} checked, ${volume.skipped} skipped'),
      '',
      'Recent scans:',
      ...status.scanHistory.map((entry) => '${_formatScanTimestamp(entry.completedAt, timezoneOffsetMinutes: entry.timezoneOffsetMinutes)} · ${entry.trigger} · ${entry.state} · ${entry.scanned} checked · ${entry.skipped} skipped'),
      '',
      'Skipped items:',
      ...status.skippedItems.map((item) => '${item.volume}/${item.path}: ${item.reason}'),
    ];
    await SharePlus.instance.share(ShareParams(text: lines.join('\n')));
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
      decoration: _dashboardCardDecoration(theme),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.manage_search_rounded, color: colors.primary, size: 20),
          const SizedBox(width: 9),
          Expanded(child: Text('Host media library', style: theme.textTheme.titleSmall?.copyWith(
            color: colors.onSurface, fontWeight: FontWeight.w800,
          ))),
          Text(scanning ? 'Scanning' : _mediaScanError != null ? 'Unavailable' : status == null ? 'Checking' : status.state == 'failed' ? 'Failed' : status.state == 'interrupted' ? 'Interrupted' : status.state == 'partial' ? 'Partial' : status.state == 'complete' ? 'Up to date' : 'Ready',
            style: theme.textTheme.labelSmall?.copyWith(
              color: scanning || _mediaScanError != null
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
                  : '${status.regularFileCount} files · ${status.mediaCount} media · Last successful ${_formatScanTimestamp(status.lastSuccessfulAt, timezoneOffsetMinutes: status.timezoneOffsetMinutes)}',
          style: theme.textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant),
        ),
        if (_mediaScanError != null) ...[
          const SizedBox(height: 7),
          Text(_mediaScanError!, style: theme.textTheme.bodySmall?.copyWith(color: colors.error)),
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
            '${_formatBytes(status.indexedBytes)} indexed · ${_formatBytes(status.mediaBytes)} media',
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
                ? '${status.state == 'interrupted' ? 'Interrupted' : 'Started'} ${_formatScanTimestamp(status.lastAttemptStartedAt, timezoneOffsetMinutes: status.timezoneOffsetMinutes)} · ${status.scanTrigger == 'manual' ? 'Manual' : 'Automatic'}'
                : 'Last attempt: ${_formatScanTimestamp(status.lastAttemptFinishedAt, timezoneOffsetMinutes: status.timezoneOffsetMinutes)} · ${status.scanTrigger == 'manual' ? 'Manual' : 'Automatic'}',
            style: theme.textTheme.labelSmall?.copyWith(color: colors.onSurfaceVariant),
          ),
          Text(
            'Last successful: ${_formatScanTimestamp(status.lastSuccessfulAt, timezoneOffsetMinutes: status.timezoneOffsetMinutes)}',
            style: theme.textTheme.labelSmall?.copyWith(color: colors.onSurfaceVariant),
          ),
          if (status.lastAutomaticScanAt > 0)
            Text(
              'Last automatic: ${_formatScanTimestamp(status.lastAutomaticScanAt, timezoneOffsetMinutes: status.timezoneOffsetMinutes)}',
              style: theme.textTheme.labelSmall?.copyWith(color: colors.onSurfaceVariant),
            ),
          if (!scanning && status.lastCompletedAt > 0)
            Text(
              'Duration: ${(status.elapsedMs / 1000).toStringAsFixed(1)}s · ${status.newFiles} new · ${status.updatedFiles} updated',
              style: theme.textTheme.labelSmall?.copyWith(color: colors.onSurfaceVariant),
            ),
          if (status.scannedBytes > 0)
            Text(
              '${_formatBytes(status.scannedBytes)} traversed',
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
            ..._volumes.where((volume) => !volume.available).map((volume) => Padding(
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
                onPressed: () => _showMediaScanHistory(status),
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
                  '${_formatScanTimestamp(entry.completedAt, timezoneOffsetMinutes: entry.timezoneOffsetMinutes)} · ${entry.trigger == 'manual' ? 'Manual' : 'Automatic'}',
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
                    onTap: () => _showSkippedItemsInfo(status),
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
                    ? 'Every ${_formatScanInterval(status.automaticScanning.intervalMinutes)} · startup and storage changes'
                    : 'Disabled',
                style: theme.textTheme.labelSmall?.copyWith(color: colors.onSurfaceVariant),
              ),
              if (status.automaticScanning.enabled && status.automaticScanning.nextScanAt > 0)
                Text('Next check: ${_formatScanTimestamp(status.automaticScanning.nextScanAt, timezoneOffsetMinutes: status.timezoneOffsetMinutes)}',
                  style: theme.textTheme.labelSmall?.copyWith(color: colors.onSurfaceVariant)),
            ])),
            Switch.adaptive(
              value: status.automaticScanning.enabled,
              onChanged: scanning || _savingMediaScanSettings ? null : (enabled) =>
                  _updateAutomaticMediaScanning(
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
                onSelected: scanning || _savingMediaScanSettings ? null : (selected) =>
                    _updateAutomaticMediaScanning(
                      enabled: status.automaticScanning.enabled,
                      intervalMinutes: status.automaticScanning.intervalMinutes,
                      scanOnStartup: selected,
                      scanOnStorageChange: status.automaticScanning.scanOnStorageChange,
                    ),
              ),
              FilterChip(
                label: const Text('On storage connect'),
                selected: status.automaticScanning.scanOnStorageChange,
                onSelected: scanning || _savingMediaScanSettings ? null : (selected) =>
                    _updateAutomaticMediaScanning(
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
                onChanged: scanning || _savingMediaScanSettings ? null : (minutes) {
                  if (minutes != null) _updateAutomaticMediaScanning(
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
            onPressed: scanning || _startingMediaScan || _checking || _serverOnline != true
                ? null
                : _startHostMediaScan,
            style: TextButton.styleFrom(
              foregroundColor: const Color(0xFF8C9EFF),
              backgroundColor: const Color(0xFF536DFE).withValues(alpha: 0.16),
              padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              shape: const StadiumBorder(),
            ),
            icon: _startingMediaScan || scanning
                ? const SizedBox(width: 15, height: 15, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.refresh_rounded, size: 17),
            label: Text(scanning ? 'Scanning…' : _startingMediaScan ? 'Starting…' : 'Scan host now'),
          ),
        ),
        if (status != null && (status.state == 'partial' || status.state == 'failed' || status.state == 'interrupted' || status.skipped > 0))
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: scanning || _startingMediaScan || _serverOnline != true ? null : _retryFailedMediaScan,
              icon: const Icon(Icons.replay_rounded, size: 16),
              label: const Text('Retry failed scan'),
            ),
          ),
        if (status != null && status.lastScanStartedAt > 0)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => _shareMediaScanReport(status),
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
      return Container(
        decoration: _dashboardCardDecoration(theme),
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(18),
          clipBehavior: Clip.antiAlias,
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
              padding: const EdgeInsets.only(bottom: 24),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                sectionTitle('Quick actions', action: 'Edit', onAction: _editQuickActions),
                const SizedBox(height: 14),
                if (_quickActions.isEmpty)
                  OutlinedButton.icon(
                    onPressed: _editQuickActions,
                    icon: const Icon(Icons.add_rounded),
                    label: const Text('Add quick actions'),
                  )
                else
                  GridView.count(
                    padding: EdgeInsets.zero,
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
                    decoration: _dashboardCardDecoration(theme, radius: 20),
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
                  Container(
                    decoration: _dashboardCardDecoration(theme, radius: 20),
                    child: Material(
                      color: Colors.transparent,
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
                          trailing: SmokedGlassPopoverMenu<String>(
                            tooltip: 'File actions',
                            items: const [
                              SmokedGlassPopoverMenuItem(value: 'download', label: 'Download', icon: Icons.download_rounded),
                              SmokedGlassPopoverMenuItem(value: 'share', label: 'Share', icon: Icons.ios_share_rounded),
                              SmokedGlassPopoverMenuItem(value: 'rename', label: 'Rename', icon: Icons.drive_file_rename_outline_rounded),
                              SmokedGlassPopoverMenuItem(value: 'delete', label: 'Delete', icon: Icons.delete_outline_rounded, destructive: true, dividerBefore: true),
                            ],
                            onSelected: (action) => _handleRecentAction(_recentFiles[index], action),
                            child: const Padding(
                              padding: EdgeInsets.all(8),
                              child: Icon(Icons.more_vert_rounded, size: 18),
                            ),
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
                  ),
              ]),
            )
          : const SizedBox.shrink(),
    };



    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        automaticallyImplyLeading: false,
        leadingWidth: 70,
        leading: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: SizedBox.square(
              dimension: 38,
              child: GlassCircleButton(
                tooltip: 'Open navigation menu',
                onPressed: widget.onOpenDrawer,
                child: const Icon(Icons.menu_rounded, size: 18),
              ),
            ),
          ),
        ),
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        flexibleSpace: const FeatheredGlassHeaderBackground(),
        titleSpacing: 8,
        title: Transform.translate(
          offset: const Offset(0, 6),
          child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('PocketLink', style: theme.textTheme.titleLarge?.copyWith(
              fontSize: 26,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.5,
            )),
            Text('Your private space', style: theme.textTheme.labelSmall?.copyWith(
              color: colors.onSurfaceVariant,
              fontWeight: FontWeight.w500,
            )),
          ],
          ),
        ),
        actionsPadding: const EdgeInsets.only(right: 16),
        actions: [
          SmokedGlassPopoverMenu<String>(
            tooltip: 'More actions',
            items: [
              SmokedGlassPopoverMenuItem(
                value: 'transfers',
                label: 'Transfers',
                icon: Icons.swap_vert_rounded,
                trailing: AnimatedBuilder(
                  animation: TransferManager.instance,
                  builder: (context, _) {
                    final count = TransferManager.instance.tasks
                        .where((task) => task.status == TransferStatus.running)
                        .length;
                    return count == 0
                        ? const SizedBox.shrink()
                        : Container(
                            constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
                            padding: const EdgeInsets.symmetric(horizontal: 5),
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: const Color(0xFF536DFE),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(count > 9 ? '9+' : '$count',
                              style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w800)),
                          );
                  },
                ),
              ),
              SmokedGlassPopoverMenuItem(
                value: 'refresh',
                label: 'Refresh server status',
                icon: Icons.refresh_rounded,
                enabled: !_checking,
                dividerBefore: true,
              ),
            ],
            onSelected: (value) {
              if (value == 'transfers') {
                Navigator.of(context).push(MaterialPageRoute<void>(
                  builder: (_) => const TransferManagerScreen(),
                ));
              } else if (value == 'refresh') {
                _refreshStatus(forceRefresh: true);
              }
            },
            child: const Padding(
              padding: EdgeInsets.symmetric(vertical: 4),
              child: SizedBox.square(
                dimension: 38,
                child: GlassCircleButton(
                  tooltip: 'Open more actions',
                  onPressed: null,
                  child: Icon(Icons.more_vert_rounded, size: 18),
                ),
              ),
            ),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => _refreshStatus(forceRefresh: true),
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: EdgeInsets.fromLTRB(
            18,
            LayoutInsetsScope.of(context).topClearance + 2,
            18,
            LayoutInsetsScope.of(context).bottomClearance,
          ),
          children: [
            _buildServerTelemetry(),
            const SizedBox(height: 12),
            HostDeviceMetricsCard(
              telemetry: _hostTelemetry,
              telemetryError: _telemetryError,
              serverOnline: _serverOnline == true,
              volumes: _volumes,
              cardDecoration: _dashboardCardDecoration(theme, radius: 20),
              formatBytes: _formatBytes,
            ),
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