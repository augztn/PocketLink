import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';

class FileEntry {
  const FileEntry({
    required this.name,
    required this.type,
    required this.size,
    required this.modified,
  });

  final String name;
  final String type;
  final int size;
  final String modified;

  bool get isDirectory => type == 'directory';

  factory FileEntry.fromJson(Map<String, dynamic> json) => FileEntry(
        name: json['name'] as String,
        type: json['type'] as String,
        size: (json['size'] as num?)?.toInt() ?? 0,
        modified: json['modified']?.toString() ?? '',
      );
}

class DirectoryListing {
  const DirectoryListing({required this.path, required this.items});

  final String path;
  final List<FileEntry> items;

  factory DirectoryListing.fromJson(Map<String, dynamic> json) =>
      DirectoryListing(
        path: json['path'] as String? ?? '',
        items: (json['items'] as List<dynamic>? ?? const [])
            .map((item) => FileEntry.fromJson(item as Map<String, dynamic>))
            .toList(growable: false),
      );
}

class RecentFile {
  const RecentFile({
    required this.file,
    required this.path,
    required this.volume,
    required this.volumeName,
  });

  final FileEntry file;
  final String path;
  final String? volume;
  final String volumeName;

  String get parentPath {
    final separator = path.lastIndexOf('/');
    return separator < 0 ? '' : path.substring(0, separator);
  }

  DateTime get modifiedAt =>
      DateTime.tryParse(file.modified)?.toLocal() ?? DateTime(1970);
}

class VideoMetadata {
  const VideoMetadata({required this.durationMs, required this.width, required this.height});

  final int durationMs;
  final int width;
  final int height;

  factory VideoMetadata.fromJson(Map<String, dynamic> json) => VideoMetadata(
        durationMs: (json['duration_ms'] as num?)?.toInt() ?? 0,
        width: (json['width'] as num?)?.toInt() ?? 0,
        height: (json['height'] as num?)?.toInt() ?? 0,
      );

  String get resolution => width > 0 && height > 0 ? '${width}×${height}' : '';
}

class StorageVolume {
  const StorageVolume({
    required this.id,
    required this.name,
    required this.available,
    required this.writable,
  });

  final String id;
  final String name;
  final bool available;
  final bool writable;

  factory StorageVolume.fromJson(Map<String, dynamic> json) => StorageVolume(
        id: json['id'] as String,
        name: json['name'] as String,
        available: json['available'] as bool? ?? false,
        writable: json['writable'] as bool? ?? false,
      );
}

class ServerApi {
  ServerApi({
    required String baseUrl,
    required String username,
    required String password,
  }) : _dio = Dio(
          BaseOptions(
            baseUrl: _normalizeBaseUrl(baseUrl),
            connectTimeout: const Duration(seconds: 8),
            receiveTimeout: const Duration(seconds: 30),
            sendTimeout: const Duration(seconds: 30),
            headers: {
              'Accept': 'application/json',
              'Authorization':
                  'Basic ${base64Encode(utf8.encode('$username:$password'))}',
            },
          ),
        );

  final Dio _dio;

  static String _normalizeBaseUrl(String value) {
    final trimmed = value.trim();
    final withScheme = trimmed.startsWith('http://') ||
            trimmed.startsWith('https://')
        ? trimmed
        : 'http://$trimmed';
    final uri = Uri.tryParse(withScheme);

    if (uri == null ||
        trimmed.isEmpty ||
        trimmed.contains(RegExp(r'\s')) ||
        !uri.hasAuthority ||
        uri.host.isEmpty ||
        uri.host.contains('%') ||
        (uri.scheme != 'http' && uri.scheme != 'https') ||
        uri.userInfo.isNotEmpty ||
        (uri.hasPort && (uri.port < 1 || uri.port > 65535))) {
      throw const FormatException('Enter a valid server address and port.');
    }

    return uri.replace(path: '', query: null, fragment: null).toString();
  }

  /// Builds an authenticated streaming URL without downloading media into memory.
  String mediaStreamUrl(String path, {String? volume}) {
    final endpoint = volume == null
        ? '/api/files/stream'
        : '/api/storage/download';
    final query = volume == null
        ? <String, String>{'path': path}
        : <String, String>{'volume': volume, 'path': path};
    return Uri.parse(_dio.options.baseUrl)
        .resolve(endpoint)
        .replace(queryParameters: query)
        .toString();
  }

  /// Headers required by the native media player for authenticated requests.
  Map<String, String> get mediaHeaders => {
        'Authorization': _dio.options.headers['Authorization'] as String,
      };

  final Map<String, Future<Uint8List?>> _thumbnailCache = {};
  final Map<String, Future<VideoMetadata?>> _metadataCache = {};

  void clearMediaCache() {
    _thumbnailCache.clear();
    _metadataCache.clear();
  }

  String _mediaCacheKey(String path, String? volume) => '${volume ?? 'internal'}:$path';

  Future<VideoMetadata?> videoMetadata(String path, {String? volume}) {
    final key = _mediaCacheKey(path, volume);
    final cached = _metadataCache[key];
    if (cached != null) return cached;
    final future = () async {
      try {
        final response = await _dio.get<Map<String, dynamic>>(
          '/api/media/metadata',
          queryParameters: {'path': path, if (volume != null) 'volume': volume},
        );
        return VideoMetadata.fromJson(response.data ?? const {});
      } on DioException {
        return null;
      }
    }();
    _metadataCache[key] = future;
    if (_metadataCache.length > 160) _metadataCache.remove(_metadataCache.keys.first);
    return future;
  }

  Future<Uint8List?> videoThumbnail(String path, {String? volume}) {
    final key = _mediaCacheKey(path, volume);
    final cached = _thumbnailCache[key];
    if (cached != null) return cached;
    final future = () async {
      try {
        final response = await _dio.get<List<int>>(
          '/api/media/thumbnail',
          queryParameters: {'path': path, if (volume != null) 'volume': volume},
          options: Options(responseType: ResponseType.bytes),
        );
        final bytes = response.data;
        return bytes == null || bytes.isEmpty ? null : Uint8List.fromList(bytes);
      } on DioException {
        return null;
      }
    }();
    _thumbnailCache[key] = future;
    if (_thumbnailCache.length > 160) _thumbnailCache.remove(_thumbnailCache.keys.first);
    return future;
  }
  Future<DirectoryListing> authenticate() async => listDirectory('');

  Future<DirectoryListing> listDirectory(String path) async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/api/files/',
      queryParameters: {'path': path},
    );
    return DirectoryListing.fromJson(response.data ?? const {});
  }

  /// Returns recent files from common media/document folders and connected volume roots.
  /// Scans a bounded set of directories only; it never recursively walks storage.
  Future<List<RecentFile>> listRecentFiles({
    int limit = 8,
    List<StorageVolume> volumes = const [],
  }) async {
    final candidates = <({String path, String? volume, String volumeName})>[
      for (final path in const [
        'DCIM', 'Pictures', 'Download', 'Documents', 'Music', 'Movies',
      ])
        (path: path, volume: null, volumeName: 'Internal storage'),
      for (final volume in volumes.where((item) => item.available))
        (path: '', volume: volume.id, volumeName: volume.name),
    ];

    final found = <RecentFile>[];
    final childDirectories = <({String path, String? volume, String volumeName})>[];

    Future<void> scan(
      ({String path, String? volume, String volumeName}) candidate, {
      bool collectChildren = false,
    }) async {
      try {
        final listing = candidate.volume == null
            ? await listDirectory(candidate.path)
            : await listStorageDirectory(candidate.volume!, candidate.path);
        for (final item in listing.items) {
          if (item.name.startsWith('.')) continue;
          final path = candidate.path.isEmpty
              ? item.name
              : '${candidate.path}/${item.name}';
          if (item.isDirectory) {
            if (collectChildren && childDirectories.length < 24) {
              childDirectories.add((
                path: path,
                volume: candidate.volume,
                volumeName: candidate.volumeName,
              ));
            }
          } else {
            found.add(RecentFile(
              file: item,
              path: path,
              volume: candidate.volume,
              volumeName: candidate.volumeName,
            ));
          }
        }
      } catch (_) {
        // A missing, revoked, or unreadable folder must not hide other results.
      }
    }

    await Future.wait(candidates.map(
      (candidate) => scan(candidate, collectChildren: true),
    ));
    await Future.wait(childDirectories.map(scan));

    found.sort((a, b) => b.modifiedAt.compareTo(a.modifiedAt));
    return found.take(limit.clamp(1, 50).toInt()).toList(growable: false);
  }

  Future<void> uploadFile(
    String path,
    String filename,
    Uint8List bytes, {
    ProgressCallback? onSendProgress,
    CancelToken? cancelToken,
  }) async {
    final form = FormData.fromMap({
      'file': MultipartFile.fromBytes(bytes, filename: filename),
    });
    await _dio.post<void>(
      '/api/files/upload',
      queryParameters: {'path': path},
      data: form,
      onSendProgress: onSendProgress,
      cancelToken: cancelToken,
    );
  }

  Future<Uint8List> downloadFile(
    String path, {
    ProgressCallback? onReceiveProgress,
    CancelToken? cancelToken,
  }) async {
    final response = await _dio.get<List<int>>(
      '/api/files/download',
      queryParameters: {'path': path},
      options: Options(responseType: ResponseType.bytes),
      onReceiveProgress: onReceiveProgress,
      cancelToken: cancelToken,
    );
    return Uint8List.fromList(response.data ?? const <int>[]);
  }

  Future<void> createFolder(String path, String name) async {
    await _dio.post<void>(
      '/api/files/mkdir',
      data: {'path': path, 'name': name},
    );
  }

  Future<void> renameItem(String path, String newName) async {
    await _dio.patch<void>(
      '/api/files/rename',
      data: {'path': path, 'new_name': newName},
    );
  }

  Future<void> deleteItem(String path) async {
    await _dio.delete<void>(
      '/api/files/item',
      queryParameters: {'path': path},
    );
  }

  Future<List<StorageVolume>> listStorageVolumes() async {
    final response =
        await _dio.get<Map<String, dynamic>>('/api/storage/volumes');
    return (response.data?['items'] as List<dynamic>? ?? const [])
        .map((item) => StorageVolume.fromJson(item as Map<String, dynamic>))
        .toList(growable: false);
  }

  Future<DirectoryListing> listStorageDirectory(
    String volume,
    String path,
  ) async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/api/storage/list',
      queryParameters: {'volume': volume, 'path': path},
    );
    return DirectoryListing.fromJson(response.data ?? const {});
  }

  Future<void> uploadStorageFile(
    String volume,
    String path,
    String filename,
    Uint8List bytes, {
    ProgressCallback? onSendProgress,
    CancelToken? cancelToken,
  }) async {
    final form = FormData.fromMap({
      'file': MultipartFile.fromBytes(bytes, filename: filename),
    });
    await _dio.post<void>(
      '/api/storage/upload',
      queryParameters: {'volume': volume, 'path': path},
      data: form,
      onSendProgress: onSendProgress,
      cancelToken: cancelToken,
    );
  }

  Future<Uint8List> downloadStorageFile(
    String volume,
    String path, {
    ProgressCallback? onReceiveProgress,
    CancelToken? cancelToken,
  }) async {
    final response = await _dio.get<List<int>>(
      '/api/storage/download',
      queryParameters: {'volume': volume, 'path': path},
      options: Options(responseType: ResponseType.bytes),
      onReceiveProgress: onReceiveProgress,
      cancelToken: cancelToken,
    );
    return Uint8List.fromList(response.data ?? const <int>[]);
  }

  Future<void> createStorageFolder(
    String volume,
    String path,
    String name,
  ) async {
    await _dio.post<void>(
      '/api/storage/mkdir',
      data: {'volume': volume, 'path': path, 'name': name},
    );
  }

  Future<void> renameStorageItem(
    String volume,
    String path,
    String name,
  ) async {
    await _dio.post<void>(
      '/api/storage/rename',
      data: {'volume': volume, 'path': path, 'new_name': name},
    );
  }

  Future<void> deleteStorageItem(String volume, String path) async {
    await _dio.delete<void>(
      '/api/storage/item',
      queryParameters: {'volume': volume, 'path': path},
    );
  }
}
