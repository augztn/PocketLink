import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../lib/features/media/discover/discover_home_feed_store.dart';
import '../../../../lib/features/media/discover/discover_models.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  DiscoverHomeFeed sampleFeed({String continuation = 'next-page'}) =>
      DiscoverHomeFeed(
        continuation: continuation,
        shelves: [
          DiscoverHomeShelf(
            title: 'Quick Picks',
            tracks: const [
              DiscoverTrack(
                videoId: 'track-1',
                title: 'First track',
                artist: 'Artist',
                durationText: '3:20',
                thumbnailUrl: 'https://example.test/cover.jpg',
              ),
            ],
          ),
        ],
      );

  test('persists and restores a feed for its region', () async {
    final updatedAt = DateTime.utc(2026, 11, 26, 10);
    await DiscoverHomeFeedStore.write(
      'IN',
      sampleFeed(),
      clock: () => updatedAt,
    );

    final cached = await DiscoverHomeFeedStore.read(
      'IN',
      clock: () => updatedAt.add(const Duration(minutes: 5)),
    );

    expect(cached, isNotNull);
    expect(cached!.isStale, isFalse);
    expect(cached.feed.continuation, 'next-page');
    expect(cached.feed.shelves.single.title, 'Quick Picks');
    expect(cached.feed.shelves.single.tracks.single.videoId, 'track-1');
    expect(await DiscoverHomeFeedStore.read('US'), isNull);
  });

  test('persists collection cards with their navigation metadata', () async {
    final feed = DiscoverHomeFeed(
      shelves: [
        DiscoverHomeShelf(
          title: 'From the community',
          tracks: const [],
          items: const [
            DiscoverHomeItem(
              type: DiscoverHomeItemType.playlist,
              id: 'VLPL1234567890',
              title: 'Sunday songs',
              subtitle: 'Community playlist',
              browseId: 'VLPL1234567890',
              params: 'playlist-params',
              thumbnailUrl: 'https://example.test/playlist.jpg',
            ),
          ],
        ),
      ],
    );

    await DiscoverHomeFeedStore.write('IN', feed);
    final cached = await DiscoverHomeFeedStore.read('IN');

    expect(cached, isNotNull);
    final item = cached!.feed.shelves.single.items.single;
    expect(item.type, DiscoverHomeItemType.playlist);
    expect(item.browseId, 'VLPL1234567890');
    expect(item.params, 'playlist-params');
  });

  test('keeps stale shelves for offline display but drops continuation', () async {
    final updatedAt = DateTime.utc(2026, 11, 26, 10);
    await DiscoverHomeFeedStore.write(
      'IN',
      sampleFeed(),
      clock: () => updatedAt,
    );

    final cached = await DiscoverHomeFeedStore.read(
      'IN',
      clock: () => updatedAt.add(const Duration(minutes: 21)),
    );

    expect(cached, isNotNull);
    expect(cached!.isStale, isTrue);
    expect(cached.feed.shelves.single.tracks.single.title, 'First track');
    expect(cached.feed.continuation, isEmpty);
  });

  test('removes malformed persisted data', () async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString('discover_home_feed_v2_IN', '{invalid');

    expect(await DiscoverHomeFeedStore.read('IN'), isNull);
    expect(preferences.getString('discover_home_feed_v2_IN'), isNull);
  });

  test('clear removes only the selected region snapshot', () async {
    await DiscoverHomeFeedStore.write('IN', sampleFeed());
    await DiscoverHomeFeedStore.write('US', sampleFeed());

    await DiscoverHomeFeedStore.clear('IN');

    expect(await DiscoverHomeFeedStore.read('IN'), isNull);
    expect(await DiscoverHomeFeedStore.read('US'), isNotNull);
  });
}
