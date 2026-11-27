import 'package:flutter_test/flutter_test.dart';
import 'package:pocketlink_client/features/media/media_metadata.dart';

void main() {
  group('resolveMediaArtist', () {
    test('uses embedded artist metadata when it is meaningful', () {
      expect(
        resolveMediaArtist(
          artist: 'Vishnu',
          title: 'Indrajaalam',
          path: '/Music/Indrajaalam.flac',
          fallback: 'PocketLink',
        ),
        'Vishnu',
      );
    });

    test('parses artist suffix from the media title', () {
      expect(
        resolveMediaArtist(
          artist: 'PocketLink',
          title: 'Indrajaalam - Vishnu',
          path: '/Music/Indrajaalam.flac',
          fallback: 'PocketLink',
        ),
        'Vishnu',
      );
    });

    test('parses artist suffix from filename when title metadata omits it', () {
      expect(
        resolveMediaArtist(
          artist: 'PocketLink',
          title: 'Indrajaalam',
          path: '/Music/Indrajaalam - Vishnu.flac',
          fallback: 'PocketLink',
        ),
        'Vishnu',
      );
    });

    test('uses a meaningful album folder before a generic source label', () {
      expect(
        resolveMediaArtist(
          artist: 'PocketLink',
          title: 'Indrajaalam',
          path: '/Music/Vishnu/Indrajaalam.flac',
          fallback: 'PocketLink',
        ),
        'Vishnu',
      );
    });

    test('does not expose generic source labels as artist metadata', () {
      expect(
        resolveMediaArtist(
          artist: 'PocketLink',
          title: 'Indrajaalam',
          path: '/Music/Indrajaalam.flac',
          fallback: 'PocketLink',
        ),
        'Unknown artist',
      );
    });
  });
}
