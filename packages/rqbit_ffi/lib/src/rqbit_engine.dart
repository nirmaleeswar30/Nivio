import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'bindings.dart';
import 'rqbit_client.dart';

/// Manages the lifecycle of the embedded rqbit engine: boots the native HTTP
/// API via FFI and hands back a [RqbitClient] to drive it.
///
/// Usage:
/// ```dart
/// final engine = RqbitEngine.instance;
/// final client = await engine.ensureStarted();
/// final add = await client.addTorrent(magnet);
/// final url = client.streamUrl(add.id!, fileIndex); // -> media_kit
/// ```
class RqbitEngine {
  RqbitEngine._();
  static final RqbitEngine instance = RqbitEngine._();

  RqbitClient? _client;
  int? _port;
  String? _downloadDir;
  Future<RqbitClient>? _starting;

  bool get isRunning => _client != null;
  int? get port => _port;
  String? get baseUrl => _port == null ? null : 'http://127.0.0.1:$_port';
  String? get downloadDir => _downloadDir;

  /// Starts the engine if not already running (idempotent; concurrent callers
  /// share the same start). [downloadDir] defaults to an app cache subfolder.
  Future<RqbitClient> ensureStarted({String? downloadDir, int? port}) {
    if (_client != null) return Future.value(_client);
    return _starting ??= _start(downloadDir: downloadDir, port: port)
      ..whenComplete(() => _starting = null);
  }

  Future<RqbitClient> _start({String? downloadDir, int? port}) async {
    final dir = downloadDir ?? await _defaultDownloadDir();
    await Directory(dir).create(recursive: true);

    final chosenPort = port ?? await _freePort();
    var rc = RqbitBindings.instance().start(chosenPort, dir);
    if (rc == -13) {
      // An orphaned native engine is already running (e.g., from a session
      // prior to a Flutter hot restart or previous stream). Stop it cleanly
      // and restart fresh on the chosen port.
      RqbitBindings.instance().stop();
      rc = RqbitBindings.instance().start(chosenPort, dir);
    }
    if (rc != 0) {
      final err = RqbitBindings.instance().lastError() ?? 'unknown error';
      throw StateError('rqbit_start failed (code $rc): $err');
    }

    _port = chosenPort;
    _downloadDir = dir;
    final client = RqbitClient('http://127.0.0.1:$chosenPort');
    _client = client;
    return client;
  }

  /// Stops the engine and releases the native runtime.
  Future<void> stop() async {
    _client?.close();
    _client = null;
    _port = null;
    RqbitBindings.instance().stop();
  }

  static Future<String> _defaultDownloadDir() async {
    Directory base;
    try {
      base = await getApplicationCacheDirectory();
    } catch (_) {
      base = await getTemporaryDirectory();
    }
    return '${base.path}${Platform.pathSeparator}nivio_torrents';
  }

  /// Asks the OS for an unused loopback TCP port.
  static Future<int> _freePort() async {
    final s = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final p = s.port;
    await s.close();
    return p;
  }
}
