import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pocketlink_client/features/media/discover/discover_models.dart';
import 'package:pocketlink_client/features/media/discover/discover_speed_dial_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  DiscoverTrack track(String id) => DiscoverTrack(
        videoId: id,
        title: 'Track $id',
        artist: 'Artist',
        durationText: '3:20',
        thumbnailUrl: 'https://example.test/$id.jpg',
      );

  test('pins tracks, moves a duplicate to the front, and persists metadata', () async {
    await DiscoverSpeedDialStore.pin(track('one'));
    await DiscoverSpeedDialStore.pin(track('two'));
    final updated = await DiscoverSpeedDialStore.pin(track('one'));

    expect(updated.map((item) => item.videoId), ['one', 'two']);
    final restored = await DiscoverSpeedDialStore.read();
    expect(restored.first.title, 'Track one');
    expect(restored.first.thumbnailUrl, 'https://example.test/one.jpg');
  });

  test('removes a pinned track without changing the others', () async {
    await DiscoverSpeedDialStore.pin(track('one'));
    await DiscoverSpeedDialStore.pin(track('two'));

    final updated = await DiscoverSpeedDialStore.remove('one');

    expect(updated.map((item) => item.videoId), ['two']);
    expect((await DiscoverSpeedDialStore.read()).map((item) => item.videoId), ['two']);
  });

  test('caps the store at twelve unique tracks', () async {
    for (var index = 0; index < 14; index++) {
      await DiscoverSpeedDialStore.pin(track('track-$index'));
    }

    final restored = await DiscoverSpeedDialStore.read();

    expect(restored, hasLength(12));
    expect(restored.first.videoId, 'track-13');
    expect(restored.last.videoId, 'track-2');
  });

  test('ignores invalid tracks', () async {
    await DiscoverSpeedDialStore.pin(
      const DiscoverTrack(videoId: '', title: 'Missing ID', artist: 'Artist'),
    );

    expect(await DiscoverSpeedDialStore.read(), isEmpty);
  });
}
