import 'package:flutter_test/flutter_test.dart';
import 'package:pocketlink_client/core/network/server_api_models.dart';

void main() {
  ServerDownloadJob job({
    int? totalBytes = 1000,
    int downloadedBytes = 250,
    int speedBytesPerSecond = 250,
    String status = 'downloading',
  }) => ServerDownloadJob(
    id: 'job-1',
    url: 'https://example.test/archive.zip',
    fileName: 'archive.zip',
    createdAt: DateTime.utc(2026, 11, 27),
    downloadedBytes: downloadedBytes,
    totalBytes: totalBytes,
    speedBytesPerSecond: speedBytesPerSecond,
    status: status,
  );

  test('estimates remaining time from known size and active speed', () {
    expect(job().estimatedRemaining, const Duration(seconds: 3));
  });

  test('returns zero when all known bytes have arrived', () {
    expect(
      job(downloadedBytes: 1000).estimatedRemaining,
      Duration.zero,
    );
  });

  test('does not estimate without a known total or active speed', () {
    expect(job(totalBytes: null).estimatedRemaining, isNull);
    expect(job(speedBytesPerSecond: 0).estimatedRemaining, isNull);
  });

  test('does not show an ETA for a non-downloading job', () {
    expect(job(status: 'paused').estimatedRemaining, isNull);
  });
}
