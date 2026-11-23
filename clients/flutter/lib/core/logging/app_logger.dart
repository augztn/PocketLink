import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

/// Small, private, rotating diagnostic log for troubleshooting PocketLink.
class AppLogger {
  AppLogger._();

  static const int _maxBytes = 1024 * 1024;
  static const int _maxBackupBytes = 1024 * 1024;
  static const int _maxDiagnosticExportBytes = 2 * 1024 * 1024;
  static const MethodChannel _nativeDiagnosticsChannel = MethodChannel('pocketlink/saf');
  static Directory? _directory;
  static Future<void> _writeQueue = Future<void>.value();
  static File? _logFile;
  static DateTime? _sessionStartedAt;
  static int _eventSequence = 0;
  static String? _sessionId;
  static bool _initialized = false;
  static int _writeFailures = 0;
  static int _droppedEvents = 0;

  static Map<String, int> get health => {
        'write_failures': _writeFailures,
        'dropped_events': _droppedEvents,
      };

  static String nextEventId([String prefix = 'evt']) =>
      '$prefix-${++_eventSequence}';

  @visibleForTesting
  static Future<void> initializeForTesting(Directory directory) async {
    await _writeQueue;
    await directory.create(recursive: true);
    _directory = directory;
    _logFile = File('${directory.path}/pocketlink.log');
    _sessionStartedAt = DateTime.now().toUtc();
    _sessionId = 'test-session-${_sessionStartedAt!.microsecondsSinceEpoch}';
    _eventSequence = 0;
    _writeFailures = 0;
    _droppedEvents = 0;
    _writeQueue = Future<void>.value();
    _initialized = true;
  }
  static Future<void> initialize() async {
    if (_initialized) return;
    _sessionStartedAt = DateTime.now().toUtc();
    _sessionId = 'session-$pid-${_sessionStartedAt!.microsecondsSinceEpoch}';
    try {
      _directory = await getApplicationSupportDirectory();
      await _directory!.create(recursive: true);
      _logFile = File('${_directory!.path}/pocketlink.log');
      final legacyLog = File('${_directory!.path}/homeserver.log');
      final legacyBackup = File('${_directory!.path}/homeserver.log.1');
      if (!await _logFile!.exists() && await legacyLog.exists()) {
        await legacyLog.rename(_logFile!.path);
      }
      final backup = File('${_logFile!.path}.1');
      if (!await backup.exists() && await legacyBackup.exists()) {
        await legacyBackup.rename(backup.path);
      }
      await _rotateIfNeeded();
      _initialized = true;
      await info('Application started', fields: {
        'platform': Platform.operatingSystem,
        'debug': kDebugMode,
        'session': _sessionId!,
        'pid': pid,
        'processors': Platform.numberOfProcessors,
      });
    } catch (error) {
      debugPrint('PocketLink logger initialization failed: ${_redact(error.toString())}');
    }
  }

  static Future<void> info(
    String message, {
    String category = 'app',
    String? component,
    String? correlationId,
    Map<String, Object?> fields = const {},
  }) => _write('INFO', message, category: category, component: component,
      correlationId: correlationId, fields: fields);

  static Future<void> warning(
    String message, {
    String category = 'app',
    String? component,
    String? correlationId,
    Map<String, Object?> fields = const {},
  }) => _write('WARN', message, category: category, component: component,
      correlationId: correlationId, fields: fields);

  static Future<void> error(
    String message, {
    Object? error,
    StackTrace? stackTrace,
    String category = 'error',
    String? component,
    String? correlationId,
    Map<String, Object?> fields = const {},
  }) => _write('ERROR', message, error: error, stackTrace: stackTrace,
      category: category, component: component, correlationId: correlationId,
      fields: fields);

  static Future<void> _write(
    String level,
    String message, {
    Object? error,
    StackTrace? stackTrace,
    String category = 'app',
    String? component,
    String? correlationId,
    Map<String, Object?> fields = const {},
  }) {
    final file = _logFile;
    if (file == null) {
      _droppedEvents++;
      debugPrint('[' + level + '] ' + _redact(message));
      return Future<void>.value();
    }
    final timestamp = DateTime.now().toUtc();
    final record = <String, Object?>{
      'event_id': (_sessionId ?? 'uninitialized') + '-' + nextEventId(),
      'session_id': _sessionId ?? 'uninitialized',
      'timestamp': timestamp.toIso8601String(),
      'level': level,
      'category': _redact(category),
      if (component != null) 'component': _redact(component),
      if (correlationId != null) 'correlation_id': _redact(correlationId),
      'message': _redact(message),
      'fields': _sanitizeFields(fields),
      if (error != null) 'error': _redact(error.toString()),
      if (stackTrace != null) 'stack_trace': _redact(stackTrace.toString()),
    };
    final line = timestamp.toIso8601String() + ' [' + level + '] ' +
        jsonEncode(record) + '\n';
    _writeQueue = _writeQueue.then((_) async {
      try {
        await _rotateIfNeeded();
        await file.writeAsString(line, mode: FileMode.append, flush: true);
      } catch (writeError) {
        _writeFailures++;
        _droppedEvents++;
        debugPrint('PocketLink log write failed: ' + _redact(writeError.toString()));
      }
    });
    return _writeQueue;
  }

  static String _normalizeFieldKey(String key) => key.replaceAllMapped(
        RegExp(r'[A-Z]'),
        (match) => '_' + match.group(0)!.toLowerCase(),
      ).toLowerCase();

  static bool _isSensitiveKey(String key) {
    final normalized = _normalizeFieldKey(key);
    const safeOperationalFields = {
      'host_mode', 'host_status', 'host_state', 'host_type',
      'server_status', 'server_state', 'server_type', 'server_mode',
    };
    if (safeOperationalFields.contains(normalized)) return false;
    return RegExp(
      r'(^|_)(password|passwd|authorization|token|secret|api_key|username|user|login|cookie|host|hostname|address|server)(_|$)',
      caseSensitive: false,
    ).hasMatch(normalized);
  }

  static bool _isSensitivePathKey(String key, [Object? value]) {
    final normalized = _normalizeFieldKey(key);
    if (!RegExp(r'(^|_)(path|filename|directory|folder|uri)(_|$)')
        .hasMatch(normalized)) return false;
    // API route templates are operational metadata, not user filesystem paths.
    if (value is String && RegExp(r'^/api/[a-zA-Z0-9_/{}/-]+/?$').hasMatch(value)) {
      return false;
    }
    return true;
  }
  static Map<String, Object?> _sanitizeFields(Map<String, Object?> fields) {
    return fields.map((key, value) {
      if (_isSensitiveKey(key)) return MapEntry(key, '[REDACTED]');
      if (_isSensitivePathKey(key, value)) return MapEntry(key, '[REDACTED_PATH]');
      return MapEntry(key, _sanitizeValue(value));
    });
  }

  static Object? _sanitizeValue(Object? value) {
    if (value == null || value is bool || value is num) return value;
    if (value is String) return _redact(value);
    if (value is Map) {
      return value.map((key, nestedValue) {
        final name = key.toString();
        if (_isSensitiveKey(name)) return MapEntry(name, '[REDACTED]');
        if (_isSensitivePathKey(name, nestedValue)) return MapEntry(name, '[REDACTED_PATH]');
        return MapEntry(name, _sanitizeValue(nestedValue));
      });
    }
    if (value is Iterable) return value.map(_sanitizeValue).toList();
    return _redact(value.toString());
  }

  @visibleForTesting
  static Map<String, Object?> sanitizeDiagnosticFields(Map<String, Object?> fields) =>
      _sanitizeFields(fields);

  @visibleForTesting
  static String sanitizeDiagnosticContent(String value) => _redact(value);

  static String _redact(String value) {
    final withSchemesRedacted = value
        .replaceAll(
          RegExp(r'Basic\s+[A-Za-z0-9+/=]+', caseSensitive: false),
          'Basic [REDACTED]',
        )
        .replaceAll(
          RegExp(r'Bearer\s+[A-Za-z0-9._~+/-]+=*', caseSensitive: false),
          'Bearer [REDACTED]',
        );

    final withCredentialsRedacted = withSchemesRedacted.replaceAllMapped(
      RegExp(
        r'''((?:password|passwd|authorization|token|secret|api[_-]?key|username|user|login|cookie|set-cookie)\s*["']?\s*[:=]\s*)(?:"[^"]*"|'[^']*'|[^,;\s}]+)''',
        caseSensitive: false,
      ),
      (match) {
        final original = match.group(0)!;
        final valueStart = match.group(1)!.length;
        final credential = original.substring(valueStart);
        final replacement = credential.startsWith('"')
            ? '"[REDACTED]"'
            : credential.startsWith("'")
                ? "'[REDACTED]'"
                : '[REDACTED]';
        return '${match.group(1)}$replacement';
      },
    );

    final withUrlHostsRedacted = withCredentialsRedacted.replaceAllMapped(
      RegExp(r'\b((?:https?|wss?)://)(?:[^/@\s]+@)?(?:\[[^\]]+\]|[^:/?#\s]+)(?::\d+)?', caseSensitive: false),
      (match) => match.group(1)! + '[REDACTED_HOST]',
    );

    return withUrlHostsRedacted
        .replaceAll(
          RegExp(
            r'(?<![\d.])(?:25[0-5]|2[0-4]\d|1?\d?\d)(?:\.(?:25[0-5]|2[0-4]\d|1?\d?\d)){3}(?![\d.])',
          ),
          '[REDACTED_HOST]',
        )
        .replaceAll(
          RegExp(
            r'(?<![0-9A-Fa-f:])(?=[0-9A-Fa-f:]*[A-Fa-f]|[0-9A-Fa-f:]*::)(?:[0-9A-Fa-f]{0,4}:){2,7}[0-9A-Fa-f]{0,4}(?![0-9A-Fa-f:])',
          ),
          '[REDACTED_HOST]',
        )
        .replaceAll(
          RegExp(r'(?<![:\w])/(?:data|storage|sdcard|mnt|home|users|private|var|tmp|opt)/[^\s,;)}\]]+', caseSensitive: false),
          '[REDACTED_PATH]',
        )
        .replaceAll(
          RegExp(r'[A-Za-z]:\\(?:[^\\\s]+\\)*[^\\\s]*'),
          '[REDACTED_PATH]',
        );
  }

  static Future<void> _rotateIfNeeded() async {
    final file = _logFile;
    if (file == null || !await file.exists()) return;
    if (await file.length() < _maxBytes) return;
    final backup = File('${file.path}.1');
    if (await backup.exists()) await backup.delete();
    await file.rename(backup.path);
    await file.create();
    final backupLength = await backup.length();
    if (backupLength > _maxBackupBytes) {
      final start = backupLength - _maxBackupBytes;
      final tail = await backup.openRead(start).fold<List<int>>(
        <int>[],
        (bytes, chunk) => bytes..addAll(chunk),
      );
      final firstLineBreak = tail.indexOf(10);
      final retained = firstLineBreak < 0 ? tail : tail.sublist(firstLineBreak + 1);
      await backup.writeAsBytes(retained, flush: true);
    }
  }

  static Future<String> readLogs({bool currentSessionOnly = false}) async {
    await _writeQueue;
    final file = _logFile;
    if (file == null || !await file.exists()) return 'No diagnostic logs yet.';
    final backup = File('${file.path}.1');
    final parts = <String>[];
    if (await backup.exists()) parts.add(await backup.readAsString());
    parts.add(await file.readAsString());
    final logs = parts.join('\n');
    return currentSessionOnly
        ? filterSessionLogs(logs, _sessionId ?? 'uninitialized')
        : logs;
  }

  @visibleForTesting
  static String filterSessionLogs(String logs, String sessionId) {
    final result = <String>[];
    var includeEvent = false;
    for (final line in logs.split('\n')) {
      if (RegExp(r'^\d{4}-\d{2}-\d{2}T').hasMatch(line)) {
        includeEvent = line.contains('"session_id":"' + sessionId + '"') ||
            line.contains('session: ' + sessionId);
      }
      if (includeEvent) result.add(line);
    }
    return result.join('\n').trimRight();
  }

  static Future<String> _diagnosticHeader() async {
    final now = DateTime.now().toUtc();
    final sessionStartedAt = _sessionStartedAt ?? now;
    final uptime = now.difference(sessionStartedAt);
    final lines = <String>[
      'PocketLink diagnostic report',
      'Captured: ${now.toIso8601String()}',
      'Session: ${_sessionId ?? 'uninitialized'}',
      'Session started: ${sessionStartedAt.toIso8601String()}',
      'Session uptime: ${uptime.inSeconds}s',
      'Platform: ${Platform.operatingSystem}',
      'OS version: ${Platform.operatingSystemVersion}',
      'Dart: ${Platform.version.split(' ').first}',
      'CPU cores: ${Platform.numberOfProcessors}',
      'Logger write failures: $_writeFailures',
      'Logger dropped events: $_droppedEvents',
    ];
    try {
      lines.add('Process RSS: ${(ProcessInfo.currentRss / (1024 * 1024)).toStringAsFixed(1)} MB');
      lines.add('Peak process RSS: ${(ProcessInfo.maxRss / (1024 * 1024)).toStringAsFixed(1)} MB');
    } catch (_) {
      lines.add('Process memory: unavailable');
    }
    return '${lines.join('\n')}\n\n';
  }

  static Future<(bool, int)> _appendCurrentSessionLog(
    File source,
    IOSink sink,
    int remainingBytes,
  ) async {
    if (!await source.exists()) return (true, remainingBytes);
    final events = <String>[];
    final current = StringBuffer();
    var includeEvent = false;

    void finishEvent() {
      if (includeEvent && current.isNotEmpty) events.add(current.toString());
      current.clear();
    }

    for (final line in await source.readAsLines()) {
      if (RegExp(r'^\d{4}-\d{2}-\d{2}T').hasMatch(line)) {
        finishEvent();
        includeEvent = line.contains('"session_id":"' + (_sessionId ?? 'uninitialized') + '"') ||
            line.contains('session: ' + (_sessionId ?? 'uninitialized'));
      }
      if (includeEvent) current.writeln(line);
    }
    finishEvent();

    // Select from the newest event backwards so a full backup can never crowd
    // out the active session's latest diagnostics.
    final retained = <List<int>>[];
    var complete = true;
    for (final event in events.reversed) {
      final bytes = utf8.encode(_redact(event));
      if (bytes.length > remainingBytes) {
        complete = false;
        break;
      }
      retained.add(bytes);
      remainingBytes -= bytes.length;
    }
    for (final bytes in retained.reversed) {
      sink.add(bytes);
    }
    return (complete, remainingBytes);
  }

  static List<int> _latestCompleteDiagnosticLines(String content, int maxBytes) {
    final lines = content.split('\n');
    final retained = <List<int>>[];
    var remaining = maxBytes;
    for (final line in lines.reversed) {
      if (line.isEmpty) continue;
      final bytes = utf8.encode(_redact(line) + '\n');
      if (bytes.length > remaining) break;
      retained.add(bytes);
      remaining -= bytes.length;
    }
    return retained.reversed.expand((line) => line).toList(growable: false);
  }

  @visibleForTesting
  static List<int> latestCompleteDiagnosticLinesForTesting(String content, int maxBytes) =>
      _latestCompleteDiagnosticLines(content, maxBytes);

  static Future<String> _readNativeDiagnostics() async {
    if (!Platform.isAndroid) return '';
    try {
      return await _nativeDiagnosticsChannel.invokeMethod<String>('readNativeDiagnostics') ?? '';
    } on PlatformException catch (error) {
      return '[Native Android diagnostics unavailable: ${error.code}]\n';
    } on MissingPluginException {
      return '[Native Android diagnostics bridge unavailable]\n';
    }
  }

  static Future<void> _clearNativeDiagnostics() async {
    if (!Platform.isAndroid) return;
    try {
      await _nativeDiagnosticsChannel.invokeMethod<bool>('clearNativeDiagnostics');
    } on PlatformException {
      // Keep Flutter log clearing available if the optional native bridge fails.
    } on MissingPluginException {
      // Non-plugin test and desktop runtimes have no native diagnostics channel.
    }
  }

  static Future<File> createDiagnosticFile() async {
    await _writeQueue;
    final directory = _directory ?? await getApplicationSupportDirectory();
    final file = File('${directory.path}/pocketlink-diagnostics-${DateTime.now().toUtc().millisecondsSinceEpoch}.txt');
    final sink = file.openWrite();
    try {
      final header = sanitizeDiagnosticContent(await _diagnosticHeader());
      sink.write(header);
      var remainingBytes = _maxDiagnosticExportBytes - utf8.encode(header).length;
      final logFile = _logFile;
      if (logFile != null) {
        final currentSection = '--- Current Flutter session ---\\n';
        sink.write(currentSection);
        remainingBytes -= utf8.encode(currentSection).length;
        final currentResult = await _appendCurrentSessionLog(logFile, sink, remainingBytes);
        remainingBytes = currentResult.$2;
        // The byte budget is strict; do not append a marker that would exceed it.

        final nativeLogs = await _readNativeDiagnostics();
        if (nativeLogs.isNotEmpty && remainingBytes > utf8.encode('--- Native Android diagnostics ---\\n').length) {
          final nativeSection = '--- Native Android diagnostics ---\\n';
          sink.write(nativeSection);
          remainingBytes -= utf8.encode(nativeSection).length;
          final nativeBytes = _latestCompleteDiagnosticLines(nativeLogs, remainingBytes);
          sink.add(nativeBytes);
          remainingBytes -= nativeBytes.length;
        }

        final backup = File('${logFile.path}.1');
        if (await backup.exists() && remainingBytes > utf8.encode('--- Rotated Flutter session log (older events) ---\\n').length) {
          final backupSection = '--- Rotated Flutter session log (older events) ---\\n';
          sink.write(backupSection);
          remainingBytes -= utf8.encode(backupSection).length;
          final backupResult = await _appendCurrentSessionLog(backup, sink, remainingBytes);
          remainingBytes = backupResult.$2;

        }
      }
      await sink.flush();
    } catch (_) {
      await sink.close();
      rethrow;
    }
    await sink.close();
    return file;
  }

  static Future<int> logSize() async {
    await _writeQueue;
    final file = _logFile;
    var size = file != null && await file.exists() ? await file.length() : 0;
    final backup = file == null ? null : File('${file.path}.1');
    if (backup != null && await backup.exists()) size += await backup.length();
    if (Platform.isAndroid) {
      try {
        size += await _nativeDiagnosticsChannel.invokeMethod<int>('nativeDiagnosticsSize') ?? 0;
      } on PlatformException {
        // Report the Flutter log size if native diagnostics are temporarily unavailable.
      } on MissingPluginException {
        // Non-plugin Android test runtimes have no native diagnostics channel.
      }
    }
    return size;
  }

  static Future<void> clear() async {
    await _writeQueue;
    final file = _logFile;
    if (file != null && await file.exists()) await file.writeAsString('', flush: true);
    final backup = file == null ? null : File('${file.path}.1');
    if (backup != null && await backup.exists()) await backup.delete();
    await _clearNativeDiagnostics();
  }
}
