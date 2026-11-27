import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pocketlink_client/core/network/server_api.dart';
import 'package:pocketlink_client/features/media/data/media_library_repository.dart';
import 'package:pocketlink_client/features/media/media_library_catalog.dart';

class _MediaPageAdapter implements HttpClientAdapter {
  _MediaPageAdapter(this.pages);

  final List<Map<String, dynamic>> pages;
  final requests = <RequestOptions>[];
  var _nextPage = 0;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    final page = pages[_nextPage++];
    return ResponseBody.fromString(
      jsonEncode(page),
      200,
      headers: {Headers.contentTypeHeader: ['application/json']},
    );
  }

  @override
  void close({bool force = false}) {}
}

Map<String, dynamic> _indexedFile({
  required String name,
  required String path,
  String volume = 'internal',
  String mime = 'audio/mpeg',
}) => {
  'volume': volume,
  'path': path,
  'name': name,
  'type': 'file',
  'size': 1024,
  'modified': '2026-11-20T10:00:00.000Z',
  'mime': mime,
  'category': mime.startsWith('video/') ? 'video' : 'music',
};

Map<String, dynamic> _page(List<Map<String, dynamic>> items) => {
  'items': items,
  'status': {
    'state': 'complete',
    'scanned': items.length,
    'skipped': 0,
    'last_completed_at': 1795168800000,
    'file_count': items.length,
    'media_count': items.length,
  },
};

void main() {
  group('MediaLibraryRepository', () {
    test('paginates, filters, normalizes volumes and sorts indexed music', () async {
      final firstPage = List.generate(500, (index) {
        final number = 500 - index;
        final name = 'track_${number.toString().padLeft(3, '0')}.mp3';
        return _indexedFile(name: name, path: 'Music/$name');
      });
      final secondPage = [
        _indexedFile(name: 'track_000.mp3', path: 'Music/track_000.mp3'),
        _indexedFile(
          name: 'z_usb.flac',
          path: 'Music/z_usb.flac',
          volume: 'usb1',
          mime: 'audio/flac',
        ),
        _indexedFile(
          name: 'wrong-extension.mp4',
          path: 'Music/wrong-extension.mp4',
        ),
        _indexedFile(
          name: 'wrong-mime.mp3',
          path: 'Music/wrong-mime.mp3',
          mime: 'video/mp4',
        ),
      ];
      final adapter = _MediaPageAdapter([
        _page(firstPage),
        _page(secondPage),
      ]);
      final api = ServerApi(
        baseUrl: 'http://127.0.0.1:8000',
        username: 'admin',
        password: 'secret',
        httpClientAdapter: adapter,
      );

      try {
        final result = await MediaLibraryRepository(
          api: api,
          type: MediaLibraryType.music,
        ).readIndexedMedia();

        expect(result.items, hasLength(502));
        expect(result.items.first.entry.name, 'track_000.mp3');
        expect(result.items[1].entry.name, 'track_001.mp3');
        expect(result.items.last.entry.name, 'z_usb.flac');
        expect(result.items.first.volume, isNull);
        expect(result.items.last.volume, 'usb1');
        expect(result.status.state, 'complete');
        expect(adapter.requests, hasLength(2));
        expect(adapter.requests.last.path, '/api/index/media');
        expect(
          adapter.requests.take(2).map((request) => request.queryParameters['category']),
          everyElement('music'),
        );
        expect(
          adapter.requests.take(2).map((request) => request.queryParameters['q']),
          everyElement(''),
        );
        expect(
          adapter.requests.take(2).map((request) => request.queryParameters['limit']),
          everyElement(500),
        );
        expect(
          adapter.requests.take(2).map((request) => request.queryParameters['offset']),
          [0, 500],
        );
      } finally {
        api.close(force: true);
      }
    });

    test('uses persisted index tags without requesting the legacy music catalog', () async {
      final track = _indexedFile(name: 'song.mp3', path: 'Music/song.mp3')
        ..addAll({
          'title': 'Persisted Title',
          'artist': 'Persisted Artist',
          'album': 'Persisted Album',
          'duration_ms': 187000,
          'metadata_scanned': true,
        });
      final adapter = _MediaPageAdapter([_page([track])]);
      final api = ServerApi(
        baseUrl: 'http://127.0.0.1:8000',
        username: 'admin',
        password: 'secret',
        httpClientAdapter: adapter,
      );

      try {
        final result = await MediaLibraryRepository(
          api: api,
          type: MediaLibraryType.music,
        ).readIndexedMedia();

        expect(result.items.single.title, 'Persisted Title');
        expect(result.items.single.artist, 'Persisted Artist');
        expect(result.items.single.album, 'Persisted Album');
        expect(result.items.single.durationMs, 187000);
        expect(adapter.requests, hasLength(1));
        expect(adapter.requests.single.path, '/api/index/media');
      } finally {
        api.close(force: true);
      }
    });

    test('searches embedded title, artist and album metadata after indexing', () async {
      final firstTrack = _indexedFile(
        name: 'track_001.mp3',
        path: 'Music/track_001.mp3',
      )..addAll({
          'title': 'Midnight City',
          'artist': 'M83',
          'album': 'Hurry Up, We Are Dreaming',
          'duration_ms': 243000,
          'metadata_scanned': true,
        });
      final secondTrack = _indexedFile(
        name: 'track_002.mp3',
        path: 'Music/track_002.mp3',
      )..addAll({
          'title': 'Outro',
          'artist': 'M83',
          'album': 'Hurry Up, We Are Dreaming',
          'metadata_scanned': true,
        });
      final adapter = _MediaPageAdapter([
        _page([firstTrack, secondTrack]),
      ]);
      final api = ServerApi(
        baseUrl: 'http://127.0.0.1:8000',
        username: 'admin',
        password: 'secret',
        httpClientAdapter: adapter,
      );

      try {
        final result = await MediaLibraryRepository(
          api: api,
          type: MediaLibraryType.music,
        ).readIndexedMedia(query: 'midnight city');

        expect(result.items, hasLength(1));
        expect(result.items.single.title, 'Midnight City');
        expect(result.items.single.artist, 'M83');
        expect(adapter.requests, hasLength(1));
        expect(adapter.requests.single.path, '/api/index/media');
        expect(adapter.requests.first.queryParameters['q'], '');
      } finally {
        api.close(force: true);
      }
    });

    test('uses the video category and preserves compatible container MIME files', () async {
      final adapter = _MediaPageAdapter([
        _page([
          _indexedFile(
            name: 'clip.mp4',
            path: 'Movies/clip.mp4',
            mime: 'video/mp4',
          ),
          _indexedFile(
            name: 'legacy.mkv',
            path: 'Movies/legacy.mkv',
            mime: 'application/octet-stream',
          ),
          _indexedFile(
            name: 'song.mp3',
            path: 'Music/song.mp3',
            mime: 'audio/mpeg',
          ),
        ]),
      ]);
      final api = ServerApi(
        baseUrl: 'http://127.0.0.1:8000',
        username: 'admin',
        password: 'secret',
        httpClientAdapter: adapter,
      );

      try {
        final result = await MediaLibraryRepository(
          api: api,
          type: MediaLibraryType.video,
        ).readIndexedMedia();

        expect(result.items.map((item) => item.entry.name), [
          'clip.mp4',
          'legacy.mkv',
        ]);
        expect(adapter.requests.single.queryParameters['category'], 'video');
      } finally {
        api.close(force: true);
      }
    });

    test('stops paging when the owning screen is no longer active', () async {
      final adapter = _MediaPageAdapter([
        _page(List.generate(
          500,
          (index) => _indexedFile(
            name: 'track_$index.mp3',
            path: 'Music/track_$index.mp3',
          ),
        )),
        _page([
          _indexedFile(name: 'next.mp3', path: 'Music/next.mp3'),
        ]),
      ]);
      final api = ServerApi(
        baseUrl: 'http://127.0.0.1:8000',
        username: 'admin',
        password: 'secret',
        httpClientAdapter: adapter,
      );

      try {
        final result = await MediaLibraryRepository(
          api: api,
          type: MediaLibraryType.music,
        ).readIndexedMedia(shouldContinue: () => false);

        expect(result.items, isEmpty);
        expect(adapter.requests, hasLength(1));
      } finally {
        api.close(force: true);
      }
    });
  });
}
