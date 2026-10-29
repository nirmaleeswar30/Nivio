import 'dart:async';

import 'package:nivio/core/debug_log.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

/// Keeps the screen awake while anything still needs it.
///
/// WakelockPlus is a single on/off switch, so one owner turning it off (a
/// finished download, a closed trailer, or the old player screen being
/// disposed after the next episode's screen opened) would let the screen sleep
/// under a video that's still playing. Each owner holds it under its own key
/// instead, and the screen may sleep only once nobody holds it.
class ScreenWakeLock {
  ScreenWakeLock._();

  static final Set<Object> _holders = {};

  static bool isHeldBy(Object holder) => _holders.contains(holder);

  static void acquire(Object holder) {
    final added = _holders.add(holder);
    // Re-asserted even when already held: cheap, and recovers if the flag
    // was cleared behind our back.
    _apply();
    if (added) appDebugLog('💡 Wake lock held by ${_name(holder)} (${_holders.length} holders)');
  }

  static void release(Object holder) {
    if (!_holders.remove(holder)) return;
    _apply();
    appDebugLog('💡 Wake lock released by ${_name(holder)} (${_holders.length} holders)');
  }

  static void _apply() {
    // Platform calls run in order, so the last state set wins.
    final enable = _holders.isNotEmpty;
    unawaited((enable ? WakelockPlus.enable() : WakelockPlus.disable()).catchError((Object e) {
      appDebugLog('💡 Wake lock ${enable ? 'enable' : 'disable'} failed: $e');
    }));
  }

  static String _name(Object holder) => holder is String ? holder : holder.runtimeType.toString();
}
