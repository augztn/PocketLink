import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class HomeActivityItem {
  const HomeActivityItem({
    required this.kind,
    required this.title,
    required this.path,
    required this.serverUrl,
    required this.updatedAt,
    this.volume,
  });

  final String kind;
  final String title;
  final String path;
  final String serverUrl;
  final String? volume;
  final DateTime updatedAt;

  bool get isFolder => kind == 'folder';
  String get parentPath {
    final separator = path.lastIndexOf('/');
    return separator < 0 ? '' : path.substring(0, separator);
  }

  Map<String, Object?> toJson() => {
    'kind': kind,
    'title': title,
    'path': path,
    'serverUrl': serverUrl,
    'volume': volume,
    'updatedAt': updatedAt.toIso8601String(),
  };

  static HomeActivityItem? fromJson(Object? value) {
    if (value is! Map) return null;
    final map = Map<String, Object?>.from(value);
    final kind = map['kind'];
    final title = map['title'];
    final path = map['path'];
    final serverUrl = map['serverUrl'];
    final updatedAt = DateTime.tryParse(map['updatedAt']?.toString() ?? '');
    if (kind is! String || !const {'track', 'folder', 'file'}.contains(kind) ||
        title is! String || path is! String || serverUrl is! String || updatedAt == null) {
      return null;
    }
    return HomeActivityItem(
      kind: kind,
      title: title,
      path: path,
      serverUrl: serverUrl,
      volume: map['volume'] is String ? map['volume'] as String : null,
      updatedAt: updatedAt,
    );
  }
}

class HomeActivityStore extends ChangeNotifier {
  HomeActivityStore._();

  static final instance = HomeActivityStore._();
  static const _key = 'home_recent_activity_v1';
  static const _favoritesKey = 'files_favorites_v1';

  List<HomeActivityItem> _items = const [];
  List<HomeActivityItem> _favorites = const [];

  List<HomeActivityItem> favoritesForServer(String serverUrl) =>
      _favorites.where((item) => item.serverUrl == serverUrl).toList(growable: false);

  bool isFavorite({required String serverUrl, required String path, String? volume}) =>
      _favorites.any((item) => item.serverUrl == serverUrl && item.path == path && item.volume == volume);
  Future<void> _writeQueue = Future<void>.value();

  List<HomeActivityItem> itemsForServer(String serverUrl) =>
      _items.where((item) => item.serverUrl == serverUrl).toList(growable: false);

  Future<void> load() async {
    await _writeQueue;
    _playCounts = const [];
    try {
      final preferences = await SharedPreferences.getInstance();
      final rawCounts = preferences.getString(_playCountsKey);
      final decodedCounts = rawCounts == null ? const [] : jsonDecode(rawCounts);
      if (decodedCounts is List) {
        _playCounts = decodedCounts
            .map(HomeActivityPlayCount.fromJson)
            .whereType<HomeActivityPlayCount>()
            .toList(growable: false);
      }
      final rawFavorites = preferences.getString(_favoritesKey);
      final decodedFavorites = rawFavorites == null ? const [] : jsonDecode(rawFavorites);
      if (decodedFavorites is List) {
        _favorites = decodedFavorites.map(HomeActivityItem.fromJson).whereType<HomeActivityItem>().toList(growable: false);
      }
      final raw = preferences.getString(_key);
      final decoded = raw == null ? const [] : jsonDecode(raw);
      if (decoded is List) {
        _items = decoded.map(HomeActivityItem.fromJson).whereType<HomeActivityItem>().toList()
          ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
      }
    } catch (_) {
      _items = const [];
      _favorites = const [];
    }
    notifyListeners();
  }

  Future<void> toggleFavorite({
    required String serverUrl,
    required String title,
    required String path,
    required bool isFolder,
    String? volume,
  }) {
    final write = _writeQueue.then((_) async {
      final preferences = await SharedPreferences.getInstance();
      final existing = _favorites.indexWhere((item) =>
          item.serverUrl == serverUrl && item.path == path && item.volume == volume);
      final updated = _favorites.toList();
      if (existing >= 0) {
        updated.removeAt(existing);
      } else {
        updated.insert(0, HomeActivityItem(
          kind: isFolder ? 'folder' : 'file',
          title: title,
          path: path,
          serverUrl: serverUrl,
          volume: volume,
          updatedAt: DateTime.now(),
        ));
      }
      _favorites = List.unmodifiable(updated.take(200));
      await preferences.setString(_favoritesKey,
          jsonEncode(_favorites.map((item) => item.toJson()).toList()));
      notifyListeners();
    });
    _writeQueue = write.catchError((_) {});
    return write;
  }

  Future<void> recordTrack({
    required String serverUrl,
    required String title,
    required String path,
    String? volume,
  }) => _record(
    kind: 'track', serverUrl: serverUrl, title: title, path: path,
    volume: volume, incrementPlayCount: true,
  );

  List<HomeActivityPlayCount> mostPlayedForServer(String serverUrl) =>
      _playCounts.where((item) => item.serverUrl == serverUrl).toList()
        ..sort((a, b) => b.count.compareTo(a.count));

  static const _playCountsKey = 'home_track_play_counts_v1';
  List<HomeActivityPlayCount> _playCounts = const [];

  Future<void> recordFolder({
    required String serverUrl,
    required String path,
    String? volume,
  }) => _record(kind: 'folder', serverUrl: serverUrl, title: path.split('/').last, path: path, volume: volume);

  Future<void> recordFile({
    required String serverUrl,
    required String title,
    required String path,
    String? volume,
  }) => _record(kind: 'file', serverUrl: serverUrl, title: title, path: path, volume: volume);

  Future<void> _record({
    required String kind,
    required String serverUrl,
    required String title,
    required String path,
    String? volume,
    bool incrementPlayCount = false,
  }) {
    final write = _writeQueue.then((_) async {
      final preferences = await SharedPreferences.getInstance();
      _items = [
        HomeActivityItem(
          kind: kind,
          title: title.isEmpty ? (path.isEmpty ? 'Internal storage' : path) : title,
          path: path,
          serverUrl: serverUrl,
          volume: volume,
          updatedAt: DateTime.now(),
        ),
        ..._items.where((item) =>
          !(item.kind == kind && item.serverUrl == serverUrl &&
            item.volume == volume && item.path == path)),
      ].take(20).toList(growable: false);
      await preferences.setString(_key, jsonEncode(_items.map((item) => item.toJson()).toList()));
      if (incrementPlayCount) {
        final index = _playCounts.indexWhere((item) =>
          item.serverUrl == serverUrl && item.path == path && item.volume == volume);
        final updated = _playCounts.toList();
        final count = index < 0 ? 1 : updated[index].count + 1;
        final play = HomeActivityPlayCount(
          serverUrl: serverUrl, path: path, volume: volume, count: count,
        );
        if (index < 0) {
          updated.add(play);
        } else {
          updated[index] = play;
        }
        if (updated.length > 2000) {
          updated.sort((a, b) => b.count.compareTo(a.count));
          updated.removeRange(2000, updated.length);
        }
        _playCounts = List.unmodifiable(updated);
        await preferences.setString(_playCountsKey,
          jsonEncode(_playCounts.map((item) => item.toJson()).toList()));
      }
      notifyListeners();
    });
    _writeQueue = write.catchError((_) {});
    return write;
  }
}


class HomeActivityPlayCount {
  const HomeActivityPlayCount({
    required this.serverUrl,
    required this.path,
    required this.count,
    this.volume,
  });

  final String serverUrl;
  final String path;
  final String? volume;
  final int count;

  Map<String, Object?> toJson() => {
    'serverUrl': serverUrl,
    'path': path,
    'volume': volume,
    'count': count,
  };

  static HomeActivityPlayCount? fromJson(Object? value) {
    if (value is! Map) return null;
    final map = Map<String, Object?>.from(value);
    final serverUrl = map['serverUrl'];
    final path = map['path'];
    final count = map['count'];
    if (serverUrl is! String || path is! String || count is! int || count < 1) {
      return null;
    }
    return HomeActivityPlayCount(
      serverUrl: serverUrl,
      path: path,
      volume: map['volume'] is String ? map['volume'] as String : null,
      count: count,
    );
  }
}
