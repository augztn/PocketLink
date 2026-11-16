import 'package:flutter_test/flutter_test.dart';
import 'package:homeserver_client/core/network/server_api.dart';

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
    });
  });
}
