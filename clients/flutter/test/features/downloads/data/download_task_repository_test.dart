import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:pocketlink_client/features/downloads/data/download_task_repository.dart';
import 'package:pocketlink_client/features/downloads/download_task.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('round-trips queued and completed download metadata', () async {
    final repository = DownloadTaskRepository();
    final createdAt = DateTime.utc(2026, 11, 22, 10);
    final tasks = [
      DownloadTask(
        id: 'server-file-1',
        url: 'http://127.0.0.1:8000/api/files/download',
        fileName: 'album.flac',
        destinationPath: '/downloads/album.flac',
        createdAt: createdAt,
        downloadedBytes: 4096,
        totalBytes: 8192,
        speedBytesPerSecond: 512,
        status: DownloadStatus.paused,
        serverBaseUrl: 'http://127.0.0.1:8000',
        serverPath: 'Music/album.flac',
        volume: 'usb-1',
      ),
      DownloadTask(
        id: 'external-2',
        url: 'https://example.test/video.mp4',
        fileName: 'video.mp4',
        destinationPath: '/downloads/video.mp4',
        createdAt: createdAt,
        downloadedBytes: 100,
        totalBytes: 100,
        status: DownloadStatus.completed,
      ),
    ];

    await repository.save(tasks);
    final restored = await repository.load();

    expect(restored, hasLength(2));
    expect(restored.first.id, 'server-file-1');
    expect(restored.first.status, DownloadStatus.paused);
    expect(restored.first.serverBaseUrl, 'http://127.0.0.1:8000');
    expect(restored.first.serverPath, 'Music/album.flac');
    expect(restored.first.volume, 'usb-1');
    expect(restored.first.downloadedBytes, 4096);
    expect(restored.last.status, DownloadStatus.completed);
  });

  test('malformed queue is discarded atomically', () async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(
      'downloads_tasks_v1',
      '[{"id":"valid","url":"https://example.test/a","fileName":"a","destinationPath":"/a","createdAt":"2026-11-22T10:00:00Z"},{"id":7}]',
    );

    final restored = await DownloadTaskRepository().load();

    expect(restored, isEmpty);
    expect(preferences.containsKey('downloads_tasks_v1'), isFalse);
  });

  test('ignores non-task list entries and preserves valid tasks', () async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(
      'downloads_tasks_v1',
      '[null, 42, {"id":"valid","url":"https://example.test/a","fileName":"a","destinationPath":"/a","createdAt":"2026-11-22T10:00:00Z"}]',
    );

    final restored = await DownloadTaskRepository().load();

    expect(restored, hasLength(1));
    expect(restored.single.id, 'valid');
  });
}
