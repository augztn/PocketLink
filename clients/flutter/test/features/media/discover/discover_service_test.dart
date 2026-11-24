import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pocketlink_client/core/settings/app_settings.dart';
import 'package:pocketlink_client/core/network/server_api_models.dart';
import 'package:pocketlink_client/features/media/discover/discover_models.dart';
import 'package:pocketlink_client/features/media/discover/discover_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('pocketlink/saf');
  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  test('resolve forwards persisted quality, resolver and region preferences', () async {
    SharedPreferences.setMockInitialValues({});
    await AppSettings.instance.reloadPreferences();
    await AppSettings.instance.setDiscoverPlaybackOptions(
      audioQuality: 'data_saver',
      resolverProfile: 'player_api_first',
      region: 'JP',
    );
    messenger.setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'discoverResolve');
      expect(call.arguments, {
        'videoId': 'abcdefghijk',
        'quality': 'data_saver',
        'resolverProfile': 'player_api_first',
        'region': 'JP',
      });
      return {
        'url': 'https://r1.googlevideo.com/videoplayback',
        'mimeType': 'audio/webm',
        'userAgent': 'test-agent',
        'bitrateBps': 96000,
        'resolver': 'ANDROID_VR',
        'codec': 'opus',
        'quality': 'data_saver',
        'qualityFallbackReason': '',
        'audioOnly': true,
      };
    });

    final stream = await DiscoverService().resolve(
      const DiscoverTrack(videoId: 'abcdefghijk', title: 'Track', artist: 'Artist'),
    );

    expect(stream.resolver, 'ANDROID_VR');
    expect(stream.codec, 'opus');
    expect(stream.bitrateBps, 96000);
    expect(stream.audioOnly, isTrue);
    messenger.setMockMethodCallHandler(channel, null);
  });


  test('parses dynamic Moods and Moments sections and category endpoints', () {
    final section = DiscoverMoodSection.fromJson({
      'title': 'Moods & moments',
      'items': [
        {
          'title': 'Chill',
          'browseId': 'FEmusic_mood_chill',
          'params': 'browse-params',
          'stripeColor': 4281545523,
        },
      ],
    });

    expect(section.title, 'Moods & moments');
    expect(section.items.single.title, 'Chill');
    expect(section.items.single.browseId, 'FEmusic_mood_chill');
    expect(section.items.single.params, 'browse-params');
    expect(section.items.single.stripeColor, 4281545523);
  });

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

  group('DiscoverService progressive queue ordering', () {
    test('resolves immediate neighbours before remaining tracks', () {
      expect(
        DiscoverService.progressiveQueueOrder(6, 3),
        [2, 4, 1, 0, 5],
      );
    });

    test('handles first and last selected tracks', () {
      expect(DiscoverService.progressiveQueueOrder(4, 0), [1, 2, 3]);
      expect(DiscoverService.progressiveQueueOrder(4, 3), [2, 1, 0]);
    });

    test('rejects invalid queue positions', () {
      expect(DiscoverService.progressiveQueueOrder(0, 0), isEmpty);
      expect(DiscoverService.progressiveQueueOrder(3, -1), isEmpty);
      expect(DiscoverService.progressiveQueueOrder(3, 3), isEmpty);
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

    test('finds artist from an ancestor when the immediate folder is an album', () {
      final files = [
        IndexedFile(
          volume: 'internal',
          path: 'Music/Fleetwood Mac/Rumours/Dreams.flac',
          name: 'Dreams.flac',
          type: 'file',
          size: 12000000,
          modified: '',
          mime: 'audio/flac',
          category: 'music',
        ),
      ];
      expect(DiscoverService.findLocalLosslessMatch(track, files)?.path,
          'Music/Fleetwood Mac/Rumours/Dreams.flac');
    });

    test('matches artist-title filenames outside an artist folder', () {
      final files = [
        IndexedFile(
          volume: 'internal',
          path: 'Music/Fleetwood Mac - Dreams.flac',
          name: 'Fleetwood Mac - Dreams.flac',
          type: 'file',
          size: 12000000,
          modified: '',
          mime: 'audio/flac',
          category: 'music',
        ),
      ];
      expect(DiscoverService.findLocalLosslessMatch(track, files)?.name,
          'Fleetwood Mac - Dreams.flac');
    });

    test('matches Unicode regional-language titles without ASCII loss', () {
      final regionalTrack = DiscoverTrack(
        videoId: 'regional12345',
        title: 'പവിഴമഴ',
        artist: 'KS Harisankar',
      );
      final files = [
        IndexedFile(
          volume: 'internal',
          path: 'Music/KS Harisankar/പവിഴമഴ.flac',
          name: 'പവിഴമഴ.flac',
          type: 'file',
          size: 12000000,
          modified: '',
          mime: 'audio/flac',
          category: 'music',
        ),
      ];
      expect(
        DiscoverService.findLocalLosslessMatch(regionalTrack, files)?.name,
        'പവിഴമഴ.flac',
      );
    });

    test('allows an exact title match when the provider has no artist credit', () {
      final noArtist = DiscoverTrack(
        videoId: 'noartist12345',
        title: 'Dreams',
      );
      final files = [
        IndexedFile(
          volume: 'internal',
          path: 'Music/Dreams.flac',
          name: 'Dreams.flac',
          type: 'file',
          size: 12000000,
          modified: '',
          mime: 'audio/flac',
          category: 'music',
        ),
      ];
      expect(DiscoverService.findLocalLosslessMatch(noArtist, files)?.name,
          'Dreams.flac');
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
