import 'package:flutter/foundation.dart';
import 'package:webview_all/webview_all.dart';
import 'package:webview_all_linux/webview_all_linux.dart';
import 'package:webview_all_windows/webview_all_windows.dart';

import 'playback_runtime_diagnostics.dart';

final class WebRuntimeService {
  WebRuntimeService._();

  static final WebRuntimeService instance = WebRuntimeService._();

  bool _registered = false;

  WebViewController createController() {
    _ensureRegistered();
    PlaybackRuntimeDiagnostics.webViewsCreated++;
    PlaybackRuntimeDiagnostics.webLog(
      'WebView Created count=${PlaybackRuntimeDiagnostics.webViewsCreated}',
    );
    PlaybackRuntimeDiagnostics.snapshot('after WebView create');
    return WebViewController.fromPlatformCreationParams(_creationParams());
  }

  String webViewUserAgent() {
    if (defaultTargetPlatform == TargetPlatform.windows) {
      return 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) '
          'AppleWebKit/537.36 (KHTML, like Gecko) '
          'Chrome/120.0.0.0 Safari/537.36';
    }
    return 'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 '
        '(KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36';
  }

  Future<void> disposeController(WebViewController controller) async {
    final platform = controller.platform;
    try {
      if (platform is LinuxWebViewController) {
        await platform.dispose();
      }
    } catch (_) {}
  }

  void markReused() {
    PlaybackRuntimeDiagnostics.webViewReuseCount++;
    PlaybackRuntimeDiagnostics.webLog(
      'WebView Reused count=${PlaybackRuntimeDiagnostics.webViewReuseCount}',
    );
  }

  void markDestroyed() {
    PlaybackRuntimeDiagnostics.webViewsDestroyed++;
    PlaybackRuntimeDiagnostics.webLog(
      'WebView Destroyed count=${PlaybackRuntimeDiagnostics.webViewsDestroyed}',
    );
    PlaybackRuntimeDiagnostics.snapshot('after WebView destroy');
  }

  String limitationsSummary() {
    return 'webview_all platform packages do not expose WebContext, WebsiteDataManager, '
        'UserContentManager, renderer PID, GPU memory, CPU usage, or explicit '
        'persistent cache/storage directory configuration.';
  }

  void _ensureRegistered() {
    if (_registered) return;
    switch (defaultTargetPlatform) {
      case TargetPlatform.linux:
        LinuxWebViewPlatform.registerWith();
      case TargetPlatform.windows:
        WindowsWebViewPlatform.registerWith();
      default:
        throw UnsupportedError(
          'Embedded web playback is supported only on Linux and Windows.',
        );
    }
    _registered = true;
    PlaybackRuntimeDiagnostics.webLog(
      'WebRuntimeService initialized for ${defaultTargetPlatform.name} '
      'with shared Dart runtime; native WebContext/DataManager reuse is '
      'plugin-managed.',
    );
  }

  PlatformWebViewControllerCreationParams _creationParams() {
    switch (defaultTargetPlatform) {
      case TargetPlatform.linux:
        return const LinuxWebViewControllerCreationParams(
          javascriptCanOpenWindowsAutomatically: false,
          mediaPlaybackRequiresUserGesture: false,
          mediaPlaybackAllowsInline: true,
          pageCacheEnabled: true,
        );
      case TargetPlatform.windows:
        return const WindowsWebViewControllerCreationParams(
          popupWindowPolicy: WindowsPopupWindowPolicy.sameWindow,
        );
      default:
        throw UnsupportedError(
          'Embedded web playback is supported only on Linux and Windows.',
        );
    }
  }
}
