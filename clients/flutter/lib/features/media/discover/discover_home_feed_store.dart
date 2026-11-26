import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'discover_models.dart';

/// Persistent, device-local snapshot of the last successful Discover feed.
/// A stale snapshot remains available for offline rendering, but its opaque
/// continuation token is not reused after the cache TTL.
class DiscoverHomeFeedStore {
  DiscoverHomeFeedStore._();

  static const Duration ttl = Duration(minutes: 20);
  static const int _maxShelves = 30;
  static const int _maxTracksPerShelf = 50;

  static String _key(String region) =>
      'discover_home_feed_v1_${region.trim().toUpperCase()}';

  static Future<DiscoverCachedHomeFeed?> read(
    String region, {
    DateTime Function()? clock,
  }) async {
    final preferences = await SharedPreferences.getInstance();
    final key = _key(region);
    final raw = preferences.getString(key);
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) throw const FormatException('Invalid feed cache');
      final values = decoded.map((key, value) => MapEntry(key.toString(), value));
      final updatedAtMs = values['updatedAtMs'];
      final rawFeed = values['feed'];
      if (updatedAtMs is! int || rawFeed is! Map) {
        throw const FormatException('Invalid feed cache metadata');
      }
      final feed = DiscoverHomeFeed.fromJson(
        rawFeed.map((key, value) => MapEntry(key.toString(), value)),
      );
      final updatedAt = DateTime.fromMillisecondsSinceEpoch(updatedAtMs);
      final now = (clock ?? DateTime.now)();
      final stale = now.isBefore(updatedAt) || now.difference(updatedAt) >= ttl;
      return DiscoverCachedHomeFeed(
        feed: DiscoverHomeFeed(
          shelves: feed.shelves,
          continuation: stale ? '' : feed.continuation,
        ),
        updatedAt: updatedAt,
        isStale: stale,
      );
    } catch (_) {
      await preferences.remove(key);
      return null;
    }
  }

  static Future<void> write(
    String region,
    DiscoverHomeFeed feed, {
    DateTime Function()? clock,
  }) async {
    final preferences = await SharedPreferences.getInstance();
    final shelves = feed.shelves.take(_maxShelves).map((shelf) => {
      'title': shelf.title,
      'tracks': shelf.tracks.take(_maxTracksPerShelf).map((track) => {
        'videoId': track.videoId,
        'title': track.title,
        'artist': track.artist,
        'durationText': track.durationText,
        'thumbnailUrl': track.thumbnailUrl,
      }).toList(growable: false),
    }).toList(growable: false);
    await preferences.setString(_key(region), jsonEncode({
      'updatedAtMs': (clock ?? DateTime.now)().millisecondsSinceEpoch,
      'feed': {
        'shelves': shelves,
        'continuation': feed.continuation,
      },
    }));
  }

  static Future<void> clear(String region) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.remove(_key(region));
  }
}

class DiscoverCachedHomeFeed {
  const DiscoverCachedHomeFeed({
    required this.feed,
    required this.updatedAt,
    required this.isStale,
  });

  final DiscoverHomeFeed feed;
  final DateTime updatedAt;
  final bool isStale;
}
