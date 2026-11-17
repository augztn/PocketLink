import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path_provider/path_provider.dart';

import 'server_api.dart';

class OfflineFile {
  const OfflineFile({
    required this.key,
    required this.server,
    required this.path,
    required this.volume,
    required this.name,
    required this.size,
    required this.modified,
    required this.localPath,
    required this.accessedAt,
  });

  final String key;
  final String server;
  final String path;
  final String? volume;
  final String name;
  final int size;
  final String modified;
  final String localPath;
  final DateTime accessedAt;

  FileEntry get entry => FileEntry(
        name: name,
        type: 'file',
        size: size,
        modified: modified,
      );

  Map<String, Object?> toJson() => {
        'key': key,
        'server': server,
        'path': path,
        'volume': volume,
        'name': name,
        'size': size,
        'modified': modified,
        'localPath': localPath,
        'accessedAt': accessedAt.toIso8601String(),
      };

  factory OfflineFile.fromJson(Map<String, dynamic> json) => OfflineFile(
        key: json['key'] as String,
        server: json['server'] as String,
        path: json['path'] as String,
        volume: json['volume'] as String?,
        name: json['name'] as String,
        size: (json['size'] as num).toInt(),
        modified: json['modified'] as String? ?? '',
        localPath: json['localPath'] as String,
        accessedAt: DateTime.tryParse(json['accessedAt'] as String? ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(0),
      );
}

/// Persistent, app-private LRU cache. Cached bytes are the original server
/// response; this service never transcodes, recompresses, or rewrites content.
class OfflineFileCache {
  OfflineFileCache({this.maxBytes = 512 * 1024 * 1024});

  final int maxBytes;
  final Map<String, OfflineFile> _entries = {};
  Future<void>? _loading;
  Directory? _directory;

  Future<Directory> _root() async {
    final cached = _directory;
    if (cached != null) return cached;
    final support = await getApplicationSupportDirectory();
    final root = Directory('${support.path}/pocketlink/offline-cache');
    final legacy = Directory('${support.path}/homeserver/offline-cache');
    if (!await root.exists() && await legacy.exists()) {
      await legacy.rename(root.path);
    }
    await root.create(recursive: true);
    _directory = root;
    return root;
  }

  String serverId(ServerApi api) => sha256
      .convert(utf8.encode('${api.baseUrl}|${api.mediaHeaders['Authorization']}'))
      .toString();

  String _key(String server, String? volume, String path) =>
      sha256.convert(utf8.encode('$server|${volume ?? 'internal'}|$path')).toString();

  Future<void> _ensureLoaded() async {
    if (_loading != null) return _loading!;
    _loading = () async {
      final root = await _root();
      final index = File('${root.path}/index.json');
      if (!await index.exists()) return;
      try {
        final decoded = jsonDecode(await index.readAsString()) as List<dynamic>;
        for (final item in decoded) {
          final entry = OfflineFile.fromJson(item as Map<String, dynamic>);
          if (await File(entry.localPath).exists()) _entries[entry.key] = entry;
        }
      } catch (_) {
        _entries.clear();
      }
    }();
    await _loading;
  }

  Future<void> _persist() async {
    final root = await _root();
    final target = File('${root.path}/index.json');
    final temp = File('${root.path}/index.json.tmp');
    await temp.writeAsString(jsonEncode(_entries.values.map((e) => e.toJson()).toList()));
    if (await target.exists()) await target.delete();
    await temp.rename(target.path);
  }

  Future<List<OfflineFile>> list({String? server}) async {
    await _ensureLoaded();
    return _entries.values
        .where((e) => server == null || e.server == server)
        .toList()
      ..sort((a, b) => b.accessedAt.compareTo(a.accessedAt));
  }

  Future<OfflineFile?> find(String server, String? volume, String path) async {
    await _ensureLoaded();
    final key = _key(server, volume, path);
    final entry = _entries[key];
    if (entry == null) return null;
    if (!await File(entry.localPath).exists()) {
      _entries.remove(key);
      await _persist();
      return null;
    }
    return entry;
  }

  Future<OfflineFile> cache({
    required ServerApi api,
    required String path,
    required String name,
    required int size,
    required String modified,
    String? volume,
  }) async {
    if (size < 0 || size > maxBytes) {
      throw StateError('This file is larger than the offline cache limit.');
    }
    await _ensureLoaded();
    final server = serverId(api);
    final key = _key(server, volume, path);
    final existing = _entries[key];
    if (existing != null && await File(existing.localPath).exists()) return existing;

    final root = await _root();
    final extension = name.contains('.')
        ? name.substring(name.lastIndexOf('.') + 1).toLowerCase()
        : '';
    final validExtension = extension.isNotEmpty &&
        extension.length <= 12 &&
        extension.runes.every((value) =>
            (value >= 48 && value <= 57) || (value >= 97 && value <= 122));
    final safeExtension = validExtension ? extension : 'bin';
    final target = File('${root.path}/$key.$safeExtension');
    final temp = File('${root.path}/$key.part');
    try {
      await api.downloadToFile(path, temp.path, volume: volume);
      final actualSize = await temp.length();
      if (actualSize > maxBytes) {
        throw StateError('Downloaded file exceeds the offline cache limit.');
      }
      var used = _entries.values.fold<int>(0, (sum, item) => sum + item.size);
      final victims = _entries.values.toList()
        ..sort((a, b) => a.accessedAt.compareTo(b.accessedAt));
      for (final victim in victims) {
        if (used + actualSize <= maxBytes) break;
        await File(victim.localPath).delete().catchError((_) => File(victim.localPath));
        _entries.remove(victim.key);
        used -= victim.size;
      }
      if (used + actualSize > maxBytes) {
        throw StateError('Not enough space in the offline cache.');
      }
      if (await target.exists()) await target.delete();
      await temp.rename(target.path);
      final entry = OfflineFile(
        key: key,
        server: server,
        path: path,
        volume: volume,
        name: name,
        size: actualSize,
        modified: modified,
        localPath: target.path,
        accessedAt: DateTime.now(),
      );
      _entries[key] = entry;
      await _persist();
      return entry;
    } catch (_) {
      if (await temp.exists()) await temp.delete();
      rethrow;
    }
  }

  Future<void> remove(String server, String? volume, String path) async {
    await _ensureLoaded();
    final key = _key(server, volume, path);
    final entry = _entries.remove(key);
    if (entry != null) {
      await File(entry.localPath).delete().catchError((_) => File(entry.localPath));
      await _persist();
    }
  }

  Future<void> clear({String? server}) async {
    await _ensureLoaded();
    final selected = _entries.values
        .where((e) => server == null || e.server == server)
        .toList();
    for (final entry in selected) {
      await File(entry.localPath).delete().catchError((_) => File(entry.localPath));
      _entries.remove(entry.key);
    }
    await _persist();
  }
}
