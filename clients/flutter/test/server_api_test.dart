import 'dart:async';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pocketlink_client/core/network/server_api.dart';

class _RequestCaptureAdapter implements HttpClientAdapter {
  final List<RequestOptions> requests = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    return ResponseBody.fromString(
      '{"ok":true}',
      200,
      headers: {Headers.contentTypeHeader: ['application/json']},
    );
  }

  @override
  void close({bool force = false}) {}
}

class _RouteMissingAdapter implements HttpClientAdapter {
  final Map<String, int> requests = {};

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.update(options.uri.path, (count) => count + 1, ifAbsent: () => 1);
    return ResponseBody.fromString(
      '{"detail":"Not Found"}',
      404,
      headers: {Headers.contentTypeHeader: ['application/json']},
    );
  }

  @override
  void close({bool force = false}) {}
}

class _StorageRoutesAdapter implements HttpClientAdapter {
  final List<RequestOptions> requests = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    final body = options.uri.path.endsWith('/download')
        ? 'file-bytes'
        : '{"path":"Movies","items":[]}';
    return ResponseBody.fromString(
      body,
      200,
      headers: {
        Headers.contentTypeHeader: [
          options.uri.path.endsWith('/download')
              ? 'application/octet-stream'
              : 'application/json',
        ],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

class _CloseTrackingAdapter implements HttpClientAdapter {
  int closeCalls = 0;
  bool? force;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async => ResponseBody.fromString('', 200);

  @override
  void close({bool force = false}) {
    closeCalls++;
    this.force = force;
  }
}

class _DelayedReadAdapter implements HttpClientAdapter {
  final started = Completer<void>();
  final response = Completer<ResponseBody>();
  bool? force;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) {
    if (!started.isCompleted) started.complete();
    return response.future;
  }

  @override
  void close({bool force = false}) {
    this.force = force;
  }
}

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
    if (delay > Duration.zero) await Future<void>.delayed(delay);
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


class _SharedConcurrencyTracker {
  int active = 0;
  int maxActive = 0;
}

class _TrackedConcurrencyAdapter implements HttpClientAdapter {
  _TrackedConcurrencyAdapter(this.tracker);

  final _SharedConcurrencyTracker tracker;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    tracker.active++;
    if (tracker.active > tracker.maxActive) {
      tracker.maxActive = tracker.active;
    }
    await Future<void>.delayed(const Duration(milliseconds: 30));
    tracker.active--;
    return ResponseBody.fromString(
      '{"path":"","items":[]}',
      200,
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
    await Future<void>.delayed(const Duration(milliseconds: 40));
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

class _MediaFailureAdapter implements HttpClientAdapter {
  final Map<String, int> requests = {};

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.update(options.uri.path, (count) => count + 1, ifAbsent: () => 1);
    final status = options.uri.path == '/api/music/library' ? 404 : 400;
    return ResponseBody.fromString(
      '{"detail":"unsupported"}',
      status,
      headers: {Headers.contentTypeHeader: ['application/json']},
    );
  }

  @override
  void close({bool force = false}) {}
}

class _PriorityLaneAdapter implements HttpClientAdapter {
  final mediaStarted = Completer<void>();
  final coreStarted = Completer<void>();
  final releaseMedia = Completer<void>();
  int mediaRequestsStarted = 0;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    if (options.uri.path == '/api/media/thumbnail') {
      mediaRequestsStarted++;
      if (!mediaStarted.isCompleted) mediaStarted.complete();
      await releaseMedia.future;
      return ResponseBody.fromString(
        'image-data',
        200,
        headers: {Headers.contentTypeHeader: ['image/jpeg']},
      );
    }
    if (!coreStarted.isCompleted) coreStarted.complete();
    return ResponseBody.fromString(
      '{"path":"","items":[]}',
      200,
      headers: {Headers.contentTypeHeader: ['application/json']},
    );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  group('ServerApi', () {
    test('deletes music files from internal and SAF-backed storage', () async {
      final adapter = _RequestCaptureAdapter();
      final api = ServerApi(
        baseUrl: 'http://127.0.0.1:8000',
        username: 'admin',
        password: 'secret',
        httpClientAdapter: adapter,
      );

      await api.deleteMediaFile('Music/internal.mp3');
      await api.deleteMediaFile('Music/usb.mp3', volume: 'usb1');

      expect(adapter.requests, hasLength(2));
      expect(adapter.requests[0].method, 'DELETE');
      expect(adapter.requests[0].uri.path, '/api/files/item');
      expect(adapter.requests[0].queryParameters['path'], 'Music/internal.mp3');
      expect(adapter.requests[1].method, 'DELETE');
      expect(adapter.requests[1].uri.path, '/api/storage/usb1/item');
      expect(adapter.requests[1].queryParameters.containsKey('volume'), isFalse);
      expect(adapter.requests[1].queryParameters['path'], 'Music/usb.mp3');
      api.close();
    });


    test('SAF storage methods use the mounted volume route contract', () async {
      final adapter = _StorageRoutesAdapter();
      final api = ServerApi(
        baseUrl: 'http://127.0.0.1:8000',
        username: 'admin',
        password: 'secret',
        httpClientAdapter: adapter,
      );

      await api.listStorageDirectory('usb1', 'Movies');
      await api.uploadStorageFile(
        'usb1',
        'Movies/clip.mp4',
        'clip.mp4',
        Uint8List.fromList([1, 2, 3]),
      );
      await api.downloadStorageFile('usb1', 'Movies/clip.mp4');
      await api.createStorageFolder('usb1', 'Movies', 'New folder');
      await api.renameStorageItem('usb1', 'Movies/old.mp4', 'new.mp4');
      await api.deleteStorageItem('usb1', 'Movies/new.mp4');

      expect(adapter.requests.map((request) => request.uri.path), [
        '/api/storage/usb1/',
        '/api/storage/usb1/upload',
        '/api/storage/usb1/download',
        '/api/storage/usb1/mkdir',
        '/api/storage/usb1/rename',
        '/api/storage/usb1/item',
      ]);
      expect(adapter.requests.map((request) => request.method), [
        'GET', 'PUT', 'GET', 'POST', 'POST', 'DELETE',
      ]);
      expect(adapter.requests[0].queryParameters['path'], 'Movies');
      expect(adapter.requests[1].queryParameters['path'], 'Movies/clip.mp4');
      expect(adapter.requests[3].queryParameters['name'], 'New folder');
      expect(adapter.requests[4].queryParameters['name'], 'new.mp4');
      api.close();
    });

    test('indexed media pages are cached until invalidated', () async {
      final adapter = _RequestCaptureAdapter();
      final api = ServerApi(
        baseUrl: 'http://127.0.0.1:8000',
        username: 'admin',
        password: 'secret',
        httpClientAdapter: adapter,
      );

      await api.indexedMedia('music');
      await api.indexedMedia('music');
      expect(adapter.requests, hasLength(1));

      api.invalidateIndexedMediaCache();
      await api.indexedMedia('music');
      expect(adapter.requests, hasLength(2));
      api.close();
    });

    test('route-level 404 disables unsupported video endpoints for this session', () async {
      final adapter = _RouteMissingAdapter();
      final api = ServerApi(
        baseUrl: 'http://127.0.0.1:8000',
        username: 'admin',
        password: 'secret',
        httpClientAdapter: adapter,
      );

      expect(await api.videoThumbnail('Movies/one.mp4'), isNull);
      expect(await api.videoThumbnail('Movies/two.mp4'), isNull);
      expect(await api.videoMetadata('Movies/one.mp4'), isNull);
      expect(await api.videoMetadata('Movies/two.mp4'), isNull);
      expect(adapter.requests['/api/media/thumbnail'], 1);
      expect(adapter.requests['/api/media/metadata'], 1);
      api.close();
    });

    test('media thumbnail work cannot occupy the core API request lane', () async {
      final adapter = _PriorityLaneAdapter();
      final api = ServerApi(
        baseUrl: 'http://127.0.0.1:8000',
        username: 'admin',
        password: 'secret',
        httpClientAdapter: adapter,
      );

      final thumbnails = Future.wait([
        api.videoThumbnail('Movies/one.mp4'),
        api.videoThumbnail('Movies/two.mp4'),
        api.videoThumbnail('Movies/three.mp4'),
        api.videoThumbnail('Movies/four.mp4'),
      ]);
      await adapter.mediaStarted.future;

      final coreRead = api.authenticate();
      await adapter.coreStarted.future.timeout(const Duration(milliseconds: 250));
      expect(adapter.mediaRequestsStarted, 1);

      adapter.releaseMedia.complete();
      await thumbnails;
      expect((await coreRead).items, isEmpty);
      api.close();
    });

    test('404 optional music endpoint is cached for the API session', () async {
      final adapter = _MediaFailureAdapter();
      final api = ServerApi(
        baseUrl: 'http://127.0.0.1:8000',
        username: 'admin',
        password: 'secret',
        httpClientAdapter: adapter,
      );

      expect(await api.musicLibrary(), isEmpty);
      expect(await api.musicLibrary(), isEmpty);
      expect(adapter.requests['/api/music/library'], 1);
      api.close();
    });

    test('400/404 media failures stay negatively cached after cache clearing', () async {
      final adapter = _MediaFailureAdapter();
      final api = ServerApi(
        baseUrl: 'http://127.0.0.1:8000',
        username: 'admin',
        password: 'secret',
        httpClientAdapter: adapter,
      );

      expect(await api.videoThumbnail('Movies/broken.mp4'), isNull);
      api.clearMediaCache();
      expect(await api.videoThumbnail('Movies/broken.mp4'), isNull);
      expect(adapter.requests['/api/media/thumbnail'], 1);
      api.close();
    });

    test('close releases the HTTP adapter exactly once', () {
      final adapter = _CloseTrackingAdapter();
      final api = ServerApi(
        baseUrl: 'http://127.0.0.1:8000',
        username: 'admin',
        password: 'test',
        httpClientAdapter: adapter,
      );

      api.close();
      api.close();

      expect(adapter.closeCalls, 1);
      expect(adapter.force, isFalse);
    });

    test('in-flight cached reads complete during graceful disposal', () async {
      final adapter = _DelayedReadAdapter();
      final api = ServerApi(
        baseUrl: 'http://127.0.0.1:8119',
        username: 'admin',
        password: 'test',
        httpClientAdapter: adapter,
      );

      final pending = api.listDirectory('');
      await adapter.started.future;
      api.close();
      adapter.response.complete(ResponseBody.fromString(
        '{"path":"","items":[]}',
        200,
        headers: {Headers.contentTypeHeader: ['application/json']},
      ));

      expect((await pending).items, isEmpty);
      expect(adapter.force, isFalse);
    });

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

    test('limits simultaneous requests globally across ServerApi instances', () async {
      final tracker = _SharedConcurrencyTracker();
      final firstApi = ServerApi(
        baseUrl: 'http://127.0.0.1:8000',
        username: 'admin',
        password: 'secret',
        httpClientAdapter: _TrackedConcurrencyAdapter(tracker),
      );
      final secondApi = ServerApi(
        baseUrl: 'http://127.0.0.1:8000',
        username: 'admin',
        password: 'secret',
        httpClientAdapter: _TrackedConcurrencyAdapter(tracker),
      );

      await Future.wait([
        ...List.generate(
          6,
          (index) => firstApi.listDirectory('first-$index'),
        ),
        ...List.generate(
          6,
          (index) => secondApi.listDirectory('second-$index'),
        ),
      ]);

      expect(tracker.maxActive, 4);
      expect(tracker.active, 0);
      firstApi.close();
      secondApi.close();
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
