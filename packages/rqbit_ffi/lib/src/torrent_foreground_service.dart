import 'dart:io';

import 'package:flutter_foreground_task/flutter_foreground_task.dart';

/// Keeps the app process (and the FFI engine's networking threads) alive while
/// torrents are active, via an Android foreground service with a persistent
/// notification. No-op on non-Android platforms.
///
/// It runs the service *without* a task-handler isolate — the engine lives in
/// the main isolate, so we only need the service to hold the process at
/// foreground priority. All calls are defensive: failures never propagate.
class TorrentForegroundService {
  TorrentForegroundService._();
  static final TorrentForegroundService instance = TorrentForegroundService._();

  bool _initialized = false;
  bool _running = false;

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

  /// Starts the foreground service if not already running (Android only).
  Future<void> start({
    String title = 'Nivio',
    String text = 'Streaming torrent…',
  }) async {
    if (!Platform.isAndroid || _running) return;
    try {
      _ensureInitialized();
      if (await FlutterForegroundTask.isRunningService) {
        _running = true;
        return;
      }
      await FlutterForegroundTask.startService(
        serviceId: 2718,
        serviceTypes: [ForegroundServiceTypes.dataSync],
        notificationTitle: title,
        notificationText: text,
      );
      _running = true;
    } catch (_) {
      // Non-fatal: streaming still works in the foreground without the service.
    }
  }

  /// Stops the foreground service if running.
  Future<void> stop() async {
    if (!Platform.isAndroid || !_running) return;
    _running = false;
    try {
      await FlutterForegroundTask.stopService();
    } catch (_) {}
  }
}
