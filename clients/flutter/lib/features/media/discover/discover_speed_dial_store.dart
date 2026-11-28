import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'discover_models.dart';

/// Device-local pinned tracks for one-tap playback from Discover.
class DiscoverSpeedDialStore {
  DiscoverSpeedDialStore._();

  static const _key = 'discover_speed_dial_v1';
  static const _limit = 12;
  static Future<void> _writeQueue = Future<void>.value();

  static List<DiscoverTrack> _decode(String? raw) {
    if (raw == null || raw.isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      final seen = <String>{};
      return decoded
          .whereType<Map>()
          .map((item) => DiscoverTrack.fromJson(
                item.map((key, value) => MapEntry(key.toString(), value)),
              ))
          .where((track) =>
              track.videoId.isNotEmpty &&
              track.title.trim().isNotEmpty &&
              seen.add(track.videoId))
          .take(_limit)
          .toList(growable: false);
    } catch (_) {
      return const [];
    }
  }

  static Future<List<DiscoverTrack>> read() async {
    final preferences = await SharedPreferences.getInstance();
    return _decode(preferences.getString(_key));
  }

  static Future<List<DiscoverTrack>> pin(DiscoverTrack track) {
    if (track.videoId.isEmpty || track.title.trim().isEmpty) return read();
    final operation = _writeQueue.then((_) async {
      final preferences = await SharedPreferences.getInstance();
      final current = _decode(preferences.getString(_key));
      final updated = [
        track,
        ...current.where((item) => item.videoId != track.videoId),
      ].take(_limit).toList(growable: false);
      await preferences.setString(
        _key,
        jsonEncode(updated.map((item) => {
          'videoId': item.videoId,
          'title': item.title,
          'artist': item.artist,
          'durationText': item.durationText,
          'thumbnailUrl': item.thumbnailUrl,
        }).toList(growable: false)),
      );
      return List<DiscoverTrack>.unmodifiable(updated);
    });
    _writeQueue = operation.then<void>((_) {}, onError: (Object _) {});
    return operation;
  }

  static Future<List<DiscoverTrack>> remove(String videoId) {
    final operation = _writeQueue.then((_) async {
      final preferences = await SharedPreferences.getInstance();
      final updated = _decode(preferences.getString(_key))
          .where((item) => item.videoId != videoId)
          .toList(growable: false);
      await preferences.setString(
        _key,
        jsonEncode(updated.map((item) => {
          'videoId': item.videoId,
          'title': item.title,
          'artist': item.artist,
          'durationText': item.durationText,
          'thumbnailUrl': item.thumbnailUrl,
        }).toList(growable: false)),
      );
      return List<DiscoverTrack>.unmodifiable(updated);
    });
    _writeQueue = operation.then<void>((_) {}, onError: (Object _) {});
    return operation;
  }
}
