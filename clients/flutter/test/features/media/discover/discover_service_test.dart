import 'package:flutter_test/flutter_test.dart';
import 'package:pocketlink_client/core/network/server_api_models.dart';
import 'package:pocketlink_client/features/media/discover/discover_models.dart';
import 'package:pocketlink_client/features/media/discover/discover_service.dart';

void main() {
  group('DiscoverService.parseLrc', () {
    test('parses fractional timestamps and sorts lines', () {
      final lines = DiscoverService.parseLrc('[00:12.34]Second\n[00:02.1]First');
      expect(lines.map((line) => line.text).toList(), ['First', 'Second']);
      expect(lines.first.timeMs, 2100);
      expect(lines.last.timeMs, 12340);
    });

    test('expands multiple timestamps on one line', () {
      final lines = DiscoverService.parseLrc('[00:01.00][00:02.00]Repeat');
      expect(lines.map((line) => line.timeMs).toList(), [1000, 2000]);
    });
  });

  group('DiscoverService lossless matching', () {
    final track = DiscoverTrack(
      videoId: 'abc12345678',
      title: 'Dreams',
      artist: 'Fleetwood Mac',
    );

    test('prefers an exact lossless filename in the artist folder', () {
      final files = [
        IndexedFile(
          volume: 'internal',
          path: 'Music/Fleetwood Mac/Dreams.flac',
          name: 'Dreams.flac',
          type: 'file',
          size: 12000000,
          modified: '',
          mime: 'audio/flac',
          category: 'music',
        ),
        IndexedFile(
          volume: 'internal',
          path: 'Music/Fleetwood Mac/Dreams.mp3',
          name: 'Dreams.mp3',
          type: 'file',
          size: 3000000,
          modified: '',
          mime: 'audio/mpeg',
          category: 'music',
        ),
      ];
      final match = DiscoverService.findLocalLosslessMatch(track, files);
      expect(match?.name, 'Dreams.flac');
    });

    test('does not substitute a different recording with a different title', () {
      final files = [
        IndexedFile(
          volume: 'internal',
          path: 'Music/Fleetwood Mac/Go Your Own Way.flac',
          name: 'Go Your Own Way.flac',
          type: 'file',
          size: 12000000,
          modified: '',
          mime: 'audio/flac',
          category: 'music',
        ),
      ];
      expect(DiscoverService.findLocalLosslessMatch(track, files), isNull);
    });
  });
}
