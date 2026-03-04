import 'package:flutter/foundation.dart';

void appDebugLog(Object? message) {
  if (kDebugMode) {
    debugPrint(message?.toString());
  }
}
