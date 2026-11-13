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
  });
}
