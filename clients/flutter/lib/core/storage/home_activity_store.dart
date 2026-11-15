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
      volume: map['volume'] as String?,
      updatedAt: updatedAt,
    );
  }
}

class HomeActivityStore extends ChangeNotifier {
  HomeActivityStore._();

  static final instance = HomeActivityStore._();
  static const _key = 'home_recent_activity_v1';

  List<HomeActivityItem> _items = const [];
  Future<void> _writeQueue = Future<void>.value();

  List<HomeActivityItem> itemsForServer(String serverUrl) =>
      _items.where((item) => item.serverUrl == serverUrl).toList(growable: false);

  Future<void> load() async {
    try {
      final preferences = await SharedPreferences.getInstance();
      final raw = preferences.getString(_key);
      final decoded = raw == null ? const [] : jsonDecode(raw);
      if (decoded is List) {
        _items = decoded.map(HomeActivityItem.fromJson).whereType<HomeActivityItem>().toList()
          ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
      }
    } catch (_) {
      _items = const [];
    }
    notifyListeners();
  }

  Future<void> recordTrack({
    required String serverUrl,
    required String title,
    required String path,
    String? volume,
  }) => _record(kind: 'track', serverUrl: serverUrl, title: title, path: path, volume: volume);

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
      notifyListeners();
    });
    _writeQueue = write.catchError((_) {});
    return write;
  }
}
