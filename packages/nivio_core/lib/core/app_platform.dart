import 'dart:async';
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

  static const MethodChannel _hdrWindowChannel = MethodChannel('com.nivio/hdr_window');
  static StreamController<String>? _hdrWindowEvents;

  /// Calls from the native HDR video host (Windows, Linux).
  static Stream<String> get _hdrEvents {
    var controller = _hdrWindowEvents;
    if (controller == null) {
      controller = _hdrWindowEvents = StreamController<String>.broadcast();
      if (Platform.isWindows || Platform.isLinux) {
        _hdrWindowChannel.setMethodCallHandler((call) async {
          _hdrWindowEvents?.add(call.method);
          return null;
        });
      }
    }
    return controller.stream;
  }

  /// Fires when the HDR state of the app's screen may have changed (HDR
  /// switched on/off, or the window moved to another monitor; Windows and
  /// Linux). Call [hdrDisplay] again for the new state.
  static Stream<void> get hdrDisplayChanges => _hdrEvents.where((m) => m == 'displayChanged');

  /// Linux: the app window was hidden, which takes the HDR video surface
  /// (a subsurface of the window's) with it.
  static Stream<void> get hdrSurfaceLost => _hdrEvents.where((m) => m == 'surfaceLost');

  /// Whether the screen can show HDR. Android: asked once, then cached (a TV
  /// box reports what the connected TV supports). Windows: the monitor the
  /// app window is on, with Windows HDR switched on. Linux: the screen the
  /// window is on, with the compositor's HDR mode on (Wayland). Windows and
  /// Linux are asked fresh each time.
  static Future<HdrDisplayInfo> hdrDisplay() {
    if (Platform.isWindows || Platform.isLinux) return _desktopHdrDisplay();
    return _hdrDisplay ??= () async {
      if (!Platform.isAndroid && !Platform.isIOS) return const HdrDisplayInfo();
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

  static Future<HdrDisplayInfo> _desktopHdrDisplay() async {
    try {
      final info = await _hdrWindowChannel.invokeMapMethod<String, dynamic>('displayInfo');
      final isHdr = info?['isHdr'] == true;
      return HdrDisplayInfo(
        isHdr: isHdr,
        types: isHdr ? const ['hdr10'] : const [],
        maxLuminance: (info?['maxLuminance'] as num?)?.toDouble(),
        adapter: info?['adapter'] as String?,
        hdrSupported: info?['hdrSupported'] as bool?,
      );
    } catch (e) {
      if (kDebugMode) debugPrint('hdrDisplay (${Platform.operatingSystem}) failed: $e');
      return const HdrDisplayInfo();
    }
  }

  /// Call before the player's brightness gesture first changes the
  /// brightness. iOS has no per-window brightness: the gesture changes the
  /// system brightness itself, so the level it had is saved natively to be
  /// put back by [resetWindowBrightness] (and while Nivio is in the
  /// background). No-op elsewhere.
  static Future<void> rememberSystemBrightness() async {
    if (!Platform.isIOS) return;
    try {
      await _channel.invokeMethod<void>('rememberBrightness');
    } catch (e) {
      if (kDebugMode) debugPrint('rememberSystemBrightness failed: $e');
    }
  }

  /// Hands the screen brightness back to the system setting after the
  /// player's brightness gesture overrode it for the app window (Android),
  /// or restores the brightness saved by [rememberSystemBrightness] (iOS).
  static Future<void> resetWindowBrightness() async {
    if (!Platform.isAndroid && !Platform.isIOS) return;
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

  /// Windows: the GPU driving the screen (for mpv's d3d11-adapter).
  final String? adapter;

  /// Windows: whether the screen can do HDR at all, even while Windows HDR is
  /// switched off for it ([isHdr] is whether it's on). Linux: false when the
  /// desktop has no HDR support at all (X11, or a Wayland compositor without
  /// colour management). Null if unknown.
  final bool? hdrSupported;

  const HdrDisplayInfo({this.isHdr = false, this.types = const [], this.maxLuminance, this.adapter, this.hdrSupported});
}
