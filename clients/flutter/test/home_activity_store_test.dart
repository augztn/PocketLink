import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../lib/core/storage/home_activity_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('HomeActivityStore', () {
    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      await HomeActivityStore.instance.load();
    });

    test('persists recent tracks and folders per server', () async {
      final store = HomeActivityStore.instance;

      await store.recordTrack(
        serverUrl: 'http://server-a:8000',
        title: 'Track.flac',
        path: 'Music/Track.flac',
      );
      await store.recordFolder(
        serverUrl: 'http://server-a:8000',
        path: 'Music/Albums',
      );
      await store.recordFile(
        serverUrl: 'http://server-b:8000',
        title: 'Photo.jpg',
        path: 'Pictures/Photo.jpg',
      );

      final serverA = store.itemsForServer('http://server-a:8000');
      expect(serverA.map((item) => item.kind), ['folder', 'track']);
      expect(serverA.first.title, 'Albums');
      expect(store.itemsForServer('http://server-b:8000').single.title, 'Photo.jpg');

      await store.load();
      expect(store.itemsForServer('http://server-a:8000').length, 2);
    });

    test('persists file and folder favorites per server and toggles them', () async {
      final store = HomeActivityStore.instance;
      await store.toggleFavorite(
        serverUrl: 'http://server-a:8000',
        title: 'Documents',
        path: 'Documents',
        isFolder: true,
      );
      await store.toggleFavorite(
        serverUrl: 'http://server-a:8000',
        title: 'Photo.jpg',
        path: 'Pictures/Photo.jpg',
        isFolder: false,
        volume: 'usb1',
      );
      await store.toggleFavorite(
        serverUrl: 'http://server-b:8000',
        title: 'Private',
        path: 'Private',
        isFolder: true,
      );

      expect(store.favoritesForServer('http://server-a:8000'), hasLength(2));
      expect(store.isFavorite(
        serverUrl: 'http://server-a:8000',
        path: 'Pictures/Photo.jpg',
        volume: 'usb1',
      ), isTrue);

      await store.load();
      expect(store.favoritesForServer('http://server-a:8000'), hasLength(2));
      await store.toggleFavorite(
        serverUrl: 'http://server-a:8000',
        title: 'Documents',
        path: 'Documents',
        isFolder: true,
      );
      expect(store.favoritesForServer('http://server-a:8000').map((item) => item.path),
          ['Pictures/Photo.jpg']);
      expect(store.favoritesForServer('http://server-b:8000').single.path, 'Private');
    });

    test('moves repeated activity to the top without duplicate entries', () async {
      final store = HomeActivityStore.instance;
      await store.recordFolder(
        serverUrl: 'http://server-a:8000',
        path: 'Documents',
      );
      await store.recordFolder(
        serverUrl: 'http://server-a:8000',
        path: 'Pictures',
      );
      await store.recordFolder(
        serverUrl: 'http://server-a:8000',
        path: 'Documents',
      );

      final items = store.itemsForServer('http://server-a:8000');
      expect(items.length, 2);
      expect(items.first.path, 'Documents');
    });
    test('tracks play counts per server and storage volume', () async {
      final store = HomeActivityStore.instance;
      await store.recordTrack(
        serverUrl: 'http://server-a:8000',
        title: 'Track.flac',
        path: 'Music/Track.flac',
      );
      await store.recordTrack(
        serverUrl: 'http://server-a:8000',
        title: 'Track.flac',
        path: 'Music/Track.flac',
      );
      await store.recordTrack(
        serverUrl: 'http://server-a:8000',
        title: 'USB Track.flac',
        path: 'Music/Track.flac',
        volume: 'usb1',
      );
      await store.recordTrack(
        serverUrl: 'http://server-b:8000',
        title: 'Track.flac',
        path: 'Music/Track.flac',
      );

      final serverA = store.mostPlayedForServer('http://server-a:8000');
      expect(serverA.first.count, 2);
      expect(serverA.first.volume, isNull);
      expect(serverA.last.count, 1);
      expect(serverA.last.volume, 'usb1');
      expect(store.mostPlayedForServer('http://server-b:8000').single.count, 1);

      await store.load();
      expect(store.mostPlayedForServer('http://server-a:8000').first.count, 2);
    });

    test('clears in-memory play counts when persisted history is absent', () async {
      final store = HomeActivityStore.instance;
      await store.recordTrack(
        serverUrl: 'http://server-a:8000',
        title: 'Track.flac',
        path: 'Music/Track.flac',
      );
      final preferences = await SharedPreferences.getInstance();
      await preferences.remove('home_track_play_counts_v1');

      await store.load();

      expect(store.mostPlayedForServer('http://server-a:8000'), isEmpty);
    });

  });
}
