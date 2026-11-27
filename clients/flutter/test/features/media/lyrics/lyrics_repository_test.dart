import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:pocketlink_client/features/media/lyrics/lyrics_repository.dart';
import 'package:pocketlink_client/features/media/persistent_audio_player.dart';

void main() {
  test('raw lyrics parser accepts plain text and filters LRC metadata', () {
    final result = LyricsRepository.parseRawLyricsText(
      '[ar:Artist]\n[ti:Title]\nFirst line\nSecond line',
      providerId: 'local',
      providerName: 'Local LRC',
    );

    expect(result, isNotNull);
    expect(result!.synced, isFalse);
    expect(result.lines.map((line) => line.text), ['First line', 'Second line']);
  });

  test('raw lyrics parser keeps synchronized sidecar timestamps', () {
    final result = LyricsRepository.parseRawLyricsText(
      '[00:01.50]First line\n[00:02.25]Second line',
      providerId: 'local',
      providerName: 'Local LRC',
    );

    expect(result, isNotNull);
    expect(result!.synced, isTrue);
    expect(result.lines.map((line) => line.timeMs), [1500, 2250]);
  });

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

  test('lyrics search cleanup removes catalogue numbering, tags, and view counts', () {
    expect(
      LyricsProvider.clean('14-Ya Nabi Salam Alayka (international version)'),
      'Ya Nabi Salam Alayka',
    );
    expect(
      LyricsProvider.clean('03 - Song Title (Official Audio) feat. Guest.flac'),
      'Song Title',
    );
    expect(
      LyricsProvider.clean('Maher Zain • 5.2M views'),
      'Maher Zain',
    );
    expect(
      LyricsProvider.cleanArtist('Hamada Helal • 3.1M views'),
      'Hamada Helal',
    );
  });
  test('track identity ignores mutable metadata and preserves known artwork', () {
    const original = MediaQueueItem(
      title: 'Track',
      path: '/music/track.flac',
      artworkUrl: 'https://example.com/cover.jpg',
      lyricsVideoId: 'video-1',
      durationText: '3:20',
    );
    const partial = MediaQueueItem(
      title: 'Track',
      path: '/music/track.flac',
      durationText: '3:21',
    );

    expect(original.stableTrackId, partial.stableTrackId);
    final merged = original.mergeMetadata(partial);
    expect(merged.artworkUrl, original.artworkUrl);
    expect(merged.lyricsVideoId, original.lyricsVideoId);
    expect(merged.durationText, '3:21');
  });

  test('lyrics lookup keeps the first active match when later providers miss', () async {
    final first = _FakeLyricsProvider(
      'lrclib',
      Completer<LyricsDocument?>(),
    );
    final second = _FakeLyricsProvider(
      'youtube_music',
      Completer<LyricsDocument?>(),
    );
    final repository = LyricsRepository(providers: [first, second]);
    const track = MediaQueueItem(
      title: 'Track',
      path: '/music/track.flac',
      lyricsVideoId: 'video-1',
    );
    final query = LyricsTrackQuery(track: track, api: null);
    final lookup = repository.lookup(query);
    final document = LyricsDocument(
      providerId: 'lrclib',
      providerName: 'LRCLIB',
      lines: const [LyricsLine(1000, 'A lyric line')],
      synced: true,
    );

    first.completer.complete(document);
    await Future<void>.delayed(Duration.zero);
    expect(repository.current(query.key), same(document));

    second.completer.complete(null);
    await lookup;
    expect(repository.current(query.key), same(document));
    expect(repository.resultsFor(query.key)['youtube_music']?.status,
        LyricsLookupStatus.notFound);
  });

  test('cancelling a completed lookup clears cached results for retry', () async {
    final provider = _FakeLyricsProvider(
      'lrclib',
      Completer<LyricsDocument?>(),
    );
    final repository = LyricsRepository(providers: [provider]);
    const track = MediaQueueItem(
      title: 'Track',
      path: '/music/retry.flac',
    );
    final query = LyricsTrackQuery(track: track, api: null);
    final lookup = repository.lookup(query);
    provider.completer.complete(LyricsDocument(
      providerId: 'lrclib',
      providerName: 'LRCLIB',
      lines: const [LyricsLine(1000, 'Cached lyric')],
      synced: true,
    ));
    await lookup;

    expect(repository.current(query.key), isNotNull);
    expect(repository.resultsFor(query.key), isNotEmpty);
    repository.cancel(query.key);
    expect(repository.current(query.key), isNull);
    expect(repository.resultsFor(query.key), isEmpty);
  });

  test('lyrics lookup deduplicates concurrent requests for one track ID', () async {
    final provider = _FakeLyricsProvider(
      'lrclib',
      Completer<LyricsDocument?>(),
    );
    final repository = LyricsRepository(providers: [provider]);
    const track = MediaQueueItem(
      title: 'Track',
      path: '/music/track.flac',
      lyricsVideoId: 'video-2',
    );
    final query = LyricsTrackQuery(track: track, api: null);
    final first = repository.lookup(query);
    final second = repository.lookup(query);
    expect(provider.calls, 1);
    provider.completer.complete(null);
    await Future.wait([first, second]);
    expect(provider.calls, 1);
  });
  test('lyrics lookup runs no more than four providers concurrently', () async {
    final providers = List.generate(
      7,
      (index) => _GateLyricsProvider('provider_$index'),
    );
    final repository = LyricsRepository(providers: providers);
    const track = MediaQueueItem(title: 'Track', path: '/music/track.flac');
    final lookup = repository.lookup(LyricsTrackQuery(track: track, api: null));

    await Future<void>.delayed(Duration.zero);
    expect(providers.where((provider) => provider.started).length, 4);
    for (final provider in providers.take(4)) {
      provider.completer.complete(null);
    }
    await Future<void>.delayed(Duration.zero);
    expect(providers.where((provider) => provider.started).length, 7);
    for (final provider in providers.skip(4)) {
      provider.completer.complete(null);
    }
    await lookup;
  });

  test('cancelling a lookup prevents late providers from replacing active lyrics', () async {
    final first = _GateLyricsProvider('first');
    final second = _GateLyricsProvider('second');
    final repository = LyricsRepository(providers: [first, second]);
    const track = MediaQueueItem(title: 'Track', path: '/music/track.flac');
    final query = LyricsTrackQuery(track: track, api: null);
    final lookup = repository.lookup(query);

    await Future<void>.delayed(Duration.zero);
    repository.cancel(query.key);
    first.completer.complete(LyricsDocument(
      providerId: 'first',
      providerName: 'First',
      lines: const [LyricsLine(1000, 'Stale result')],
      synced: true,
    ));
    second.completer.complete(null);
    await lookup;

    expect(repository.current(query.key), isNull);
    expect(repository.resultsFor(query.key), isEmpty);
  });

  test('higher-priority provider replaces an equal-quality later result', () async {
    final lrclib = _FakeLyricsProvider('lrclib', Completer<LyricsDocument?>());
    final youtube = _FakeLyricsProvider('youtube_music', Completer<LyricsDocument?>());
    final repository = LyricsRepository(providers: [lrclib, youtube]);
    const track = MediaQueueItem(
      title: 'Track',
      path: '/music/track.flac',
      lyricsVideoId: 'video-priority',
    );
    final query = LyricsTrackQuery(track: track, api: null);
    final lookup = repository.lookup(query);
    final youtubeDocument = LyricsDocument(
      providerId: 'youtube_music',
      providerName: 'YouTube Music',
      lines: const [LyricsLine(1000, 'YouTube lyric')],
      synced: true,
    );
    final lrclibDocument = LyricsDocument(
      providerId: 'lrclib',
      providerName: 'LRCLIB',
      lines: const [LyricsLine(1000, 'LRCLIB lyric')],
      synced: true,
    );

    youtube.completer.complete(youtubeDocument);
    await Future<void>.delayed(Duration.zero);
    expect(repository.current(query.key), same(youtubeDocument));

    lrclib.completer.complete(lrclibDocument);
    await lookup;
    expect(repository.current(query.key), same(lrclibDocument));
  });

}

class _GateLyricsProvider implements LyricsProvider {
  _GateLyricsProvider(this.id);
  @override
  final String id;
  final Completer<LyricsDocument?> completer = Completer<LyricsDocument?>();
  bool started = false;
  @override
  String get name => id;
  @override
  Future<LyricsDocument?> fetch(LyricsTrackQuery query) {
    started = true;
    return completer.future;
  }
}

class _FakeLyricsProvider implements LyricsProvider {
  _FakeLyricsProvider(this.id, this.completer);
  @override
  final String id;
  final Completer<LyricsDocument?> completer;
  int calls = 0;
  @override
  String get name => id;
  @override
  Future<LyricsDocument?> fetch(LyricsTrackQuery query) {
    calls++;
    return completer.future;
  }
}
