import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';

import '../../../shared/models/stream_result.dart';
import '../models/playback_request.dart';

class NetMirrorStreamProvider {
  NetMirrorStreamProvider({Dio? dio, NetMirrorCdnRelay? cdnRelay})
    : _dio =
          dio ??
          Dio(
            BaseOptions(
              connectTimeout: const Duration(seconds: 15),
              receiveTimeout: const Duration(seconds: 20),
              validateStatus: (status) => status != null && status < 600,
            ),
          ),
      _cdnRelay = cdnRelay ?? NetMirrorCdnRelay.instance;

  final Dio _dio;
  final NetMirrorCdnRelay _cdnRelay;

  Future<StreamResult?> resolve(PlaybackRequest request) =>
      _resolveNetMirror(request);

  Future<StreamResult?> _resolveNetMirror(PlaybackRequest request) async {
    final id = request.numericMediaId;
    if (id == null ||
        request.mediaType == PlaybackMediaType.anime ||
        request.mediaType == PlaybackMediaType.liveTv) {
      return null;
    }

    final isTv = request.mediaType == PlaybackMediaType.tv;
    final mediaType = isTv ? 'tv' : 'movie';
    final season = isTv ? (request.season ?? 1).clamp(1, 9999) : 0;
    final episode = isTv ? (request.episode ?? 1).clamp(1, 9999) : 0;

    try {
      final variantInfo = await _loadVariants(
        id: id,
        mediaType: mediaType,
        season: season,
        episode: episode,
      );
      final selectedVariant = _selectVariant(
        variantInfo.variants,
        request.preferredAudioTrack,
      );
      final selectedAudio = selectedVariant?.language ?? 'Default';
      final selectedSubjectId = selectedVariant?.subjectId;
      final selectedDetailPath = selectedVariant?.detailPath;
      final queryParameters = <String, String>{
        'type': mediaType,
        'se': season.toString(),
        'ep': episode.toString(),
      };
      final defaultSubjectId = variantInfo.defaultSubjectId;
      final defaultDetailPath = variantInfo.defaultDetailPath;
      if (defaultSubjectId != null) queryParameters['sid'] = defaultSubjectId;
      if (defaultDetailPath != null) queryParameters['dp'] = defaultDetailPath;
      if (selectedSubjectId != null && selectedSubjectId != defaultSubjectId) {
        queryParameters['dub'] = selectedSubjectId;
        if (selectedDetailPath != null) {
          queryParameters['dubdp'] = selectedDetailPath;
        }
      }
      final preferredQuality = _qualityParam(request.preferredQuality);
      if (preferredQuality != null) {
        queryParameters['quality'] = preferredQuality;
      }

      final response = await _dio.get<Object?>(
        '$_netMirrorApiBaseUrl/api/embed-tmdb/$id',
        queryParameters: queryParameters,
        options: Options(
          headers: const {
            'Accept': 'application/json',
            'Referer': '$_netMirrorApiBaseUrl/',
            'User-Agent': _desktopUserAgent,
          },
        ),
      );
      if (response.statusCode != 200) return null;

      final data = _asMap(response.data);
      if (data == null || data['ok'] != true || data['noSource'] == true) {
        return null;
      }

      final mode = data['mode']?.toString().toLowerCase();
      if (mode == 'hls') {
        final m3u8 = _absoluteUrl(data['m3u8']?.toString());
        if (m3u8 == null) return null;
        final fallbackMp4 = _absoluteUrl(data['fallbackMp4']?.toString());
        final sources = [
          StreamSource(url: m3u8, quality: 'Auto', isM3U8: true),
          if (fallbackMp4 != null)
            StreamSource(
              url: fallbackMp4,
              quality: _qualityFrom(data) ?? 'MP4',
            ),
        ];
        return StreamResult(
          url: m3u8,
          quality: 'Auto',
          provider: 'Nivio',
          subtitles: _captions(data['captions']),
          availableQualities: _dedupe(sources.map((source) => source.quality)),
          availableAudios: _dedupe(
            variantInfo.variants.map((variant) => variant.language),
          ),
          selectedAudio: selectedAudio,
          isM3U8: true,
          sources: sources,
        );
      }

      if (mode != 'proxy') return null;
      final mp4 = _absoluteUrl(data['mp4']?.toString());
      if (mp4 == null) return null;

      final signedUrl = _playbackUrl(mp4);
      final streams = await _streams(data['streams']);
      final compatibleStreams = streams
          .where((source) => _usesSameHeaderProfile(signedUrl, source.url))
          .toList(growable: false);
      final quality =
          _qualityFrom(data) ??
          compatibleStreams.firstOrNull?.quality ??
          'Auto';
      final headers = _headersForPlaybackUrl(signedUrl);

      return StreamResult(
        url: signedUrl,
        quality: quality,
        provider: 'Nivio',
        subtitles: _captions(data['captions']),
        availableQualities: _dedupe(
          compatibleStreams.isEmpty
              ? [quality]
              : compatibleStreams.map((source) => source.quality),
        ),
        availableAudios: _dedupe(
          variantInfo.variants.map((variant) => variant.language),
        ),
        selectedAudio: selectedAudio,
        isM3U8: false,
        headers: headers,
        sources: compatibleStreams.isEmpty
            ? [StreamSource(url: signedUrl, quality: quality)]
            : compatibleStreams,
      );
    } on DioException {
      return null;
    } on FormatException {
      return null;
    }
  }

  static Map<String, dynamic>? _asMap(Object? value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) return Map<String, dynamic>.from(value);
    return null;
  }

  Future<_NetMirrorVariantInfo> _loadVariants({
    required int id,
    required String mediaType,
    required int season,
    required int episode,
  }) async {
    try {
      final response = await _dio.get<Object?>(
        '$_netMirrorApiBaseUrl/api/variants-tmdb/$mediaType/$id',
        queryParameters: {'se': season.toString(), 'ep': episode.toString()},
        options: Options(
          headers: const {
            'Accept': 'application/json',
            'Referer': '$_netMirrorApiBaseUrl/',
            'User-Agent': _desktopUserAgent,
          },
        ),
      );
      if (response.statusCode != 200) return const _NetMirrorVariantInfo();
      final data = _asMap(response.data);
      return _NetMirrorVariantInfo(
        defaultSubjectId: data?['defaultSubjectId']?.toString(),
        defaultDetailPath: data?['defaultDetailPath']?.toString(),
        variants: _variantsFrom(data?['variants']),
      );
    } on DioException {
      return const _NetMirrorVariantInfo();
    } on FormatException {
      return const _NetMirrorVariantInfo();
    }
  }

  static List<_NetMirrorVariant> _variantsFrom(Object? rawVariants) {
    if (rawVariants is! List) return const [];
    final variants = <_NetMirrorVariant>[];
    for (final rawVariant in rawVariants) {
      final variant = _asMap(rawVariant);
      final language = variant?['language']?.toString().trim();
      final subjectId =
          variant?['dubSubjectId']?.toString() ??
          variant?['subjectId']?.toString();
      if (language == null || language.isEmpty || subjectId == null) continue;
      variants.add(
        _NetMirrorVariant(
          language: language,
          subjectId: subjectId,
          detailPath: variant?['detailPath']?.toString(),
        ),
      );
    }
    return variants;
  }

  static _NetMirrorVariant? _selectVariant(
    List<_NetMirrorVariant> variants,
    String? preferredAudio,
  ) {
    if (variants.isEmpty) return null;
    final preferred = preferredAudio?.trim().toLowerCase();
    if (preferred != null && preferred.isNotEmpty) {
      for (final variant in variants) {
        final language = variant.language.toLowerCase();
        if (language == preferred ||
            language.contains(preferred) ||
            preferred.contains(language)) {
          return variant;
        }
      }
    }
    return variants.firstWhere(
      (variant) => variant.language.toLowerCase() == 'default',
      orElse: () => variants.first,
    );
  }

  Future<List<StreamSource>> _streams(Object? rawStreams) async {
    if (rawStreams is! List) return const [];
    final sources = <StreamSource>[];
    for (final rawStream in rawStreams) {
      final stream = _asMap(rawStream);
      final url = _absoluteUrl(stream?['url']?.toString());
      if (url == null) continue;
      final playbackUrl = _playbackUrl(url);
      sources.add(
        StreamSource(
          url: playbackUrl,
          quality: _resolutionLabel(stream?['resolution']) ?? 'Auto',
        ),
      );
    }
    return sources;
  }

  static List<SubtitleTrack> _captions(Object? rawCaptions) {
    if (rawCaptions is! List) return const [];
    final captions = <SubtitleTrack>[];
    for (final rawCaption in rawCaptions) {
      final caption = _asMap(rawCaption);
      final url = _absoluteUrl(caption?['url']?.toString());
      if (url == null) continue;
      captions.add(
        SubtitleTrack(
          url: url,
          lang:
              caption?['name']?.toString() ??
              caption?['lang']?.toString() ??
              'Unknown',
        ),
      );
    }
    return captions;
  }

  String _playbackUrl(String mediaUrl) => mediaUrl;

  Map<String, String> _headersForPlaybackUrl(String mediaUrl) {
    if (_cdnRelay.isRelayUrl(mediaUrl)) return const {};
    if (_isAndroidCdnUrl(mediaUrl)) return _netMirrorAndroidCdnHeaders;
    return _netMirrorMediaHeaders;
  }

  static bool _usesSameHeaderProfile(String primaryUrl, String sourceUrl) {
    if (_isAndroidCdnUrl(primaryUrl) || _isAndroidCdnUrl(sourceUrl)) {
      return _isAndroidCdnUrl(primaryUrl) && _isAndroidCdnUrl(sourceUrl);
    }
    if (_isNetMirrorCacheUrl(primaryUrl) || _isNetMirrorCacheUrl(sourceUrl)) {
      return _isNetMirrorCacheUrl(primaryUrl) &&
          _isNetMirrorCacheUrl(sourceUrl);
    }
    return true;
  }

  static String? _absoluteUrl(String? value) {
    if (value == null || value.trim().isEmpty) return null;
    final trimmed = value.trim();
    if (trimmed.startsWith('//')) return 'https:$trimmed';
    final uri = Uri.tryParse(trimmed);
    if (uri != null && uri.hasScheme) return trimmed;
    if (trimmed.startsWith('/')) return '$_netMirrorApiBaseUrl$trimmed';
    return null;
  }

  static bool _isNetMirrorCacheUrl(String url) {
    final host = Uri.tryParse(url)?.host.toLowerCase() ?? '';
    return host.contains('net27-r2-cache');
  }

  static bool _isAndroidCdnUrl(String url) {
    final host = Uri.tryParse(url)?.host.toLowerCase() ?? '';
    if (_isNetMirrorCacheUrl(url)) return false;
    return host == 'hakunaymatata.com' ||
        host.endsWith('.hakunaymatata.com') ||
        host == 'watch21.com' ||
        host.endsWith('.watch21.com') ||
        host == 'watch21.shop' ||
        host.endsWith('.watch21.shop') ||
        host == 'watch22.com' ||
        host.endsWith('.watch22.com') ||
        host == 'watch22.shop' ||
        host.endsWith('.watch22.shop');
  }

  static String? _qualityFrom(Map<String, dynamic> data) =>
      _resolutionLabel(data['resolution']);

  static String? _resolutionLabel(Object? value) {
    final text = value?.toString().trim();
    if (text == null || text.isEmpty || text == '0') return null;
    return text.endsWith('p') ? text : '${text}p';
  }

  static String? _qualityParam(String? quality) {
    final match = RegExp(r'(\d{3,4})').firstMatch(quality ?? '');
    return match?.group(1);
  }

  static List<String> _dedupe(Iterable<String> values) {
    final seen = <String>{};
    final result = <String>[];
    for (final value in values) {
      final trimmed = value.trim();
      final key = trimmed.toLowerCase();
      if (trimmed.isEmpty || !seen.add(key)) continue;
      result.add(trimmed);
    }
    return result.isEmpty ? const ['Auto'] : result;
  }
}

const String _desktopUserAgent =
    'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 '
    '(KHTML, like Gecko) Chrome/137.0.0.0 Safari/537.36';
const String _netMirrorApiBaseUrl = 'https://net27.cc';
const Map<String, String> _netMirrorMediaHeaders = {
  'Referer': _netMirrorApiBaseUrl,
  'User-Agent': _desktopUserAgent,
};
const Map<String, String> _netMirrorAndroidCdnHeaders = {
  'Accept': '*/*',
  'Origin': _netMirrorApiBaseUrl,
  'Referer': '$_netMirrorApiBaseUrl/',
  'User-Agent':
      'Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/137.0.0.0 Mobile Safari/537.36',
};
const Map<String, String> _netMirrorRelayHeaders = {
  ..._netMirrorAndroidCdnHeaders,
  'Accept-Encoding': 'identity',
  'Connection': 'keep-alive',
};

class NetMirrorCdnRelay {
  NetMirrorCdnRelay._();

  static final NetMirrorCdnRelay instance = NetMirrorCdnRelay._();

  final HttpClient _client = HttpClient()
    ..connectionTimeout = const Duration(seconds: 12);
  final Map<String, Uri> _targets = {};
  final Map<String, String> _tokensByUrl = {};
  HttpServer? _server;
  int _nextToken = 0;

  Future<String> proxy(String mediaUrl) async {
    final target = Uri.parse(mediaUrl);
    final host = target.host.toLowerCase();
    if (!NetMirrorStreamProvider._isAndroidCdnUrl(mediaUrl)) {
      throw ArgumentError.value(host, 'mediaUrl', 'Unsupported NetMirror host');
    }
    final server = await _ensureServer();
    final cacheKey = target.toString();
    final token = _tokensByUrl[cacheKey] ?? (++_nextToken).toRadixString(36);
    _tokensByUrl[cacheKey] = token;
    _targets[token] = target;
    return Uri(
      scheme: 'http',
      host: InternetAddress.loopbackIPv4.address,
      port: server.port,
      pathSegments: ['netmirror-cdn', token],
    ).toString();
  }

  bool isRelayUrl(String value) {
    final uri = Uri.tryParse(value);
    return uri != null &&
        uri.scheme == 'http' &&
        uri.host == InternetAddress.loopbackIPv4.address &&
        uri.pathSegments.length == 2 &&
        uri.pathSegments.first == 'netmirror-cdn';
  }

  Future<HttpServer> _ensureServer() async {
    final existing = _server;
    if (existing != null) return existing;
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _server = server;
    unawaited(server.listen(_handleRequest).asFuture<void>());
    return server;
  }

  Future<void> _handleRequest(HttpRequest request) async {
    if (request.uri.pathSegments.length != 2 ||
        request.uri.pathSegments.first != 'netmirror-cdn') {
      request.response.statusCode = HttpStatus.notFound;
      await request.response.close();
      return;
    }

    final target = _targets[request.uri.pathSegments[1]];
    if (target == null) {
      request.response.statusCode = HttpStatus.notFound;
      await request.response.close();
      return;
    }

    if (request.method != 'GET' && request.method != 'HEAD') {
      request.response.statusCode = HttpStatus.methodNotAllowed;
      await request.response.close();
      return;
    }

    try {
      final upstream = await _client.openUrl(request.method, target);
      upstream.followRedirects = true;
      upstream.maxRedirects = 5;
      for (final entry in _netMirrorRelayHeaders.entries) {
        upstream.headers.set(entry.key, entry.value);
      }
      _copyRequestHeader(request, upstream, HttpHeaders.rangeHeader);
      _copyRequestHeader(request, upstream, HttpHeaders.ifRangeHeader);
      _copyRequestHeader(request, upstream, HttpHeaders.ifNoneMatchHeader);
      _copyRequestHeader(request, upstream, HttpHeaders.ifModifiedSinceHeader);

      final upstreamResponse = await upstream.close();
      request.response.statusCode = upstreamResponse.statusCode;
      _copyResponseHeaders(upstreamResponse, request.response);
      if (request.method != 'HEAD') {
        await request.response.addStream(upstreamResponse);
      }
    } catch (_) {
      request.response.statusCode = HttpStatus.badGateway;
    } finally {
      await request.response.close();
    }
  }

  void _copyRequestHeader(
    HttpRequest request,
    HttpClientRequest upstream,
    String name,
  ) {
    final value = request.headers.value(name);
    if (value != null && value.trim().isNotEmpty) {
      upstream.headers.set(name, value);
    }
  }

  void _copyResponseHeaders(
    HttpClientResponse upstream,
    HttpResponse response,
  ) {
    const copied = {
      HttpHeaders.acceptRangesHeader,
      HttpHeaders.cacheControlHeader,
      HttpHeaders.contentEncodingHeader,
      HttpHeaders.contentLengthHeader,
      HttpHeaders.contentRangeHeader,
      HttpHeaders.contentTypeHeader,
      HttpHeaders.etagHeader,
      HttpHeaders.expiresHeader,
      HttpHeaders.lastModifiedHeader,
    };
    for (final name in copied) {
      final values = upstream.headers[name];
      if (values == null || values.isEmpty) continue;
      response.headers.set(name, values);
    }
  }
}

class _NetMirrorVariantInfo {
  const _NetMirrorVariantInfo({
    this.defaultSubjectId,
    this.defaultDetailPath,
    this.variants = const [],
  });

  final String? defaultSubjectId;
  final String? defaultDetailPath;
  final List<_NetMirrorVariant> variants;
}

class _NetMirrorVariant {
  const _NetMirrorVariant({
    required this.language,
    required this.subjectId,
    required this.detailPath,
  });

  final String language;
  final String subjectId;
  final String? detailPath;
}
