import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io' show HttpDate;
import 'dart:typed_data';

import 'package:dio/dio.dart';

import '../logging/app_logger.dart';

class FileEntry {
  const FileEntry({
    required this.name,
    required this.type,
    required this.size,
    required this.modified,
    this.created,
  });

  final String name;
  final String type;
  final int size;
  final String modified;
  final String? created;

  bool get isDirectory => type == 'directory';

  factory FileEntry.fromJson(Map<String, dynamic> json) => FileEntry(
        name: json['name'] as String,
        type: json['type'] as String,
        size: (json['size'] as num?)?.toInt() ?? 0,
        modified: json['modified']?.toString() ?? '',
        created: json['created']?.toString(),
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


class HostSystemTelemetry {
  const HostSystemTelemetry({
    required this.sampledAtMs,
    required this.manufacturer,
    required this.deviceModel,
    required this.androidVersion,
    required this.cpuModel,
    required this.cpuCores,
    required this.cpuUsagePercent,
    required this.cpuUsageStatus,
    required this.memoryTotalBytes,
    required this.memoryUsedBytes,
    required this.memoryAvailableBytes,
    required this.memoryUsagePercent,
    required this.storageTotalBytes,
    required this.storageUsedBytes,
    required this.storageAvailableBytes,
    required this.storageUsagePercent,
    required this.batteryPercent,
    required this.batteryStatus,
  });

  final int? sampledAtMs;
  final String? manufacturer;
  final String? deviceModel;
  final String? androidVersion;
  final String? cpuModel;
  final int? cpuCores;
  final double? cpuUsagePercent;
  final String cpuUsageStatus;
  final int? memoryTotalBytes;
  final int? memoryUsedBytes;
  final int? memoryAvailableBytes;
  final double? memoryUsagePercent;
  final int? storageTotalBytes;
  final int? storageUsedBytes;
  final int? storageAvailableBytes;
  final double? storageUsagePercent;
  final int? batteryPercent;
  final String batteryStatus;

  bool get isCharging => batteryStatus == 'charging';

  factory HostSystemTelemetry.fromJson(Map<String, dynamic> json) {
    Map<String, dynamic> section(String key) {
      final value = json[key];
      return value is Map<String, dynamic> ? value : const {};
    }

    int? integer(Object? value) =>
        value is num ? value.toInt() : int.tryParse(value?.toString() ?? '');
    double? decimal(Object? value) =>
        value is num ? value.toDouble() : double.tryParse(value?.toString() ?? '');
    String? string(Object? value) {
      final text = value?.toString().trim();
      return text == null || text.isEmpty ? null : text;
    }

    final device = section('device');
    final cpu = section('cpu');
    final memory = section('memory');
    final storage = section('storage');
    final battery = section('battery');

    return HostSystemTelemetry(
      sampledAtMs: integer(json['sampled_at_ms']),
      manufacturer: string(device['manufacturer']),
      deviceModel: string(device['model']),
      androidVersion: string(device['android_version']),
      cpuModel: string(cpu['model']),
      cpuCores: integer(cpu['cores']),
      cpuUsagePercent: decimal(cpu['usage_percent']),
      cpuUsageStatus: string(cpu['usage_status']) ?? 'unavailable',
      memoryTotalBytes: integer(memory['total_bytes']),
      memoryUsedBytes: integer(memory['used_bytes']),
      memoryAvailableBytes: integer(memory['available_bytes']),
      memoryUsagePercent: decimal(memory['usage_percent']),
      storageTotalBytes: integer(storage['total_bytes']),
      storageUsedBytes: integer(storage['used_bytes']),
      storageAvailableBytes: integer(storage['available_bytes']),
      storageUsagePercent: decimal(storage['usage_percent']),
      batteryPercent: integer(battery['percent']),
      batteryStatus: string(battery['status']) ?? 'unknown',
    );
  }
}

class StorageVolume {
  const StorageVolume({
    required this.id,
    required this.name,
    required this.available,
    required this.writable,
    this.totalBytes,
    this.usedBytes,
    this.availableBytes,
    this.usagePercent,
  });

  final String id;
  final String name;
  final bool available;
  final bool writable;
  final int? totalBytes;
  final int? usedBytes;
  final int? availableBytes;
  final double? usagePercent;

  factory StorageVolume.fromJson(Map<String, dynamic> json) => StorageVolume(
        id: json['id'] as String,
        name: json['name'] as String,
        available: json['available'] as bool? ?? false,
        writable: json['writable'] as bool? ?? false,
        totalBytes: (json['total_bytes'] as num?)?.toInt(),
        usedBytes: (json['used_bytes'] as num?)?.toInt(),
        availableBytes: (json['available_bytes'] as num?)?.toInt(),
        usagePercent: (json['usage_percent'] as num?)?.toDouble(),
      );
}

class IndexedFile {
  const IndexedFile({
    required this.volume, required this.path, required this.name,
    required this.type, required this.size, required this.modified,
    required this.mime, this.category,
  });
  final String volume;
  final String path;
  final String name;
  final String type;
  final int size;
  final String modified;
  final String mime;
  final String? category;
  bool get isDirectory => type == 'directory';

  factory IndexedFile.fromJson(Map<String, dynamic> json) => IndexedFile(
    volume: json['volume'] as String? ?? 'internal',
    path: json['path'] as String? ?? '',
    name: json['name'] as String? ?? '',
    type: json['type'] as String? ?? 'file',
    size: (json['size'] as num?)?.toInt() ?? 0,
    modified: json['modified']?.toString() ?? '',
    mime: json['mime']?.toString() ?? 'application/octet-stream',
    category: json['category']?.toString(),
  );

  FileEntry toFileEntry() => FileEntry(
    name: name, type: type, size: size, modified: modified,
  );
}

class SkippedMediaIndexItem {
  const SkippedMediaIndexItem({required this.volume, required this.path, required this.reason});
  final String volume;
  final String path;
  final String reason;

  factory SkippedMediaIndexItem.fromJson(Map<String, dynamic> json) => SkippedMediaIndexItem(
    volume: json['volume']?.toString() ?? 'internal',
    path: json['path']?.toString() ?? '',
    reason: json['reason']?.toString() ?? 'Could not index this location',
  );
}

class MediaIndexStatus {
  const MediaIndexStatus({
    required this.state, required this.scanned, required this.skipped,
    required this.lastCompletedAt, required this.fileCount,
    required this.mediaCount, this.lastError,
    this.lastScanStartedAt = 0, this.elapsedMs = 0, this.currentSource,
    this.currentPath, this.scannedDirectories = 0, this.unchangedCount = 0,
    this.indexedCount = 0, this.directoryCount = 0, this.regularFileCount = 0,
    this.photoCount = 0, this.videoCount = 0, this.musicCount = 0,
    this.skippedItems = const [],
  });
  final String state;
  final int scanned;
  final int skipped;
  final int lastCompletedAt;
  /// Total indexed entries, including directories (kept for API compatibility).
  final int fileCount;
  final int mediaCount;
  final String? lastError;
  final int lastScanStartedAt;
  final int elapsedMs;
  final String? currentSource;
  final String? currentPath;
  final int scannedDirectories;
  final int unchangedCount;
  final int indexedCount;
  final int directoryCount;
  final int regularFileCount;
  final int photoCount;
  final int videoCount;
  final int musicCount;
  final List<SkippedMediaIndexItem> skippedItems;
  bool get isScanning => state == 'scanning';
  bool get isUsable => state == 'complete' || state == 'partial';

  factory MediaIndexStatus.fromJson(Map<String, dynamic> json) =>
      MediaIndexStatus(
        state: json['state']?.toString() ?? 'idle',
        scanned: (json['scanned'] as num?)?.toInt() ?? 0,
        skipped: (json['skipped'] as num?)?.toInt() ?? 0,
        lastCompletedAt: (json['last_completed_at'] as num?)?.toInt() ?? 0,
        fileCount: (json['file_count'] as num?)?.toInt() ?? 0,
        mediaCount: (json['media_count'] as num?)?.toInt() ?? 0,
        lastError: json['last_error']?.toString(),
        lastScanStartedAt: (json['last_scan_started_at'] as num?)?.toInt() ?? 0,
        elapsedMs: (json['elapsed_ms'] as num?)?.toInt() ?? 0,
        currentSource: json['current_source']?.toString(),
        currentPath: json['current_path']?.toString(),
        scannedDirectories: (json['scanned_directories'] as num?)?.toInt() ?? 0,
        unchangedCount: (json['unchanged_count'] as num?)?.toInt() ?? 0,
        indexedCount: (json['indexed_count'] as num?)?.toInt() ?? 0,
        directoryCount: (json['directory_count'] as num?)?.toInt() ?? 0,
        regularFileCount: (json['regular_file_count'] as num?)?.toInt() ?? 0,
        photoCount: (json['photo_count'] as num?)?.toInt() ?? 0,
        videoCount: (json['video_count'] as num?)?.toInt() ?? 0,
        musicCount: (json['music_count'] as num?)?.toInt() ?? 0,
        skippedItems: (json['skipped_items'] as List<dynamic>? ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(SkippedMediaIndexItem.fromJson)
            .toList(growable: false),
      );
}

class IndexedMediaPage {
  const IndexedMediaPage({required this.items, required this.status});
  final List<IndexedFile> items;
  final MediaIndexStatus status;
}

class _RequestGate {
  _RequestGate(this.limit);

  final int limit;
  int _active = 0;
  final Queue<Completer<void>> _waiters = Queue<Completer<void>>();

  Future<void> acquire(CancelToken? cancelToken) async {
    if (cancelToken?.isCancelled ?? false) {
      throw DioException(
        requestOptions: RequestOptions(path: ''),
        type: DioExceptionType.cancel,
        message: 'Request cancelled while waiting for an API slot.',
      );
    }
    if (_active < limit) {
      _active++;
      return;
    }
    final waiter = Completer<void>();
    _waiters.addLast(waiter);
    cancelToken?.whenCancel.then<void>((error) {
      if (_waiters.remove(waiter) && !waiter.isCompleted) {
        waiter.completeError(error);
      }
    });
    await waiter.future;
  }

  void release() {
    if (_waiters.isNotEmpty) {
      _waiters.removeFirst().complete();
    } else if (_active > 0) {
      _active--;
    }
  }
}

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
  })  : _requestGate = _RequestGate(4),
        _dio = Dio(
          BaseOptions(
            baseUrl: _normalizeBaseUrl(baseUrl),
            connectTimeout: const Duration(seconds: 10),
            receiveTimeout: const Duration(seconds: 30),
            sendTimeout: const Duration(seconds: 30),
            headers: {
              'Accept': 'application/json',
              'Authorization':
                  'Basic ${base64Encode(utf8.encode('$username:$password'))}',
            },
          ),
        ) {
    if (httpClientAdapter != null) _dio.httpClientAdapter = httpClientAdapter;
    _dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) async {
        final queueStopwatch = Stopwatch()..start();
        try {
          await _requestGate.acquire(options.cancelToken);
          options.extra['pocketlink.requestSlot'] = true;
        } on DioException catch (error) {
          handler.reject(error);
          return;
        }
        final requestId = AppLogger.nextEventId('http');
        options.extra['pocketlink.requestId'] = requestId;
        options.extra['pocketlink.queueWaitMs'] = queueStopwatch.elapsedMilliseconds;
        options.extra['pocketlink.queryKey'] = _diagnosticQueryKey(options);
        options.extra['pocketlink.requestStopwatch'] = Stopwatch()..start();
        AppLogger.info('API request started', fields: {
          'requestId': requestId,
          'method': options.method,
          'path': options.uri.path,
          'queryKey': options.extra['pocketlink.queryKey'],
          'queueWaitMs': options.extra['pocketlink.queueWaitMs'],
          'retry': options.extra['pocketlink.retryCount'] ?? 0,
          'concurrencyLimit': 4,
        });
        handler.next(options);
      },
      onResponse: (response, handler) {
        _releaseRequestSlot(response.requestOptions);
        final options = response.requestOptions;
        final stopwatch = options.extra['pocketlink.requestStopwatch'] as Stopwatch?;
        AppLogger.info('API request completed', fields: {
          'requestId': options.extra['pocketlink.requestId'] ?? 'unknown',
          'method': options.method,
          'path': options.uri.path,
          'status': response.statusCode,
          'durationMs': stopwatch?.elapsedMilliseconds,
          'queueWaitMs': options.extra['pocketlink.queueWaitMs'],
          'queryKey': options.extra['pocketlink.queryKey'],
          'retry': options.extra['pocketlink.retryCount'] ?? 0,
        });
        handler.next(response);
      },
      onError: (error, handler) async {
        final failedOptions = error.requestOptions;
        final stopwatch = failedOptions.extra['pocketlink.requestStopwatch'] as Stopwatch?;
        AppLogger.warning('API request failed', fields: {
          'requestId': failedOptions.extra['pocketlink.requestId'] ?? 'unknown',
          'method': failedOptions.method,
          'path': failedOptions.uri.path,
          'type': error.type.name,
          'status': error.response?.statusCode,
          'durationMs': stopwatch?.elapsedMilliseconds,
          'queueWaitMs': failedOptions.extra['pocketlink.queueWaitMs'],
          'queryKey': failedOptions.extra['pocketlink.queryKey'],
          'retry': failedOptions.extra['pocketlink.retryCount'] ?? 0,
          'cancelled': failedOptions.cancelToken?.isCancelled ?? false,
        });

        final options = error.requestOptions;
        _releaseRequestSlot(options);
        final attempts = options.extra['pocketlink.retryCount'] as int? ?? 0;
        final cancelled = options.cancelToken?.isCancelled ?? false;
        final status = error.response?.statusCode;
        final transientStatus = status == 408 || status == 425 || status == 429 ||
            status == 500 || status == 502 || status == 503 || status == 504;
        final transientNetwork = error.type == DioExceptionType.connectionError ||
            error.type == DioExceptionType.connectionTimeout ||
            error.type == DioExceptionType.receiveTimeout;
        if (options.method.toUpperCase() == 'GET' &&
            attempts < 3 && !cancelled && (transientNetwork || transientStatus)) {
          options.extra['pocketlink.retryCount'] = attempts + 1;
          // A network handoff can leave an idle pooled socket bound to the old
          // Wi-Fi/mobile route. Force the retry onto a fresh TCP connection.
          options.headers['connection'] = 'close';
          final retryDelay = _retryDelay(error, attempts);
          AppLogger.warning('API retry scheduled', fields: {
            'requestId': options.extra['pocketlink.requestId'] ?? 'unknown',
            'method': options.method,
            'path': options.uri.path,
            'nextAttempt': attempts + 1,
            'delayMs': retryDelay.inMilliseconds,
            'freshConnection': true,
          });
          await Future<void>.delayed(retryDelay);
          if (options.cancelToken?.isCancelled ?? false) {
            handler.next(error);
            return;
          }
          try {
            handler.resolve(await _dio.fetch<dynamic>(options));
            return;
          } on DioException catch (retryError) {
            handler.next(retryError);
            return;
          } catch (retryError) {
            handler.next(DioException(
              requestOptions: options,
              error: retryError,
              type: DioExceptionType.unknown,
            ));
            return;
          }
        }
        handler.next(error);
      },
    ));
  }

  final Dio _dio;
  final _RequestGate _requestGate;
  static const _directoryCacheTtl = Duration(seconds: 20);
  static const _maxCachedDirectories = 512;
  final Map<String, _CacheEntry<DirectoryListing>> _directoryCache = {};
  final Map<String, Future<DirectoryListing>> _directoryRequests = {};
  static final Map<String, Future<Object?>> _sharedReadRequests = {};
  _CacheEntry<List<StorageVolume>>? _volumesCache;
  Future<List<StorageVolume>>? _volumesRequest;
  int _cacheGeneration = 0;

  String _diagnosticQueryKey(RequestOptions options) {
    final entries = options.queryParameters.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    final encoded = jsonEncode(entries.map((entry) => [
      entry.key,
      entry.value,
    ]).toList(growable: false));
    var hash = 0x811c9dc5;
    for (final unit in encoded.codeUnits) {
      hash ^= unit;
      hash = (hash * 0x01000193) & 0xffffffff;
    }
    final requestIdentity = '${options.uri.path}?$encoded';
    hash = 0x811c9dc5;
    for (final unit in requestIdentity.codeUnits) {
      hash ^= unit;
      hash = (hash * 0x01000193) & 0xffffffff;
    }
    return hash.toRadixString(16).padLeft(8, '0');
  }

  Future<T> _sharedRead<T>(
    String resourceKey,
    Future<T> Function() load,
  ) {
    final authorization = _dio.options.headers['Authorization']?.toString() ?? '';
    final key = '${_dio.options.baseUrl}:$authorization:$resourceKey';
    final existing = _sharedReadRequests[key];
    if (existing != null) return existing.then((value) => value as T);

    late final Future<T> request;
    request = load().whenComplete(() {
      if (identical(_sharedReadRequests[key], request)) {
        _sharedReadRequests.remove(key);
      }
    });
    _sharedReadRequests[key] = request;
    return request;
  }

  Duration _retryDelay(DioException error, int attempts) {
    final retryAfter = error.response?.headers.value('retry-after')?.trim();
    Duration? serverDelay;
    if (retryAfter != null && retryAfter.isNotEmpty) {
      final seconds = int.tryParse(retryAfter);
      if (seconds != null) {
        serverDelay = Duration(seconds: seconds);
      } else {
        DateTime? retryAt;
        try {
          retryAt = HttpDate.parse(retryAfter).toUtc();
        } on FormatException {
          retryAt = DateTime.tryParse(retryAfter)?.toUtc();
        }
        if (retryAt != null) {
          serverDelay = retryAt.difference(DateTime.now().toUtc());
        }
      }
    }

    final delay = serverDelay ?? Duration(seconds: 1 << attempts);
    return Duration(
      milliseconds: delay.inMilliseconds.clamp(0, 30000).toInt(),
    );
  }

  void _releaseRequestSlot(RequestOptions options) {
    if (options.extra['pocketlink.requestSlot'] == true) {
      options.extra['pocketlink.requestSlot'] = false;
      _requestGate.release();
    }
  }

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
              ? _sharedRead('files:$path', load)
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
    request = _sharedRead<List<StorageVolume>>('storage:volumes', () async {
      final response =
          await _dio.get<Map<String, dynamic>>('/api/storage/volumes');
      return (response.data?['items'] as List<dynamic>? ?? const [])
          .map((item) => StorageVolume.fromJson(item as Map<String, dynamic>))
          .toList(growable: false);
    }).then<List<StorageVolume>>((volumes) async {
      if (generation != _cacheGeneration) {
        if (identical(_volumesRequest, request)) _volumesRequest = null;
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
        () => _sharedRead('storage:$volume:$path', () async {
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
