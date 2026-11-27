import 'package:flutter_test/flutter_test.dart';
import 'package:pocketlink_client/features/media/media_metadata.dart';

void main() {
  test('mini-player artist removes YouTube view-count suffixes', () {
    expect(cleanMediaArtist('Maher Zain • 5.2M views'), 'Maher Zain');
    expect(cleanMediaArtist('Hamada Helal • 3.1M views'), 'Hamada Helal');
  });

  test('Discover artist keeps view count outside RTL isolate', () {
    expect(
      formatDiscoverArtist('سعد لمجرد • 18M views'),
      '\u2068سعد لمجرد\u2069 • 18M views',
    );
  });

  test('Discover artist keeps ordinary LTR metadata unchanged', () {
    expect(formatDiscoverArtist('Maher Zain • 11M views'), 'Maher Zain • 11M views');
  });

  test('artist falls back to the artist suffix in a track title', () {
    expect(
      resolveMediaArtist(
        artist: null,
        title: 'Indrajaalam - Vishnu Vijay',
        path: '/Music/Indrajaalam.flac',
        fallback: 'PocketLink',
      ),
      'Vishnu Vijay',
    );
  });

  test('artist falls back to a meaningful album folder', () {
    expect(
      resolveMediaArtist(
        artist: null,
        title: 'Indrajaalam',
        path: '/Music/Vishnu Vijay/Indrajaalam.flac',
        fallback: 'PocketLink',
      ),
      'Vishnu Vijay',
    );
  });

  test('generic source labels are never presented as artist metadata', () {
    expect(
      resolveMediaArtist(
        artist: null,
        title: 'Indrajaalam',
        path: '/Music/Indrajaalam.flac',
        fallback: 'PocketLink',
      ),
      'Unknown artist',
    );
  });
}
