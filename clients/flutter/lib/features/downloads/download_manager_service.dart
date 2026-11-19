import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/network/server_api.dart';
import '../../core/settings/app_settings.dart';
import 'download_task.dart';

class DownloadManagerService extends ChangeNotifier {
  DownloadManagerService._();
  static final DownloadManagerService instance = DownloadManagerService._();

  static const _tasksKey = 'downloads_tasks_v1';
  final Dio _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 15),
    sendTimeout: const Duration(seconds: 30),
    followRedirects: true,
    maxRedirects: 8,
  ));
  final List<DownloadTask> _tasks = [];
  final Map<String, CancelToken> _tokens = {};
  final Map<String, bool> _removeAfterStop = {};
  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;
  ServerApi? _serverApi;
  Future<void> _writeQueue = Future<void>.value();
  bool _initialized = false;
  Future<void>? _initialization;
  bool _isWifi = false;
  int _activeWorkers = 0;

  List<DownloadTask> get tasks => List.unmodifiable(_tasks);
  int get activeCount => _tasks.where((task) =>
      task.status == DownloadStatus.downloading).length;
  int get queuedCount =>
      _tasks.where((task) => task.status == DownloadStatus.queued).length;
  int get totalSpeedBytesPerSecond => _tasks
      .where((task) => task.status == DownloadStatus.downloading)
      .fold(0, (sum, task) => sum + task.speedBytesPerSecond);

  Future<void> initialize() async {
    if (_initialized) return;
    final pending = _initialization;
    if (pending != null) {
      await pending;
      return;
    }
    final initialization = _initialize();
    _initialization = initialization;
    try {
      await initialization;
    } catch (_) {
      _initialization = null;
      rethrow;
    }
  }

  Future<void> _initialize() async {
    final preferences = await SharedPreferences.getInstance();
    final raw = preferences.getString(_tasksKey);
    if (raw != null) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is List) {
          for (final item in decoded.whereType<Map>()) {
            final task = DownloadTask.fromJson(
              Map<String, dynamic>.from(item),
            );
            if (task.status == DownloadStatus.downloading ||
                task.status == DownloadStatus.queued) {
              task.status = AppSettings.instance.downloadAutoResume
                  ? DownloadStatus.queued
                  : DownloadStatus.paused;
              task.speedBytesPerSecond = 0;
            }
            _tasks.add(task);
          }
        }
      } catch (_) {
        await preferences.remove(_tasksKey);
      }
    }
    try {
      _isWifi = (await Connectivity().checkConnectivity())
          .contains(ConnectivityResult.wifi);
    } catch (_) {
      _isWifi = false;
    }
    try {
      _connectivitySubscription =
          Connectivity().onConnectivityChanged.listen(_handleConnectivity);
    } catch (_) {
      // A missing connectivity plugin must not prevent manual downloads.
    }
    _initialized = true;
    AppSettings.instance.addListener(_handleSettingsChanged);
    notifyListeners();
    _pumpQueue();
  }

  void bindServerApi(ServerApi api) {
    _serverApi = api;
    _pumpQueue();
  }

  void _handleSettingsChanged() {
    if (AppSettings.instance.downloadWifiOnly && !_isWifi) {
      for (final task in _tasks) {
        if (task.status == DownloadStatus.downloading) {
          task.status = DownloadStatus.queued;
          task.speedBytesPerSecond = 0;
          _tokens[task.id]?.cancel('wifi-required');
        }
      }
      _persist();
      notifyListeners();
      return;
    }
    _pumpQueue();
  }

  void _handleConnectivity(List<ConnectivityResult> results) {
    _isWifi = results.contains(ConnectivityResult.wifi);
    if (AppSettings.instance.downloadWifiOnly && !_isWifi) {
      for (final task in _tasks) {
        if (task.status == DownloadStatus.downloading) {
          task.status = DownloadStatus.queued;
          task.speedBytesPerSecond = 0;
          _tokens[task.id]?.cancel('wifi-required');
        }
      }
      _persist();
      notifyListeners();
    } else {
      _pumpQueue();
    }
  }

  Future<String> defaultDirectory() async {
    final configured = AppSettings.instance.downloadDirectory;
    if (configured != null && configured.trim().isNotEmpty) {
      return configured;
    }
    if (Platform.isAndroid) {
      const publicDownloads = '/storage/emulated/0/Download/PocketLink';
      try {
        await Directory(publicDownloads).create(recursive: true);
        return publicDownloads;
      } catch (_) {
        final appDocuments = await getApplicationDocumentsDirectory();
        return p.join(appDocuments.path, 'Downloads', 'PocketLink');
      }
    }
    Directory? downloads;
    try {
      downloads = await getDownloadsDirectory();
    } catch (_) {
      downloads = null;
    }
    downloads ??= await getApplicationDocumentsDirectory();
    return p.join(downloads.path, 'PocketLink');
  }

  Future<ResolvedDownload> resolveUrl(String rawUrl) async {
    final uri = Uri.tryParse(rawUrl.trim());
    if (uri == null ||
        !uri.hasAuthority ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        !const {'http', 'https'}.contains(uri.scheme)) {
      throw const FormatException('Enter a valid HTTP or HTTPS URL.');
    }

    Response<dynamic>? response;
    try {
      response = await _dio.head<dynamic>(uri.toString());
    } on DioException {
      // Some hosts reject HEAD. A one-byte range request is the fallback.
    }

    if (response == null ||
        (response.statusCode ?? 500) >= 400 ||
        response.headers.value('content-length') == null) {
      try {
        final fallback = await _dio.get<ResponseBody>(
          uri.toString(),
          options: Options(
            responseType: ResponseType.stream,
            headers: const {'Range': 'bytes=0-0'},
            validateStatus: (status) => status != null && status < 500,
          ),
        );
        response = fallback;
        final stream = fallback.data?.stream;
        if (stream != null) {
          final subscription = stream.listen((_) {});
          await subscription.cancel();
        }
      } on DioException {
        if (response == null) rethrow;
      }
    }

    if ((response.statusCode ?? 500) >= 400) {
      throw DioException(
        requestOptions: response.requestOptions,
        response: response,
        type: DioExceptionType.badResponse,
      );
    }
    final headers = response.headers;
    final contentRange = headers.value('content-range');
    final rangeTotal = contentRange == null
        ? null
        : int.tryParse(contentRange.split('/').last);
    final length = int.tryParse(headers.value('content-length') ?? '');
    final total = rangeTotal ?? length;
    final disposition = headers.value('content-disposition');
    final filename = _filenameFromDisposition(disposition) ??
        (response.realUri.pathSegments.isEmpty ||
                response.realUri.pathSegments.last.isEmpty
            ? 'download'
            : Uri.decodeComponent(response.realUri.pathSegments.last));
    return ResolvedDownload(
      url: response.realUri.toString(),
      fileName: sanitizeFileName(filename),
      totalBytes: total,
    );
  }

  static String sanitizeFileName(String value) {
    final cleaned = value
        .replaceAll(RegExp(r'[\\/:*?"<>|\x00-\x1F]'), '_')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    return cleaned.isEmpty || cleaned == '.' || cleaned == '..'
        ? 'download'
        : cleaned;
  }

  static String? _filenameFromDisposition(String? value) {
    if (value == null) return null;
    final extended = RegExp(
      r"filename\*\s*=\s*(?:UTF-8'')?([^;]+)",
      caseSensitive: false,
    ).firstMatch(value)?.group(1);
    if (extended != null) {
      final decoded = Uri.decodeComponent(
        extended.trim().replaceAll(RegExp(r'''^["']|["']$'''), ''),
      );
      if (decoded.isNotEmpty) return decoded;
    }
    final quoted = RegExp(
      r'filename\s*=\s*"([^"]+)"',
      caseSensitive: false,
    ).firstMatch(value)?.group(1);
    if (quoted != null && quoted.isNotEmpty) return quoted;
    return RegExp(r'filename\s*=\s*([^;]+)', caseSensitive: false)
        .firstMatch(value)
        ?.group(1)
        ?.trim();
  }

  Future<DownloadTask> enqueueUrl(
    ResolvedDownload resolved, {String? directoryPath}
  ) async {
    await initialize();
    final directory = Directory(directoryPath ?? await defaultDirectory());
    await directory.create(recursive: true);
    final destination = await _uniqueDestination(
      directory.path,
      sanitizeFileName(resolved.fileName),
    );
    final task = DownloadTask(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      url: resolved.url,
      fileName: p.basename(destination),
      destinationPath: destination,
      createdAt: DateTime.now(),
      totalBytes: resolved.totalBytes,
    );
    _tasks.insert(0, task);
    await _persist();
    notifyListeners();
    _pumpQueue();
    return task;
  }

  Future<DownloadTask> enqueueServerFile({
    required ServerApi api,
    required String name,
    required String sourcePath,
    String? volume,
    int? size,
  }) async {
    await initialize();
    bindServerApi(api);
    final directory = Directory(await defaultDirectory());
    await directory.create(recursive: true);
    final destination = await _uniqueDestination(
      directory.path,
      sanitizeFileName(name),
    );
    final task = DownloadTask(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      url: api.mediaStreamUrl(sourcePath, volume: volume),
      fileName: p.basename(destination),
      destinationPath: destination,
      createdAt: DateTime.now(),
      totalBytes: size,
      serverBaseUrl: api.baseUrl,
      serverPath: sourcePath,
      volume: volume,
    );
    _tasks.insert(0, task);
    await _persist();
    notifyListeners();
    _pumpQueue();
    return task;
  }

  Future<String> _uniqueDestination(String directory, String name) async {
    final extension = p.extension(name);
    final stem = extension.isEmpty
        ? name
        : name.substring(0, name.length - extension.length);
    var candidate = p.join(directory, name);
    var suffix = 1;
    while (await File(candidate).exists() ||
        await File('$candidate.part').exists() ||
        _tasks.any((task) => task.destinationPath == candidate)) {
      candidate = p.join(directory, '$stem ($suffix)$extension');
      suffix++;
    }
    return candidate;
  }

  void _pumpQueue() {
    if (!_initialized) return;
    if (AppSettings.instance.downloadWifiOnly && !_isWifi) return;
    final maximum = AppSettings.instance.downloadConcurrency;
    while (_activeWorkers < maximum) {
      DownloadTask? next;
      for (final task in _tasks) {
        if (task.status != DownloadStatus.queued) continue;
        if (task.isServerFile &&
            (_serverApi == null ||
                _serverApi!.baseUrl != task.serverBaseUrl)) {
          continue;
        }
        next = task;
        break;
      }
      if (next == null) break;
      _activeWorkers++;
      unawaited(_run(next));
    }
  }

  Future<void> _run(DownloadTask task) async {
    final token = CancelToken();
    _tokens[task.id] = token;
    task.status = DownloadStatus.downloading;
    task.errorMessage = null;
    task.speedBytesPerSecond = 0;
    notifyListeners();

    RandomAccessFile? output;
    try {
      await _persist();
      final file = File(task.destinationPath);
      final partialFile = File('${task.destinationPath}.part');
      await file.parent.create(recursive: true);
      var offset = await partialFile.exists() ? await partialFile.length() : 0;
      if (task.totalBytes != null && offset > task.totalBytes!) {
        await partialFile.delete();
        offset = 0;
      }
      task.downloadedBytes = offset;
      if (task.totalBytes != null && offset == task.totalBytes!) {
        if (!await partialFile.exists()) {
          await partialFile.create(recursive: true);
        }
        await partialFile.rename(task.destinationPath);
        task.status = DownloadStatus.completed;
        task.speedBytesPerSecond = 0;
        return;
      }

      final response = task.isServerFile
          ? await _serverApi!.openDownloadStream(
              path: task.serverPath!,
              volume: task.volume,
              offset: offset,
              cancelToken: token,
            )
          : await _dio.get<ResponseBody>(
              task.url,
              options: Options(
                responseType: ResponseType.stream,
                headers: offset > 0 ? {'Range': 'bytes=$offset-'} : null,
              ),
              cancelToken: token,
            );

      final statusCode = response.statusCode ?? 0;
      if (statusCode >= 400) {
        throw DioException(
          requestOptions: response.requestOptions,
          response: response,
          type: DioExceptionType.badResponse,
        );
      }

      final contentRange = response.headers.value('content-range');
      final rangeTotal = contentRange == null
          ? null
          : int.tryParse(contentRange.split('/').last);
      final responseLength =
          int.tryParse(response.headers.value('content-length') ?? '');
      final isPartial = statusCode == 206;
      if (offset > 0 && !isPartial) {
        offset = 0;
        task.downloadedBytes = 0;
      }
      task.totalBytes = rangeTotal ??
          (responseLength == null
              ? task.totalBytes
              : responseLength + (isPartial ? offset : 0));

      output = await partialFile.open(
        mode: isPartial && offset > 0 ? FileMode.append : FileMode.write,
      );
      var lastSampleBytes = offset;
      var lastSampleAt = DateTime.now();
      var lastPersistAt = DateTime.now();

      await for (final chunk in response.data!.stream) {
        if (token.isCancelled || task.status != DownloadStatus.downloading) {
          break;
        }
        await output.writeFrom(chunk);
        task.downloadedBytes += chunk.length;
        final now = DateTime.now();
        final elapsedMs = now.difference(lastSampleAt).inMilliseconds;
        if (elapsedMs >= 500) {
          task.speedBytesPerSecond =
              ((task.downloadedBytes - lastSampleBytes) * 1000 / elapsedMs)
                  .round();
          lastSampleBytes = task.downloadedBytes;
          lastSampleAt = now;
        }
        if (now.difference(lastPersistAt).inMilliseconds >= 700) {
          lastPersistAt = now;
          notifyListeners();
          unawaited(_persist());
        }
      }
      await output.flush();
      await output.close();
      output = null;
      if (task.status == DownloadStatus.downloading && !token.isCancelled) {
        await partialFile.rename(task.destinationPath);
        task.status = DownloadStatus.completed;
        task.speedBytesPerSecond = 0;
        task.totalBytes ??= task.downloadedBytes;
        task.errorMessage = null;
      }
    } on DioException catch (error) {
      if (task.status == DownloadStatus.downloading &&
          !CancelToken.isCancel(error)) {
        task.status = DownloadStatus.failed;
        task.errorMessage = error.response?.statusCode != null
            ? 'Server returned HTTP ${error.response!.statusCode}.'
            : error.message ?? 'Download failed.';
        task.speedBytesPerSecond = 0;
      }
    } catch (error) {
      if (task.status == DownloadStatus.downloading) {
        task.status = DownloadStatus.failed;
        task.errorMessage = error.toString();
        task.speedBytesPerSecond = 0;
      }
    } finally {
      try {
        await output?.close();
      } catch (_) {}
      _tokens.remove(task.id);
      final deleteFinalFile = _removeAfterStop.remove(task.id);
      if (deleteFinalFile != null) {
        try {
          final partial = File('${task.destinationPath}.part');
          if (await partial.exists()) await partial.delete();
          if (deleteFinalFile) {
            final completed = File(task.destinationPath);
            if (await completed.exists()) await completed.delete();
          }
        } catch (_) {}
      }
      _activeWorkers = (_activeWorkers - 1).clamp(0, 1 << 30);
      try {
        await _persist();
      } catch (_) {}
      notifyListeners();
      _pumpQueue();
    }
  }

  Future<void> pause(String id) async {
    final task = _find(id);
    if (task == null ||
        (task.status != DownloadStatus.downloading &&
            task.status != DownloadStatus.queued)) {
      return;
    }
    task.status = DownloadStatus.paused;
    task.speedBytesPerSecond = 0;
    _tokens[id]?.cancel('paused');
    await _persist();
    notifyListeners();
  }

  Future<void> resume(String id) async {
    final task = _find(id);
    if (task == null ||
        !{DownloadStatus.paused, DownloadStatus.failed}.contains(task.status)) {
      return;
    }
    task.status = DownloadStatus.queued;
    task.errorMessage = null;
    await _persist();
    notifyListeners();
    _pumpQueue();
  }

  Future<void> pauseAll() async {
    for (final task in _tasks) {
      if (task.status == DownloadStatus.downloading) {
        task.status = DownloadStatus.paused;
        task.speedBytesPerSecond = 0;
        _tokens[task.id]?.cancel('paused');
      } else if (task.status == DownloadStatus.queued) {
        task.status = DownloadStatus.paused;
      }
    }
    await _persist();
    notifyListeners();
  }

  Future<void> resumeAll() async {
    for (final task in _tasks) {
      if (task.status == DownloadStatus.paused ||
          task.status == DownloadStatus.failed) {
        task.status = DownloadStatus.queued;
        task.errorMessage = null;
      }
    }
    await _persist();
    notifyListeners();
    _pumpQueue();
  }

  Future<void> remove(String id, {bool deleteFile = false}) async {
    final task = _find(id);
    if (task == null) return;
    final token = _tokens[id];
    _tasks.remove(task);
    if (token != null) {
      _removeAfterStop[id] = deleteFile;
      token.cancel('removed');
    } else {
      try {
        final partial = File('${task.destinationPath}.part');
        if (await partial.exists()) await partial.delete();
      } catch (_) {}
      if (deleteFile) {
        try {
          await File(task.destinationPath).delete();
        } catch (_) {}
      }
    }
    await _persist();
    notifyListeners();
  }

  Future<void> clearCompleted() async {
    _tasks.removeWhere((task) => task.status == DownloadStatus.completed);
    await _persist();
    notifyListeners();
  }

  Future<void> openFile(DownloadTask task) async {
    if (task.status != DownloadStatus.completed) return;
    await OpenFilex.open(task.destinationPath);
  }

  DownloadTask? _find(String id) {
    for (final task in _tasks) {
      if (task.id == id) return task;
    }
    return null;
  }

  Future<void> _persist() {
    final snapshot = jsonEncode(_tasks.map((task) => task.toJson()).toList());
    final write = _writeQueue.catchError((_) {}).then((_) async {
      final preferences = await SharedPreferences.getInstance();
      await preferences.setString(_tasksKey, snapshot);
    });
    _writeQueue = write;
    return write;
  }

  @override
  void dispose() {
    AppSettings.instance.removeListener(_handleSettingsChanged);
    _connectivitySubscription?.cancel();
    for (final token in _tokens.values) {
      token.cancel('service-disposed');
    }
    _dio.close(force: true);
    super.dispose();
  }
}
