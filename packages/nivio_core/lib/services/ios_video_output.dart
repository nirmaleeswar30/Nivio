import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:nivio/core/debug_log.dart';

/// iOS video output: mpv draws each player straight into an
/// AVSampleBufferDisplayLayer (vo=avfoundation) owned by the native side
/// (packages/nivio_ios/ios/Runner/NivioVideoPlugin.swift), shown by
/// [IosVideoSurface] instead of media_kit's Flutter texture.
///
/// That gives HDR10 / HLG / Dolby Vision on HDR iPhones (iOS shows the frames
/// itself), picture-in-picture from the same layer, and no OpenGL, which iOS
/// forbids in the background. No-op on other platforms.
class IosVideoOutput {
  IosVideoOutput._();
  static final IosVideoOutput instance = IosVideoOutput._();

  static const MethodChannel _channel = MethodChannel('com.nivio/ios_video');

  /// media_kit's controller still runs (the player UI is built around it), on
  /// its software path so it never touches OpenGL; mpv's output is the
  /// display layer, set by [prepare].
  static const VideoControllerConfiguration controllerConfiguration = VideoControllerConfiguration(
    vo: 'avfoundation',
    hwdec: 'videotoolbox',
    enableHardwareAcceleration: false,
  );

  final Expando<Future<int?>> _prepared = Expando('IosVideoOutput');
  final Map<int, Player> _players = {};
  final Map<int, List<StreamSubscription<dynamic>>> _subs = {};
  final Set<int> _pipActive = {};
  bool _handlerSet = false;

  /// Whether any player is in picture-in-picture right now.
  final ValueNotifier<bool> pipActive = ValueNotifier(false);

  /// Gives [player] its display layer and points mpv at it. Idempotent; must
  /// finish before the first file is opened (mpv reads --wid when its video
  /// output starts). Returns the mpv handle, or null when not on iOS.
  Future<int?> prepare(Player player) {
    if (!Platform.isIOS) return Future.value(null);
    return _prepared[player] ??= _prepare(player);
  }

  Future<int?> _prepare(Player player) async {
    _ensureHandler();
    final handle = await player.handle;
    final layer = await _channel.invokeMethod<int>('create', {'handle': handle});
    final native = player.platform;
    if (layer == null || native is! NativePlayer) return handle;
    await native.setProperty('wid', '$layer');
    await native.setProperty('vo', 'avfoundation');
    // Subtitles go on mpv's own overlay layer next to the video, not burned
    // into frames (that's only needed in PiP, see the 'pipState' handler).
    await _trySet(native, 'avfoundation-composite-osd', 'no');
    _players[handle] = player;

    void push() {
      unawaited(_channel.invokeMethod('playback', {
        'handle': handle,
        'playing': player.state.playing,
        'durationMs': player.state.duration.inMilliseconds,
      }).catchError((_) {}));
    }

    _subs[handle] = [
      player.stream.playing.listen((_) => push()),
      player.stream.duration.listen((_) => push()),
    ];
    push();

    native.release.add(() async {
      for (final sub in _subs.remove(handle) ?? const <StreamSubscription<dynamic>>[]) {
        await sub.cancel();
      }
      _players.remove(handle);
      _setPip(handle, false);
      try {
        await _channel.invokeMethod('dispose', {'handle': handle});
      } catch (_) {}
    });
    appDebugLog('📺 [iOS video] player $handle -> AVSampleBufferDisplayLayer $layer');
    return handle;
  }

  Future<void> _call(Player player, String method, [Map<String, Object?> args = const {}]) async {
    final handle = await prepare(player);
    if (handle == null) return;
    try {
      await _channel.invokeMethod(method, {'handle': handle, ...args});
    } catch (e) {
      if (kDebugMode) debugPrint('IosVideoOutput.$method failed: $e');
    }
  }

  /// How the video fills its view ("contain", "cover", "fill").
  Future<void> setFit(Player player, String fit) => _call(player, 'setGravity', {'fit': fit});

  /// HDR video uses the screen's HDR range (on) or is tone-mapped to SDR (off).
  Future<void> setHdr(Player player, bool enabled) => _call(player, 'setHdr', {'enabled': enabled});

  /// Picture-in-picture starts by itself when Nivio goes to the background
  /// while [player] plays ("PiP on Lost Visibility").
  Future<void> setAutoPip(Player player, bool enabled) => _call(player, 'setAutoPip', {'enabled': enabled});

  Future<void> startPip(Player player) => _call(player, 'startPip');

  Future<bool> isPipActive(Player player) async {
    final handle = await prepare(player);
    if (handle == null) return false;
    try {
      return await _channel.invokeMethod<bool>('pipActive', {'handle': handle}) ?? false;
    } catch (_) {
      return false;
    }
  }

  void _ensureHandler() {
    if (_handlerSet) return;
    _handlerSet = true;
    _channel.setMethodCallHandler((call) async {
      final args = (call.arguments as Map?)?.cast<String, Object?>() ?? const {};
      final handle = (args['handle'] as num?)?.toInt();
      final player = handle == null ? null : _players[handle];
      if (handle == null || player == null) return null;
      switch (call.method) {
        case 'pipCommand':
          switch (args['command']) {
            case 'play':
              await player.play();
            case 'pause':
              await player.pause();
            case 'seekBy':
              final delta = Duration(milliseconds: (args['deltaMs'] as num?)?.toInt() ?? 0);
              var target = player.state.position + delta;
              final duration = player.state.duration;
              if (target < Duration.zero) target = Duration.zero;
              if (duration > Duration.zero && target > duration) target = duration;
              await player.seek(target);
          }
        case 'pipState':
          final active = args['active'] == true;
          if (args['error'] != null) appDebugLog('📺 [iOS video] PiP failed: ${args['error']}');
          _setPip(handle, active);
          // The PiP window shows the video frames only, so subtitles are drawn
          // into them while it is up.
          final native = player.platform;
          if (native is NativePlayer) {
            await _trySet(native, 'avfoundation-pip-composite-osd', active ? 'yes' : 'no');
          }
      }
      return null;
    });
  }

  static Future<void> _trySet(NativePlayer native, String name, String value) async {
    try {
      await native.setProperty(name, value);
    } catch (e) {
      appDebugLog('📺 [iOS video] $name=$value failed: $e');
    }
  }

  void _setPip(int handle, bool active) {
    if (active) {
      _pipActive.add(handle);
    } else {
      _pipActive.remove(handle);
    }
    pipActive.value = _pipActive.isNotEmpty;
  }
}
