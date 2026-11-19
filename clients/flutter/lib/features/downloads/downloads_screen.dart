import 'dart:async';
import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path/path.dart' as p;

import '../../core/network/server_api.dart';
import '../../core/widgets/liquid_glass_pill.dart';
import '../../core/widgets/pocketlink_app_bar.dart';
import '../../core/widgets/smoked_glass_popover_menu.dart';
import 'download_manager_service.dart';
import 'download_task.dart';

enum _DownloadFilter { all, active, completed, failed }

class DownloadsScreen extends StatefulWidget {
  const DownloadsScreen({
    required this.api,
    super.key,
  });

  final ServerApi api;

  @override
  State<DownloadsScreen> createState() => _DownloadsScreenState();
}

class _DownloadsScreenState extends State<DownloadsScreen> {
  final _manager = DownloadManagerService.instance;
  _DownloadFilter _filter = _DownloadFilter.all;

  @override
  void initState() {
    super.initState();
    unawaited(_initialize());
  }

  Future<void> _initialize() async {
    await _manager.initialize();
    _manager.bindServerApi(widget.api);
  }

  Future<void> _newDownload() async {
    await showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _NewDownloadSheet(manager: _manager),
    );
  }

  Future<void> _delete(DownloadTask task) async {
    var alsoDeleteFile = false;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Remove download?'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(task.fileName, maxLines: 2, overflow: TextOverflow.ellipsis),
              const SizedBox(height: 12),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: alsoDeleteFile,
                onChanged: (value) =>
                    setDialogState(() => alsoDeleteFile = value ?? false),
                title: const Text('Also delete downloaded file'),
                controlAffinity: ListTileControlAffinity.leading,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Remove'),
            ),
          ],
        ),
      ),
    );
    if (confirmed == true) {
      await _manager.remove(task.id, deleteFile: alsoDeleteFile);
    }
  }

  List<DownloadTask> _visibleTasks(List<DownloadTask> tasks) {
    return tasks.where((task) => switch (_filter) {
      _DownloadFilter.all => true,
      _DownloadFilter.active => task.status == DownloadStatus.downloading ||
          task.status == DownloadStatus.queued ||
          task.status == DownloadStatus.paused,
      _DownloadFilter.completed => task.status == DownloadStatus.completed,
      _DownloadFilter.failed => task.status == DownloadStatus.failed,
    }).toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _manager,
      builder: (context, _) {
        final tasks = _visibleTasks(_manager.tasks);
        final theme = Theme.of(context);
        final colors = theme.colorScheme;
        final subtitle = _manager.activeCount > 0
            ? '${_formatSpeed(_manager.totalSpeedBytesPerSecond)} · ${_manager.activeCount} active'
            : _manager.queuedCount > 0
                ? '${_manager.queuedCount} queued'
                : 'Manage your downloads';

        return Scaffold(
          extendBodyBehindAppBar: true,
          appBar: PocketLinkAppBar(
            feathered: true,
            showHome: false,
            automaticallyImplyLeading: false,
            title: SmokedGlassPopoverMenu<_DownloadFilter>(
              tooltip: 'Filter downloads',
              items: [
                for (final filter in _DownloadFilter.values)
                  SmokedGlassPopoverMenuItem(
                    value: filter,
                    label: switch (filter) {
                      _DownloadFilter.all => 'All downloads',
                      _DownloadFilter.active => 'Active',
                      _DownloadFilter.completed => 'Completed',
                      _DownloadFilter.failed => 'Failed',
                    },
                    icon: filter == _filter
                        ? Icons.radio_button_checked_rounded
                        : Icons.radio_button_unchecked_rounded,
                  ),
              ],
              onSelected: (value) => setState(() => _filter = value),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Downloads',
                          style: theme.textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.6,
                          ),
                        ),
                        Text(
                          subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: colors.onSurfaceVariant,
                            fontFeatures: const [ui.FontFeature.tabularFigures()],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 4),
                  const Icon(Icons.keyboard_arrow_down_rounded, size: 22),
                ],
              ),
            ),
            actions: [
              PocketLinkAppBarAction(
                label: 'New URL download',
                icon: Icons.add_link_rounded,
                onPressed: _newDownload,
              ),
              PocketLinkAppBarAction(
                label: 'Pause all',
                icon: Icons.pause_rounded,
                enabled: _manager.activeCount > 0 || _manager.queuedCount > 0,
                onPressed: _manager.activeCount > 0 || _manager.queuedCount > 0 ? _manager.pauseAll : null,
              ),
              PocketLinkAppBarAction(
                label: 'Resume all',
                icon: Icons.play_arrow_rounded,
                enabled: _manager.tasks.any((task) =>
                    task.status == DownloadStatus.paused ||
                    task.status == DownloadStatus.failed),
                onPressed: _manager.tasks.any((task) =>
                    task.status == DownloadStatus.paused ||
                    task.status == DownloadStatus.failed)
                    ? _manager.resumeAll
                    : null,
              ),
              PocketLinkAppBarAction(
                label: 'Clear completed',
                icon: Icons.delete_sweep_outlined,
                enabled: _manager.tasks.any(
                    (task) => task.status == DownloadStatus.completed),
                onPressed: _manager.tasks.any(
                    (task) => task.status == DownloadStatus.completed)
                    ? _manager.clearCompleted
                    : null,
                dividerBefore: true,
              ),
            ],
          ),
          body: ListView.builder(
            padding: EdgeInsets.fromLTRB(
              16,
              MediaQuery.paddingOf(context).top + kToolbarHeight + 12,
              16,
              132 + MediaQuery.paddingOf(context).bottom,
            ),
            itemCount: tasks.isEmpty ? 2 : tasks.length + 1,
            itemBuilder: (context, index) {
              if (index == 0) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 14),
                  child: SizedBox(
                    height: 44,
                    child: FilledButton.tonalIcon(
                      onPressed: _newDownload,
                      icon: const Icon(Icons.add_link_rounded),
                      label: const Text('Add URL'),
                      style: FilledButton.styleFrom(
                        alignment: Alignment.center,
                        shape: const StadiumBorder(),
                      ),
                    ),
                  ),
                );
              }
              if (tasks.isEmpty) {
                final hasAnyTasks = _manager.tasks.isNotEmpty;
                return Padding(
                  padding: const EdgeInsets.only(top: 56),
                  child: Column(
                    children: [
                      Icon(
                        hasAnyTasks
                            ? Icons.filter_alt_off_rounded
                            : Icons.download_for_offline_outlined,
                        size: 48,
                        color: colors.onSurfaceVariant.withValues(alpha: 0.65),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        hasAnyTasks ? 'No matching downloads' : 'No downloads yet',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        hasAnyTasks
                            ? 'Try another download filter.'
                            : 'Paste an HTTP or HTTPS link to add your first download.',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                );
              }
              final task = tasks[index - 1];
              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _DownloadTaskCard(
                  task: task,
                  onPause: () => _manager.pause(task.id),
                  onResume: () => _manager.resume(task.id),
                  onOpen: () => _manager.openFile(task),
                  onDelete: () => _delete(task),
                ),
              );
            },
          ),
        );
      },
    );
  }
}

class _DownloadTaskCard extends StatelessWidget {
  const _DownloadTaskCard({
    required this.task,
    required this.onPause,
    required this.onResume,
    required this.onOpen,
    required this.onDelete,
  });

  final DownloadTask task;
  final VoidCallback onPause;
  final VoidCallback onResume;
  final VoidCallback onOpen;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final completed = task.status == DownloadStatus.completed;
    final downloading = task.status == DownloadStatus.downloading;
    final failed = task.status == DownloadStatus.failed;
    final icon = _fileIcon(task.fileName);
    final status = switch (task.status) {
      DownloadStatus.queued => 'Queued',
      DownloadStatus.downloading => 'Downloading',
      DownloadStatus.paused => 'Paused',
      DownloadStatus.completed => 'Completed',
      DownloadStatus.failed => 'Failed',
    };

    return SmokedGlassSurface(
      radius: BorderRadius.circular(20),
      child: DefaultTextStyle.merge(
        style: const TextStyle(color: Colors.white),
        child: IconTheme.merge(
          data: const IconThemeData(color: Colors.white70),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: colors.primary.withValues(alpha: 0.13),
                    borderRadius: BorderRadius.circular(13),
                  ),
                  child: Icon(icon, color: colors.primary, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        task.fileName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        status,
                        style: TextStyle(
                          color: failed
                              ? const Color(0xFFFF7B86)
                              : Colors.white70,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
                if (downloading || task.status == DownloadStatus.queued)
                  IconButton(
                    tooltip: 'Pause',
                    onPressed: onPause,
                    icon: const Icon(Icons.pause_circle_outline_rounded),
                  )
                else if (!completed)
                  IconButton(
                    tooltip: failed ? 'Retry' : 'Resume',
                    onPressed: onResume,
                    icon: Icon(failed
                        ? Icons.refresh_rounded
                        : Icons.play_circle_outline_rounded),
                  )
                else
                  IconButton(
                    tooltip: 'Open file',
                    onPressed: onOpen,
                    icon: const Icon(Icons.open_in_new_rounded),
                  ),
                IconButton(
                  tooltip: 'Delete',
                  onPressed: onDelete,
                  icon: const Icon(Icons.delete_outline_rounded),
                ),
              ],
            ),
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(99),
              child: LinearProgressIndicator(
                minHeight: 5,
                value: task.progress ?? (downloading ? null : 0),
                backgroundColor: colors.onSurface.withValues(alpha: 0.10),
                color: failed ? const Color(0xFFFF7B86) : colors.primary,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${_formatBytes(task.downloadedBytes)} / ${task.totalBytes == null ? '—' : _formatBytes(task.totalBytes!)}',
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 11,
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
                if (downloading)
                  Text(
                    _formatSpeed(task.speedBytesPerSecond),
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 11,
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
                  ),
              ],
            ),
            if (task.errorMessage != null) ...[
              const SizedBox(height: 7),
              Text(
                task.errorMessage!,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Color(0xFFFF7B86), fontSize: 11),
              ),
            ],
          ],
            ),
          ),
        ),
      ),
    );
  }
}

class _NewDownloadSheet extends StatefulWidget {
  const _NewDownloadSheet({required this.manager});

  final DownloadManagerService manager;

  @override
  State<_NewDownloadSheet> createState() => _NewDownloadSheetState();
}

class _NewDownloadSheetState extends State<_NewDownloadSheet> {
  final _urlController = TextEditingController();
  ResolvedDownload? _resolved;
  String? _directory;
  String? _error;
  bool _resolving = false;
  bool _starting = false;

  @override
  void initState() {
    super.initState();
    unawaited(_loadClipboard());
    unawaited(_loadDirectory());
  }

  Future<void> _loadClipboard() async {
    try {
      final data = await Clipboard.getData(Clipboard.kTextPlain);
      final value = data?.text?.trim() ?? '';
      final uri = Uri.tryParse(value);
      if (mounted &&
          _urlController.text.isEmpty &&
          uri != null &&
          const {'http', 'https'}.contains(uri.scheme)) {
        _urlController.text = value;
      }
    } catch (_) {
      // Clipboard access is optional.
    }
  }

  Future<void> _loadDirectory() async {
    final directory = await widget.manager.defaultDirectory();
    if (mounted) setState(() => _directory = directory);
  }

  Future<void> _resolve() async {
    if (_resolving) return;
    setState(() {
      _resolving = true;
      _error = null;
      _resolved = null;
    });
    try {
      final result = await widget.manager.resolveUrl(_urlController.text);
      if (mounted) setState(() => _resolved = result);
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _resolving = false);
    }
  }

  Future<void> _chooseDirectory() async {
    final selected = await FilePicker.getDirectoryPath(
      initialDirectory: _directory,
    );
    if (selected != null && mounted) setState(() => _directory = selected);
  }

  Future<void> _start() async {
    final resolved = _resolved;
    if (resolved == null || _starting) return;
    setState(() => _starting = true);
    try {
      await widget.manager.enqueueUrl(
        resolved,
        directoryPath: _directory,
      );
      if (mounted) Navigator.of(context).pop();
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _starting = false);
    }
  }

  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return AnimatedPadding(
      duration: const Duration(milliseconds: 180),
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        top: false,
        child: Container(
          decoration: BoxDecoration(
            color: colors.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
            border: Border.all(color: colors.outlineVariant.withValues(alpha: 0.5)),
          ),
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 38,
                  height: 4,
                  decoration: BoxDecoration(
                    color: colors.onSurface.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Text('New download', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 14),
              TextField(
                controller: _urlController,
                keyboardType: TextInputType.url,
                textInputAction: TextInputAction.done,
                decoration: const InputDecoration(
                  labelText: 'HTTP or HTTPS URL',
                  hintText: 'https://example.com/file.zip',
                  border: OutlineInputBorder(),
                ),
                onSubmitted: (_) => _resolve(),
                onChanged: (_) => setState(() {
                  _resolved = null;
                  _error = null;
                }),
              ),
              const SizedBox(height: 10),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: _resolving ? null : _resolve,
                  icon: _resolving
                      ? const SizedBox.square(
                          dimension: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.link_rounded),
                  label: const Text('Resolve link'),
                ),
              ),
              if (_resolved != null) ...[
                SmokedGlassSurface(
                  radius: BorderRadius.circular(16),
                  child: DefaultTextStyle.merge(
                    style: const TextStyle(color: Colors.white),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Row(
                      children: [
                        const Icon(Icons.insert_drive_file_outlined),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(_resolved!.fileName,
                                  maxLines: 1, overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontWeight: FontWeight.w700)),
                              const SizedBox(height: 3),
                              Text(
                                _resolved!.totalBytes == null
                                    ? 'File size unavailable'
                                    : _formatBytes(_resolved!.totalBytes!),
                                style: TextStyle(
                                  color: colors.onSurfaceVariant,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.folder_outlined),
                  title: const Text('Save location'),
                  subtitle: Text(
                    _directory ?? 'Loading download folder…',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: TextButton(
                    onPressed: _chooseDirectory,
                    child: const Text('Change'),
                  ),
                ),
              ],
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(_error!, style: TextStyle(color: colors.error)),
              ],
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _resolved == null || _starting ? null : _start,
                  child: _starting
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Start download'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

String _formatBytes(int bytes) {
  if (bytes < 1024) return '${bytes} B';
  const units = ['KB', 'MB', 'GB', 'TB'];
  var value = bytes / 1024;
  var unit = 0;
  while (value >= 1024 && unit < units.length - 1) {
    value /= 1024;
    unit++;
  }
  return '${value.toStringAsFixed(1)} ${units[unit]}';
}

String _formatSpeed(int bytesPerSecond) =>
    '${_formatBytes(bytesPerSecond)}/s';

IconData _fileIcon(String name) {
  final extension = p.extension(name).toLowerCase();
  if ({'.zip', '.7z', '.rar', '.tar', '.gz'}.contains(extension)) {
    return Icons.folder_zip_outlined;
  }
  if ({'.jpg', '.jpeg', '.png', '.webp', '.gif', '.heic'}.contains(extension)) {
    return Icons.image_outlined;
  }
  if ({'.mp4', '.mkv', '.mov', '.avi', '.webm'}.contains(extension)) {
    return Icons.video_file_outlined;
  }
  if ({'.mp3', '.m4a', '.aac', '.flac', '.wav', '.ogg', '.opus'}.contains(extension)) {
    return Icons.audio_file_outlined;
  }
  if ({'.pdf', '.doc', '.docx', '.xls', '.xlsx', '.ppt', '.pptx', '.txt'}.contains(extension)) {
    return Icons.description_outlined;
  }
  return Icons.insert_drive_file_outlined;
}
