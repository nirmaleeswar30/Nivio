import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

/// Low-level FFI bindings to the `rqbit_ffi` native library.
///
/// The native side exposes only three C functions; all real work is done over
/// rqbit's localhost HTTP API. See `rust/src/lib.rs`.
class RqbitBindings {
  RqbitBindings._(this._lib) {
    _start = _lib.lookupFunction<_StartNative, _StartDart>('rqbit_start');
    _stop = _lib.lookupFunction<_StopNative, _StopDart>('rqbit_stop');
    _lastError =
        _lib.lookupFunction<_LastErrorNative, _LastErrorDart>('rqbit_last_error');
  }

  final DynamicLibrary _lib;
  late final _StartDart _start;
  late final _StopDart _stop;
  late final _LastErrorDart _lastError;

  static RqbitBindings? _instance;

  /// Loads the native library (once) and returns the bindings.
  ///
  /// Resolution order:
  ///  1. `RQBIT_FFI_LIB` env var (absolute path) — handy for desktop dev/tests.
  ///  2. Platform default name, resolved by the OS loader / Flutter's ffiPlugin
  ///     bundling (`rqbit_ffi.dll`, `librqbit_ffi.so`).
  static RqbitBindings instance() {
    return _instance ??= RqbitBindings._(_openLibrary());
  }

  static DynamicLibrary _openLibrary() {
    final override = Platform.environment['RQBIT_FFI_LIB'];
    if (override != null && override.isNotEmpty) {
      return DynamicLibrary.open(override);
    }
    if (Platform.isWindows) return DynamicLibrary.open('rqbit_ffi.dll');
    if (Platform.isAndroid || Platform.isLinux) {
      return DynamicLibrary.open('librqbit_ffi.so');
    }
    if (Platform.isMacOS) return DynamicLibrary.open('librqbit_ffi.dylib');
    throw UnsupportedError(
        'rqbit_ffi: unsupported platform ${Platform.operatingSystem}');
  }

  /// Starts the engine's HTTP API on `127.0.0.1:<port>`, storing data under
  /// [outputDir]. Blocks until the listener is bound. Returns 0 on success.
  int start(int port, String outputDir) {
    final dirPtr = outputDir.toNativeUtf8();
    try {
      return _start(port, dirPtr);
    } finally {
      malloc.free(dirPtr);
    }
  }

  /// Stops the engine. Safe to call when not running.
  void stop() => _stop();

  /// Last native error message, or null.
  String? lastError() {
    final ptr = _lastError();
    if (ptr == nullptr) return null;
    return ptr.cast<Utf8>().toDartString();
  }
}

typedef _StartNative = Int32 Function(Uint16 port, Pointer<Utf8> outputDir);
typedef _StartDart = int Function(int port, Pointer<Utf8> outputDir);
typedef _StopNative = Void Function();
typedef _StopDart = void Function();
typedef _LastErrorNative = Pointer<Utf8> Function();
typedef _LastErrorDart = Pointer<Utf8> Function();
