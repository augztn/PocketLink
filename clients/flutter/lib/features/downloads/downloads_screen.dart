import 'dart:async';
import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path/path.dart' as p;

import '../../core/network/server_api.dart';
import '../../core/widgets/liquid_glass_pill.dart';
import '../../core/widgets/pocketlink_app_bar.dart';
import '../../core/widgets/pocketlink_scaffold.dart';
import 'download_manager_service.dart';
import 'download_task.dart';

enum _DownloadFilter { all, active, completed, failed }
enum _DownloadScope { server, local, all }

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
  _DownloadScope _scope = _DownloadScope.server;
  List<ServerDownloadJob> _serverJobs = const [];
  Timer? _serverRefreshTimer;
  bool _refreshingServerJobs = false;

  @override
  void initState() {
    super.initState();
    unawaited(_initialize());
  }

  Future<void> _initialize() async {
    await _manager.initialize();
    _manager.bindServerApi(widget.api);
    await _refreshServerJobs();
    if (!mounted) return;
    _serverRefreshTimer = Timer.periodic(const Duration(seconds: 2), (_) => _refreshServerJobs());
  }

  Future<void> _refreshServerJobs() async {
    if (_refreshingServerJobs) return;
    _refreshingServerJobs = true;
    try {
      final jobs = await widget.api.listServerDownloads();
      if (mounted) setState(() => _serverJobs = jobs);
    } catch (_) {
      // Preserve the last host snapshot during a temporary disconnect.
    } finally {
      _refreshingServerJobs = false;
    }
  }

  Future<void> _newDownload() async {
    await showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _NewDownloadSheet(manager: _manager, api: widget.api),
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

  List<ServerDownloadJob> _visibleServerJobs(List<ServerDownloadJob> jobs) {
    return jobs.where((job) => switch (_filter) {
      _DownloadFilter.all => true,
      _DownloadFilter.active => job.status == 'downloading' || job.status == 'queued' || job.status == 'paused',
      _DownloadFilter.completed => job.status == 'completed',
      _DownloadFilter.failed => job.status == 'failed',
    }).toList(growable: false);
  }

  Future<void> _serverAction(Future<ServerDownloadJob> Function() action) async {
    try {
      await action();
      await _refreshServerJobs();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Server download action failed: ' + error.toString())),
        );
      }
    }
  }


  Future<void> _serverBulkAction({required bool pause}) async {
    final candidates = _serverJobs.where((job) => pause
        ? job.status == 'downloading' || job.status == 'queued'
        : job.status == 'paused' || job.status == 'failed').toList();
    for (final job in candidates) {
      try {
        if (pause) {
          await widget.api.pauseServerDownload(job.id);
        } else {
          await widget.api.resumeServerDownload(job.id);
        }
      } catch (_) {
        // Continue the remaining jobs; the refreshed list exposes failures.
      }
    }
    await _refreshServerJobs();
  }

  Future<void> _removeServerJob(ServerDownloadJob job) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Remove server download?'),
        content: Text(job.fileName + '\nThe downloaded file will remain in server storage.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Remove')),
        ],
      ),
    );
    if (confirmed == true) {
      try {
        await widget.api.removeServerDownload(job.id);
        await _refreshServerJobs();
      } catch (error) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Could not remove server download: ' + error.toString())),
          );
        }
      }
    }
  }

  @override
  void dispose() {
    _serverRefreshTimer?.cancel();
    super.dispose();
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
        final allLocalTasks = _manager.tasks;
        final allServerJobs = _serverJobs;
        final tasks = _visibleTasks(allLocalTasks).where((task) =>
            _scope != _DownloadScope.server).toList(growable: false);
        final serverJobs = _visibleServerJobs(allServerJobs).where((job) =>
            _scope != _DownloadScope.local).toList(growable: false);
        final theme = Theme.of(context);
        final colors = theme.colorScheme;
        final activeServer = allServerJobs.where((job) => job.status == 'downloading').length;
        final queuedServer = allServerJobs.where((job) => job.status == 'queued').length;
        final completedServer = allServerJobs.where((job) => job.status == 'completed').length;
        final activeLocal = _manager.activeCount;
        final queuedLocal = _manager.queuedCount;
        final subtitle = activeServer + activeLocal > 0
            ? '${activeServer + activeLocal} active · ${_formatSpeed(allServerJobs.where((j) => j.status == 'downloading').fold<int>(0, (sum, j) => sum + j.speedBytesPerSecond) + _manager.totalSpeedBytesPerSecond)}'
            : 'Server downloads to your host storage';

        return Scaffold(
          extendBodyBehindAppBar: true,
          appBar: PocketLinkAppBar(
            feathered: true,
            showHome: false,
            automaticallyImplyLeading: false,
            leading: IconButton(
              tooltip: 'Back',
              onPressed: () => Navigator.of(context).maybePop(),
              icon: const Icon(Icons.arrow_back_rounded),
            ),
            leadingWidth: 56,
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Downloads', style: theme.textTheme.titleLarge?.copyWith(
                  fontSize: 26, fontWeight: FontWeight.w700, letterSpacing: -0.5,
                )),
                Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelSmall?.copyWith(color: colors.onSurfaceVariant)),
              ],
            ),
            actions: [
              PocketLinkAppBarAction(
                label: 'New URL download',
                icon: Icons.add_link_rounded,
                onPressed: _newDownload,
              ),
              if (_scope == _DownloadScope.server)
                PocketLinkAppBarAction(
                  label: 'Pause server downloads',
                  icon: Icons.pause_rounded,
                  enabled: activeServer + queuedServer > 0,
                  onPressed: activeServer + queuedServer > 0
                      ? () => _serverBulkAction(pause: true) : null,
                ),
              if (_scope == _DownloadScope.server)
                PocketLinkAppBarAction(
                  label: 'Resume server downloads',
                  icon: Icons.play_arrow_rounded,
                  enabled: allServerJobs.any((j) => j.status == 'paused' || j.status == 'failed'),
                  onPressed: allServerJobs.any((j) => j.status == 'paused' || j.status == 'failed')
                      ? () => _serverBulkAction(pause: false) : null,
                ),
              if (_scope == _DownloadScope.local)
                PocketLinkAppBarAction(
                  label: 'Pause local downloads',
                  icon: Icons.pause_circle_outline_rounded,
                  enabled: activeLocal > 0 || queuedLocal > 0,
                  onPressed: activeLocal > 0 || queuedLocal > 0 ? _manager.pauseAll : null,
                ),
              if (_scope == _DownloadScope.local)
                PocketLinkAppBarAction(
                  label: 'Resume local downloads',
                  icon: Icons.play_circle_outline_rounded,
                  enabled: allLocalTasks.any((task) => task.status == DownloadStatus.paused || task.status == DownloadStatus.failed),
                  onPressed: allLocalTasks.any((task) => task.status == DownloadStatus.paused || task.status == DownloadStatus.failed)
                      ? _manager.resumeAll : null,
                ),
              if (_scope == _DownloadScope.local)
                PocketLinkAppBarAction(
                  label: 'Clear completed local downloads',
                  icon: Icons.delete_sweep_outlined,
                  enabled: allLocalTasks.any((task) => task.status == DownloadStatus.completed),
                  onPressed: allLocalTasks.any((task) => task.status == DownloadStatus.completed)
                      ? _manager.clearCompleted : null,
                  dividerBefore: true,
                ),
            ],
          ),
          body: ListView(
            padding: EdgeInsets.fromLTRB(
              16,
              LayoutInsetsScope.of(context).topClearance + 2,
              16,
              LayoutInsetsScope.of(context).bottomClearance,
            ),
            children: [
              _DownloadsOverview(
                serverActive: activeServer,
                serverQueued: queuedServer,
                serverCompleted: completedServer,
                localActive: activeLocal,
                localQueued: queuedLocal,
                localCompleted: allLocalTasks.where((t) => t.status == DownloadStatus.completed).length,
                scope: _scope,
                onScopeChanged: (scope) => setState(() => _scope = scope),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(child: Text(
                    _scope == _DownloadScope.server ? 'Server transfers'
                        : _scope == _DownloadScope.local ? 'Local downloads' : 'All downloads',
                    style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                  )),
                  PopupMenuButton<_DownloadFilter>(
                    tooltip: 'Filter downloads',
                    initialValue: _filter,
                    onSelected: (value) => setState(() => _filter = value),
                    itemBuilder: (_) => [
                      for (final filter in _DownloadFilter.values)
                        PopupMenuItem(
                          value: filter,
                          child: Text(switch (filter) {
                            _DownloadFilter.all => 'All statuses',
                            _DownloadFilter.active => 'Active',
                            _DownloadFilter.completed => 'Completed',
                            _DownloadFilter.failed => 'Failed',
                          }),
                        ),
                    ],
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        const Icon(Icons.filter_list_rounded, size: 18),
                        const SizedBox(width: 5),
                        Text(switch (_filter) {
                          _DownloadFilter.all => 'All',
                          _DownloadFilter.active => 'Active',
                          _DownloadFilter.completed => 'Completed',
                          _DownloadFilter.failed => 'Failed',
                        }),
                        const Icon(Icons.arrow_drop_down_rounded),
                      ]),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              if (serverJobs.isNotEmpty) ...[
                if (_scope == _DownloadScope.all)
                  const _DownloadSectionLabel(title: 'Server', icon: Icons.cloud_download_outlined),
                for (var i = 0; i < serverJobs.length; i++)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: _ServerDownloadJobCard(
                      job: serverJobs[i],
                      queuePosition: _serverQueuePosition(serverJobs[i], allServerJobs),
                      onPause: () => _serverAction(() => widget.api.pauseServerDownload(serverJobs[i].id)),
                      onResume: () => _serverAction(() => widget.api.resumeServerDownload(serverJobs[i].id)),
                      onCancel: () => _serverAction(() => widget.api.cancelServerDownload(serverJobs[i].id)),
                      onRemove: () => _removeServerJob(serverJobs[i]),
                    ),
                  ),
              ],
              if (tasks.isNotEmpty) ...[
                if (_scope == _DownloadScope.all)
                  const _DownloadSectionLabel(title: 'Local', icon: Icons.phone_android_rounded),
                for (final task in tasks)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: _DownloadTaskCard(
                      task: task,
                      onPause: () => _manager.pause(task.id),
                      onResume: () => _manager.resume(task.id),
                      onOpen: () => _manager.openFile(task),
                      onDelete: () => _delete(task),
                    ),
                  ),
              ],
              if (serverJobs.isEmpty && tasks.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 56, bottom: 40),
                  child: Column(
                    children: [
                      Icon(
                        allLocalTasks.isEmpty && allServerJobs.isEmpty
                            ? Icons.download_for_offline_outlined : Icons.filter_alt_off_rounded,
                        size: 48, color: colors.onSurfaceVariant.withValues(alpha: 0.65),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        allLocalTasks.isEmpty && allServerJobs.isEmpty
                            ? 'No downloads yet' : 'No matching downloads',
                        style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        allLocalTasks.isEmpty && allServerJobs.isEmpty
                            ? 'Add a URL and choose Server to download directly to host storage.'
                            : 'Try another destination or status filter.',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant),
                      ),
                      const SizedBox(height: 16),
                      OutlinedButton.icon(
                        onPressed: _newDownload,
                        icon: const Icon(Icons.add_link_rounded),
                        label: const Text('Add URL'),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

}

class _DownloadsOverview extends StatelessWidget {
  const _DownloadsOverview({
    required this.serverActive,
    required this.serverQueued,
    required this.serverCompleted,
    required this.localActive,
    required this.localQueued,
    required this.localCompleted,
    required this.scope,
    required this.onScopeChanged,
  });

  final int serverActive, serverQueued, serverCompleted;
  final int localActive, localQueued, localCompleted;
  final _DownloadScope scope;
  final ValueChanged<_DownloadScope> onScopeChanged;

  @override
  Widget build(BuildContext context) {
    final server = scope != _DownloadScope.local;
    final local = scope != _DownloadScope.server;
    final active = (server ? serverActive : 0) + (local ? localActive : 0);
    final queued = (server ? serverQueued : 0) + (local ? localQueued : 0);
    final completed = (server ? serverCompleted : 0) + (local ? localCompleted : 0);
    final colors = Theme.of(context).colorScheme;
    Widget metric(String value, String label) => Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
        decoration: BoxDecoration(
          color: colors.surfaceContainerHighest.withValues(alpha: 0.45),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(value, style: Theme.of(context).textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w700, fontFeatures: const [ui.FontFeature.tabularFigures()],
          )),
          const SizedBox(height: 2),
          Text(label, style: Theme.of(context).textTheme.labelSmall?.copyWith(color: colors.onSurfaceVariant)),
        ]),
      ),
    );

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        _scopeChip(context, _DownloadScope.server, 'Server', Icons.cloud_download_outlined),
        const SizedBox(width: 8),
        _scopeChip(context, _DownloadScope.local, 'Local', Icons.phone_android_rounded),
        const SizedBox(width: 8),
        _scopeChip(context, _DownloadScope.all, 'All', Icons.swap_vert_rounded),
      ]),
      const SizedBox(height: 12),
      Row(children: [
        metric('$active', 'Active'),
        const SizedBox(width: 8),
        metric('$queued', 'Queued'),
        const SizedBox(width: 8),
        metric('$completed', 'Completed'),
      ]),
    ]);
  }

  Widget _scopeChip(BuildContext context, _DownloadScope value, String label, IconData icon) {
    final selected = scope == value;
    final colors = Theme.of(context).colorScheme;
    return Expanded(
      child: Material(
        color: selected ? colors.primaryContainer : colors.surfaceContainerHighest.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(13),
        child: InkWell(
          borderRadius: BorderRadius.circular(13),
          onTap: () => onScopeChanged(value),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(icon, size: 16, color: selected ? colors.onPrimaryContainer : colors.onSurfaceVariant),
              const SizedBox(width: 5),
              Text(label, style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: selected ? colors.onPrimaryContainer : colors.onSurfaceVariant,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              )),
            ]),
          ),
        ),
      ),
    );
  }
}

class _DownloadSectionLabel extends StatelessWidget {
  const _DownloadSectionLabel({required this.title, required this.icon});
  final String title;
  final IconData icon;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(2, 8, 2, 10),
    child: Row(children: [
      Icon(icon, size: 17, color: Theme.of(context).colorScheme.onSurfaceVariant),
      const SizedBox(width: 7),
      Text(title, style: Theme.of(context).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700)),
    ]),
  );
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

  Widget _glassActionButton({
    required String tooltip,
    required IconData icon,
    required VoidCallback onPressed,
  }) {
    return SizedBox.square(
      dimension: 36,
      child: SmokedGlassSurface(
        radius: BorderRadius.circular(18),
        child: IconButton(
          tooltip: tooltip,
          onPressed: onPressed,
          padding: EdgeInsets.zero,
          iconSize: 18,
          constraints: const BoxConstraints.tightFor(width: 36, height: 36),
          style: IconButton.styleFrom(
            foregroundColor: Colors.white,
            shape: const CircleBorder(),
            backgroundColor: Colors.white.withValues(alpha: 0.035),
          ),
          icon: Icon(icon),
        ),
      ),
    );
  }

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
                        'LOCAL · ' + status,
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
                  _glassActionButton(
                    tooltip: 'Pause',
                    icon: Icons.pause_rounded,
                    onPressed: onPause,
                  )
                else if (!completed)
                  _glassActionButton(
                    tooltip: failed ? 'Retry' : 'Resume',
                    icon: failed ? Icons.refresh_rounded : Icons.play_arrow_rounded,
                    onPressed: onResume,
                  )
                else
                  _glassActionButton(
                    tooltip: 'Open file',
                    icon: Icons.open_in_new_rounded,
                    onPressed: onOpen,
                  ),
                _glassActionButton(
                  tooltip: 'Delete',
                  icon: Icons.delete_outline_rounded,
                  onPressed: onDelete,
                ),
              ],
            ),
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(99),
              child: LinearProgressIndicator(
                minHeight: 5,
                value: task.progress ?? (downloading ? null : 0),
                backgroundColor: Colors.white.withValues(alpha: 0.14),
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
                      fontFeatures: [ui.FontFeature.tabularFigures()],
                    ),
                  ),
                ),
                if (downloading)
                  Text(
                    _formatSpeed(task.speedBytesPerSecond),
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 11,
                      fontFeatures: [ui.FontFeature.tabularFigures()],
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


class _ServerDownloadJobCard extends StatelessWidget {
  const _ServerDownloadJobCard({
    required this.job,
    required this.onPause,
    required this.onResume,
    required this.onCancel,
    required this.onRemove,
    this.queuePosition,
  });

  final ServerDownloadJob job;
  final VoidCallback onPause;
  final VoidCallback onResume;
  final VoidCallback onCancel;
  final VoidCallback onRemove;
  final int? queuePosition;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final progress = job.progress;
    final downloading = job.status == 'downloading';
    final canPause = downloading || job.status == 'queued';
    final completed = job.status == 'completed';
    final failed = job.status == 'failed';
    final cancelled = job.status == 'cancelled';
    final status = switch (job.status) {
      'queued' => 'Queued on host',
      'downloading' => 'Downloading on host',
      'paused' => 'Paused',
      'completed' => 'Saved to host',
      'cancelled' => 'Cancelled',
      _ => 'Download failed',
    };
    final host = Uri.tryParse(job.url)?.host;
    final eta = job.estimatedRemaining == null
        ? null
        : _formatEta(job.estimatedRemaining!.inSeconds);

    return SmokedGlassSurface(
      radius: BorderRadius.circular(20),
      child: Padding(
        padding: const EdgeInsets.all(15),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(
              width: 42, height: 42,
              decoration: BoxDecoration(
                color: colors.primary.withValues(alpha: 0.13),
                borderRadius: BorderRadius.circular(13),
              ),
              child: Icon(_fileIcon(job.fileName), color: colors.primary, size: 22),
            ),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(job.fileName, maxLines: 1, overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 14)),
              const SizedBox(height: 3),
              Text(status, style: TextStyle(
                color: completed ? const Color(0xFF8BE0B0) : failed ? colors.error : Colors.white70,
                fontSize: 11,
              )),
            ])),
            PopupMenuButton<String>(
              tooltip: 'Download actions',
              icon: const Icon(Icons.more_vert_rounded, color: Colors.white70),
              onSelected: (value) {
                if (value == 'pause') onPause();
                if (value == 'resume') onResume();
                if (value == 'cancel') onCancel();
                if (value == 'remove') onRemove();
              },
              itemBuilder: (_) => [
                if (canPause) const PopupMenuItem(value: 'pause', child: Text('Pause')),
                if (!canPause && !completed && !cancelled)
                  PopupMenuItem(value: 'resume', child: Text(failed ? 'Retry download' : 'Resume')),
                if (!completed && !cancelled)
                  const PopupMenuItem(value: 'cancel', child: Text('Cancel')),
                const PopupMenuDivider(),
                const PopupMenuItem(value: 'remove', child: Text('Remove from history')),
              ],
            ),
          ]),
          const SizedBox(height: 13),
          ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: LinearProgressIndicator(
              value: progress ?? (downloading ? null : completed ? 1 : 0),
              minHeight: 5,
              backgroundColor: Colors.white.withValues(alpha: 0.10),
            ),
          ),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(child: Text(
              job.totalBytes == null
                  ? _formatBytes(job.downloadedBytes)
                  : '${_formatBytes(job.downloadedBytes)} / ${_formatBytes(job.totalBytes!)}',
              style: const TextStyle(color: Colors.white70, fontSize: 11),
            )),
            if (downloading && job.speedBytesPerSecond > 0)
              Text(_formatSpeed(job.speedBytesPerSecond),
                style: const TextStyle(color: Colors.white70, fontSize: 11)),
            if (progress != null) ...[
              const SizedBox(width: 9),
              Text('${(progress * 100).round()}%',
                style: const TextStyle(color: Colors.white70, fontSize: 11)),
            ],
          ]),
          if (downloading && eta != null) ...[
            const SizedBox(height: 6),
            Text('About $eta remaining', style: const TextStyle(color: Colors.white54, fontSize: 11)),
          ],
          if (queuePosition != null) ...[
            const SizedBox(height: 6),
            Text('Queue position $queuePosition', style: const TextStyle(color: Colors.white54, fontSize: 11)),
          ],
          if (host != null && host.isNotEmpty) ...[
            const SizedBox(height: 8),
            Row(children: [
              const Icon(Icons.link_rounded, size: 13, color: Colors.white54),
              const SizedBox(width: 5),
              Expanded(child: Text(host, maxLines: 1, overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white54, fontSize: 11))),
            ]),
          ],
          if (job.destinationPath != null) ...[
            const SizedBox(height: 6),
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Icon(Icons.folder_outlined, size: 13, color: Colors.white54),
              const SizedBox(width: 5),
              Expanded(child: Text(job.destinationPath!, maxLines: 2, overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white54, fontSize: 11))),
            ]),
          ],
          if (job.error != null) ...[
            const SizedBox(height: 8),
            Text(job.error!, style: TextStyle(color: colors.error, fontSize: 12)),
          ],
        ]),
      ),
    );
  }
}

int? _serverQueuePosition(ServerDownloadJob job, List<ServerDownloadJob> jobs) {
  if (job.status != 'queued') return null;
  final queued = jobs.where((item) => item.status == 'queued').toList()
    ..sort((a, b) {
      final byCreated = a.createdAt.compareTo(b.createdAt);
      return byCreated != 0 ? byCreated : a.id.compareTo(b.id);
    });
  final index = queued.indexWhere((item) => item.id == job.id);
  return index < 0 ? null : index + 1;
}

String _formatEta(int seconds) {
  if (seconds < 60) return '$seconds sec';
  final duration = Duration(seconds: seconds);
  if (duration.inHours > 0) {
    final minutes = duration.inMinutes.remainder(60);
    return minutes == 0 ? '${duration.inHours} hr' : '${duration.inHours} hr $minutes min';
  }
  return '${duration.inMinutes} min';
}

class _NewDownloadSheet extends StatefulWidget {
  const _NewDownloadSheet({required this.manager, required this.api});

  final DownloadManagerService manager;
  final ServerApi api;

  @override
  State<_NewDownloadSheet> createState() => _NewDownloadSheetState();
}

class _NewDownloadSheetState extends State<_NewDownloadSheet> {
  final _urlController = TextEditingController();
  final _fileNameController = TextEditingController();
  final _serverDirectoryController = TextEditingController();
  ResolvedDownload? _resolved;
  String _destination = 'local';
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
    if (_resolving || _destination == 'server') return;
    setState(() {
      _resolving = true;
      _error = null;
      _resolved = null;
    });
    try {
      final result = await widget.manager.resolveUrl(_urlController.text);
      if (mounted) {
        setState(() {
          _resolved = result;
          if (_fileNameController.text.trim().isEmpty) {
            _fileNameController.text = result.fileName;
          }
        });
      }
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


  Future<void> _chooseServerDirectory() async {
    var path = _serverDirectoryController.text.trim().replaceAll('\\', '/');
    var folders = <FileEntry>[];
    String? error;
    var loading = false;
    try {
      final listing = await widget.api.listDirectory(path);
      folders = listing.items.where((item) => item.isDirectory).toList()
        ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    } catch (value) {
      error = value.toString();
    }
    if (!mounted) return;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          Future<void> navigate(String nextPath) async {
            setDialogState(() {
              path = nextPath;
              loading = true;
              error = null;
            });
            try {
              final listing = await widget.api.listDirectory(nextPath);
              if (!dialogContext.mounted) return;
              setDialogState(() {
                folders = listing.items.where((item) => item.isDirectory).toList()
                  ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
                loading = false;
              });
            } catch (value) {
              if (!dialogContext.mounted) return;
              setDialogState(() {
                error = value.toString();
                loading = false;
              });
            }
          }

          final parentIndex = path.lastIndexOf('/');
          final parent = parentIndex < 0 ? '' : path.substring(0, parentIndex);
          return AlertDialog(
            title: const Text('Choose server folder'),
            content: SizedBox(
              width: 420,
              height: 360,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    IconButton(
                      tooltip: 'Parent folder',
                      onPressed: path.isEmpty || loading ? null : () => navigate(parent),
                      icon: const Icon(Icons.arrow_upward_rounded),
                    ),
                    Expanded(
                      child: Text(
                        path.isEmpty ? 'Shared storage root' : path,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                  ]),
                  const Divider(height: 1),
                  Expanded(
                    child: loading
                        ? const Center(child: CircularProgressIndicator())
                        : error != null
                            ? Center(child: Text(error!, textAlign: TextAlign.center))
                            : folders.isEmpty
                                ? const Center(child: Text('No subfolders here'))
                                : ListView.builder(
                                    itemCount: folders.length,
                                    itemBuilder: (context, index) {
                                      final folder = folders[index];
                                      return ListTile(
                                        dense: true,
                                        leading: const Icon(Icons.folder_outlined),
                                        title: Text(folder.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                                        trailing: const Icon(Icons.chevron_right_rounded),
                                        onTap: () => navigate(path.isEmpty
                                            ? folder.name : '$path/${folder.name}'),
                                      );
                                    },
                                  ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: error != null || loading
                    ? null
                    : () {
                        _serverDirectoryController.text = path;
                        Navigator.pop(dialogContext);
                      },
                child: const Text('Use folder'),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _start() async {
    final resolved = _resolved;
    if (_starting || (_destination == 'local' && resolved == null) ||
        _urlController.text.trim().isEmpty) return;
    setState(() => _starting = true);
    try {
      if (_destination == 'server') {
        await widget.api.enqueueServerDownload(
          _urlController.text.trim(),
          directory: _serverDirectoryController.text.trim(),
          fileName: _fileNameController.text.trim(),
        );
      } else {
        await widget.manager.enqueueUrl(
          resolved!,
          directoryPath: _directory,
          fileName: _fileNameController.text.trim(),
        );
      }
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
    _fileNameController.dispose();
    _serverDirectoryController.dispose();
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
              Row(
                children: [
                  Expanded(
                    child: ChoiceChip(
                      label: const Text('Local'),
                      selected: _destination == 'local',
                      onSelected: (_) => setState(() {
                        _destination = 'local';
                        _resolved = null;
                        _error = null;
                      }),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ChoiceChip(
                      label: const Text('Server'),
                      selected: _destination == 'server',
                      onSelected: (_) => setState(() {
                        _destination = 'server';
                        _resolved = null;
                        _error = null;
                      }),
                    ),
                  ),
                ],
              ),
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
                onSubmitted: (_) {
                  if (_destination == 'local') {
                    _resolve();
                  } else {
                    _start();
                  }
                },
                onChanged: (_) => setState(() {
                  _resolved = null;
                  _fileNameController.clear();
                  _error = null;
                }),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _fileNameController,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                  labelText: 'File name (optional)',
                  hintText: 'Leave blank to detect automatically',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 10),
              if (_destination == 'local')
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    onPressed: _resolving ? null : _resolve,
                    icon: _resolving
                        ? const SizedBox.square(dimension: 16, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.link_rounded),
                    label: const Text('Resolve link'),
                  ),
                )
              else
                const Padding(
                  padding: EdgeInsets.only(top: 10),
                  child: Text('The host fetches this URL directly and continues when this screen is closed.'),
                ),
              if (_destination == 'server') ...[
                const SizedBox(height: 8),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _serverDirectoryController,
                        decoration: const InputDecoration(
                          labelText: 'Server destination folder',
                          hintText: 'Default: Downloads/PocketLink',
                          helperText: 'Leave blank for automatic folders. Paths are relative to shared storage.',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    IconButton.filledTonal(
                      tooltip: 'Browse server folders',
                      onPressed: _starting ? null : _chooseServerDirectory,
                      icon: const Icon(Icons.folder_open_rounded),
                    ),
                  ],
                ),
              ],
              if (_destination == 'local' && _resolved != null) ...[
                SmokedGlassSurface(
                  radius: BorderRadius.circular(16),
                  child: DefaultTextStyle.merge(
                    style: const TextStyle(color: Colors.white),
                    child: IconTheme.merge(
                      data: const IconThemeData(color: Colors.white70),
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
                                  color: Colors.white70,
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
                  onPressed: _starting || _urlController.text.trim().isEmpty ||
                          (_destination == 'local' && _resolved == null)
                      ? null
                      : _start,
                  child: _starting
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(_destination == 'server' ? 'Download to server' : 'Start local download'),
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
