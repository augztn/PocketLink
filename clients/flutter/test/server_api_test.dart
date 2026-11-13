import 'package:flutter_test/flutter_test.dart';
import 'package:homeserver_client/core/network/server_api.dart';

void main() {
  group('ServerApi', () {
    test('accepts host and port without a scheme', () {
      expect(
        () => ServerApi(baseUrl: '192.168.1.10:8000'),
        returnsNormally,
      );
    });

    test('rejects invalid addresses', () {
      expect(
        () => ServerApi(baseUrl: 'not a valid address'),
        throwsFormatException,
      );
    });

    test('rejects embedded credentials in URL', () {
      expect(
        () => ServerApi(baseUrl: 'http://user:password@example.com:8000'),
        throwsFormatException,
      );
    });
  });
}
