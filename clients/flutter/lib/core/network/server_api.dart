import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io' show HttpDate;
import 'dart:typed_data';

import 'package:dio/dio.dart';

import 'server_api_models.dart';

import '../logging/app_logger.dart';

export 'server_api_models.dart';
part 'server_api_transport.dart';

class _CacheEntry<T> {
  const _CacheEntry(this.value, this.expiresAt);
  final T value;
  final DateTime expiresAt;
}

class ServerApi {
  ServerApi({
    required String baseUrl,
    required String username,
    required String password,
    HttpClientAdapter? httpClientAdapter,
  }) : _transport = _ServerApiTransport(
          baseUrl: baseUrl,
          username: username,
          password: password,
          httpClientAdapter: httpClientAdapter,
        );

  final _ServerApiTransport _transport;
  Dio get _dio => _transport.client;

  bool _closed = false;
  static const _directoryCacheTtl = Duration(seconds: 20);
  static const _maxCachedDirectories = 512;
  final Map<String, _CacheEntry<DirectoryListing>> _directoryCache = {};
  final Map<String, Future<DirectoryListing>> _directoryRequests = {};
  _CacheEntry<List<StorageVolume>>? _volumesCache;
  Future<List<StorageVolume>>? _volumesRequest;
  int _cacheGeneration = 0;

  Future<T> _cachedGet<T>(
    String key,
    Map<String, _CacheEntry<T>> cache,
    Map<String, Future<T>> requests,
    Future<T> Function() load,
  ) {
    final cached = cache[key];
    if (cached != null && cached.expiresAt.isAfter(DateTime.now())) {
      return Future<T>.value(cached.value);
    }
    final existing = requests[key];
    if (existing != null) return existing;

    final generation = _cacheGeneration;
    late final Future<T> request;
    request = load().then<T>((value) {
      if (generation != _cacheGeneration) {
        if (identical(requests[key], request)) requests.remove(key);
        if (_closed) return value;
        return _cachedGet<T>(key, cache, requests, load);
      }
      if (cache.length >= _maxCachedDirectories && !cache.containsKey(key)) {
        cache.remove(cache.keys.first);
      }
      cache[key] = _CacheEntry(value, DateTime.now().add(_directoryCacheTtl));
      return value;
    }).whenComplete(() {
      if (identical(requests[key], request)) requests.remove(key);
    });
    requests[key] = request;
    return request;
  }

  /// Invalidates short-lived directory and volume snapshots after refreshes or writes.
  void invalidateDirectoryCache() {
    _cacheGeneration++;
    _directoryCache.clear();
    _directoryRequests.clear();
    _volumesCache = null;
    _volumesRequest = null;
  }

  String get baseUrl => _dio.options.baseUrl;

  /// Releases the underlying HTTP adapter and cached client state.
  void close({bool force = false}) {
    if (_closed) return;
    _closed = true;
    invalidateDirectoryCache();
    clearMediaCache();
    _transport.close(force: force);
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

  /// Opens an authenticated file stream and requests a byte range when resuming.
  Future<Response<ResponseBody>> openDownloadStream({
    required String path,
    String? volume,
    int offset = 0,
    CancelToken? cancelToken,
  }) {
    return _dio.get<ResponseBody>(
      volume == null ? '/api/files/stream' : '/api/storage/download',
      queryParameters: {'path': path, if (volume != null) 'volume': volume},
      options: Options(
        responseType: ResponseType.stream,
        headers: offset > 0 ? {'Range': 'bytes=$offset-'} : null,
      ),
      cancelToken: cancelToken,
    );
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
  Future<DirectoryListing> authenticate({CancelToken? cancelToken}) =>
      listDirectory('', cancelToken: cancelToken);

  Future<DirectoryListing> listDirectory(
    String path, {CancelToken? cancelToken}
  ) => _cachedGet(
        'files:$path',
        _directoryCache,
        _directoryRequests,
        () {
          Future<DirectoryListing> load() async {
            final response = await _dio.get<Map<String, dynamic>>(
              '/api/files/',
              queryParameters: {'path': path},
              cancelToken: cancelToken,
            );
            return DirectoryListing.fromJson(response.data ?? const {});
          }

          // A cancellable caller owns its request; only non-cancellable reads are shared.
          return cancelToken == null
              ? _transport._sharedRead('files:$path', load)
              : load();
        },
      );

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
            if (collectChildren && childDirectories.length < 6) {
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
    invalidateDirectoryCache();
  }

  Future<ServerDownloadJob> enqueueServerDownload(
    String url, {String? directory}
  ) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/api/downloads',
      data: {'url': url, if (directory != null && directory.trim().isNotEmpty) 'directory': directory.trim()},
    );
    return ServerDownloadJob.fromJson(response.data ?? const {});
  }

  Future<List<ServerDownloadJob>> listServerDownloads() async {
    final response = await _dio.get<Map<String, dynamic>>('/api/downloads');
    return (response.data?['items'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(ServerDownloadJob.fromJson)
        .toList(growable: false);
  }

  Future<ServerDownloadJob> _serverDownloadAction(
    String id, String action,
  ) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/api/downloads/$id/$action',
    );
    return ServerDownloadJob.fromJson(response.data ?? const {});
  }

  Future<ServerDownloadJob> pauseServerDownload(String id) =>
      _serverDownloadAction(id, 'pause');

  Future<ServerDownloadJob> resumeServerDownload(String id) =>
      _serverDownloadAction(id, 'resume');

  Future<ServerDownloadJob> cancelServerDownload(String id) =>
      _serverDownloadAction(id, 'cancel');

  Future<void> removeServerDownload(
    String id, {bool deleteFile = false}
  ) async {
    await _dio.delete<void>(
      '/api/downloads/$id',
      queryParameters: {'delete_file': deleteFile},
    );
  }

  /// Downloads an original file directly to disk without buffering it in memory.
  Future<void> downloadToFile(
    String path,
    String destination, {
    String? volume,
    ProgressCallback? onReceiveProgress,
    CancelToken? cancelToken,
  }) async {
    await _dio.download(
      volume == null ? '/api/files/download' : '/api/storage/download',
      destination,
      queryParameters: {'path': path, if (volume != null) 'volume': volume},
      onReceiveProgress: onReceiveProgress,
      cancelToken: cancelToken,
      deleteOnError: true,
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
    invalidateDirectoryCache();
  }

  Future<void> renameItem(String path, String newName) async {
    await _dio.patch<void>(
      '/api/files/rename',
      data: {'path': path, 'new_name': newName},
    );
    invalidateDirectoryCache();
  }

  Future<void> deleteItem(String path) async {
    await _dio.delete<void>(
      '/api/files/item',
      queryParameters: {'path': path},
    );
    invalidateDirectoryCache();
  }

  Future<List<StorageVolume>> listStorageVolumes() async {
    final cached = _volumesCache;
    if (cached != null && cached.expiresAt.isAfter(DateTime.now())) {
      return cached.value;
    }
    final existing = _volumesRequest;
    if (existing != null) return existing;

    final generation = _cacheGeneration;
    late final Future<List<StorageVolume>> request;
    request = _transport._sharedRead<List<StorageVolume>>('storage:volumes', () async {
      final response =
          await _dio.get<Map<String, dynamic>>('/api/storage/volumes');
      return (response.data?['items'] as List<dynamic>? ?? const [])
          .map((item) => StorageVolume.fromJson(item as Map<String, dynamic>))
          .toList(growable: false);
    }).then<List<StorageVolume>>((volumes) async {
      if (generation != _cacheGeneration) {
        if (identical(_volumesRequest, request)) _volumesRequest = null;
        if (_closed) return volumes;
        return await listStorageVolumes();
      }
      _volumesCache = _CacheEntry(
        volumes,
        DateTime.now().add(_directoryCacheTtl),
      );
      return volumes;
    }).whenComplete(() {
      if (identical(_volumesRequest, request)) _volumesRequest = null;
    });
    _volumesRequest = request;
    return request;
  }

  Future<HostSystemTelemetry> systemTelemetry() async {
    final response = await _dio.get<Map<String, dynamic>>('/api/system/telemetry');
    return HostSystemTelemetry.fromJson(response.data ?? const {});
  }

  Future<MediaIndexStatus> mediaIndexStatus() async {
    final response = await _dio.get<Map<String, dynamic>>('/api/index/status');
    return MediaIndexStatus.fromJson(response.data ?? const {});
  }

  Future<MediaIndexStatus> startMediaIndexScan() async {
    final response = await _dio.post<Map<String, dynamic>>('/api/index/scan');
    return MediaIndexStatus.fromJson(response.data ?? const {});
  }

  Future<MediaIndexStatus> retryFailedMediaScan() async {
    final response = await _dio.post<Map<String, dynamic>>('/api/index/retry');
    return MediaIndexStatus.fromJson(response.data ?? const {});
  }

  Future<AutomaticMediaScanSettings> updateAutomaticMediaScanning({
    required bool enabled,
    required int intervalMinutes,
    required bool scanOnStartup,
    required bool scanOnStorageChange,
  }) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/api/index/settings',
      queryParameters: {
        'enabled': enabled,
        'interval_minutes': intervalMinutes,
        'scan_on_startup': scanOnStartup,
        'scan_on_storage_change': scanOnStorageChange,
      },
    );
    return AutomaticMediaScanSettings.fromJson(response.data ?? const {});
  }

  Future<IndexedMediaPage> indexedMedia(
    String category, {String query = '', int limit = 500, int offset = 0}
  ) async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/api/index/media',
      queryParameters: {'category': category, 'q': query, 'limit': limit, 'offset': offset},
    );
    final data = response.data ?? const <String, dynamic>{};
    return IndexedMediaPage(
      items: (data['items'] as List<dynamic>? ?? const [])
          .map((item) => IndexedFile.fromJson(item as Map<String, dynamic>))
          .toList(growable: false),
      status: MediaIndexStatus.fromJson(data['status'] as Map<String, dynamic>? ?? const {}),
    );
  }

  Future<IndexedMediaPage> searchIndexedFiles(
    String query, {int limit = 100, int offset = 0}
  ) async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/api/index/files',
      queryParameters: {'q': query, 'limit': limit, 'offset': offset},
    );
    final data = response.data ?? const <String, dynamic>{};
    return IndexedMediaPage(
      items: (data['items'] as List<dynamic>? ?? const [])
          .map((item) => IndexedFile.fromJson(item as Map<String, dynamic>))
          .toList(growable: false),
      status: MediaIndexStatus.fromJson(data['status'] as Map<String, dynamic>? ?? const {}),
    );
  }

  Future<DirectoryListing> listStorageDirectory(
    String volume,
    String path,
  ) => _cachedGet(
        'storage:$volume:$path',
        _directoryCache,
        _directoryRequests,
        () => _transport._sharedRead('storage:$volume:$path', () async {
          final response = await _dio.get<Map<String, dynamic>>(
            '/api/storage/list',
            queryParameters: {'volume': volume, 'path': path},
          );
          return DirectoryListing.fromJson(response.data ?? const {});
        }),
      );

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
    invalidateDirectoryCache();
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
    invalidateDirectoryCache();
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
    invalidateDirectoryCache();
  }

  Future<void> deleteStorageItem(String volume, String path) async {
    await _dio.delete<void>(
      '/api/storage/item',
      queryParameters: {'volume': volume, 'path': path},
    );
    invalidateDirectoryCache();
  }
}
