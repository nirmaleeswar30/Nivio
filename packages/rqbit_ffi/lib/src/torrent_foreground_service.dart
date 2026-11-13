import 'dart:io';

import 'package:flutter_foreground_task/flutter_foreground_task.dart';

/// Keeps the app process (and the FFI engine's networking threads) alive while
/// torrents are active, via an Android foreground service with a persistent
/// notification. No-op on non-Android platforms.
///
/// It runs the service *without* a task-handler isolate — the engine lives in
/// the main isolate, so we only need the service to hold the process at
/// foreground priority. All calls are defensive: failures never propagate.
///
/// Several users share the one service, each under its own key (torrent
/// streaming, downloads): it runs while any of them holds it, so one stopping
/// doesn't take the process down under the other.
class TorrentForegroundService {
  TorrentForegroundService._();
  static final TorrentForegroundService instance = TorrentForegroundService._();

  bool _initialized = false;
  bool _running = false;

  /// Current holders and their notification text, most recent last.
  final Map<String, String> _holders = {};

  void _ensureInitialized() {
    if (_initialized || !Platform.isAndroid) return;
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'nivio_torrents',
        channelName: 'Nivio Torrent Streaming',
        channelDescription: 'Keeps torrent streaming alive in the background.',
        channelImportance: NotificationChannelImportance.LOW,
        priority: NotificationPriority.LOW,
      ),
      iosNotificationOptions: const IOSNotificationOptions(),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.nothing(),
        allowWakeLock: true,
        allowWifiLock: true,
        autoRunOnBoot: false,
        allowAutoRestart: false,
      ),
    );
    _initialized = true;
  }

  /// Holds the foreground service for [key] (Android only), starting it if
  /// needed; [text] becomes the notification text.
  Future<void> start({
    String key = 'stream',
    String title = 'Nivio',
    String text = 'Streaming torrent…',
  }) async {
    if (!Platform.isAndroid) return;
    _holders.remove(key);
    _holders[key] = text;
    try {
      _ensureInitialized();
      if (_running || await FlutterForegroundTask.isRunningService) {
        _running = true;
        await FlutterForegroundTask.updateService(
          notificationTitle: title,
          notificationText: text,
        );
        return;
      }
      final result = await FlutterForegroundTask.startService(
        serviceId: 2718,
        serviceTypes: [ForegroundServiceTypes.dataSync],
        notificationTitle: title,
        notificationText: text,
      );
      // Fails e.g. when asked while the app is in the background; the next
      // start() tries again.
      _running = result is ServiceRequestSuccess;
    } catch (_) {
      // Non-fatal: everything still works in the foreground without it.
    }
  }

  /// Releases [key]'s hold; the service stops once nothing holds it.
  Future<void> stop({String key = 'stream'}) async {
    if (!Platform.isAndroid) return;
    if (_holders.remove(key) == null) return;
    if (_holders.isNotEmpty) {
      if (!_running) return;
      try {
        await FlutterForegroundTask.updateService(
          notificationText: _holders.values.last,
        );
      } catch (_) {}
      return;
    }
    if (!_running) return;
    _running = false;
    try {
      await FlutterForegroundTask.stopService();
    } catch (_) {}
  }
}
