import 'package:flutter_test/flutter_test.dart';
import 'package:pocketlink_client/core/logging/app_logger.dart';

void main() {
  group('AppLogger.filterSessionLogs', () {
    test('keeps only events tagged with the active session', () {
      const logs = '2026-11-17T10:00:00Z [INFO] old event | {session: session-old}\n'
          '2026-11-17T10:01:00Z [INFO] current event | {session: session-new}\n'
          '  stack trace detail\n'
          '2026-11-17T10:02:00Z [INFO] later old event | {session: session-old}\n';
      final filtered = AppLogger.filterSessionLogs(logs, 'session-new');
      expect(filtered, contains('current event'));
      expect(filtered, contains('stack trace detail'));
      expect(filtered, isNot(contains('old event')));
    });
  });

  group('AppLogger.sanitizeDiagnosticFields', () {
    test('preserves typed values while redacting sensitive keys', () {
      final sanitized = AppLogger.sanitizeDiagnosticFields({
        'status_code': 404,
        'retryable': false,
        'elapsed_ms': 125.5,
        'password': 'private-value',
        'file_path': '/sdcard/Documents/private.pdf',
        'nested': {'access_token': 'opaque', 'attempt': 2},
        'items': ['safe', '/sdcard/Photos/private.jpg'],
      });

      expect(sanitized['status_code'], 404);
      expect(sanitized['retryable'], false);
      expect(sanitized['elapsed_ms'], 125.5);
      expect(sanitized['password'], '[REDACTED]');
      expect(sanitized['file_path'], '[REDACTED_PATH]');
      expect(sanitized['nested'], {'access_token': '[REDACTED]', 'attempt': 2});
      expect(sanitized['items'], ['safe', '[REDACTED_PATH]']);
    });
  });
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
