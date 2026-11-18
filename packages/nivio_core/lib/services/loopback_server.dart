import 'dart:io';

import 'package:flutter/widgets.dart';

/// Helpers for Nivio's localhost HTTP servers (HLS proxy, local stream
/// server).
///
/// iOS may reclaim the listening sockets of a suspended app (Apple TN2277):
/// after a long time in the background the server object still exists but
/// nothing answers on its port any more. [onIosResume] lets a server check
/// itself with [loopbackPortAccepts] when Nivio comes back and rebind (on the
/// same port when possible, so URLs already handed to the player keep
/// working).

/// Binds a loopback server, on [preferredPort] if it's free, else any port.
Future<HttpServer> bindLoopback({int preferredPort = 0}) async {
  if (preferredPort != 0) {
    try {
      return await HttpServer.bind(InternetAddress.loopbackIPv4, preferredPort);
    } catch (_) {
      // Taken (or not allowed): fall back to any free port.
    }
  }
  return HttpServer.bind(InternetAddress.loopbackIPv4, 0);
}

/// Whether something accepts connections on 127.0.0.1:[port].
Future<bool> loopbackPortAccepts(int port) async {
  try {
    final socket = await Socket.connect(
      InternetAddress.loopbackIPv4,
      port,
      timeout: const Duration(seconds: 1),
    );
    socket.destroy();
    return true;
  } catch (_) {
    return false;
  }
}

final List<AppLifecycleListener> _listeners = [];

/// Runs [callback] each time the app returns to the foreground, on iOS only.
void onIosResume(Future<void> Function() callback) {
  if (!Platform.isIOS) return;
  _listeners.add(AppLifecycleListener(onResume: () => callback()));
}
