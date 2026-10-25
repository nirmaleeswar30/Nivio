import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:nivio/core/debug_log.dart';

typedef _GetJavaVmNative = Pointer<Void> Function();
typedef _GetJavaVm = Pointer<Void> Function();
typedef _SetJavaVmNative = Int32 Function(Pointer<Void> vm, Pointer<Void> logCtx);
typedef _SetJavaVm = int Function(Pointer<Void> vm, Pointer<Void> logCtx);
typedef _CopyAssetNative = Void Function(Pointer<Uint8> asset, Pointer<Uint8> result);
typedef _CopyAsset = void Function(Pointer<Uint8> asset, Pointer<Uint8> result);
typedef _MallocNative = Pointer<Void> Function(IntPtr size);
typedef _Malloc = Pointer<Void> Function(int size);
typedef _FreeNative = Void Function(Pointer<Void> ptr);
typedef _Free = void Function(Pointer<Void> ptr);

/// Absolute path of the CA certificate bundle for mpv's HTTPS (libcurl with
/// verification), once [setUpMpvForAndroid] has copied it out of the APK.
/// Null elsewhere, and for media_kit's own libmpv (which doesn't need it).
String? mpvCaBundlePath;

/// One-time Android setup for the mpvlibAndroid build of mpv, which the
/// Android app ships instead of media_kit's (see android/app/build.gradle.kts,
/// where its FFmpeg is renamed to libmvcodec.so etc. to sit next to FFmpegKit's).
/// Call once at startup, after `MediaKit.ensureInitialized()`.
///
/// * Java VM: media_kit only registers it with `libavcodec.so` (FFmpegKit's
///   now), so mpv's FFmpeg never got it: no MediaCodec, and mpv's Android
///   video output failed with "No Java virtual machine has been registered"
///   (black video, audio only).
/// * CA bundle: this mpv opens HTTPS through libcurl with certificate checks
///   and needs a bundle file (`tls-ca-file`); without it every HTTPS stream
///   failed with "TLS certificate verification failed".
void setUpMpvForAndroid() {
  if (!Platform.isAndroid) return;
  try {
    final DynamicLibrary codec;
    try {
      codec = DynamicLibrary.open('libmvcodec.so');
    } catch (_) {
      return; // Not the mpvlib build; media_kit's own libmpv handles this itself.
    }
    final helper = DynamicLibrary.open('libmediakitandroidhelper.so');
    _registerJavaVm(helper, codec);
    mpvCaBundlePath = _copyAsset(helper, 'cacert.pem');
    appDebugLog('🎞️ mpv CA bundle: $mpvCaBundlePath');
  } catch (e) {
    appDebugLog('🎞️ mpv Android setup failed: $e');
  }
}

void _registerJavaVm(DynamicLibrary helper, DynamicLibrary codec) {
  final getVm = helper.lookupFunction<_GetJavaVmNative, _GetJavaVm>('MediaKitAndroidHelperGetJavaVM');
  final setVm = codec.lookupFunction<_SetJavaVmNative, _SetJavaVm>('av_jni_set_java_vm');
  // The helper learns the VM in its JNI_OnLoad, which can land a moment later.
  for (var i = 0; i < 100; i++) {
    final vm = getVm();
    if (vm != nullptr) {
      final rc = setVm(vm, nullptr);
      appDebugLog('🎞️ Registered Java VM with mpv FFmpeg (rc=$rc)');
      return;
    }
    sleep(const Duration(milliseconds: 20));
  }
  appDebugLog('🎞️ mpv FFmpeg: Java VM not available');
}

/// Copies an APK asset to the app's files directory (media_kit's helper) and
/// returns its path, or null if it isn't there.
String? _copyAsset(DynamicLibrary helper, String asset) {
  final copy = helper.lookupFunction<_CopyAssetNative, _CopyAsset>('MediaKitAndroidHelperCopyAssetToFilesDir');
  final libc = DynamicLibrary.open('libc.so');
  final malloc = libc.lookupFunction<_MallocNative, _Malloc>('malloc');
  final free = libc.lookupFunction<_FreeNative, _Free>('free');

  final nameBytes = utf8.encode(asset);
  final name = malloc(nameBytes.length + 1).cast<Uint8>();
  name.asTypedList(nameBytes.length + 1)
    ..setAll(0, nameBytes)
    ..[nameBytes.length] = 0;
  const resultSize = 4096;
  final result = malloc(resultSize).cast<Uint8>();
  result.asTypedList(resultSize).fillRange(0, resultSize, 0);
  try {
    copy(name, result);
    final bytes = result.asTypedList(resultSize);
    final end = bytes.indexOf(0);
    final path = utf8.decode(bytes.sublist(0, end < 0 ? resultSize : end)).trim();
    return path.isNotEmpty && File(path).existsSync() ? path : null;
  } finally {
    free(name.cast());
    free(result.cast());
  }
}
