import 'dart:async';

import 'package:flutter/widgets.dart';

import '../core/config/app_environment.dart';
import '../core/services/deep_link_service.dart';
import '../core/services/desktop_cache_service.dart';
import '../features/auth/desktop_cloud_sync_service.dart';
import '../features/auth/firebase_auth_rest_service.dart';
import '../features/library/services/desktop_download_service.dart';
import '../features/library/services/episode_tracking_service.dart';
import '../features/library/services/library_persistence.dart';
import '../features/history/desktop_watch_history_repository.dart';
import '../features/party/services/watch_party_supabase_config.dart';
import '../features/player/services/playback_runtime_diagnostics.dart';
import 'app.dart';

/// Prepares Flutter desktop services before starting the app.
Future<void> bootstrap() async {
  final startupClock = Stopwatch()..start();
  WidgetsFlutterBinding.ensureInitialized();
  PlaybackRuntimeDiagnostics.lifecycleLog(
    'Flutter binding initialized',
    clock: startupClock,
  );
  runApp(const NivioStartupSplashApp());

  try {
    await AppEnvironment.load();
    PlaybackRuntimeDiagnostics.lifecycleLog(
      'Environment loaded',
      clock: startupClock,
    );
    await FirebaseAuthRestService.instance.initialize();
    PlaybackRuntimeDiagnostics.lifecycleLog(
      'Firebase auth restored',
      clock: startupClock,
    );
    await WatchPartySupabaseConfig.initializeIfConfigured();
    PlaybackRuntimeDiagnostics.lifecycleLog(
      'Watch party services initialized',
      clock: startupClock,
    );
    await LibraryPersistence.init();
    PlaybackRuntimeDiagnostics.lifecycleLog(
      'Library persistence initialized',
      clock: startupClock,
    );
    await DesktopCacheService.instance.init();
    PlaybackRuntimeDiagnostics.lifecycleLog(
      'Cache manager initialized',
      clock: startupClock,
    );
    unawaited(LibraryEpisodeTrackingService.instance.runAppLaunchCheck());
    await DesktopDownloadService.instance.restorePendingDownloads();
    PlaybackRuntimeDiagnostics.lifecycleLog(
      'Download manager initialized',
      clock: startupClock,
    );
    await DesktopWatchHistoryRepository.instance.initialize();
    PlaybackRuntimeDiagnostics.lifecycleLog(
      'Watch history initialized',
      clock: startupClock,
    );
    await DesktopCloudSyncService.instance.initialize();
    PlaybackRuntimeDiagnostics.lifecycleLog(
      'Cloud sync initialized',
      clock: startupClock,
    );
    unawaited(DeepLinkService.instance.initialize());
    runApp(const NivioDesktopApp());
    WidgetsBinding.instance.addPostFrameCallback((_) {
      PlaybackRuntimeDiagnostics.lifecycleLog(
        'First Flutter frame rendered',
        clock: startupClock,
      );
      PlaybackRuntimeDiagnostics.snapshot(
        'startup complete',
        clock: startupClock,
      );
    });
  } catch (error, stackTrace) {
    FlutterError.reportError(
      FlutterErrorDetails(
        exception: error,
        stack: stackTrace,
        library: 'nivio desktop bootstrap',
      ),
    );
    runApp(NivioStartupErrorApp(message: error.toString()));
  }
}
