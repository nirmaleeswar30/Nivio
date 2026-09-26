import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:window_manager/window_manager.dart';

/// Whether the desktop window is currently in app-driven fullscreen.
///
/// The custom title bar overlay listens to this so its minimize / maximize /
/// close buttons are hidden while the player is fullscreen.
final ValueNotifier<bool> windowFullScreenNotifier = ValueNotifier(false);

/// Enters or leaves window fullscreen on desktop. No-op on mobile.
///
/// Always use this instead of calling [WindowManager.setFullScreen] directly so
/// [windowFullScreenNotifier] stays in sync.
Future<void> setWindowFullScreen(bool isFullScreen) async {
  if (Platform.isAndroid || Platform.isIOS) return;
  // Update first so the title bar disappears before the window resizes.
  windowFullScreenNotifier.value = isFullScreen;
  await windowManager.setFullScreen(isFullScreen);
  // On Windows, setFullScreen() rewrites the native window style and undoes
  // TitleBarStyle.hidden, which brings back the OS caption buttons. Re-assert
  // the hidden style after every toggle.
  if (Platform.isWindows) {
    await windowManager.setTitleBarStyle(TitleBarStyle.hidden);
  }
}
