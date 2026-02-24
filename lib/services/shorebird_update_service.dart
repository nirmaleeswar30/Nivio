import 'package:flutter/foundation.dart';
import 'package:shorebird_code_push/shorebird_code_push.dart';

enum ShorebirdUpdateAction {
  unavailable,
  upToDate,
  downloaded,
  restartRequired,
  failed,
}

class ShorebirdUpdateResult {
  const ShorebirdUpdateResult({required this.action, required this.message});

  final ShorebirdUpdateAction action;
  final String message;
}

class ShorebirdUpdateService {
  ShorebirdUpdateService._();

  static final ShorebirdUpdater _updater = ShorebirdUpdater();

  static bool get isAvailable => _updater.isAvailable;

  static Future<int?> currentPatchNumber() async {
    if (!isAvailable) return null;
    final patch = await _updater.readCurrentPatch();
    return patch?.number;
  }

  static Future<ShorebirdUpdateResult> checkAndUpdate({
    UpdateTrack track = UpdateTrack.stable,
  }) async {
    if (!isAvailable) {
      return const ShorebirdUpdateResult(
        action: ShorebirdUpdateAction.unavailable,
        message: 'OTA updates are not available in this build.',
      );
    }

    try {
      final status = await _updater.checkForUpdate(track: track);
      switch (status) {
        case UpdateStatus.unavailable:
          return const ShorebirdUpdateResult(
            action: ShorebirdUpdateAction.unavailable,
            message: 'No update channel available right now.',
          );
        case UpdateStatus.upToDate:
          return const ShorebirdUpdateResult(
            action: ShorebirdUpdateAction.upToDate,
            message: 'You already have the latest OTA patch.',
          );
        case UpdateStatus.outdated:
          await _updater.update(track: track);
          return const ShorebirdUpdateResult(
            action: ShorebirdUpdateAction.downloaded,
            message: 'New OTA patch downloaded. Restart the app to apply it.',
          );
        case UpdateStatus.restartRequired:
          return const ShorebirdUpdateResult(
            action: ShorebirdUpdateAction.restartRequired,
            message: 'An OTA patch is ready. Restart the app to apply it.',
          );
      }
    } on UpdateException catch (error) {
      return ShorebirdUpdateResult(
        action: ShorebirdUpdateAction.failed,
        message: 'OTA update failed: ${error.message}',
      );
    } catch (error) {
      return ShorebirdUpdateResult(
        action: ShorebirdUpdateAction.failed,
        message: 'OTA update check failed: $error',
      );
    }
  }

  static Future<void> checkAndUpdateInBackground() async {
    final result = await checkAndUpdate();
    debugPrint('[Shorebird] ${result.message}');
  }
}
