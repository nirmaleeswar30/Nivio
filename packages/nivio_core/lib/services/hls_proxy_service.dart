import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:nivio/core/debug_log.dart';
import 'package:nivio/services/loopback_server.dart';
import 'package:nivio/services/network_client_factory.dart';

class HlsProxyService {
  static final HlsProxyService instance = HlsProxyService._internal();
  factory HlsProxyService() => instance;
  HlsProxyService._internal();

  HttpServer? _server;
  http.Client? _cronetClient;
  bool _resumeHooked = false;
  final _redirects = <String, Uri Function()>{};
  final _random = Random.secure();

  /// Issues a fresh upstream URL on each player request, including seeks.
  String? registerMediaRedirect(Uri Function() destination) {
    final server = _server;
    if (server == null) return null;
    final id = base64Url.encode(List.generate(18, (_) => _random.nextInt(256)));
    if (_redirects.length >= 256) _redirects.remove(_redirects.keys.first);
    _redirects[id] = destination;
    return 'http://127.0.0.1:${server.port}/media-redirect/$id';
  }

  Future<void> start() async {
    if (_server != null) return;
    
    _cronetClient ??= NetworkClientFactory.createClient();
    await _bind(0);
    appDebugLog('🚀 HlsProxyService started on port ${_server!.port}');

    if (!_resumeHooked) {
      _resumeHooked = true;
      onIosResume(_reviveIfDead);
    }
  }

  Future<void> _bind(int preferredPort) async {
    final server = await bindLoopback(preferredPort: preferredPort);
    _server = server;
    server.listen(
      (HttpRequest request) {
        _handleRequest(request);
      },
      onError: (Object e) => appDebugLog('⚠️ HlsProxyService listen error: $e'),
      onDone: () {
        if (identical(_server, server)) _server = null;
      },
    );
  }

  /// iOS: the listening socket may have been reclaimed while suspended.
  Future<void> _reviveIfDead() async {
    final server = _server;
    if (server == null) {
      if (_cronetClient != null) await start();
      return;
    }
    final port = server.port;
    if (await loopbackPortAccepts(port)) return;
    appDebugLog('♻️ HlsProxyService socket was reclaimed; rebinding on $port');
    _server = null;
    try {
      await server.close(force: true);
    } catch (_) {}
    try {
      await _bind(port);
    } catch (e) {
      appDebugLog('⚠️ HlsProxyService rebind failed: $e');
    }
  }

  Future<void> stop() async {
    await _server?.close(force: true);
    _server = null;
    _cronetClient?.close();
    _cronetClient = null;
    _redirects.clear();
    appDebugLog('🛑 HlsProxyService stopped');
  }

  int get port => _server?.port ?? 0;

  static bool _startsWithPlaylistTag(List<int> bytes) {
    var i = 0;
    // UTF-8 byte order mark and leading whitespace.
    if (bytes.length >= 3 && bytes[0] == 0xEF && bytes[1] == 0xBB && bytes[2] == 0xBF) i = 3;
    while (i < bytes.length && (bytes[i] == 0x20 || bytes[i] == 0x0A || bytes[i] == 0x0D || bytes[i] == 0x09)) {
      i++;
    }
    const tag = '#EXTM3U';
    if (bytes.length - i < tag.length) return false;
    for (var j = 0; j < tag.length; j++) {
      if (bytes[i + j] != tag.codeUnitAt(j)) return false;
    }
    return true;
  }

  static Future<List<int>> _collect(Stream<List<int>> stream) async {
    final builder = BytesBuilder(copy: false);
    await for (final chunk in stream) {
      builder.add(chunk);
    }
    return builder.takeBytes();
  }

  String getProxyUrl(String targetUrl, String userAgent, Map<String, String> cookies, {String? referer, String? origin, String? extension}) {
    if (_server == null) throw Exception('HlsProxyService is not running');
    // Remove padding to keep URL clean, we add it back during decode
    String trimBase64(String str) => str.replaceAll('=', '');
    
    final base64UrlParam = trimBase64(base64Url.encode(utf8.encode(targetUrl)));
    final cookieString = cookies.entries.map((e) => '${e.key}=${e.value}').join('; ');
    final base64Cookie = trimBase64(base64Url.encode(utf8.encode(cookieString)));
    final base64Ua = trimBase64(base64Url.encode(utf8.encode(userAgent)));
    final base64Ref = referer != null ? trimBase64(base64Url.encode(utf8.encode(referer))) : '';
    final base64Origin = origin != null ? trimBase64(base64Url.encode(utf8.encode(origin))) : '';
    
    final extParam = extension != null ? '&ext=$extension' : '&ext=.m3u8';
    return 'http://127.0.0.1:${_server!.port}/proxy?url=$base64UrlParam&cookie=$base64Cookie&ua=$base64Ua&ref=$base64Ref&origin=$base64Origin$extParam';
  }

  Future<void> _handleRequest(HttpRequest request) async {
    if (request.uri.path.startsWith('/media-redirect/')) {
      final destination = _redirects[request.uri.pathSegments.last];
      final response = request.response;
      if (destination == null) {
        response.statusCode = HttpStatus.notFound;
        await response.close();
      } else if (request.method != 'GET' && request.method != 'HEAD') {
        response.statusCode = HttpStatus.methodNotAllowed;
        await response.close();
      } else {
        response.headers.set(HttpHeaders.cacheControlHeader, 'no-store');
        await response.redirect(
          destination(),
          status: HttpStatus.temporaryRedirect,
        );
      }
      return;
    }
    appDebugLog('📥 Proxy received request: ${request.uri.toString()}');

    if (!request.uri.path.startsWith('/proxy')) {
      request.response
        ..statusCode = HttpStatus.notFound
        ..close();
      return;
    }

    try {
      final base64UrlParam = request.uri.queryParameters['url'];
      final base64Cookie = request.uri.queryParameters['cookie'];
      final base64Ua = request.uri.queryParameters['ua'];
      final base64Ref = request.uri.queryParameters['ref'];
      final base64OriginParam = request.uri.queryParameters['origin'];

      if (base64UrlParam == null) {
        request.response
          ..statusCode = HttpStatus.badRequest
          ..close();
        return;
      }

      // Add padding if missing since Dart's decoder is strict
      String padBase64(String str) {
        return str.padRight(str.length + (4 - str.length % 4) % 4, '=');
      }

      final targetUrl = utf8.decode(base64Url.decode(padBase64(base64UrlParam)));
      final userAgent = base64Ua != null && base64Ua.isNotEmpty ? utf8.decode(base64Url.decode(padBase64(base64Ua))) : '';
      final referer = base64Ref != null && base64Ref.isNotEmpty ? utf8.decode(base64Url.decode(padBase64(base64Ref))) : 'https://kwik.cx/';
      final origin = base64OriginParam != null && base64OriginParam.isNotEmpty ? utf8.decode(base64Url.decode(padBase64(base64OriginParam))) : 'https://kwik.cx';

      final headers = {
        'Referer': referer,
        'User-Agent': userAgent,
        'Accept': '*/*',
        'Origin': origin,
        'Sec-Fetch-Site': 'cross-site',
        'Sec-Fetch-Mode': 'cors',
        'Sec-Fetch-Dest': 'empty',
      };

      final cronetRequest = http.Request(request.method, Uri.parse(targetUrl));
      cronetRequest.headers.addAll(headers);

      final response = await _cronetClient!.send(cronetRequest);
      appDebugLog('📤 Proxy Cronet returned status: ${response.statusCode} for $targetUrl');

      request.response.statusCode = response.statusCode;
      response.headers.forEach((key, value) {
        final lowerKey = key.toLowerCase();
        // Do not forward chunked encoding, we will handle it
        if (lowerKey == 'transfer-encoding') return;
        // Do not forward content-encoding since dart/cronet automatically decompressed it
        if (lowerKey == 'content-encoding') return;
        // Do not forward content-length since decompressed length differs
        if (lowerKey == 'content-length') return;
        
        request.response.headers.set(key, value);
      });

      var isM3u8 = response.headers['content-type']?.toLowerCase().contains('mpegurl') == true || targetUrl.contains('.m3u8');
      // Some hosts serve playlists from extension-less URLs with a generic
      // MIME type (and a parent playlist then gets them proxied as segments).
      // Look at the body: one that starts with #EXTM3U is a playlist. Without
      // this the links inside weren't rewritten and FFmpeg refused the file
      // ("Not detecting m3u8/hls with non standard extension"), so it
      // "played" as a broken one-second image.
      Stream<List<int>> body = response.stream;
      if (!isM3u8 && response.statusCode >= 200 && response.statusCode < 300) {
        final iterator = StreamIterator(response.stream);
        final hasFirst = await iterator.moveNext();
        final first = hasFirst ? iterator.current : const <int>[];
        if (_startsWithPlaylistTag(first)) isM3u8 = true;
        body = () async* {
          if (hasFirst) yield first;
          while (await iterator.moveNext()) {
            yield iterator.current;
          }
        }();
      }

      if (response.statusCode == 403) {
        final bodyBytes = await _collect(body);
        final bodyString = utf8.decode(bodyBytes, allowMalformed: true);
        appDebugLog('❌ HlsProxyService 403 Response from $targetUrl: \\n$bodyString');
        request.response.statusCode = 403;
        request.response.add(bodyBytes);
        await request.response.close();
        return;
      }

      if (isM3u8) {
        final bodyBytes = await _collect(body);
        final bodyString = utf8.decode(bodyBytes);
        final lines = bodyString.split('\n');
        final modifiedLines = <String>[];

        for (var line in lines) {
          final trimmed = line.trim();
          if (trimmed.isEmpty) continue;
          
          String trimBase64(String str) => str.replaceAll('=', '');
          
          if (trimmed.startsWith('#')) {
            // Every URI="..." attribute must go through the proxy too: keys,
            // init segments (EXT-X-MAP) and, in master playlists, the audio
            // and subtitle renditions (EXT-X-MEDIA). Left relative, mpv
            // resolved them against the proxy itself (/audio/ja/index.m3u8 →
            // 404), lost the audio track and fell back to opening every video
            // variant, which took long enough for Autoplay to give up.
            final uriMatch = RegExp(r'URI="([^"]+)"').firstMatch(trimmed);
            if (uriMatch != null) {
              final originalUri = uriMatch.group(1)!;
              String absoluteUri = originalUri;
              if (!originalUri.startsWith('http')) {
                absoluteUri = Uri.parse(targetUrl).resolve(originalUri).toString();
              }
              final ext = trimmed.startsWith('#EXT-X-KEY:') ||
                      trimmed.startsWith('#EXT-X-SESSION-KEY:')
                  ? '.key'
                  : trimmed.startsWith('#EXT-X-MEDIA:') ||
                          trimmed.startsWith('#EXT-X-I-FRAME-STREAM-INF:') ||
                          absoluteUri.contains('.m3u8')
                      ? '.m3u8'
                      : '.ts';
              final newBase64Url = trimBase64(base64Url.encode(utf8.encode(absoluteUri)));
              final newUrl = 'http://127.0.0.1:${_server!.port}/proxy?url=$newBase64Url&cookie=${base64Cookie ?? ''}&ua=${base64Ua ?? ''}&ref=${base64Ref ?? ''}&origin=${base64OriginParam ?? ''}&ext=$ext';
              modifiedLines.add(trimmed.replaceFirst('URI="$originalUri"', 'URI="$newUrl"'));
              continue;
            }
            modifiedLines.add(trimmed);
          } else {
            // It's a URL
            String absoluteUrl = trimmed;
            if (!trimmed.startsWith('http')) {
              final targetUri = Uri.parse(targetUrl);
              absoluteUrl = targetUri.resolve(trimmed).toString();
            }
            
            final newBase64Url = trimBase64(base64Url.encode(utf8.encode(absoluteUrl)));
            final isSegmentM3u8 = absoluteUrl.contains('.m3u8');
            final newUrl = 'http://127.0.0.1:${_server!.port}/proxy?url=$newBase64Url&cookie=${base64Cookie ?? ''}&ua=${base64Ua ?? ''}&ref=${base64Ref ?? ''}&origin=${base64OriginParam ?? ''}&ext=${isSegmentM3u8 ? '.m3u8' : '.ts'}';
            modifiedLines.add(newUrl);
          }
        }
        
        final modifiedBody = modifiedLines.join('\n');
        final modifiedBytes = utf8.encode(modifiedBody);
        
        request.response.headers.set('content-length', modifiedBytes.length.toString());
        // FFmpeg only accepts an HLS playlist with an .m3u8 URL or this type.
        request.response.headers.set('content-type', 'application/vnd.apple.mpegurl');
        request.response.add(modifiedBytes);
        await request.response.close();
      } else {
        bool isFirstChunk = true;
        bool isDisguisedPng = false;
        List<int> buffer = [];
        bool headerStripped = false;
        
        await body.listen((chunk) {
          if (headerStripped) {
            request.response.add(chunk);
            return;
          }
          
          if (isFirstChunk) {
            isFirstChunk = false;
            // Check for PNG signature
            if (chunk.length >= 4 && chunk[0] == 0x89 && chunk[1] == 0x50 && chunk[2] == 0x4E && chunk[3] == 0x47) {
              isDisguisedPng = true;
            } else {
              headerStripped = true;
              request.response.add(chunk);
              return;
            }
          }
          
          if (isDisguisedPng && !headerStripped) {
            buffer.addAll(chunk);
            // Search for TS sync byte (0x47) that repeats after 188 bytes
            int tsStart = -1;
            for (int i = 0; i < buffer.length - 188; i++) {
              if (buffer[i] == 0x47 && buffer[i + 188] == 0x47) {
                tsStart = i;
                break;
              }
            }
            if (tsStart != -1) {
              headerStripped = true;
              appDebugLog('🛠️ HlsProxyService: Stripping fake PNG header of size $tsStart bytes.');
              request.response.add(buffer.sublist(tsStart));
              buffer = [];
            } else if (buffer.length > 5000) {
              // Safety fallback
              headerStripped = true;
              appDebugLog('⚠️ HlsProxyService: Fake PNG header detected but no TS sync byte found within 5KB! Piping as-is.');
              request.response.add(buffer);
              buffer = [];
            }
          }
        }).asFuture();
        
        await request.response.close();
      }
    } catch (e) {
      appDebugLog('❌ HlsProxyService Error: $e');
      try {
        request.response
          ..statusCode = HttpStatus.internalServerError
          ..close();
      } catch (_) {}
    }
  }
}
