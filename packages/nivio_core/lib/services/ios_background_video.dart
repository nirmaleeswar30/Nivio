import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:media_kit/media_kit.dart';
import 'package:nivio/services/ios_video_output.dart';

/// iOS: turns video off while Nivio is in the background without
/// picture-in-picture.
///
/// Playback keeps going in the background (sound only, UIBackgroundModes:
/// audio) unless "pause on lost visibility" is on. iOS invalidates hardware
/// (VideoToolbox) decoding sessions of background apps, so without PiP showing
/// the video, decoding it only wastes battery or falls back to the CPU.
/// Disabling the video track (`vid=no`) leaves just the sound; the track is
/// put back when Nivio returns to the foreground. When PiP takes over (see
/// IosVideoOutput) the video keeps playing. No-op on other platforms.
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
      // The PiP window closed while Nivio is still in the background.
      IosVideoOutput.instance.pipActive.addListener(() {
        if (_inBackground && !IosVideoOutput.instance.pipActive.value) {
          for (final p in _players.toList()) {
            _hide(p);
          }
        }
      });
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
    // Automatic PiP starts as the app leaves the foreground; give it a moment.
    await Future<void>.delayed(const Duration(milliseconds: 800));
    if (!_inBackground || !_players.contains(player)) return;
    if (await IosVideoOutput.instance.isPipActive(player)) return;
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
