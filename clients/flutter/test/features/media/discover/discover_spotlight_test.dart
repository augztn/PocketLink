import 'package:flutter_test/flutter_test.dart';
import 'package:pocketlink_client/features/media/discover/discover_models.dart';

void main() {
  group('buildDiscoverSpotlightTracks', () {
    test('uses feed tracks first and fills from listening history', () {
      const shelves = [
        DiscoverHomeShelf(
          title: 'Made for you',
          tracks: [
            DiscoverTrack(videoId: 'feed-1', title: 'Feed one', artist: 'A'),
            DiscoverTrack(videoId: 'feed-2', title: 'Feed two', artist: 'A'),
          ],
        ),
      ];
      const recent = [
        DiscoverTrack(videoId: 'recent-1', title: 'Recent one', artist: 'B'),
      ];

      final result = buildDiscoverSpotlightTracks(
        shelves: shelves,
        recentlyPlayed: recent,
      );

      expect(result.map((track) => track.videoId),
          ['feed-1', 'feed-2', 'recent-1']);
    });

    test('includes playable feed items but excludes non-playable collections', () {
      const shelves = [
        DiscoverHomeShelf(
          title: 'Mixed shelf',
          tracks: [],
          items: [
            DiscoverHomeItem(
              type: DiscoverHomeItemType.playlist,
              id: 'playlist-1',
              title: 'Playlist',
              browseId: 'browse-1',
            ),
            DiscoverHomeItem(
              type: DiscoverHomeItemType.track,
              id: 'track-1',
              videoId: 'track-1',
              title: 'Playable',
              subtitle: 'Artist',
            ),
          ],
        ),
      ];

      final result = buildDiscoverSpotlightTracks(
        shelves: shelves,
        recentlyPlayed: const [],
      );

      expect(result.map((track) => track.videoId), ['track-1']);
    });

    test('deduplicates by video ID, rejects invalid tracks, and respects limit', () {
      const shelves = [
        DiscoverHomeShelf(
          title: 'First',
          tracks: [
            DiscoverTrack(videoId: 'same', title: 'Original', artist: 'A'),
            DiscoverTrack(videoId: '', title: 'No ID', artist: 'A'),
            DiscoverTrack(videoId: 'second', title: 'Second', artist: 'A'),
          ],
        ),
        DiscoverHomeShelf(
          title: 'Second',
          tracks: [
            DiscoverTrack(videoId: 'same', title: 'Duplicate', artist: 'B'),
            DiscoverTrack(videoId: 'third', title: 'Third', artist: 'B'),
          ],
        ),
      ];

      final result = buildDiscoverSpotlightTracks(
        shelves: shelves,
        recentlyPlayed: const [],
        limit: 2,
      );

      expect(result.map((track) => track.videoId), ['same', 'second']);
      expect(
        buildDiscoverSpotlightTracks(
          shelves: shelves,
          recentlyPlayed: const [],
          limit: 0,
        ),
        isEmpty,
      );
    });
  });
}
