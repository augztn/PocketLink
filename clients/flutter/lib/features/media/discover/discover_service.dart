import 'dart:math' as math;

import 'package:dio/dio.dart';
import 'package:flutter/services.dart';

import '../../../core/network/server_api_models.dart';

import 'discover_models.dart';

/// YouTube music discovery and LRCLIB lyrics access.
///
/// Search and stream extraction run in the Android plugin so YouTube's
/// signature/n-parameter handling never runs on the Flutter UI isolate.
class DiscoverService {
  DiscoverService({Dio? httpClient})
      : _http = httpClient ??
            Dio(BaseOptions(
              connectTimeout: const Duration(seconds: 8),
              receiveTimeout: const Duration(seconds: 12),
              sendTimeout: const Duration(seconds: 8),
              headers: const {'User-Agent': 'PocketLink/1.0'},
            ));

  static const MethodChannel _channel = MethodChannel('pocketlink/saf');
  final Dio _http;

  Future<List<DiscoverTrack>> search(String query, {int limit = 30}) async {
    final clean = query.trim();
    if (clean.length < 2) return const [];
    final raw = await _channel.invokeListMethod<Object?>(
      'discoverSearch',
      {'query': clean, 'limit': limit.clamp(1, 50)},
    );
    return _parseTracks(raw);
  }

  Future<List<DiscoverTrack>> home({int limit = 30}) async {
    final raw = await _channel.invokeListMethod<Object?>(
      'discoverHome',
      {'limit': limit.clamp(1, 50)},
    );
    return _parseTracks(raw);
  }

  Future<List<DiscoverTrack>> radio(DiscoverTrack track, {int limit = 25}) async {
    final raw = await _channel.invokeListMethod<Object?>(
      'discoverRadio',
      {'videoId': track.videoId, 'limit': limit.clamp(1, 50)},
    );
    return _parseTracks(raw);
  }

  static List<int> progressiveQueueOrder(int trackCount, int selectedIndex) {
    if (trackCount <= 0 || selectedIndex < 0 || selectedIndex >= trackCount) {
      return const [];
    }
    return [
      if (selectedIndex > 0) selectedIndex - 1,
      if (selectedIndex + 1 < trackCount) selectedIndex + 1,
      for (var index = selectedIndex - 2; index >= 0; index--) index,
      for (var index = selectedIndex + 2; index < trackCount; index++) index,
    ];
  }

  List<DiscoverTrack> _parseTracks(List<Object?>? raw) => (raw ?? const [])
      .whereType<Map<Object?, Object?>>()
      .map((item) => DiscoverTrack.fromJson(
            item.map((key, value) => MapEntry(key.toString(), value)),
          ))
      .where((track) => track.videoId.isNotEmpty && track.title.isNotEmpty)
      .toList(growable: false);

  Future<DiscoverResolvedStream> resolve(DiscoverTrack track) async {
    final raw = await _channel.invokeMapMethod<String, dynamic>(
      'discoverResolve',
      {'videoId': track.videoId},
    );
    if (raw == null || (raw['url']?.toString().isEmpty ?? true)) {
      throw StateError('No playable audio stream was returned.');
    }
    return DiscoverResolvedStream.fromJson(raw);
  }

  Future<DiscoverLyrics?> lyrics(DiscoverTrack track) async {
    final title = _cleanTitle(track.title);
    final artist = _cleanArtist(track.artist);
    if (title.isEmpty) return null;

    final response = await _http.get<List<dynamic>>(
      'https://lrclib.net/api/search',
      queryParameters: {'track_name': title, if (artist.isNotEmpty) 'artist_name': artist},
      options: Options(responseType: ResponseType.json),
    );
    final candidates = response.data ?? const [];
    Map<String, dynamic>? best;
    var bestScore = 0.0;
    for (final value in candidates) {
      if (value is! Map) continue;
      final candidate = value.map((key, item) => MapEntry(key.toString(), item));
      final candidateTitle = _cleanTitle(candidate['trackName']?.toString() ?? '');
      final candidateArtist = _cleanArtist(candidate['artistName']?.toString() ?? '');
      final titleScore = _similarity(title, candidateTitle);
      final artistScore = artist.isEmpty ? 0.5 : _similarity(artist, candidateArtist);
      final duration = (candidate['duration'] as num?)?.toDouble() ?? 0;
      final targetDuration = _durationSeconds(track.durationText);
      final durationScore = targetDuration <= 0 || duration <= 0
          ? 0.0
          : (1 - ((duration - targetDuration).abs() / 30)).clamp(-1.0, 1.0).toDouble();
      final score = titleScore * 0.65 + artistScore * 0.25 + durationScore * 0.10;
      if (score > bestScore) {
        bestScore = score;
        best = candidate;
      }
    }
    if (best == null || bestScore < 0.66) return null;

    final synced = best['syncedLyrics']?.toString();
    final plain = best['plainLyrics']?.toString();
    final sourceText = synced?.trim().isNotEmpty == true ? synced! : plain ?? '';
    if (sourceText.trim().isEmpty) return null;
    final isSynced = synced?.trim().isNotEmpty == true;
    final lines = isSynced ? parseLrc(sourceText) : sourceText
        .split(RegExp(r'\r?\n'))
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .map((line) => DiscoverLyricsLine(timeMs: 0, text: line))
        .toList(growable: false);
    if (lines.isEmpty) return null;
    return DiscoverLyrics(
      lines: List.unmodifiable(lines),
      isSynced: isSynced,
      source: 'LRCLIB',
    );
  }

  static List<DiscoverLyricsLine> parseLrc(String input) {
    final result = <DiscoverLyricsLine>[];
    final timestamp = RegExp(r'\[(\d{1,2}):(\d{2})(?:\.(\d{1,3}))?\]');
    for (final rawLine in input.split(RegExp(r'\r?\n'))) {
      final matches = timestamp.allMatches(rawLine).toList(growable: false);
      final text = rawLine.replaceAll(timestamp, '').trim();
      if (text.isEmpty) continue;
      for (final match in matches) {
        final minutes = int.tryParse(match.group(1) ?? '') ?? 0;
        final seconds = int.tryParse(match.group(2) ?? '') ?? 0;
        final fraction = (match.group(3) ?? '').padRight(3, '0');
        final milliseconds = int.tryParse(fraction) ?? 0;
        result.add(DiscoverLyricsLine(
          timeMs: minutes * 60000 + seconds * 1000 + milliseconds,
          text: text,
        ));
      }
    }
    result.sort((a, b) => a.timeMs.compareTo(b.timeMs));
    return result;
  }

  static bool isLosslessFile(String name) {
    final extension = name.split('.').last.toLowerCase();
    return const {'flac', 'alac', 'wav', 'aiff', 'aif', 'wv', 'ape', 'dsf', 'dff'}
        .contains(extension);
  }

  /// Conservative filename/path matcher. It refuses ambiguous matches rather
  /// than silently substituting a different recording or remix.
  static IndexedFile? findLocalLosslessMatch(
    DiscoverTrack track,
    List<IndexedFile> library,
  ) {
    final targetTitle = _normalize(_cleanTitle(track.title));
    final targetArtist = _normalize(_cleanArtist(track.artist));
    if (targetTitle.length < 3) return null;

    IndexedFile? best;
    var bestScore = 0.0;
    for (final item in library) {
      if (!isLosslessFile(item.name)) continue;
      final basename = item.name.replaceFirst(RegExp(r'\.[^.]+$'), '');
      final pathParts = item.path.split('/')..removeLast();
      final pieces = basename.split(RegExp(r'\s+[-–—]\s+'));
      var candidateTitleText = basename;
      var artistHintText = pathParts.isEmpty ? '' : pathParts.last;
      if (pieces.length >= 2) {
        final firstTitleScore = _similarity(targetTitle, _normalize(_cleanTitle(pieces.first)));
        final lastTitleScore = _similarity(targetTitle, _normalize(_cleanTitle(pieces.last)));
        if (lastTitleScore > firstTitleScore) {
          candidateTitleText = pieces.last;
          if (artistHintText.isEmpty ||
              const {'music', 'audio', 'songs', 'download', 'downloads'}
                  .contains(artistHintText.toLowerCase())) {
            artistHintText = pieces.first;
          }
        }
      }

      final candidateTitle = _normalize(_cleanTitle(candidateTitleText));
      if (candidateTitle.isEmpty) continue;
      final titleScore = _similarity(targetTitle, candidateTitle);
      final artistHint = _normalize(artistHintText);
      if (artistHint.isEmpty ||
          const {'music', 'audio', 'songs', 'download', 'downloads'}
              .contains(artistHint)) {
        continue;
      }
      final artistScore = targetArtist.isEmpty ? 0.5 : _similarity(targetArtist, artistHint);
      if (targetArtist.isNotEmpty && artistScore < 0.45) continue;
      final score = titleScore * 0.82 + artistScore * 0.18;
      if (score > bestScore) {
        bestScore = score;
        best = item;
      }
    }
    return bestScore >= 0.84 ? best : null;
  }

  static String _cleanTitle(String value) => value
      .replaceAll(RegExp(r'\s*\([^)]*(official|audio|video|lyrics?|remaster|live|visualizer)[^)]*\)', caseSensitive: false), '')
      .replaceAll(RegExp(r'\s*\[[^]]*(official|audio|video|lyrics?|remaster|live|visualizer)[^]]*\]', caseSensitive: false), '')
      .replaceAll(RegExp(r'\s*[-–]\s*(official|audio|video|lyrics?).*$', caseSensitive: false), '')
      .trim();

  static String _cleanArtist(String value) => value
      .replaceAll(RegExp(r'\s*(,|&|feat\.?|ft\.?|featuring).*$', caseSensitive: false), '')
      .trim();

  static String _normalize(String value) => value
      .toLowerCase()
      .replaceAll(RegExp(r'[^\p{L}\p{N}\s]+', unicode: true), ' ')
      .trim()
      .replaceAll(RegExp(r'\s+'), ' ');

  static double _similarity(String a, String b) {
    if (a.isEmpty || b.isEmpty) return 0;
    if (a == b) return 1;
    final left = a.split(' ').toSet();
    final right = b.split(' ').toSet();
    final union = left.union(right).length;
    final jaccard = union == 0 ? 0.0 : left.intersection(right).length / union;
    final maxLength = math.max(a.length, b.length);
    final distance = _levenshtein(a, b);
    return (jaccard * 0.65 + (1 - distance / maxLength) * 0.35).clamp(0.0, 1.0).toDouble();
  }

  static int _levenshtein(String a, String b) {
    var previous = List<int>.generate(b.length + 1, (i) => i);
    for (var i = 0; i < a.length; i++) {
      final current = List<int>.filled(b.length + 1, 0)..[0] = i + 1;
      for (var j = 0; j < b.length; j++) {
        final cost = a.codeUnitAt(i) == b.codeUnitAt(j) ? 0 : 1;
        current[j + 1] = math.min(
          math.min(current[j] + 1, previous[j + 1] + 1),
          previous[j] + cost,
        );
      }
      previous = current;
    }
    return previous.last;
  }

  static int _durationSeconds(String text) {
    final parts = text.split(':').map(int.tryParse).toList();
    if (parts.length != 2 || parts.any((part) => part == null)) return 0;
    return parts[0]! * 60 + parts[1]!;
  }
}
