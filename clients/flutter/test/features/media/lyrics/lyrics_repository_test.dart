import 'package:flutter_test/flutter_test.dart';
import 'package:pocketlink_client/features/media/lyrics/lyrics_repository.dart';

void main() {
  group('LyricsRepository.parseLrc', () {
    test('parses millisecond and centisecond timestamps', () {
      final lines = LyricsRepository.parseLrc(
        '[00:01.23]First line\n[00:02.4]Second line',
      );

      expect(lines, hasLength(2));
      expect(lines[0].timeMs, 1230);
      expect(lines[0].text, 'First line');
      expect(lines[1].timeMs, 2400);
    });

    test('expands repeated timestamps and sorts chronologically', () {
      final lines = LyricsRepository.parseLrc(
        '[00:04.00][00:02.00]Repeated\n[00:03.00]Middle',
      );

      expect(lines.map((line) => line.timeMs), [2000, 3000, 4000]);
      expect(lines.first.text, 'Repeated');
      expect(lines.last.text, 'Repeated');
    });

    test('ignores metadata and untimed rows', () {
      final lines = LyricsRepository.parseLrc(
        '[ar:Artist]\n[ti:Title]\nuntimed\n[00:10.00]Timed',
      );

      expect(lines, hasLength(1));
      expect(lines.single.timeMs, 10000);
      expect(lines.single.text, 'Timed');
    });
  });

  test('duration parsing supports hour-long tracks', () {
    final query = LyricsTrackQuery(
      track: const MediaQueueItem(
        title: 'Live Set',
        path: '/music/live.flac',
        durationText: '1:02:03',
      ),
      api: null,
    );
    expect(query.durationSeconds, 3723);
  });

  test('LRCLIB ranking rejects a wrong cover in favour of exact synced recording', () {
    final result = LyricsRepository.selectBestLrclibCandidate(
      [
        {
          'trackName': 'The Only Exception (Acoustic Cover)',
          'artistName': 'Random Cover Band',
          'duration': 190,
          'plainLyrics': 'Wrong plain lyrics',
        },
        {
          'trackName': 'The Only Exception',
          'artistName': 'Paramore',
          'albumName': 'Brand New Eyes',
          'duration': 268,
          'syncedLyrics': '[00:12.00]When I was younger I saw\n[00:16.50]My daddy cry and curse at the wind',
        },
      ],
      title: 'The Only Exception',
      artist: 'Paramore',
      durationSeconds: 267,
    );

    expect(result, isNotNull);
    expect(result!.synced, isTrue);
    expect(result.lines, hasLength(2));
    expect(result.lines.first.timeMs, 12000);
    expect(result.lines.first.text, 'When I was younger I saw');
  });

  test('LRCLIB ranking rejects candidates with unrelated title and artist', () {
    final result = LyricsRepository.selectBestLrclibCandidate(
      [
        {
          'trackName': 'Completely Different Song',
          'artistName': 'Unrelated Artist',
          'duration': 200,
          'syncedLyrics': '[00:01.00]Wrong lyrics',
        },
      ],
      title: 'Song Title',
      artist: 'Correct Artist',
      durationSeconds: 201,
    );

    expect(result, isNull);
  });

  test('lyrics search cleanup removes packaging noise and credits', () {
    expect(
      LyricsProvider.clean('03 - Song Title (Official Audio) feat. Guest.flac'),
      'Song Title',
    );
  });
}
