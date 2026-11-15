import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

enum TransferStatus { running, completed, failed, cancelled }

class TransferTask {
  TransferTask({
    required this.id,
    required this.name,
    required this.direction,
    required this.location,
    required this.startedAt,
    required this.cancelToken,
  });

  final String id;
  final String name;
  final String direction;
  final String location;
  final DateTime startedAt;
  final CancelToken cancelToken;
  int transferred = 0;
  int total = 0;
  TransferStatus status = TransferStatus.running;
  String? error;

  double? get progress => total > 0
      ? (transferred / total).clamp(0.0, 1.0)
      : null;
}

class TransferManager extends ChangeNotifier {
  TransferManager._();
  static final TransferManager instance = TransferManager._();

  final List<TransferTask> _tasks = [];
  List<TransferTask> get tasks => List.unmodifiable(_tasks);

  Future<bool> run({
    required String name,
    required String direction,
    required String location,
    required Future<void> Function(
      CancelToken token,
      void Function(int transferred, int total) onProgress,
    ) operation,
  }) async {
    final task = TransferTask(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      name: name,
      direction: direction,
      location: location,
      startedAt: DateTime.now(),
      cancelToken: CancelToken(),
    );
    _tasks.insert(0, task);
    notifyListeners();

    try {
      await operation(task.cancelToken, (transferred, total) {
        if (task.status != TransferStatus.running || task.cancelToken.isCancelled) return;
        task.transferred = transferred;
        task.total = total;
        notifyListeners();
      });
      if (task.cancelToken.isCancelled) {
        task.status = TransferStatus.cancelled;
        notifyListeners();
        return false;
      }
      task.status = TransferStatus.completed;
      if (task.total > 0) task.transferred = task.total;
      notifyListeners();
      return true;
    } on DioException catch (error) {
      if (CancelToken.isCancel(error) || task.cancelToken.isCancelled) {
        task.status = TransferStatus.cancelled;
      } else {
        task.status = TransferStatus.failed;
        task.error = error.message ?? 'Network transfer failed.';
      }
      notifyListeners();
      return false;
    } catch (error) {
      task.status = task.cancelToken.isCancelled
          ? TransferStatus.cancelled
          : TransferStatus.failed;
      task.error = task.status == TransferStatus.failed
          ? error.toString()
          : null;
      notifyListeners();
      return false;
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

  void clearFinished() {
    _tasks.removeWhere((task) => task.status != TransferStatus.running);
    notifyListeners();
  }
}
