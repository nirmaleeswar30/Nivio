import 'dart:io';

import 'package:flutter/foundation.dart';

/// Debug-only log file, truncated on each launch:
/// `%TEMP%\nivio_debug.log` (Windows) / `$TMPDIR/nivio_debug.log` elsewhere.
RandomAccessFile? _logFile;
String? debugLogFilePath;

String _timestamp() {
  final now = DateTime.now();
  return '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}.${now.millisecond.toString().padLeft(3, '0')}';
}

void _writeToFile(String line) {
  final file = _logFile;
  if (file == null) return;
  try {
    // Flushed synchronously so the tail survives a native crash.
    file.writeStringSync('$line\n');
    file.flushSync();
  } catch (_) {}
}

void appDebugLog(Object? message) {
  if (kDebugMode) {
    final line = '[${_timestamp()}] ${message?.toString()}';
    debugPrint(line);
    _writeToFile(line);
  }
}

/// Opens the log file and mirrors Flutter/async errors into it (condensed and
/// de-duplicated, so a per-frame assertion loop doesn't bury everything else).
/// Call after any other FlutterError/PlatformDispatcher handlers are installed.
void initDebugLogFile() {
  if (!kDebugMode) return;
  try {
    final path = '${Directory.systemTemp.path}${Platform.pathSeparator}nivio_debug.log';
    _logFile = File(path).openSync(mode: FileMode.write);
    debugLogFilePath = path;
    _writeToFile('==== Nivio debug log — started ${DateTime.now().toIso8601String()} ====');
    debugPrint('📝 Debug log file: $path');
  } catch (e) {
    debugPrint('📝 Could not open debug log file: $e');
    return;
  }

  final previousFlutterOnError = FlutterError.onError;
  FlutterError.onError = (details) {
    _logError('FLUTTER', details.exception, details.stack);
    if (previousFlutterOnError != null) {
      previousFlutterOnError(details);
    } else {
      FlutterError.presentError(details);
    }
  };

  final previousPlatformOnError = PlatformDispatcher.instance.onError;
  PlatformDispatcher.instance.onError = (error, stack) {
    _logError('ASYNC', error, stack);
    return previousPlatformOnError?.call(error, stack) ?? false;
  };
}

final Map<String, int> _errorCounts = {};

void _logError(String kind, Object error, StackTrace? stack) {
  final firstLine = error.toString().split('\n').first.trim();
  final count = (_errorCounts[firstLine] ?? 0) + 1;
  _errorCounts[firstLine] = count;

  // Full-ish detail for the first 3 hits, then a heartbeat every 100.
  if (count <= 3) {
    final frames = (stack?.toString() ?? '')
        .split('\n')
        .where((l) => l.trim().isNotEmpty)
        .take(12)
        .map((l) => '      $l')
        .join('\n');
    _writeToFile('[${_timestamp()}] 💥 $kind ERROR (#$count): ${error.toString().trim()}\n$frames');
  } else if (count % 100 == 0) {
    _writeToFile('[${_timestamp()}] 💥 $kind ERROR repeated $count× so far: $firstLine');
  }
}
