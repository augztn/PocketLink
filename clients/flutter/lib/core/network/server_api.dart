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

  Future<DirectoryListing> authenticate() async => listDirectory('');

  Future<DirectoryListing> listDirectory(String path) async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/api/files/',
      queryParameters: {'path': path},
    );
    return DirectoryListing.fromJson(response.data ?? const {});
  }

  Future<void> uploadFile(
    String path,
    String filename,
    Uint8List bytes, {
    ProgressCallback? onSendProgress,
  }) async {
    final form = FormData.fromMap({
      'file': MultipartFile.fromBytes(bytes, filename: filename),
    });
    await _dio.post<void>(
      '/api/files/upload',
      queryParameters: {'path': path},
      data: form,
      onSendProgress: onSendProgress,
    );
  }

  Future<Uint8List> downloadFile(
    String path, {
    ProgressCallback? onReceiveProgress,
  }) async {
    final response = await _dio.get<List<int>>(
      '/api/files/download',
      queryParameters: {'path': path},
      options: Options(responseType: ResponseType.bytes),
      onReceiveProgress: onReceiveProgress,
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
  }) async {
    final form = FormData.fromMap({
      'file': MultipartFile.fromBytes(bytes, filename: filename),
    });
    await _dio.post<void>(
      '/api/storage/upload',
      queryParameters: {'volume': volume, 'path': path},
      data: form,
      onSendProgress: onSendProgress,
    );
  }

  Future<Uint8List> downloadStorageFile(
    String volume,
    String path, {
    ProgressCallback? onReceiveProgress,
  }) async {
    final response = await _dio.get<List<int>>(
      '/api/storage/download',
      queryParameters: {'volume': volume, 'path': path},
      options: Options(responseType: ResponseType.bytes),
      onReceiveProgress: onReceiveProgress,
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
