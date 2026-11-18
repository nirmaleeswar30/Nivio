import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:media_kit/media_kit.dart';

/// iOS: turns video output off while Nivio is in the background.
///
/// media_kit draws video on iOS with OpenGL ES, and iOS terminates an app
/// that submits GPU work while it is in the background. Playback keeps going
/// in the background (sound only, UIBackgroundModes: audio) unless "pause on
/// lost visibility" is on, so every new frame would be a GL call. Disabling
/// the video track (`vid=no`) stops decoding and drawing; the track is put
/// back when Nivio returns to the foreground. No-op on other platforms.
class IosBackgroundVideo with WidgetsBindingObserver {
  IosBackgroundVideo._();
  static final IosBackgroundVideo instance = IosBackgroundVideo._();

  final Set<Player> _players = {};

  /// Video track ids that were switched off, to restore on resume.
  final Map<Player, String> _hidden = {};
  bool _observing = false;
  bool _inBackground = false;

  /// Starts guarding [player] (idempotent).
  void track(Player player) {
    if (!Platform.isIOS) return;
    _players.add(player);
    if (!_observing) {
      _observing = true;
      WidgetsBinding.instance.addObserver(this);
    }
    if (_inBackground) _hide(player);
  }

  /// Stops guarding [player], e.g. before it is disposed.
  void untrack(Player player) {
    if (!Platform.isIOS) return;
    _players.remove(player);
    _hidden.remove(player);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.hidden:
      case AppLifecycleState.paused:
        if (_inBackground) return;
        _inBackground = true;
        for (final player in _players.toList()) {
          _hide(player);
        }
      case AppLifecycleState.inactive:
      case AppLifecycleState.resumed:
        if (!_inBackground) return;
        _inBackground = false;
        for (final player in _players.toList()) {
          _show(player);
        }
      case AppLifecycleState.detached:
        break;
    }
  }

  Future<void> _hide(Player player) async {
    final platform = player.platform;
    if (platform is! NativePlayer || _hidden.containsKey(player)) return;
    try {
      final vid = await platform.getProperty('vid');
      if (vid == 'no') return; // audio-only already
      _hidden[player] = vid.isEmpty ? 'auto' : vid;
      await platform.setProperty('vid', 'no');
    } catch (e) {
      if (kDebugMode) debugPrint('IosBackgroundVideo: hide failed: $e');
    }
  }

  Future<void> _show(Player player) async {
    final platform = player.platform;
    final vid = _hidden.remove(player);
    if (platform is! NativePlayer || vid == null) return;
    try {
      await platform.setProperty('vid', vid);
    } catch (e) {
      if (kDebugMode) debugPrint('IosBackgroundVideo: restore failed: $e');
    }
  }
}
