import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:nivio/core/debug_log.dart';

/// What mpv opens for a trailer: a video URL, plus a separate audio URL when
/// the site serves them apart (YouTube above 360p), and the User-Agent the
/// URLs were issued for.
class TrailerStream {
  const TrailerStream({required this.video, this.audio, this.userAgent});

  final Uri video;
  final Uri? audio;
  final String? userAgent;
}

class TrailerUnavailableException implements Exception {
  const TrailerUnavailableException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Turns a trailer reference from TMDB/AniList (site + key) into streams mpv
/// can play directly, so trailers need no web view.
class TrailerStreamResolver {
  TrailerStreamResolver._();

  // YouTube's stream URLs stay valid for about six hours.
  static const Duration _cacheFor = Duration(hours: 1);
  static final Map<String, ({DateTime at, TrailerStream value})> _cache = {};
  static final Map<String, Future<TrailerStream>> _inFlight = {};
  static final http.Client _client = http.Client();

  /// [maxHeight] caps the resolution picked when the site offers several.
  static Future<TrailerStream> resolve(
    String site,
    String key, {
    int maxHeight = 1080,
  }) async {
    final cacheKey = '${site.toLowerCase()}:$key:$maxHeight';
    final cached = _cache[cacheKey];
    if (cached != null && DateTime.now().difference(cached.at) < _cacheFor) {
      return cached.value;
    }
    // A block body: returning the removed future would make it wait on itself.
    final stream = await (_inFlight[cacheKey] ??= _resolve(site, key, maxHeight)
        .whenComplete(() {
      _inFlight.remove(cacheKey);
    }));
    if (_cache.length > 64) _cache.remove(_cache.keys.first);
    _cache[cacheKey] = (at: DateTime.now(), value: stream);
    return stream;
  }

  static Future<TrailerStream> _resolve(String site, String key, int maxHeight) {
    switch (site.toLowerCase()) {
      case 'youtube':
        return _YouTube.resolve(_client, key, maxHeight);
      case 'vimeo':
        return _vimeo(key);
      case 'dailymotion':
        return _dailymotion(key);
      default:
        throw TrailerUnavailableException('Trailers from $site can\'t play in Nivio.');
    }
  }

  static Future<TrailerStream> _vimeo(String id) async {
    try {
      final reply = await _client.get(
        Uri.parse('https://player.vimeo.com/video/$id/config'),
        headers: {'Referer': 'https://player.vimeo.com/video/$id'},
      );
      final data = jsonDecode(reply.body) as Map<String, dynamic>;
      final files = (data['request'] as Map<String, dynamic>?)?['files'] as Map<String, dynamic>?;

      // A progressive MP4 when there is one, otherwise HLS.
      final progressive = (files?['progressive'] as List<dynamic>? ?? const [])
          .whereType<Map<String, dynamic>>()
          .toList()
        ..sort((a, b) => ((b['height'] as num?) ?? 0).compareTo((a['height'] as num?) ?? 0));
      final file = progressive.firstOrNull?['url'] as String?;
      if (file != null) return TrailerStream(video: Uri.parse(file));

      final hls = files?['hls'] as Map<String, dynamic>?;
      final cdns = hls?['cdns'] as Map<String, dynamic>?;
      final cdn = (cdns?[hls?['default_cdn']] ?? cdns?.values.firstOrNull) as Map<String, dynamic>?;
      final url = (cdn?['avc_url'] ?? cdn?['url']) as String?;
      if (url != null) return TrailerStream(video: Uri.parse(url));
    } catch (e) {
      appDebugLog('🎬 Vimeo trailer $id failed: $e');
    }
    throw const TrailerUnavailableException('Couldn\'t load this trailer from Vimeo.');
  }

  static Future<TrailerStream> _dailymotion(String id) async {
    try {
      final reply = await _client.get(
        Uri.parse('https://www.dailymotion.com/player/metadata/video/$id'),
      );
      final data = jsonDecode(reply.body) as Map<String, dynamic>;
      final qualities = data['qualities'] as Map<String, dynamic>?;
      final auto = (qualities?['auto'] as List<dynamic>?)?.firstOrNull as Map<String, dynamic>?;
      final url = auto?['url'] as String?;
      if (url != null) return TrailerStream(video: Uri.parse(url));
    } catch (e) {
      appDebugLog('🎬 Dailymotion trailer $id failed: $e');
    }
    throw const TrailerUnavailableException('Couldn\'t load this trailer from Dailymotion.');
  }
}

/// A YouTube InnerTube client profile.
class _YtClient {
  const _YtClient({
    required this.name,
    required this.id,
    required this.version,
    required this.userAgent,
    required this.context,
  });

  final String name;

  /// X-YouTube-Client-Name.
  final String id;
  final String version;
  final String userAgent;
  final Map<String, Object> context;
}

/// YouTube streams without a web view, the way Inzx plays podcast videos:
/// the visionOS client (Apple Vision Pro app) gets direct stream URLs that
/// need no signature deciphering, no `n` challenge and no PO token, and
/// play to the end. Clients that hand out URLs YouTube cuts off after about
/// a minute (ANDROID_VR today) are only a fallback and are checked first.
class _YouTube {
  static const _visionOsUa =
      'Mozilla/5.0 (Macintosh; Intel Mac OS X 15_7_3) AppleWebKit/605.1.15 '
      '(KHTML, like Gecko) Version/26.0 Safari/605.1.15';

  static const _clients = [
    _YtClient(
      name: 'VISIONOS',
      id: '101',
      version: '1.02',
      userAgent: _visionOsUa,
      context: {
        'clientName': 'VISIONOS',
        'clientVersion': '1.02',
        'osName': 'visionOS',
        'osVersion': '26.5.23O471',
        'deviceMake': 'Apple',
        'deviceModel': 'RealityDevice17,1',
      },
    ),
    _YtClient(
      name: 'VISIONOS_0_1',
      id: '101',
      version: '0.1',
      userAgent: 'Mozilla/5.0 (Macintosh; Intel Mac OS X 14_6) AppleWebKit/605.1.15 '
          '(KHTML, like Gecko) Version/17.5 Safari/605.1.15',
      context: {
        'clientName': 'VISIONOS',
        'clientVersion': '0.1',
        'osName': 'VISION_OS',
        'osVersion': '1.3',
        'deviceMake': 'Apple',
        'deviceModel': 'RealityDevice14,1',
        'platform': 'MOBILE',
      },
    ),
    _YtClient(
      name: 'ANDROID_VR',
      id: '28',
      version: '1.65.10',
      userAgent: 'com.google.android.apps.youtube.vr.oculus/1.65.10 '
          '(Linux; U; Android 12L; eureka-user Build/SQ3A.220605.009.A1) gzip',
      context: {
        'clientName': 'ANDROID_VR',
        'clientVersion': '1.65.10',
        'osName': 'Android',
        'osVersion': '12L',
        'deviceMake': 'Oculus',
        'deviceModel': 'Quest 3',
        'androidSdkVersion': 32,
      },
    ),
  ];

  static String? _visitorData;
  static DateTime? _visitorDataAt;

  static Future<TrailerStream> resolve(http.Client client, String videoId, int maxHeight) async {
    final visitorData = await _getVisitorData(client);
    String? unplayableReason;
    for (final yt in _clients) {
      try {
        final response = await _player(client, yt, videoId, visitorData);
        if (response == null) continue;
        final status = response['playabilityStatus'] as Map<String, dynamic>?;
        if (status?['status'] != 'OK') {
          unplayableReason ??= status?['reason'] as String?;
          continue;
        }
        final data = response['streamingData'] as Map<String, dynamic>?;
        if (data == null) continue;
        final stream = await _pick(client, yt, data, maxHeight);
        if (stream != null) {
          appDebugLog('🎬 YouTube trailer $videoId via ${yt.name}');
          return stream;
        }
      } catch (e) {
        appDebugLog('🎬 YouTube trailer $videoId via ${yt.name} failed: $e');
      }
    }
    throw TrailerUnavailableException(
      unplayableReason != null
          ? 'YouTube: $unplayableReason'
          : 'Couldn\'t load this trailer from YouTube.',
    );
  }

  /// Video and audio as separate adaptive streams (what mpv starts fastest),
  /// else the muxed 360p file, else HLS (slowest to open: YouTube's masters
  /// list every auto-dubbed audio track).
  static Future<TrailerStream?> _pick(
    http.Client client,
    _YtClient yt,
    Map<String, dynamic> data,
    int maxHeight,
  ) async {
    final adaptive = (data['adaptiveFormats'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .where((f) => f['url'] != null)
        .toList();

    int height(Map<String, dynamic> f) {
      final w = (f['width'] as num?)?.toInt() ?? 0;
      final h = (f['height'] as num?)?.toInt() ?? 0;
      // Vertical videos: the short side is what "1080p" refers to.
      return w > 0 && w < h ? w : h;
    }

    // H.264 decodes in hardware nearly everywhere; VP9 and AV1 after it.
    int codecRank(Map<String, dynamic> f) {
      final mime = f['mimeType']?.toString() ?? '';
      if (mime.contains('avc1')) return 0;
      if (mime.contains('vp9') || mime.contains('vp09')) return 1;
      return 2;
    }

    final videos = adaptive
        .where((f) =>
            (f['mimeType']?.toString() ?? '').startsWith('video/') &&
            height(f) > 0 &&
            height(f) <= maxHeight)
        .toList()
      ..sort((a, b) {
        final byHeight = height(b).compareTo(height(a));
        if (byHeight != 0) return byHeight;
        final byCodec = codecRank(a).compareTo(codecRank(b));
        if (byCodec != 0) return byCodec;
        return ((b['fps'] as num?) ?? 0).compareTo((a['fps'] as num?) ?? 0);
      });

    final audios = adaptive.where((f) {
      if (!(f['mimeType']?.toString() ?? '').startsWith('audio/')) return false;
      if (f['isDrc'] == true) return false;
      // The original language, not an auto-dubbed track.
      final track = f['audioTrack'] as Map<String, dynamic>?;
      return track == null || track['audioIsDefault'] == true;
    }).toList()
      ..sort((a, b) {
        // AAC first (plays everywhere), then by bitrate.
        final aAac = (a['mimeType']?.toString() ?? '').contains('mp4a') ? 0 : 1;
        final bAac = (b['mimeType']?.toString() ?? '').contains('mp4a') ? 0 : 1;
        if (aAac != bAac) return aAac.compareTo(bAac);
        return ((b['bitrate'] as num?) ?? 0).compareTo((a['bitrate'] as num?) ?? 0);
      });

    if (videos.isNotEmpty && audios.isNotEmpty) {
      final video = Uri.parse(videos.first['url'] as String);
      final audio = Uri.parse(audios.first['url'] as String);
      if (await _playsToTheEnd(client, yt, videos.first) &&
          await _playsToTheEnd(client, yt, audios.first)) {
        return TrailerStream(video: video, audio: audio, userAgent: yt.userAgent);
      }
      appDebugLog('🎬 ${yt.name} streams stop early; trying the next client');
      return null;
    }

    final muxed = (data['formats'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .where((f) => f['url'] != null)
        .toList();
    if (muxed.isNotEmpty && await _playsToTheEnd(client, yt, muxed.last)) {
      return TrailerStream(video: Uri.parse(muxed.last['url'] as String), userAgent: yt.userAgent);
    }

    final hls = data['hlsManifestUrl'] as String?;
    if (hls != null && hls.isNotEmpty) {
      return TrailerStream(video: Uri.parse(hls), userAgent: yt.userAgent);
    }
    return null;
  }

  /// Whether YouTube serves the end of [format]: without a PO token some
  /// clients' URLs are refused (403) past about the first minute.
  static Future<bool> _playsToTheEnd(
    http.Client client,
    _YtClient yt,
    Map<String, dynamic> format,
  ) async {
    final length = int.tryParse(format['contentLength']?.toString() ?? '');
    if (length == null || length <= 1) return true;
    try {
      final request = http.Request('GET', Uri.parse(format['url'] as String))
        ..headers['User-Agent'] = yt.userAgent
        ..headers['Range'] = 'bytes=${length - 1}-${length - 1}';
      final reply = await client.send(request).timeout(const Duration(seconds: 8));
      await reply.stream.drain<void>();
      return reply.statusCode == 206 || reply.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  static Future<Map<String, dynamic>?> _player(
    http.Client client,
    _YtClient yt,
    String videoId,
    String? visitorData,
  ) async {
    // As YouTube's own apps do (and Inzx): these clients talk to the
    // music.youtube.com endpoint.
    const origin = 'https://music.youtube.com';
    final reply = await client
        .post(
          Uri.parse('$origin/youtubei/v1/player?prettyPrint=false'),
          headers: {
            'Content-Type': 'application/json',
            'Accept-Language': 'en-US,en;q=0.9',
            'X-Goog-Api-Format-Version': '1',
            'Origin': origin,
            'X-Origin': origin,
            'Referer': '$origin/',
            'User-Agent': yt.userAgent,
            'X-YouTube-Client-Name': yt.id,
            'X-YouTube-Client-Version': yt.version,
            if (visitorData != null) 'X-Goog-Visitor-Id': visitorData,
          },
          body: jsonEncode({
            'context': {
              'client': {
                ...yt.context,
                'hl': 'en',
                'gl': 'US',
                if (visitorData != null) 'visitorData': visitorData,
              },
              'user': {'lockedSafetyMode': false},
            },
            'videoId': videoId,
            'racyCheckOk': true,
            'contentCheckOk': true,
          }),
        )
        .timeout(const Duration(seconds: 15));
    if (reply.statusCode != 200) {
      appDebugLog('🎬 YouTube ${yt.name} player answered ${reply.statusCode}');
      return null;
    }
    return jsonDecode(reply.body) as Map<String, dynamic>;
  }

  /// The visitor id from music.youtube.com, which YouTube binds requests to.
  /// Refreshed every few hours.
  static Future<String?> _getVisitorData(http.Client client) async {
    final at = _visitorDataAt;
    if (_visitorData != null && at != null && DateTime.now().difference(at) < const Duration(hours: 6)) {
      return _visitorData;
    }
    try {
      final reply = await client.get(
        Uri.parse('https://music.youtube.com/'),
        headers: {
          'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:140.0) Gecko/20100101 Firefox/140.0',
          'Accept-Language': 'en-US,en;q=0.9',
        },
      ).timeout(const Duration(seconds: 10));
      final value = RegExp(r'"VISITOR_DATA"\s*:\s*"([^"]+)"').firstMatch(reply.body)?.group(1);
      if (value != null && value.isNotEmpty) {
        _visitorData = value;
        _visitorDataAt = DateTime.now();
      }
    } catch (e) {
      appDebugLog('🎬 YouTube visitor id fetch failed: $e');
    }
    return _visitorData;
  }
}
