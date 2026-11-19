import 'package:flutter_test/flutter_test.dart';
import 'package:pocketlink_client/features/downloads/download_manager_service.dart';
import 'package:pocketlink_client/features/downloads/download_task.dart';

void main() {
  test('download task survives JSON persistence', () {
    final task = DownloadTask(
      id: 'task-1',
      url: 'https://example.com/archive.zip',
      fileName: 'archive.zip',
      destinationPath: '/tmp/PocketLink/archive.zip',
      createdAt: DateTime.utc(2026, 11, 20),
      downloadedBytes: 512,
      totalBytes: 1024,
      speedBytesPerSecond: 128,
      status: DownloadStatus.paused,
      errorMessage: null,
    );

    final restored = DownloadTask.fromJson(task.toJson());

    expect(restored.id, task.id);
    expect(restored.url, task.url);
    expect(restored.fileName, task.fileName);
    expect(restored.destinationPath, task.destinationPath);
    expect(restored.createdAt, task.createdAt);
    expect(restored.downloadedBytes, 512);
    expect(restored.totalBytes, 1024);
    expect(restored.speedBytesPerSecond, 128);
    expect(restored.status, DownloadStatus.paused);
    expect(restored.progress, 0.5);
  });

  test('file names are made safe for local paths', () {
    expect(
      DownloadManagerService.sanitizeFileName('../unsafe:name?.zip'),
      '.._unsafe_name_.zip',
    );
    expect(DownloadManagerService.sanitizeFileName('..'), 'download');
    expect(DownloadManagerService.sanitizeFileName('  '), 'download');
  });
}
