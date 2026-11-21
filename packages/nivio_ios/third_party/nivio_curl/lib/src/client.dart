import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:isolate';

import 'package:ffi/ffi.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

import 'bindings.dart';

/// A package:http client that sends requests with libcurl-impersonate, so
/// the TLS handshake and HTTP/2 settings are a real Chrome's. This is the iOS
/// counterpart of Cronet on Android: Cloudflare-fronted sources check that
/// fingerprint, and Apple's NSURLSession presents Safari's.
///
/// Only the fingerprint is impersonated: headers are exactly the request's
/// own (plus [defaultUserAgent] when it sets none), like Cronet, which adds no
/// browser headers either.
///
/// Each request runs `curl_easy_perform` in its own short-lived isolate and
/// streams the body back, so the UI isolate never blocks. Bodies come back
/// decoded (gzip, deflate, br, zstd), with Content-Encoding/Content-Length
/// dropped from the headers accordingly, as NSURLSession and Cronet do.
class CurlImpersonateClient extends http.BaseClient {
  CurlImpersonateClient._(this._caBundle, {required this.target, required this.defaultUserAgent});

  /// curl-impersonate target. chrome131_android: Chrome on Android, the
  /// browser whose network stack Cronet is on the Android build.
  final String target;

  /// Sent when a request sets no User-Agent.
  final String defaultUserAgent;

  final TransferableTypedData _caBundle;

  /// Loads libcurl-impersonate and the CA bundle. Returns null when the
  /// framework isn't in the app (e.g. a build that skipped it), so callers can
  /// fall back to another client.
  static Future<CurlImpersonateClient?> create({
    String target = 'chrome131_android',
    String defaultUserAgent =
        'Mozilla/5.0 (Linux; Android 13; Pixel 7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Mobile Safari/537.36',
  }) async {
    try {
      final bindings = CurlBindings.open();
      // Process-wide and not thread-safe: once, before any worker runs.
      final rc = bindings.globalInit(curlGlobalDefault);
      if (rc != 0) return null;
      final pem = await rootBundle.load('packages/nivio_curl/assets/cacert.pem');
      final bytes = pem.buffer.asUint8List(pem.offsetInBytes, pem.lengthInBytes);
      return CurlImpersonateClient._(
        TransferableTypedData.fromList([bytes]),
        target: target,
        defaultUserAgent: defaultUserAgent,
      );
    } catch (_) {
      return null;
    }
  }

  // TransferableTypedData can only be materialized once; keep a copy to hand
  // a fresh one to each worker.
  late final Uint8List _caBytes = _caBundle.materialize().asUint8List();

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final body = await request.finalize().toBytes();

    final headerLines = <String>[];
    var hasUserAgent = false;
    request.headers.forEach((name, value) {
      if (name.toLowerCase() == 'user-agent') hasUserAgent = true;
      headerLines.add('$name: $value');
    });
    if (!hasUserAgent) headerLines.add('User-Agent: $defaultUserAgent');
    // curl otherwise adds "Expect: 100-continue" to larger uploads, which no
    // browser sends.
    headerLines.add('Expect:');

    final cancelFlag = calloc<Int32>();
    final port = ReceivePort();
    final responseCompleter = Completer<http.StreamedResponse>();
    late final StreamController<List<int>> bodyController;
    var freed = false;

    void finish() {
      port.close();
      if (!freed) {
        freed = true;
        calloc.free(cancelFlag);
      }
    }

    bodyController = StreamController<List<int>>(
      onCancel: () {
        // The worker sees this on its next callback and aborts the transfer.
        if (!freed) cancelFlag.value = 1;
      },
    );

    void fail(Object error) {
      if (!responseCompleter.isCompleted) {
        responseCompleter.completeError(http.ClientException('$error', request.url));
      } else if (!bodyController.isClosed) {
        bodyController.addError(http.ClientException('$error', request.url));
        bodyController.close();
      }
    }

    port.listen((message) {
      if (message is List && message.isNotEmpty) {
        switch (message[0]) {
          case 'h':
            final status = message[1] as int;
            final reason = message[2] as String?;
            final headers = _headerMap((message[3] as List).cast<String>());
            if (!responseCompleter.isCompleted) {
              responseCompleter.complete(http.StreamedResponse(
                bodyController.stream,
                status,
                headers: headers,
                reasonPhrase: reason,
                request: request,
                isRedirect: false,
                persistentConnection: false,
              ));
            }
          case 'd':
            if (!bodyController.isClosed) {
              bodyController.add((message[1] as TransferableTypedData).materialize().asUint8List());
            }
          case 'e':
            if (!bodyController.isClosed) bodyController.close();
          case 'x':
            fail(message[1] as String);
          default:
            // onError: [error, stackTrace] as strings.
            fail(message[0] ?? 'curl worker failed');
        }
        return;
      }
      if (message == null) {
        // Isolate exited; anything not delivered by now never will be.
        fail('curl worker exited before finishing');
        finish();
      }
    });

    final job = _CurlJob(
      sendPort: port.sendPort,
      url: request.url.toString(),
      method: request.method,
      headerLines: headerLines,
      body: body.isEmpty ? null : TransferableTypedData.fromList([body]),
      followRedirects: request.followRedirects,
      maxRedirects: request.maxRedirects,
      target: target,
      caBundle: TransferableTypedData.fromList([_caBytes]),
      cancelFlagAddress: cancelFlag.address,
    );

    try {
      await Isolate.spawn<_CurlJob>(
        _curlWorker,
        job,
        onExit: port.sendPort,
        onError: port.sendPort,
        debugName: 'curl ${request.method} ${request.url.host}',
      );
    } catch (e) {
      finish();
      throw http.ClientException('Could not start curl worker: $e', request.url);
    }
    return responseCompleter.future;
  }

  static Map<String, String> _headerMap(List<String> lines) {
    final map = <String, String>{};
    for (final line in lines) {
      final i = line.indexOf(':');
      if (i <= 0) continue;
      final name = line.substring(0, i).trim().toLowerCase();
      final value = line.substring(i + 1).trim();
      map[name] = map.containsKey(name) ? '${map[name]},$value' : value;
    }
    // libcurl decoded the body (CURLOPT_ACCEPT_ENCODING), so these describe
    // bytes the caller never sees.
    if (map.containsKey('content-encoding')) {
      map.remove('content-encoding');
      map.remove('content-length');
    }
    return map;
  }
}

class _CurlJob {
  _CurlJob({
    required this.sendPort,
    required this.url,
    required this.method,
    required this.headerLines,
    required this.body,
    required this.followRedirects,
    required this.maxRedirects,
    required this.target,
    required this.caBundle,
    required this.cancelFlagAddress,
  });

  final SendPort sendPort;
  final String url;
  final String method;
  final List<String> headerLines;
  final TransferableTypedData? body;
  final bool followRedirects;
  final int maxRedirects;
  final String target;
  final TransferableTypedData caBundle;
  final int cancelFlagAddress;
}

// ---------------------------------------------------------------------------
// Worker isolate. One request per isolate, so these statics are per request.
// ---------------------------------------------------------------------------

late SendPort _port;
late Pointer<Int32> _cancel;
final List<String> _headers = [];
int _status = 0;
String? _reason;
bool _headersSent = false;

void _sendHeaders() {
  if (_headersSent) return;
  _headersSent = true;
  _port.send(['h', _status, _reason, List<String>.of(_headers)]);
}

int _onHeader(Pointer<Uint8> data, int size, int nmemb, Pointer<Void> _) {
  final n = size * nmemb;
  final line = latin1.decode(data.asTypedList(n), allowInvalid: true).trimRight();
  if (line.startsWith('HTTP/')) {
    // A new response: a redirect hop, or the final one after "100 Continue".
    _headers.clear();
    final parts = line.split(' ');
    _status = parts.length > 1 ? int.tryParse(parts[1]) ?? 0 : 0;
    _reason = parts.length > 2 ? parts.sublist(2).join(' ') : null;
  } else if (line.isNotEmpty) {
    _headers.add(line);
  }
  return n;
}

int _onWrite(Pointer<Uint8> data, int size, int nmemb, Pointer<Void> _) {
  if (_cancel.value != 0) return 0; // aborts with CURLE_WRITE_ERROR
  final n = size * nmemb;
  _sendHeaders();
  if (n > 0) {
    _port.send(['d', TransferableTypedData.fromList([Uint8List.fromList(data.asTypedList(n))])]);
  }
  return n;
}

int _onProgress(Pointer<Void> _, int a, int b, int c, int d) => _cancel.value != 0 ? 1 : 0;

void _curlWorker(_CurlJob job) {
  _port = job.sendPort;
  _cancel = Pointer<Int32>.fromAddress(job.cancelFlagAddress);

  final curl = CurlBindings.open();
  final easy = curl.easyInit();
  if (easy == nullptr) {
    _port.send(['x', 'curl_easy_init failed']);
    return;
  }

  final allocs = <Pointer>[];
  Pointer<Utf8> str(String s) {
    final p = s.toNativeUtf8();
    allocs.add(p);
    return p;
  }

  final onHeader = NativeCallable<CurlDataCallback>.isolateLocal(_onHeader, exceptionalReturn: 0);
  final onWrite = NativeCallable<CurlDataCallback>.isolateLocal(_onWrite, exceptionalReturn: 0);
  final onProgress = NativeCallable<CurlXferInfoCallback>.isolateLocal(_onProgress, exceptionalReturn: 1);

  var headerList = nullptr.cast<Void>();
  try {
    // TLS + HTTP/2 fingerprint only; 0 = no default browser headers.
    final impersonated = curl.easyImpersonate(easy, str(job.target), 0);
    if (impersonated != 0) {
      _port.send(['x', 'curl_easy_impersonate(${job.target}): ${curl.easyStrerror(impersonated).toDartString()}']);
      return;
    }

    curl.setoptPtr(easy, CurlOpt.url, str(job.url).cast());
    curl.setoptLong(easy, CurlOpt.noSignal, 1);
    curl.setoptLong(easy, CurlOpt.connectTimeoutMs, 30000);
    // Give up on a transfer that stalls for a minute (no total timeout:
    // video segments and downloads can legitimately take long).
    curl.setoptLong(easy, CurlOpt.lowSpeedLimit, 1);
    curl.setoptLong(easy, CurlOpt.lowSpeedTime, 60);
    curl.setoptLong(easy, CurlOpt.followLocation, job.followRedirects ? 1 : 0);
    curl.setoptLong(easy, CurlOpt.maxRedirs, job.maxRedirects);
    // Chrome's own list and order; libcurl also decodes the body.
    curl.setoptPtr(easy, CurlOpt.acceptEncoding, str('gzip, deflate, br, zstd').cast());

    final ca = job.caBundle.materialize().asUint8List();
    final caData = calloc<Uint8>(ca.length);
    allocs.add(caData);
    caData.asTypedList(ca.length).setAll(0, ca);
    final blob = calloc<CurlBlob>();
    allocs.add(blob);
    blob.ref
      ..data = caData.cast()
      ..len = ca.length
      ..flags = curlBlobCopy;
    curl.setoptPtr(easy, CurlOpt.caInfoBlob, blob.cast());

    for (final line in job.headerLines) {
      headerList = curl.slistAppend(headerList, str(line));
    }
    curl.setoptPtr(easy, CurlOpt.httpHeader, headerList);

    final method = job.method.toUpperCase();
    final body = job.body?.materialize().asUint8List();
    if (method == 'HEAD') {
      curl.setoptLong(easy, CurlOpt.noBody, 1);
    } else if (body != null) {
      final bodyData = calloc<Uint8>(body.length);
      allocs.add(bodyData);
      bodyData.asTypedList(body.length).setAll(0, body);
      curl.setoptLong(easy, CurlOpt.post, 1);
      curl.setoptOffT(easy, CurlOpt.postFieldSizeLarge, body.length);
      curl.setoptPtr(easy, CurlOpt.copyPostFields, bodyData.cast());
      if (method != 'POST') curl.setoptPtr(easy, CurlOpt.customRequest, str(method).cast());
    } else if (method != 'GET') {
      curl.setoptPtr(easy, CurlOpt.customRequest, str(method).cast());
    }

    curl.setoptPtr(easy, CurlOpt.headerFunction, onHeader.nativeFunction.cast());
    curl.setoptPtr(easy, CurlOpt.writeFunction, onWrite.nativeFunction.cast());
    curl.setoptLong(easy, CurlOpt.noProgress, 0);
    curl.setoptPtr(easy, CurlOpt.xferInfoFunction, onProgress.nativeFunction.cast());

    final rc = curl.easyPerform(easy);
    if (_cancel.value != 0) {
      _port.send(['e']);
    } else if (rc != 0) {
      _port.send(['x', 'curl: ${curl.easyStrerror(rc).toDartString()} (${job.url})']);
    } else {
      if (_status == 0) {
        final code = calloc<Long>();
        curl.getinfoLong(easy, CurlInfo.responseCode, code);
        _status = code.value;
        calloc.free(code);
      }
      _sendHeaders();
      _port.send(['e']);
    }
  } catch (e) {
    _port.send(['x', 'curl worker: $e']);
  } finally {
    if (headerList != nullptr) curl.slistFreeAll(headerList);
    curl.easyCleanup(easy);
    onHeader.close();
    onWrite.close();
    onProgress.close();
    for (final p in allocs) {
      malloc.free(p);
    }
  }
}
