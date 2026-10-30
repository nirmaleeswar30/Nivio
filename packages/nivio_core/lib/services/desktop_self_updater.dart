import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:nivio/core/debug_log.dart';
import 'package:nivio/services/github_release_update_service.dart';

/// Installs a desktop update from inside Nivio, so nobody has to uninstall
/// the old version or juggle files:
///
/// * Windows: downloads the new Setup exe, quits, and runs it silently; the
///   installer closes any Nivio still running, upgrades in place and starts
///   the new version (packages/nivio_desktop/installer/windows/nivio.iss).
/// * Linux (AppImage): downloads the new AppImage next to the running one,
///   swaps it in under the same file name (so launchers and the nivio://
///   handler keep pointing at it), and restarts into it.
///
/// Anything else (Android, a Linux build not run as an AppImage, a failed
/// download) falls back to opening the download in the browser.
class DesktopSelfUpdater {
  DesktopSelfUpdater._();

  static final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 20),
      headers: const {'User-Agent': 'Nivio-App-Updater'},
    ),
  );

  static String? get _appImagePath {
    final path = Platform.environment['APPIMAGE'];
    return (path != null && path.isNotEmpty && File(path).existsSync()) ? path : null;
  }

  /// Whether [url] (a release asset) can be installed in-app on this platform.
  static bool canInstall(String url) {
    final lower = url.toLowerCase();
    if (Platform.isWindows) return lower.endsWith('.exe');
    if (Platform.isLinux) return lower.endsWith('.appimage') && _appImagePath != null;
    return false;
  }

  /// Installs the update at [url] in-app where possible, otherwise opens it
  /// in the browser. [context] must outlive the dialog that called this
  /// (pass the screen's context, not the update dialog's).
  static Future<void> installOrOpen(BuildContext context, String url) async {
    if (!canInstall(url)) {
      await GitHubReleaseUpdateService.openReleasePage(url);
      return;
    }
    // Let the update prompt that called us close first.
    await Future<void>.delayed(Duration.zero);
    if (!context.mounted) return;

    final progress = ValueNotifier<double?>(null);
    final cancelToken = CancelToken();
    final navigator = Navigator.of(context, rootNavigator: true);
    var dialogOpen = true;
    unawaited(showDialog<void>(
      context: context,
      useRootNavigator: true,
      barrierDismissible: false,
      builder: (dialogContext) => PopScope(
        canPop: false,
        child: AlertDialog(
          title: const Text('Updating Nivio'),
          content: ValueListenableBuilder<double?>(
            valueListenable: progress,
            builder: (context, value, _) => Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(value == null
                    ? 'Starting download...'
                    : value >= 1
                        ? 'Installing. Nivio will restart on its own.'
                        : 'Downloading ${(value * 100).round()}%'),
                const SizedBox(height: 14),
                LinearProgressIndicator(value: value != null && value < 1 ? value : null),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => cancelToken.cancel(),
              child: const Text('Cancel'),
            ),
          ],
        ),
      ),
    ).whenComplete(() => dialogOpen = false));

    void closeDialog() {
      if (dialogOpen) navigator.pop();
    }

    try {
      if (Platform.isWindows) {
        final setup = await _download(url, Directory.systemTemp.path, 'Nivio-Setup-update.exe', progress, cancelToken);
        progress.value = 1;
        await _runWindowsInstaller(setup);
      } else {
        final appImage = _appImagePath!;
        final dir = File(appImage).parent.path;
        final download = await _download(url, dir, '.nivio-update.AppImage', progress, cancelToken);
        progress.value = 1;
        await _swapAppImage(download, appImage);
      }
    } catch (e) {
      closeDialog();
      if (e is DioException && CancelToken.isCancel(e)) return;
      appDebugLog('⬆️ In-app update failed: $e');
      if (context.mounted) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          const SnackBar(content: Text("Couldn't install the update here. Opening the download instead.")),
        );
      }
      await GitHubReleaseUpdateService.openReleasePage(url);
    }
  }

  static Future<File> _download(
    String url,
    String dir,
    String name,
    ValueNotifier<double?> progress,
    CancelToken cancelToken,
  ) async {
    final file = File('$dir${Platform.pathSeparator}$name');
    await _dio.download(
      url,
      file.path,
      cancelToken: cancelToken,
      deleteOnError: true,
      onReceiveProgress: (received, total) {
        if (total > 0) progress.value = (received / total).clamp(0.0, 0.99);
      },
    );
    return file;
  }

  /// Runs the Inno Setup installer silently and quits, so nothing of this
  /// version is running while it upgrades. It asks for admin rights (UAC)
  /// when Nivio is installed for all users, then starts the new version.
  static Future<void> _runWindowsInstaller(File setup) async {
    const args = ['/SILENT', '/SUPPRESSMSGBOXES', '/NORESTART', '/CLOSEAPPLICATIONS'];
    try {
      await Process.start(setup.path, args, mode: ProcessStartMode.detached);
    } on ProcessException catch (e) {
      // 740: the exe insists on admin rights up front, which a plain process
      // start can't grant; ShellExecute (Start-Process) shows the UAC prompt.
      if (e.errorCode != 740) rethrow;
      final path = setup.path.replaceAll("'", "''");
      await Process.start(
        'powershell',
        [
          '-NoProfile',
          '-WindowStyle',
          'Hidden',
          '-Command',
          "Start-Process -FilePath '$path' -ArgumentList ${args.map((a) => "'$a'").join(',')}",
        ],
        mode: ProcessStartMode.detached,
      );
    }
    appDebugLog('⬆️ Installer started; exiting for the update');
    exit(0);
  }

  /// Replaces the running AppImage with [download] and restarts into it. The
  /// running copy keeps working until it exits: the rename only swaps which
  /// file the name points to.
  static Future<void> _swapAppImage(File download, String appImage) async {
    final chmod = await Process.run('chmod', ['+x', download.path]);
    if (chmod.exitCode != 0) throw StateError('chmod failed: ${chmod.stderr}');
    await download.rename(appImage);
    // Start the new version only once this process is gone; otherwise it would
    // find this one still holding the single-instance port and quit.
    await Process.start(
      '/bin/sh',
      ['-c', 'while kill -0 "\$1" 2>/dev/null; do sleep 0.2; done; exec "\$0"', appImage, '$pid'],
      mode: ProcessStartMode.detached,
    );
    appDebugLog('⬆️ AppImage replaced; restarting into the update');
    exit(0);
  }
}
