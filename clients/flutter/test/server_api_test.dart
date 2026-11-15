import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:homeserver_client/core/network/server_api.dart';

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

void main() {
  group('ServerApi', () {
    test('retries transient GET failures and then succeeds', () async {
      final adapter = _SequenceAdapter([503, 200]);
      final api = ServerApi(baseUrl: 'http://127.0.0.1:8000', username: 'admin', password: 'secret', httpClientAdapter: adapter);
      final listing = await api.authenticate();
      expect(listing.items, isEmpty);
      expect(adapter.requests, 2);
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

    test('parses separate external storage volume status', () {
      final volume = StorageVolume.fromJson({
        'id': 'usb1',
        'name': 'USB Storage 1',
        'available': true,
        'writable': true,
      });

      expect(volume.id, 'usb1');
      expect(volume.available, isTrue);
      expect(volume.writable, isTrue);
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
