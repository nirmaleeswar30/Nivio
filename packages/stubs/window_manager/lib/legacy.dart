/// No-op `window_manager` legacy API for the Android build. Nivio only calls
/// it on Windows, Linux and macOS, so every call here does nothing.
library;

import 'dart:ui';

enum TitleBarStyle { normal, hidden }

class WindowOptions {
  const WindowOptions({
    this.size,
    this.minimumSize,
    this.maximumSize,
    this.center,
    this.backgroundColor,
    this.skipTaskbar,
    this.title,
    this.titleBarStyle,
    this.alwaysOnTop,
    this.fullScreen,
    this.windowButtonVisibility,
  });

  final Size? size;
  final Size? minimumSize;
  final Size? maximumSize;
  final bool? center;
  final Color? backgroundColor;
  final bool? skipTaskbar;
  final String? title;
  final TitleBarStyle? titleBarStyle;
  final bool? alwaysOnTop;
  final bool? fullScreen;
  final bool? windowButtonVisibility;
}

class WindowManager {
  WindowManager._();

  static final WindowManager instance = WindowManager._();

  Future<void> ensureInitialized() async {}
  Future<void> waitUntilReadyToShow([WindowOptions? options, VoidCallback? callback]) async {
    callback?.call();
  }

  Future<void> show({bool inactive = false}) async {}
  Future<void> focus() async {}
  Future<void> close() async {}
  Future<void> minimize() async {}
  Future<void> maximize({bool vertically = false}) async {}
  Future<void> unmaximize() async {}
  Future<bool> isMaximized() async => false;
  Future<bool> isFullScreen() async => false;
  Future<void> setFullScreen(bool isFullScreen) async {}
  Future<void> startDragging() async {}
  Future<void> setTitleBarStyle(
    TitleBarStyle titleBarStyle, {
    bool windowButtonVisibility = true,
  }) async {}
}

final windowManager = WindowManager.instance;
