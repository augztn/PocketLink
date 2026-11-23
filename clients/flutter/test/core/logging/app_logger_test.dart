import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pocketlink_client/core/logging/app_logger.dart';

void main() {
  group('AppLogger structured persistence', () {
    late Directory directory;

    setUp(() async {
      directory = await Directory.systemTemp.createTemp('pocketlink-logger-test-');
      await AppLogger.initializeForTesting(directory);
    });

    tearDown(() async {
      if (await directory.exists()) await directory.delete(recursive: true);
    });

    test('writes parseable structured records with correlation and typed fields', () async {
      await AppLogger.info(
        'Request completed',
        category: 'network',
        component: 'api_client',
        correlationId: 'request-42',
        fields: {'status_code': 200, 'retryable': false, 'elapsed_ms': 18.5},
      );

      final logs = await AppLogger.readLogs(currentSessionOnly: true);
      final jsonStart = logs.indexOf('{');
      expect(jsonStart, greaterThanOrEqualTo(0));
      final record = jsonDecode(logs.substring(jsonStart)) as Map<String, dynamic>;

      expect(record['event_id'], contains(record['session_id']));
      expect(record['category'], 'network');
      expect(record['component'], 'api_client');
      expect(record['correlation_id'], 'request-42');
      expect(record['fields'], {
        'status_code': 200,
        'retryable': false,
        'elapsed_ms': 18.5,
      });
    });

    test('exposes typed logger health counters', () async {
      // The test initializer resets counters; verify the health snapshot remains typed.
      expect(AppLogger.health, {'write_failures': 0, 'dropped_events': 0});
    });
  });
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
  group('AppLogger.sanitizeDiagnosticFields additional privacy cases', () {
    test('redacts camelCase paths and private paths in nested values', () {
      final sanitized = AppLogger.sanitizeDiagnosticFields({
        'filePath': '/storage/emulated/0/Documents/report.pdf',
        'documentUri': 'content://private/document/123',
        'metadata': {'folderPath': '/data/user/0/private/cache'},
      });

      expect(sanitized['filePath'], '[REDACTED_PATH]');
      expect(sanitized['documentUri'], '[REDACTED_PATH]');
      expect(sanitized['metadata'], {'folderPath': '[REDACTED_PATH]'});
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

    test('redacts URL hostnames but preserves API routes and ports', () {
      final sanitized = AppLogger.sanitizeDiagnosticContent(
        'GET https://pocketlink.example:8000/api/files/ returned 200',
      );

      expect(sanitized, isNot(contains('pocketlink.example')));
      expect(sanitized, contains('[REDACTED_HOST]'));
      expect(sanitized, contains('/api/files/'));
      expect(sanitized, contains('200'));
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
