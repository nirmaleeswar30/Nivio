import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:cronet_http/cronet_http.dart';
import 'package:http/http.dart' as http;
import 'package:nivio/core/debug_log.dart';

class HlsProxyService {
  static final HlsProxyService instance = HlsProxyService._internal();
  factory HlsProxyService() => instance;
  HlsProxyService._internal();

  HttpServer? _server;
  http.Client? _cronetClient;

  Future<void> start() async {
    if (_server != null) return;
    
    _cronetClient = CronetClient.defaultCronetEngine();
    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    appDebugLog('🚀 HlsProxyService started on port ${_server!.port}');

    _server!.listen((HttpRequest request) {
      _handleRequest(request);
    });
  }

  Future<void> stop() async {
    await _server?.close(force: true);
    _server = null;
    _cronetClient?.close();
    _cronetClient = null;
    appDebugLog('🛑 HlsProxyService stopped');
  }

  int get port => _server?.port ?? 0;

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

      final isM3u8 = response.headers['content-type']?.toLowerCase().contains('mpegurl') == true || targetUrl.contains('.m3u8');

      if (response.statusCode == 403) {
        final bodyBytes = await response.stream.toBytes();
        final bodyString = utf8.decode(bodyBytes, allowMalformed: true);
        appDebugLog('❌ HlsProxyService 403 Response from $targetUrl: \\n$bodyString');
        request.response.statusCode = 403;
        request.response.add(bodyBytes);
        await request.response.close();
        return;
      }

      if (isM3u8) {
        final bodyBytes = await response.stream.toBytes();
        final bodyString = utf8.decode(bodyBytes);
        final lines = bodyString.split('\n');
        final modifiedLines = <String>[];

        for (var line in lines) {
          final trimmed = line.trim();
          if (trimmed.isEmpty) continue;
          
          String trimBase64(String str) => str.replaceAll('=', '');
          
          if (trimmed.startsWith('#')) {
            if (trimmed.startsWith('#EXT-X-KEY:')) {
              // Extract URI="..."
              final uriMatch = RegExp(r'URI="([^"]+)"').firstMatch(trimmed);
              if (uriMatch != null) {
                final originalUri = uriMatch.group(1)!;
                String absoluteUri = originalUri;
                if (!originalUri.startsWith('http')) {
                  absoluteUri = Uri.parse(targetUrl).resolve(originalUri).toString();
                }
                final newBase64Url = trimBase64(base64Url.encode(utf8.encode(absoluteUri)));
                final newUrl = 'http://127.0.0.1:${_server!.port}/proxy?url=$newBase64Url&cookie=${base64Cookie ?? ''}&ua=${base64Ua ?? ''}&ref=${base64Ref ?? ''}&origin=${base64OriginParam ?? ''}&ext=.key';
                final replacedLine = trimmed.replaceAll('URI="$originalUri"', 'URI="$newUrl"');
                modifiedLines.add(replacedLine);
                continue;
              }
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
        request.response.add(modifiedBytes);
        await request.response.close();
      } else {
        await response.stream.pipe(request.response);
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
