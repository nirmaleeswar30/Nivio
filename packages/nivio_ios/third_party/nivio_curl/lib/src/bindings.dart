import 'dart:ffi';

import 'package:ffi/ffi.dart';

/// The libcurl(-impersonate) entry points Nivio uses.
///
/// `curl_easy_setopt` and `curl_easy_getinfo` are C variadic functions. On
/// Apple arm64 variadic arguments are passed on the stack, so they must be
/// bound with [VarArgs], one lookup per argument type.
class CurlBindings {
  CurlBindings(DynamicLibrary lib)
      : globalInit = lib.lookupFunction<Int32 Function(Long), int Function(int)>('curl_global_init'),
        easyInit = lib.lookupFunction<Pointer<Void> Function(), Pointer<Void> Function()>('curl_easy_init'),
        easyCleanup = lib.lookupFunction<Void Function(Pointer<Void>), void Function(Pointer<Void>)>('curl_easy_cleanup'),
        easyPerform = lib.lookupFunction<Int32 Function(Pointer<Void>), int Function(Pointer<Void>)>('curl_easy_perform'),
        easyImpersonate = lib.lookupFunction<Int32 Function(Pointer<Void>, Pointer<Utf8>, Int32),
            int Function(Pointer<Void>, Pointer<Utf8>, int)>('curl_easy_impersonate'),
        easyStrerror = lib.lookupFunction<Pointer<Utf8> Function(Int32), Pointer<Utf8> Function(int)>('curl_easy_strerror'),
        slistAppend = lib.lookupFunction<Pointer<Void> Function(Pointer<Void>, Pointer<Utf8>),
            Pointer<Void> Function(Pointer<Void>, Pointer<Utf8>)>('curl_slist_append'),
        slistFreeAll = lib.lookupFunction<Void Function(Pointer<Void>), void Function(Pointer<Void>)>('curl_slist_free_all'),
        setoptLong = lib.lookupFunction<Int32 Function(Pointer<Void>, Int32, VarArgs<(Long,)>),
            int Function(Pointer<Void>, int, int)>('curl_easy_setopt'),
        setoptOffT = lib.lookupFunction<Int32 Function(Pointer<Void>, Int32, VarArgs<(Int64,)>),
            int Function(Pointer<Void>, int, int)>('curl_easy_setopt'),
        setoptPtr = lib.lookupFunction<Int32 Function(Pointer<Void>, Int32, VarArgs<(Pointer<Void>,)>),
            int Function(Pointer<Void>, int, Pointer<Void>)>('curl_easy_setopt'),
        getinfoLong = lib.lookupFunction<Int32 Function(Pointer<Void>, Int32, VarArgs<(Pointer<Long>,)>),
            int Function(Pointer<Void>, int, Pointer<Long>)>('curl_easy_getinfo');

  final int Function(int flags) globalInit;
  final Pointer<Void> Function() easyInit;
  final void Function(Pointer<Void>) easyCleanup;
  final int Function(Pointer<Void>) easyPerform;
  final int Function(Pointer<Void>, Pointer<Utf8> target, int defaultHeaders) easyImpersonate;
  final Pointer<Utf8> Function(int code) easyStrerror;
  final Pointer<Void> Function(Pointer<Void> list, Pointer<Utf8> line) slistAppend;
  final void Function(Pointer<Void> list) slistFreeAll;
  final int Function(Pointer<Void>, int option, int value) setoptLong;
  final int Function(Pointer<Void>, int option, int value) setoptOffT;
  final int Function(Pointer<Void>, int option, Pointer<Void> value) setoptPtr;
  final int Function(Pointer<Void>, int info, Pointer<Long> out) getinfoLong;

  static const String libraryPath = 'CurlImpersonate.framework/CurlImpersonate';

  static CurlBindings open() => CurlBindings(DynamicLibrary.open(libraryPath));
}

/// `struct curl_blob` (curl/easy.h).
final class CurlBlob extends Struct {
  external Pointer<Void> data;

  @Size()
  external int len;

  @UnsignedInt()
  external int flags;
}

/// Write / header callback: size_t (char *ptr, size_t size, size_t nmemb, void *userdata).
typedef CurlDataCallback = Size Function(Pointer<Uint8>, Size, Size, Pointer<Void>);

/// Progress callback: int (void *clientp, curl_off_t dltotal, curl_off_t dlnow,
/// curl_off_t ultotal, curl_off_t ulnow).
typedef CurlXferInfoCallback = Int32 Function(Pointer<Void>, Int64, Int64, Int64, Int64);

// Option ids from curl/curl.h (libcurl 8.23, curl-impersonate v2.3.2).
abstract final class CurlOpt {
  static const url = 10002;
  static const writeFunction = 20011;
  static const headerFunction = 20079;
  static const httpHeader = 10023;
  static const customRequest = 10036;
  static const noBody = 44;
  static const httpGet = 80;
  static const post = 47;
  static const postFieldSizeLarge = 30120;
  static const copyPostFields = 10165;
  static const followLocation = 52;
  static const maxRedirs = 68;
  static const acceptEncoding = 10102;
  static const connectTimeoutMs = 156;
  static const noSignal = 99;
  static const caInfoBlob = 40309;
  static const lowSpeedLimit = 19;
  static const lowSpeedTime = 20;
  static const xferInfoFunction = 20219;
  static const noProgress = 43;
}

abstract final class CurlInfo {
  static const responseCode = 0x200000 + 2;
}

const int curlGlobalDefault = 3;
const int curlBlobCopy = 1;
