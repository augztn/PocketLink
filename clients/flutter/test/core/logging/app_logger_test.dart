import 'package:flutter_test/flutter_test.dart';
import 'package:homeserver/core/logging/app_logger.dart';

void main() {
  group('AppLogger.sanitizeDiagnosticContent', () {
    test('redacts usernames and private IPv4 addresses', () {
      final sanitized = AppLogger.sanitizeDiagnosticContent(
        'Connection attempt | {host: 100.114.216.8, username: admin, port: 8000}',
      );

      expect(sanitized, isNot(contains('100.114.216.8')));
      expect(sanitized, isNot(contains('admin')));
      expect(sanitized, contains('[REDACTED_HOST]'));
      expect(sanitized, contains('username: [REDACTED]'));
      expect(sanitized, contains('port: 8000'));
    });

    test('redacts JSON credentials and authorization schemes', () {
      final sanitized = AppLogger.sanitizeDiagnosticContent(
        '{"username":"admin","password":"secret","authorization":"Basic abc123=="} '
        'Bearer opaque-token',
      );

      expect(sanitized, isNot(contains('admin')));
      expect(sanitized, isNot(contains('secret')));
      expect(sanitized, isNot(contains('abc123')));
      expect(sanitized, isNot(contains('opaque-token')));
      expect(sanitized, contains('[REDACTED]'));
    });

    test('redacts IPv6 addresses without altering timestamps', () {
      final sanitized = AppLogger.sanitizeDiagnosticContent(
        '2026-11-16T14:10:00Z host: fd7a:115c:a1e0::1234',
      );

      expect(sanitized, contains('2026-11-16T14:10:00Z'));
      expect(sanitized, isNot(contains('fd7a:115c:a1e0::1234')));
    });

    test('preserves useful API paths and status codes', () {
      final sanitized = AppLogger.sanitizeDiagnosticContent(
        'GET /api/files/ returned 200',
      );

      expect(sanitized, contains('/api/files/'));
      expect(sanitized, contains('200'));
    });
  });
}
