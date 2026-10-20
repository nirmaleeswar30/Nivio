import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:path_provider/path_provider.dart';

/// Manages a custom WebView2 environment on Windows.
///
/// On Windows, if no custom [userDataFolder] is specified, WebView2 defaults to
/// writing to `<exe_dir>\nivio.exe.WebView2`. When the application is installed in
/// `C:\Program Files`, standard users do not have write permissions, causing
/// WebView2 initialization to fail with an "Access Denied" dialog.
///
/// By directing [userDataFolder] to the user's local application data directory
/// (`%LOCALAPPDATA%\Nivio\webview2_data`), WebView2 can read and write its cache,
/// cookies, and state without requiring administrative privileges.
class AppWebViewEnvironment {
  static WebViewEnvironment? instance;
  static bool _initialized = false;

  /// Initializes the WebViewEnvironment on Windows.
  /// Safe to call on all platforms (no-op on non-Windows).
  static Future<void> initialize() async {
    if (_initialized || kIsWeb || !Platform.isWindows) return;
    _initialized = true;

    try {
      final appDir = await getApplicationSupportDirectory();
      final userDataDir = Directory('${appDir.path}${Platform.pathSeparator}webview2_data');
      if (!await userDataDir.exists()) {
        await userDataDir.create(recursive: true);
      }

      final availableVersion = await WebViewEnvironment.getAvailableVersion();
      if (availableVersion != null) {
        instance = await WebViewEnvironment.create(
          settings: WebViewEnvironmentSettings(
            userDataFolder: userDataDir.path,
          ),
        );
        debugPrint('🌐 Initialized Windows WebViewEnvironment at: ${userDataDir.path}');
      } else {
        debugPrint('⚠️ WebView2 runtime is not available on this system.');
      }
    } catch (e) {
      debugPrint('⚠️ Failed to initialize Windows WebViewEnvironment: $e');
    }
  }
}
