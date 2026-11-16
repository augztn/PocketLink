import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// Small, private, rotating diagnostic log for troubleshooting PocketLink.
class AppLogger {
  AppLogger._();

  static const int _maxBytes = 1024 * 1024;
  static const int _maxBackupBytes = 1024 * 1024;
  static Directory? _directory;
  static Future<void> _writeQueue = Future<void>.value();
  static File? _logFile;

  static Future<void> initialize() async {
    try {
      _directory = await getApplicationSupportDirectory();
      await _directory!.create(recursive: true);
      _logFile = File('${_directory!.path}/homeserver.log');
      await _rotateIfNeeded();
      await info('Application started', fields: {
        'platform': Platform.operatingSystem,
        'debug': kDebugMode,
      });
    } catch (error) {
      debugPrint('PocketLink logger initialization failed: ${_redact(error.toString())}');
    }
  }

  static Future<void> info(String message, {Map<String, Object?> fields = const {}}) =>
      _write('INFO', message, fields: fields);

  static Future<void> warning(String message, {Map<String, Object?> fields = const {}}) =>
      _write('WARN', message, fields: fields);

  static Future<void> error(
    String message, {
    Object? error,
    StackTrace? stackTrace,
    Map<String, Object?> fields = const {},
  }) => _write('ERROR', message, error: error, stackTrace: stackTrace, fields: fields);

  static Future<void> _write(
    String level,
    String message, {
    Object? error,
    StackTrace? stackTrace,
    Map<String, Object?> fields = const {},
  }) async {
    final file = _logFile;
    if (file == null) {
      debugPrint('[$level] ${_redact(message)}');
      return;
    }
    final safeFields = fields.map((key, value) => MapEntry(
      key,
      RegExp(r'password|passwd|authorization|token|secret|api[_-]?key|username|user|login|cookie', caseSensitive: false).hasMatch(key)
          ? '[REDACTED]'
          : _redact(value.toString()),
    ));
    final line = StringBuffer()
      ..write(DateTime.now().toUtc().toIso8601String())
      ..write(' [$level] ')
      ..write(_redact(message));
    if (safeFields.isNotEmpty) line.write(' | $safeFields');
    if (error != null) line.write(' | error: ${_redact(error.toString())}');
    if (stackTrace != null) line.write('\n${_redact(stackTrace.toString())}');
    line.write('\n');

    _writeQueue = _writeQueue.then((_) async {
      try {
        await _rotateIfNeeded();
        await file.writeAsString(line.toString(), mode: FileMode.append, flush: true);
      } catch (writeError) {
        debugPrint('PocketLink log write failed: ${_redact(writeError.toString())}');
      }
    });
  }

  @visibleForTesting
  static String sanitizeDiagnosticContent(String value) => _redact(value);

  static String _redact(String value) {
    final withSchemesRedacted = value
        .replaceAll(
          RegExp(r'Basic\s+[A-Za-z0-9+/=]+', caseSensitive: false),
          'Basic [REDACTED]',
        )
        .replaceAll(
          RegExp(r'''Bearer\s+[^,;\s}"']+''', caseSensitive: false),
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
        return '\${match.group(1)}$replacement';
      },
    );

    return withCredentialsRedacted
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
    if (await backup.length() > _maxBackupBytes) {
      await backup.writeAsBytes(await backup.openRead(0, _maxBackupBytes).fold<List<int>>(
        <int>[],
        (bytes, chunk) => bytes..addAll(chunk),
      ), flush: true);
    }
  }

  static Future<String> readLogs() async {
    await _writeQueue;
    final file = _logFile;
    if (file == null || !await file.exists()) return 'No diagnostic logs yet.';
    final backup = File('${file.path}.1');
    final parts = <String>[];
    if (await backup.exists()) parts.add(await backup.readAsString());
    parts.add(await file.readAsString());
    return parts.join('\n');
  }

  static Future<File> createDiagnosticFile() async {
    final directory = _directory ?? await getApplicationSupportDirectory();
    final content = sanitizeDiagnosticContent(await readLogs());
    final file = File('${directory.path}/pocketlink-diagnostics-${DateTime.now().toUtc().millisecondsSinceEpoch}.txt');
    await file.writeAsString(content, flush: true);
    return file;
  }

  static Future<int> logSize() async {
    await _writeQueue;
    final file = _logFile;
    if (file == null || !await file.exists()) return 0;
    return file.length();
  }

  static Future<void> clear() async {
    await _writeQueue;
    final file = _logFile;
    if (file != null && await file.exists()) await file.writeAsString('', flush: true);
    final backup = file == null ? null : File('${file.path}.1');
    if (backup != null && await backup.exists()) await backup.delete();
  }
}
