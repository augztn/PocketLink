import 'package:material_ui/material_ui.dart';
import '../../core/widgets/pocketlink_app_bar.dart';

import 'transfer_manager.dart';

class TransferManagerScreen extends StatelessWidget {
  const TransferManagerScreen({super.key});

  String _size(int bytes) {
    if (bytes < 1024) return '$bytes B';
    const units = ['KB', 'MB', 'GB', 'TB'];
    var value = bytes / 1024;
    var index = 0;
    while (value >= 1024 && index < units.length - 1) {
      value /= 1024;
      index++;
    }
    return '${value.toStringAsFixed(1)} ${units[index]}';
  }

  String _status(TransferTask task) => switch (task.status) {
    TransferStatus.running => task.cancelToken.isCancelled ? 'Cancelling' : 'Transferring',
    TransferStatus.completed => 'Completed',
    TransferStatus.failed => 'Failed',
    TransferStatus.cancelled => 'Cancelled',
  };

  IconData _icon(TransferTask task) => task.direction == 'Upload'
      ? Icons.cloud_upload_outlined
      : Icons.download_rounded;

  @override
  Widget build(BuildContext context) {
    final manager = TransferManager.instance;
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: PocketLinkAppBar(
        feathered: true,
        title: const Text('Transfers'),
        actions: [
          PocketLinkAppBarAction(label: 'Clear history', icon: Icons.delete_sweep_outlined, onPressed: manager.clearFinished),
        ],
      ),
      body: AnimatedBuilder(
        animation: manager,
        builder: (context, _) {
          final tasks = manager.tasks;
          if (tasks.isEmpty) {
            return Padding(
              padding: EdgeInsets.only(
                top: MediaQuery.paddingOf(context).top + kToolbarHeight,
              ),
              child: const Center(
                child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.swap_vert_rounded, size: 52),
                  SizedBox(height: 12),
                  Text('No transfers yet'),
                  SizedBox(height: 4),
                  Text('Uploads and downloads will appear here.'),
                ],
                ),
              ),
            );
          }
          return ListView.separated(
            padding: EdgeInsets.fromLTRB(
              16,
              MediaQuery.paddingOf(context).top + kToolbarHeight + 16,
              16,
              16 + MediaQuery.paddingOf(context).bottom,
            ),
            itemCount: tasks.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (context, index) {
              final task = tasks[index];
              final running = task.status == TransferStatus.running;
              final progress = task.progress;
              return Card(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(_icon(task), color: Theme.of(context).colorScheme.primary),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(task.name, maxLines: 1, overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context).textTheme.titleSmall),
                                Text('${task.direction} · ${task.location}',
                                  maxLines: 1, overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context).textTheme.bodySmall),
                              ],
                            ),
                          ),
                          Text(_status(task), style: Theme.of(context).textTheme.labelMedium),
                          if (!running &&
                              task.operation != null &&
                              (task.status == TransferStatus.failed ||
                                  task.status == TransferStatus.cancelled))
                            IconButton(
                              tooltip: 'Retry transfer',
                              onPressed: manager.isRetrying(task.id)
                                  ? null
                                  : () => manager.retry(task.id),
                              icon: manager.isRetrying(task.id)
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(strokeWidth: 2),
                                    )
                                  : const Icon(Icons.refresh_rounded),
                            ),
                          if (running && !task.cancelToken.isCancelled)
                            IconButton(
                              tooltip: 'Cancel transfer',
                              onPressed: () => manager.cancel(task.id),
                              icon: const Icon(Icons.close_rounded),
                            ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      LinearProgressIndicator(
                        value: running ? progress : (task.status == TransferStatus.completed ? 1 : 0),
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              task.total > 0
                                  ? '${_size(task.transferred)} / ${_size(task.total)}'
                                  : (task.error ?? _status(task)),
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ),
                          if (progress != null && running)
                            Text('${(progress * 100).round()}%',
                              style: Theme.of(context).textTheme.labelMedium),
                        ],
                      ),
                      if (task.error != null && !running)
                        Text(task.error!, style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                          fontSize: 12,
                        )),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
