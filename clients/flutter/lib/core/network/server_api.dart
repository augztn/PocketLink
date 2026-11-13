import 'dart:convert';

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
        modified: json['modified'] as String? ?? '',
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
        !uri.hasAuthority ||
        uri.host.isEmpty ||
        (uri.scheme != 'http' && uri.scheme != 'https') ||
        uri.userInfo.isNotEmpty) {
      throw const FormatException('Enter a valid server address and port.');
    }

    return uri.replace(path: '', query: null, fragment: null).toString();
  }

  Future<bool> checkHealth() async {
    final response = await _dio.get<dynamic>(
      '/health',
      options: Options(headers: {'Authorization': null}),
    );
    return response.statusCode == 200;
  }

  Future<DirectoryListing> authenticate() async => listDirectory('');

  Future<DirectoryListing> listDirectory(String path) async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/api/files/',
      queryParameters: {'path': path},
    );
    return DirectoryListing.fromJson(response.data ?? const {});
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
}
