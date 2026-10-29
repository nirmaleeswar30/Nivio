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

  static Future<HdrDisplayInfo>? _hdrDisplay;

  /// Whether the screen can show HDR (Android only; asked once, then cached).
  /// A TV box reports what the connected TV supports.
  static Future<HdrDisplayInfo> hdrDisplay() {
    return _hdrDisplay ??= () async {
      if (!Platform.isAndroid) return const HdrDisplayInfo();
      try {
        final info = await _channel.invokeMapMethod<String, dynamic>('hdrInfo');
        return HdrDisplayInfo(
          isHdr: info?['isHdr'] == true,
          types: ((info?['types'] as List?) ?? const []).map((e) => '$e').toList(),
          maxLuminance: (info?['maxLuminance'] as num?)?.toDouble(),
        );
      } catch (_) {
        return const HdrDisplayInfo();
      }
    }();
  }

  /// Hands the screen brightness back to the system setting after the
  /// player's brightness gesture overrode it for the app window (Android).
  static Future<void> resetWindowBrightness() async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod<void>('resetWindowBrightness');
    } catch (e) {
      if (kDebugMode) debugPrint('resetWindowBrightness failed: $e');
    }
  }

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

/// What the screen can show for HDR video.
class HdrDisplayInfo {
  /// The screen (or connected TV) supports HDR.
  final bool isHdr;

  /// e.g. hdr10, hlg, dolbyVision, hdr10plus.
  final List<String> types;

  /// Desired peak brightness in nits, if the system reports it.
  final double? maxLuminance;

  const HdrDisplayInfo({this.isHdr = false, this.types = const [], this.maxLuminance});
}
