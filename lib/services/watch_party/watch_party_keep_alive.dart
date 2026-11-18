import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Starts/stops the Android foreground service (WatchPartyKeepAliveService in
/// MainActivity's package) that keeps the process running while the user is
/// in a watch party, so the party survives Nivio going to the background.
///
/// iOS has no foreground services; the party holds the app's background
/// keep-alive instead (NivioPlugin.swift), which buys a few minutes of
/// background time, enough to share the invite link from another app.
/// No-op on other platforms.
class WatchPartyKeepAlive {
  WatchPartyKeepAlive._();

  static const MethodChannel _channel = MethodChannel(
    'com.nivio/watch_party_keepalive',
  );
  static const MethodChannel _iosChannel = MethodChannel(
    'com.nivio/background_keepalive',
  );
  static const _iosKey = {'key': 'watch_party'};

  static Future<void> start({
    required String sessionCode,
    required bool isHost,
  }) async {
    if (Platform.isIOS) {
      try {
        await _iosChannel.invokeMethod<bool>('hold', _iosKey);
      } catch (e) {
        if (kDebugMode) debugPrint('WatchPartyKeepAlive.start failed: $e');
      }
      return;
    }
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
    if (Platform.isIOS) {
      try {
        await _iosChannel.invokeMethod<bool>('release', _iosKey);
      } catch (e) {
        if (kDebugMode) debugPrint('WatchPartyKeepAlive.stop failed: $e');
      }
      return;
    }
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod<bool>('stop');
    } catch (e) {
      if (kDebugMode) debugPrint('WatchPartyKeepAlive.stop failed: $e');
    }
  }
}
