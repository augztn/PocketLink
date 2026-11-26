import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pocketlink_client/features/media/discover/discover_models.dart';
import 'package:pocketlink_client/features/media/discover/discover_recently_played_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
  });

  test('stores recent tracks newest first and moves repeats to the top', () async {
    const first = DiscoverTrack(
      videoId: 'abcdefghijk',
      title: 'First',
      artist: 'Artist',
    );
    const second = DiscoverTrack(
      videoId: 'lmnopqrstuv',
      title: 'Second',
      artist: 'Artist',
    );

    await DiscoverRecentlyPlayedStore.record(first);
    await DiscoverRecentlyPlayedStore.record(second);
    await DiscoverRecentlyPlayedStore.record(first);

    final recent = await DiscoverRecentlyPlayedStore.read();
    expect(recent.map((track) => track.videoId).toList(),
        ['abcdefghijk', 'lmnopqrstuv']);
  });

  test('keeps a bounded history', () async {
    for (var index = 0; index < 25; index++) {
      await DiscoverRecentlyPlayedStore.record(DiscoverTrack(
        videoId: 'video${index.toString().padLeft(7, '0')}',
        title: 'Track $index',
        artist: 'Artist',
      ));
    }

    final recent = await DiscoverRecentlyPlayedStore.read();
    expect(recent, hasLength(20));
    expect(recent.first.title, 'Track 24');
    expect(recent.last.title, 'Track 5');
  });
}
