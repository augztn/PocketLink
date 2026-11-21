import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pocketlink_client/core/network/server_api.dart';

class _NetworkHandoffAdapter implements HttpClientAdapter {
  int requests = 0;
  bool retryUsedFreshConnection = false;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests++;
    if (requests == 1) {
      throw DioException(
        requestOptions: options,
        type: DioExceptionType.connectionTimeout,
        message: 'Simulated network handoff',
      );
    }
    retryUsedFreshConnection =
        options.headers['connection'] == 'close';
    return ResponseBody.fromString(
      '{"path":"","items":[]}',
      200,
      headers: {Headers.contentTypeHeader: ['application/json']},
    );
  }

  @override
  void close({bool force = false}) {}
}

class _RetryAfterAdapter implements HttpClientAdapter {
  int requests = 0;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests++;
    if (requests == 1) {
      return ResponseBody.fromString(
        '{"detail":"slow down"}',
        429,
        headers: {
          Headers.contentTypeHeader: ['application/json'],
          'retry-after': ['0'],
        },
      );
    }
    return ResponseBody.fromString(
      '{"path":"","items":[]}',
      200,
      headers: {Headers.contentTypeHeader: ['application/json']},
    );
  }

  @override
  void close({bool force = false}) {}
}

class _SequenceAdapter implements HttpClientAdapter {
  _SequenceAdapter(this.statuses, {this.delay = Duration.zero});
  final List<int> statuses;
  final Duration delay;
  int requests = 0;
  int active = 0;
  int maxActive = 0;
  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    final index = requests++;
    active++;
    if (active > maxActive) maxActive = active;
    await Future<void>.delayed(const Duration(milliseconds: 40));
    active--;
    final status = statuses[index.clamp(0, statuses.length - 1)];
    return ResponseBody.fromString(
      status == 200 ? '{"path":"","items":[]}' : '{"detail":"temporary"}',
      status,
      headers: {Headers.contentTypeHeader: ['application/json']},
    );
  }
  @override
  void close({bool force = false}) {}
}

class _SharedReadAdapter implements HttpClientAdapter {
  int requests = 0;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests++;
    if (delay > Duration.zero) await Future<void>.delayed(delay);
    final body = options.uri.path == '/api/storage/volumes'
        ? '{"items":[{"id":"usb1","name":"USB 1","available":true,"writable":false}]}'
        : '{"path":"","items":[]}';
    return ResponseBody.fromString(
      body,
      200,
      headers: {Headers.contentTypeHeader: ['application/json']},
    );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  group('ServerApi', () {
    test('parses skipped media-index paths while remaining compatible with old hosts', () {
      final status = MediaIndexStatus.fromJson({
        'state': 'partial',
        'scanned': 42,
        'skipped': 2,
        'last_completed_at': 1794940000000,
        'file_count': 40,
        'media_count': 12,
        'skipped_items': [
          {
            'volume': 'internal',
            'path': 'Android/data',
            'reason': 'Folder could not be read',
          },
        ],
      });

      expect(status.skipped, 2);
      expect(status.skippedItems, hasLength(1));
      expect(status.skippedItems.single.volume, 'internal');
      expect(status.skippedItems.single.path, 'Android/data');
      expect(status.skippedItems.single.reason, 'Folder could not be read');

      final legacyStatus = MediaIndexStatus.fromJson({
        'state': 'partial',
        'skipped': 1,
      });
      expect(legacyStatus.skippedItems, isEmpty);
    });

    test('parses host telemetry without inventing unavailable readings', () {
      final telemetry = HostSystemTelemetry.fromJson({
        'sampled_at_ms': 1794940000000,
        'device': {
          'manufacturer': 'Samsung',
          'model': 'Galaxy',
          'android_version': '16',
        },
        'cpu': {
          'model': 'Snapdragon',
          'cores': 8,
          'usage_percent': null,
          'usage_status': 'sampling',
        },
        'memory': {
          'total_bytes': 8000,
          'used_bytes': 5000,
          'available_bytes': 3000,
          'usage_percent': 62.5,
        },
        'storage': {
          'total_bytes': 10000,
          'used_bytes': 4000,
          'available_bytes': 6000,
          'usage_percent': 40,
        },
        'battery': {'percent': 87, 'status': 'charging'},
      });

      expect(telemetry.deviceModel, 'Galaxy');
      expect(telemetry.cpuCores, 8);
      expect(telemetry.cpuUsagePercent, isNull);
      expect(telemetry.cpuUsageStatus, 'sampling');
      expect(telemetry.memoryUsagePercent, 62.5);
      expect(telemetry.storageAvailableBytes, 6000);
      expect(telemetry.batteryPercent, 87);
      expect(telemetry.isCharging, isTrue);
    });
    test('retries transient GET failures and then succeeds', () async {
      final adapter = _SequenceAdapter([503, 200]);
      final api = ServerApi(baseUrl: 'http://127.0.0.1:8000', username: 'admin', password: 'secret', httpClientAdapter: adapter);
      final listing = await api.authenticate();
      expect(listing.items, isEmpty);
      expect(adapter.requests, 2);
    });

    test('honors a zero-second Retry-After response', () async {
      final adapter = _RetryAfterAdapter();
      final api = ServerApi(
        baseUrl: 'http://127.0.0.1:8000',
        username: 'admin',
        password: 'secret',
        httpClientAdapter: adapter,
      );

      final stopwatch = Stopwatch()..start();
      final listing = await api.authenticate();

      expect(listing.items, isEmpty);
      expect(adapter.requests, 2);
      expect(stopwatch.elapsed, lessThan(const Duration(milliseconds: 900)));
    });

    test('retries a connection timeout on a fresh socket after network handoff', () async {
      final adapter = _NetworkHandoffAdapter();
      final api = ServerApi(
        baseUrl: 'http://100.114.216.8:8000',
        username: 'admin',
        password: 'secret',
        httpClientAdapter: adapter,
      );

      final listing = await api.authenticate();

      expect(listing.items, isEmpty);
      expect(adapter.requests, 2);
      expect(adapter.retryUsedFreshConnection, isTrue);
    });

    test('deduplicates identical in-flight directory requests and caches briefly', () async {
      final adapter = _SequenceAdapter([200], delay: const Duration(milliseconds: 40));
      final api = ServerApi(baseUrl: 'http://127.0.0.1:8000', username: 'admin', password: 'secret', httpClientAdapter: adapter);
      final results = await Future.wait([
        api.listDirectory(''),
        api.listDirectory(''),
        api.listDirectory(''),
      ]);
      expect(results, hasLength(3));
      expect(adapter.requests, 1);
      await api.listDirectory('');
      expect(adapter.requests, 1);
      api.invalidateDirectoryCache();
      await api.listDirectory('');
      expect(adapter.requests, 2);
    });

    test('coalesces identical directory reads across ServerApi instances', () async {
      final firstAdapter = _SharedReadAdapter();
      final secondAdapter = _SharedReadAdapter();
      final firstApi = ServerApi(
        baseUrl: 'http://127.0.0.1:8000',
        username: 'admin',
        password: 'secret',
        httpClientAdapter: firstAdapter,
      );
      final secondApi = ServerApi(
        baseUrl: 'http://127.0.0.1:8000',
        username: 'admin',
        password: 'secret',
        httpClientAdapter: secondAdapter,
      );

      final results = await Future.wait([
        firstApi.listDirectory(''),
        secondApi.listDirectory(''),
      ]);

      expect(results, hasLength(2));
      expect(firstAdapter.requests + secondAdapter.requests, 1);
    });

    test('coalesces storage-volume reads across ServerApi instances', () async {
      final firstAdapter = _SharedReadAdapter();
      final secondAdapter = _SharedReadAdapter();
      final firstApi = ServerApi(
        baseUrl: 'http://127.0.0.1:8000',
        username: 'admin',
        password: 'secret',
        httpClientAdapter: firstAdapter,
      );
      final secondApi = ServerApi(
        baseUrl: 'http://127.0.0.1:8000',
        username: 'admin',
        password: 'secret',
        httpClientAdapter: secondAdapter,
      );

      final results = await Future.wait([
        firstApi.listStorageVolumes(),
        secondApi.listStorageVolumes(),
      ]);

      expect(results, hasLength(2));
      expect(results.first.single.id, 'usb1');
      expect(results.last.single.id, 'usb1');
      expect(firstAdapter.requests + secondAdapter.requests, 1);
    });

    test('does not return a directory response invalidated while in flight', () async {
      final adapter = _SequenceAdapter([200, 200], delay: const Duration(milliseconds: 50));
      final api = ServerApi(baseUrl: 'http://127.0.0.1:8000', username: 'admin', password: 'secret', httpClientAdapter: adapter);
      final pending = api.listDirectory('');
      await Future<void>.delayed(const Duration(milliseconds: 10));
      api.invalidateDirectoryCache();
      await pending;
      expect(adapter.requests, 2);
    });

    test('limits simultaneous API requests to four', () async {
      final adapter = _SequenceAdapter(List.filled(12, 200), delay: const Duration(milliseconds: 20));
      final api = ServerApi(baseUrl: 'http://127.0.0.1:8000', username: 'admin', password: 'secret', httpClientAdapter: adapter);
      await Future.wait(List.generate(12, (index) => api.listDirectory('folder-$index')));
      expect(adapter.maxActive, lessThanOrEqualTo(4));
    });

    test('does not retry authentication failures', () async {
      final adapter = _SequenceAdapter([401, 200]);
      final api = ServerApi(baseUrl: 'http://127.0.0.1:8000', username: 'admin', password: 'wrong', httpClientAdapter: adapter);
      await expectLater(api.authenticate(), throwsA(isA<DioException>()));
      expect(adapter.requests, 1);
    });

    test('accepts host and port without a scheme', () {
      expect(
        () => ServerApi(
          baseUrl: '192.168.1.10:8000',
          username: 'admin',
          password: 'secret',
        ),
        returnsNormally,
      );
    });

    test('rejects invalid addresses', () {
      expect(
        () => ServerApi(
          baseUrl: 'not a valid address',
          username: 'admin',
          password: 'secret',
        ),
        throwsFormatException,
      );
    });

    test('rejects embedded credentials in URL', () {
      expect(
        () => ServerApi(
          baseUrl: 'http://user:password@example.com:8000',
          username: 'admin',
          password: 'secret',
        ),
        throwsFormatException,
      );
    });
    test('parses SAF listings with numeric modified timestamps', () {
      final listing = DirectoryListing.fromJson({
        'path': '',
        'items': [
          {
            'name': 'movie.mp4',
            'type': 'file',
            'size': 1024,
            'modified': 1794528000000,
          },
        ],
      });

      expect(listing.items.single.modified, '1794528000000');
      expect(listing.items.single.size, 1024);
    });

    test('parses external storage capacity when the host exposes it', () {
      final volume = StorageVolume.fromJson({
        'id': 'usb1',
        'name': 'USB Storage 1',
        'available': true,
        'writable': true,
        'total_bytes': 32000,
        'used_bytes': 20000,
        'available_bytes': 12000,
        'usage_percent': 62.5,
      });

      expect(volume.id, 'usb1');
      expect(volume.available, isTrue);
      expect(volume.writable, isTrue);
      expect(volume.totalBytes, 32000);
      expect(volume.usedBytes, 20000);
      expect(volume.availableBytes, 12000);
      expect(volume.usagePercent, 62.5);
    });

    test('keeps external storage capacity unavailable when not supplied', () {
      final volume = StorageVolume.fromJson({
        'id': 'usb1',
        'name': 'USB Storage 1',
        'available': true,
        'writable': false,
      });

      expect(volume.totalBytes, isNull);
      expect(volume.usedBytes, isNull);
      expect(volume.availableBytes, isNull);
      expect(volume.usagePercent, isNull);
    });

    test('parses the existing backend file listing format', () {
      final listing = DirectoryListing.fromJson({
        'path': '.',
        'items': [
          {
            'name': 'Documents',
            'type': 'directory',
            'size': 0,
            'modified': '2026-11-13T00:00:00+00:00',
          },
          {
            'name': 'notes.txt',
            'type': 'file',
            'size': 42,
            'modified': '2026-11-13T00:00:00+00:00',
          },
        ],
      });

      expect(listing.path, '.');
      expect(listing.items, hasLength(2));
      expect(listing.items.first.isDirectory, isTrue);
      expect(listing.items.last.name, 'notes.txt');
      expect(listing.items.last.size, 42);
    });
  });
}
