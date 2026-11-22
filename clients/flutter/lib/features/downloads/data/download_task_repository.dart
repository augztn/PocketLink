import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../download_task.dart';

/// Persists the download queue independently from scheduling and transfer I/O.
class DownloadTaskRepository {
  static const _tasksKey = 'downloads_tasks_v1';

  Future<void> _writeQueue = Future<void>.value();

  Future<List<DownloadTask>> load() async {
    final preferences = await SharedPreferences.getInstance();
    final raw = preferences.getString(_tasksKey);
    if (raw == null) return const [];

    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return decoded
          .whereType<Map>()
          .map((item) => DownloadTask.fromJson(
                Map<String, dynamic>.from(item),
              ))
          .toList(growable: true);
    } catch (_) {
      // Reject the entire malformed queue rather than restoring a partial list.
      await preferences.remove(_tasksKey);
      return const [];
    }
  }

  Future<void> save(Iterable<DownloadTask> tasks) {
    final snapshot = jsonEncode(tasks.map((task) => task.toJson()).toList());
    final write = _writeQueue.catchError((_) {}).then((_) async {
      final preferences = await SharedPreferences.getInstance();
      await preferences.setString(_tasksKey, snapshot);
    });
    _writeQueue = write;
    return write;
  }
}
