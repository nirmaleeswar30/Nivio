import 'package:flutter/foundation.dart';

void appDebugLog(Object? message) {
  if (kDebugMode) {
    final now = DateTime.now();
    final timestamp = '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}.${now.millisecond.toString().padLeft(3, '0')}';
    debugPrint('[$timestamp] ${message?.toString()}');
  }
}
