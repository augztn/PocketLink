import 'package:flutter_test/flutter_test.dart';
import 'package:pocketlink_client/core/network/server_api.dart';

void main() {
  group('ServerApi media streaming', () {
    test('builds a safely encoded stream URL', () {
      final api = ServerApi(
        baseUrl: 'http://127.0.0.1:8000',
        username: 'admin',
        password: 'secret',
      );

      final uri = Uri.parse(api.mediaStreamUrl('Music/Track 1.mp3'));

      expect(uri.path, '/api/files/stream');
      expect(uri.queryParameters['path'], 'Music/Track 1.mp3');
    });

    test('provides the Basic Authentication header to the player', () {
      final api = ServerApi(
        baseUrl: 'http://127.0.0.1:8000',
        username: 'admin',
        password: 'secret',
      );

      expect(
        api.mediaHeaders['Authorization'],
        'Basic YWRtaW46c2VjcmV0',
      );
    });

    test('parses indexed media paths and internal storage identifiers', () {
      final item = IndexedFile.fromJson({
        'volume': 'internal',
        'path': 'Music/Track 1.mp3',
        'name': 'Track 1.mp3',
        'type': 'file',
        'size': 1024,
        'modified': '2026-11-16T10:00:00.000Z',
        'mime': 'audio/mpeg',
        'category': 'music',
      });

      expect(item.volume, 'internal');
      expect(item.path, 'Music/Track 1.mp3');
      expect(item.toFileEntry().name, 'Track 1.mp3');
      expect(item.category, 'music');
    });

    test('parses index scan status without requiring optional error fields', () {
      final status = MediaIndexStatus.fromJson({
        'state': 'scanning',
        'scanned': 120,
        'skipped': 0,
        'last_completed_at': 0,
        'file_count': 80,
        'media_count': 20,
      });

      expect(status.isScanning, isTrue);
      expect(status.fileCount, 80);
      expect(status.lastError, isNull);
      expect(status.lastScanStartedAt, 0);
      expect(status.elapsedMs, 0);
      expect(status.currentSource, isNull);
    });

    test('parses scan trigger, counters, volume status and history', () {
      final status = MediaIndexStatus.fromJson({
        'state': 'complete',
        'scanned': 12,
        'skipped': 1,
        'last_completed_at': 1794900005000,
        'last_scan_started_at': 1794900000000,
        'elapsed_ms': 5000,
        'file_count': 10,
        'media_count': 4,
        'scan_trigger': 'manual',
        'new_files': 2,
        'updated_files': 1,
        'scanned_bytes': 4096,
        'volumes': [
          {'volume': 'internal', 'state': 'partial', 'started_at': 1794900000000, 'completed_at': 1794900005000, 'scanned': 12, 'skipped': 1}
        ],
        'scan_history': [
          {'started_at': 1794900000000, 'completed_at': 1794900005000, 'duration_ms': 5000, 'trigger': 'manual', 'state': 'partial', 'scanned': 12, 'skipped': 1, 'new_files': 2, 'updated_files': 1, 'scanned_bytes': 4096}
        ],
      });

      expect(status.scanTrigger, 'manual');
      expect(status.newFiles, 2);
      expect(status.updatedFiles, 1);
      expect(status.scannedBytes, 4096);
      expect(status.volumes.single.state, 'partial');
      expect(status.scanHistory.single.trigger, 'manual');
      expect(status.scanHistory.single.durationMs, 5000);
    });

    test('parses remote host scan progress details', () {
      final status = MediaIndexStatus.fromJson({
        'state': 'scanning',
        'scanned': 420,
        'skipped': 2,
        'last_completed_at': 0,
        'last_scan_started_at': 1794900000000,
        'elapsed_ms': 12500,
        'current_source': 'internal',
        'file_count': 900,
        'media_count': 240,
      });

      expect(status.isScanning, isTrue);
      expect(status.scanned, 420);
      expect(status.elapsedMs, 12500);
      expect(status.currentSource, 'internal');
      expect(status.lastScanStartedAt, 1794900000000);
    });
  });
}
