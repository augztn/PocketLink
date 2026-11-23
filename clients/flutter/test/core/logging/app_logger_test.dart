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
    test('preserves API route fields and non-sensitive operational metadata', () {
      final sanitized = AppLogger.sanitizeDiagnosticFields({
        'path': '/api/files/',
        'endpointPath': '/api/storage/volumes',
        'filePath': '/sdcard/Documents/private.pdf',
        'hostMode': 'tailscale',
        'serverStatus': 'online',
        'username': 'admin',
      });

      expect(sanitized['path'], '/api/files/');
      expect(sanitized['endpointPath'], '/api/storage/volumes');
      expect(sanitized['filePath'], '[REDACTED_PATH]');
      expect(sanitized['hostMode'], 'tailscale');
      expect(sanitized['serverStatus'], 'online');
      expect(sanitized['username'], '[REDACTED]');
    });

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

    test('preserves safe API route fields while redacting private paths', () {
      final sanitized = AppLogger.sanitizeDiagnosticFields({
        'route': '/api/index/status',
        'endpoint': '/api/files/',
        'path': '/api/storage/volumes',
        'file_path': '/sdcard/Private/movie.mp4',
      });

      expect(sanitized['route'], '/api/index/status');
      expect(sanitized['endpoint'], '/api/files/');
      expect(sanitized['path'], '/api/storage/volumes');
      expect(sanitized['file_path'], '[REDACTED_PATH]');
    });
  });


  group('AppLogger diagnostic export boundaries', () {
    late Directory directory;

    setUp(() async {
      directory = await Directory.systemTemp.createTemp('pocketlink-export-test-');
      await AppLogger.initializeForTesting(directory);
    });

    tearDown(() async {
      if (await directory.exists()) await directory.delete(recursive: true);
    });

    test('retains the active session event before a large rotated log', () async {
      await AppLogger.info('LATEST_ACTIVE_SESSION_EVENT');
      final current = await File('${directory.path}/pocketlink.log').readAsString();
      final jsonStart = current.indexOf('{');
      final sessionId = (jsonDecode(current.substring(jsonStart)) as Map<String, dynamic>)['session_id'];

      final oldEvents = List.generate(2200, (index) {
        final event = jsonEncode({
          'event_id': 'old-$index',
          'session_id': sessionId,
          'timestamp': '2026-11-22T00:00:00.000Z',
          'level': 'INFO',
          'message': 'older event ${List.filled(1200, 'x').join()}',
        });
        return '2026-11-22T00:00:00.000Z [INFO] $event';
      }).join('\n');
      await File('${directory.path}/pocketlink.log.1').writeAsString('$oldEvents\n');

      final exported = await AppLogger.createDiagnosticFile();
      final content = await exported.readAsString();

      expect(content, contains('LATEST_ACTIVE_SESSION_EVENT'));
      expect(await exported.length(), lessThanOrEqualTo(2 * 1024 * 1024));
    });

    test('native export truncation keeps complete UTF-8 JSON event lines', () {
      final older = jsonEncode({'event_id': 'older', 'message': 'old'});
      final newest = jsonEncode({'event_id': 'newest', 'message': 'USB connected 🔌'});
      final newestBytes = utf8.encode('$newest\n');
      final bytes = AppLogger.latestCompleteDiagnosticLinesForTesting(
        '$older\n$newest\n',
        newestBytes.length,
      );
      final retained = utf8.decode(bytes);
      final records = retained.trimRight().split('\n').map(
            (line) => jsonDecode(line) as Map<String, dynamic>,
          );

      expect(records.map((record) => record['event_id']), ['newest']);
      expect(retained, contains('🔌'));
    });
  });

}
