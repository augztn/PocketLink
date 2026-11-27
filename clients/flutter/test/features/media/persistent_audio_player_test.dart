import 'package:flutter_test/flutter_test.dart';
import 'package:pocketlink_client/features/media/persistent_audio_player.dart';

void main() {
  test('provisional Discover tracks retain their source before stream resolution', () {
    const item = MediaQueueItem(
      title: 'Discover track',
      path: 'abcdefghijk',
      lyricsVideoId: 'abcdefghijk',
      isDiscover: true,
    );

    expect(item.sourceLabel, 'Discover');
    expect(
      item.mergeMetadata(const MediaQueueItem(
        title: 'Discover track',
        path: 'abcdefghijk',
        streamUrl: 'https://example.invalid/audio',
      )).sourceLabel,
      'Discover',
    );
  });

  test('local and PocketLink file sources remain distinct from Discover', () {
    const local = MediaQueueItem(
      title: 'Local track',
      path: '/storage/music/local.flac',
      localPath: '/storage/music/local.flac',
    );
    const server = MediaQueueItem(
      title: 'Server track',
      path: 'Music/server.flac',
    );

    expect(local.sourceLabel, 'Local');
    expect(server.sourceLabel, 'PocketLink');
  });
}
