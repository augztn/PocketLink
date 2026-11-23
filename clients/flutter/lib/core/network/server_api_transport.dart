part of 'server_api.dart';

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

class _ServerApiTransport {
  _ServerApiTransport({
    required String baseUrl,
    required String username,
    required String password,
    HttpClientAdapter? httpClientAdapter,
  })  : _dio = Dio(
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
        AppLogger.info('API request started', category: 'network', component: 'server_api', correlationId: requestId, fields: {
          'requestId': requestId,
          'operation': '${options.method.toUpperCase()} ${options.uri.path}',
          'endpoint': options.uri.path,
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
        final requestId = options.extra['pocketlink.requestId']?.toString() ?? 'unknown';
        AppLogger.info('API request completed', category: 'network', component: 'server_api', correlationId: requestId, fields: {
          'requestId': requestId,
          'operation': '${options.method.toUpperCase()} ${options.uri.path}',
          'endpoint': options.uri.path,
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
        final requestId = failedOptions.extra['pocketlink.requestId']?.toString() ?? 'unknown';
        AppLogger.warning('API request failed', category: 'network', component: 'server_api', correlationId: requestId, fields: {
          'requestId': requestId,
          'operation': '${failedOptions.method.toUpperCase()} ${failedOptions.uri.path}',
          'endpoint': failedOptions.uri.path,
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
  // One app-wide budget across every ServerApi/transport instance.
  static final _RequestGate _requestGate = _RequestGate(4);
  static final Map<String, Future<Object?>> _sharedReadRequests = {};

  Dio get client => _dio;

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

  void close({bool force = false}) => _dio.close(force: force);
}
