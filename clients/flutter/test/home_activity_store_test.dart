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
  });
}
