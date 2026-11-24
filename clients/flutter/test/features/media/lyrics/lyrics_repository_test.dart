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

  test('lyrics search cleanup removes packaging noise and credits', () {
    expect(
      LyricsProvider.clean('Song Title (Official Audio) feat. Guest'),
      'Song Title',
    );
  });
}
