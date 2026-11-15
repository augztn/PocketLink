import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import 'transfer_history_store.dart';

typedef TransferOperation = Future<void> Function(
  CancelToken token,
  void Function(int transferred, int total) onProgress,
);

enum TransferStatus { running, completed, failed, cancelled }

class TransferTask {
  TransferTask({
    required this.id,
    required this.name,
    required this.direction,
    required this.location,
    required this.startedAt,
    required this.cancelToken,
    required this.operation,
    this.transferred = 0,
    this.total = 0,
    this.status = TransferStatus.running,
    this.error,
  });

  final String id;
  final String name;
  final String direction;
  final String location;
  final DateTime startedAt;
  final CancelToken cancelToken;
  TransferOperation? operation;
  int transferred;
  int total;
  TransferStatus status;
  String? error;

  double? get progress =>
      total > 0 ? (transferred / total).clamp(0.0, 1.0).toDouble() : null;

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'direction': direction,
    'location': location,
    'startedAt': startedAt.toIso8601String(),
    'transferred': transferred,
    'total': total,
    'status': status.name,
    'error': error,
  };

  factory TransferTask.fromJson(Map<String, dynamic> json) {
    final statusName = json['status'];
    final parsedStatus = TransferStatus.values.where(
      (value) => value.name == statusName,
    );
    var status = parsedStatus.isEmpty
        ? TransferStatus.failed
        : parsedStatus.first;
    var error = json['error'] as String?;
    if (status == TransferStatus.running) {
      status = TransferStatus.failed;
      error = 'App closed before this transfer finished.';
    }
    return TransferTask(
      id: json['id'] as String,
      name: json['name'] as String,
      direction: json['direction'] as String,
      location: json['location'] as String,
      startedAt: DateTime.parse(json['startedAt'] as String),
      cancelToken: CancelToken(),
      operation: null,
      transferred: (json['transferred'] as num?)?.toInt() ?? 0,
      total: (json['total'] as num?)?.toInt() ?? 0,
      status: status,
      error: error,
    );
  }
}

class TransferManager extends ChangeNotifier {
  TransferManager._(Future<TransferHistoryStore> storeFuture)
      : _storeFuture = storeFuture {
    _ready = _restoreHistory();
  }

  static final TransferManager instance = TransferManager._(
    TransferHistoryStore.inApplicationSupportDirectory(),
  );

  @visibleForTesting
  TransferManager.forTesting(TransferHistoryStore store)
      : this._(Future.value(store));

  final Future<TransferHistoryStore> _storeFuture;
  late final Future<void> _ready;
  final List<TransferTask> _tasks = [];
  final Set<String> _retryingIds = {};

  List<TransferTask> get tasks => List.unmodifiable(_tasks);
  Future<void> get ready => _ready;
  bool isRetrying(String id) => _retryingIds.contains(id);

  Future<void> _restoreHistory() async {
    try {
      final entries = await (await _storeFuture).load();
      for (final entry in entries.reversed.take(100)) {
        try {
          _tasks.add(TransferTask.fromJson(entry));
        } catch (_) {
          // Ignore malformed entries while preserving the rest of the history.
        }
      }
      _tasks.sort((a, b) => b.startedAt.compareTo(a.startedAt));
      notifyListeners();
      await _persist();
    } catch (_) {
      // History is best-effort; a storage issue must not block file transfers.
    }
  }

  Future<void> _persist() async {
    try {
      final snapshot = _tasks.take(100).map((task) => task.toJson()).toList();
      await (await _storeFuture).save(snapshot);
    } catch (_) {
      // Transfer execution remains independent from history persistence.
    }
  }

  Future<bool> run({
    required String name,
    required String direction,
    required String location,
    required TransferOperation operation,
  }) async {
    await _ready;
    final task = TransferTask(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      name: name,
      direction: direction,
      location: location,
      startedAt: DateTime.now(),
      cancelToken: CancelToken(),
      operation: operation,
    );
    _tasks.insert(0, task);
    await _persist();
    notifyListeners();

    try {
      await operation(task.cancelToken, (transferred, total) {
        if (task.status != TransferStatus.running ||
            task.cancelToken.isCancelled) return;
        task.transferred = transferred;
        task.total = total;
        notifyListeners();
      });
      if (task.cancelToken.isCancelled) {
        task.status = TransferStatus.cancelled;
        await _persist();
        notifyListeners();
        return false;
      }
      task.status = TransferStatus.completed;
      task.operation = null;
      if (task.total > 0) task.transferred = task.total;
      await _persist();
      notifyListeners();
      return true;
    } on DioException catch (error) {
      if (CancelToken.isCancel(error) || task.cancelToken.isCancelled) {
        task.status = TransferStatus.cancelled;
      } else {
        task.status = TransferStatus.failed;
        task.error = error.message ?? 'Network transfer failed.';
      }
      await _persist();
      notifyListeners();
      return false;
    } catch (error) {
      task.status = task.cancelToken.isCancelled
          ? TransferStatus.cancelled
          : TransferStatus.failed;
      task.error = task.status == TransferStatus.failed
          ? error.toString()
          : null;
      await _persist();
      notifyListeners();
      return false;
    }
  }

  Future<bool> retry(String id) async {
    if (!_retryingIds.add(id)) return false;
    notifyListeners();
    try {
      await _ready;
      TransferTask? task;
      for (final candidate in _tasks) {
        if (candidate.id == id) {
          task = candidate;
          break;
        }
      }
      final operation = task?.operation;
      if (task == null ||
          operation == null ||
          task.status == TransferStatus.running ||
          task.status == TransferStatus.completed) {
        return false;
      }
      return await run(
        name: task.name,
        direction: task.direction,
        location: task.location,
        operation: operation,
      );
    } finally {
      _retryingIds.remove(id);
      notifyListeners();
    }
  }

  void cancel(String id) {
    TransferTask? task;
    for (final candidate in _tasks) {
      if (candidate.id == id) {
        task = candidate;
        break;
      }
    }
    if (task == null ||
        task.status != TransferStatus.running ||
        task.cancelToken.isCancelled) return;
    task.cancelToken.cancel('Cancelled by user');
    notifyListeners();
  }

  Future<void> clearFinished() async {
    await _ready;
    _tasks.removeWhere((task) => task.status != TransferStatus.running);
    await _persist();
    notifyListeners();
  }
}
