import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// Where Nivio is running, split into what the device *is* and how the UI
/// should be laid out.
///
/// Android TV runs the Android build but uses the desktop layout (side nav
/// rail, poster grids, wide pages) and is driven with a D-pad remote. Use
/// [useDesktopLayout] for layout decisions and [isDesktopOS] for anything that
/// needs a desktop OS (window_manager, single-instance IPC, Discord RPC, ...).
class AppPlatform {
  AppPlatform._();

  static const MethodChannel _channel = MethodChannel('com.nivio/device');

  /// `flutter run --dart-define=NIVIO_TV=true` forces TV mode on any device,
  /// handy for trying the TV layout/remote handling on a phone or desktop.
  static const bool _forceTv = bool.fromEnvironment('NIVIO_TV');

  static bool _isTv = _forceTv;

  /// Running on Android TV / Google TV (or TV mode forced for testing).
  static bool get isTv => _isTv;

  /// Windows, Linux or macOS.
  static bool get isDesktopOS =>
      Platform.isWindows || Platform.isLinux || Platform.isMacOS;

  /// Big-screen layout: desktop, or a TV.
  static bool get useDesktopLayout => isDesktopOS || _isTv;

  /// Asks Android whether this is a TV. Call once before `runApp`.
  static Future<void> init() async {
    if (!_forceTv && Platform.isAndroid) {
      try {
        _isTv = await _channel.invokeMethod<bool>('isTv') ?? false;
      } catch (e) {
        if (kDebugMode) debugPrint('AppPlatform.init failed: $e');
      }
    }
    // No touchscreen on a TV, so always draw focus highlights. Flutter
    // otherwise only switches to them for keys from a "real" keyboard device,
    // and some remotes (e.g. HDMI-CEC) arrive as the virtual one.
    if (_isTv) {
      FocusManager.instance.highlightStrategy =
          FocusHighlightStrategy.alwaysTraditional;
    }
  }
}
