import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Starts/stops the Android foreground service (WatchPartyKeepAliveService in
/// MainActivity's package) that keeps the process running while the user is
/// in a watch party, so the party survives Nivio going to the background.
/// No-op on other platforms.
class WatchPartyKeepAlive {
  WatchPartyKeepAlive._();

  static const MethodChannel _channel = MethodChannel(
    'com.nivio/watch_party_keepalive',
  );

  static Future<void> start({
    required String sessionCode,
    required bool isHost,
  }) async {
    if (!Platform.isAndroid) return;
    final code = sessionCode.toUpperCase();
    try {
      await _channel.invokeMethod<bool>('start', {
        'text': isHost ? 'Hosting room $code' : 'In room $code',
      });
    } catch (e) {
      if (kDebugMode) debugPrint('WatchPartyKeepAlive.start failed: $e');
    }
  }

  static Future<void> stop() async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod<bool>('stop');
    } catch (e) {
      if (kDebugMode) debugPrint('WatchPartyKeepAlive.stop failed: $e');
    }
  }
}
