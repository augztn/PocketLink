import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'discover_models.dart';

/// Device-local listening history for Discover. It does not require a YouTube
/// account and is intentionally separate from the server's file activity.
class DiscoverRecentlyPlayedStore {
  DiscoverRecentlyPlayedStore._();

  static const _key = 'discover_recently_played_v1';
  static const _limit = 20;
  static Future<void> _writeQueue = Future<void>.value();

  static Future<List<DiscoverTrack>> read() async {
    final preferences = await SharedPreferences.getInstance();
    final raw = preferences.getString(_key);
    if (raw == null || raw.isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return decoded
          .whereType<Map>()
          .map((item) => DiscoverTrack.fromJson(
                item.map((key, value) => MapEntry(key.toString(), value)),
              ))
          .where((track) => track.videoId.isNotEmpty && track.title.isNotEmpty)
          .take(_limit)
          .toList(growable: false);
    } catch (_) {
      return const [];
    }
  }

  static Future<void> record(DiscoverTrack track) {
    final write = _writeQueue.then((_) async {
      final preferences = await SharedPreferences.getInstance();
      final current = await read();
      final next = [
        track,
        ...current.where((item) => item.videoId != track.videoId),
      ].take(_limit).map((item) => {
        'videoId': item.videoId,
        'title': item.title,
        'artist': item.artist,
        'durationText': item.durationText,
        'thumbnailUrl': item.thumbnailUrl,
      }).toList(growable: false);
      await preferences.setString(_key, jsonEncode(next));
    });
    _writeQueue = write.catchError((_) {});
    return write;
  }
}
