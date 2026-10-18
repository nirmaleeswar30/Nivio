import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nivio/core/debug_log.dart';
import 'package:nivio/models/stream_result.dart';
import 'package:nivio/services/skip_times_models.dart';
import 'package:nivio/services/hls_proxy_service.dart';

final animetsuScraperProvider = Provider((ref) => AnimetsuScraperService(providerName: 'Animetsu'));

class AnimetsuScraperService {
  final String providerName;

  AnimetsuScraperService({this.providerName = 'Animetsu'});

  final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 20),
      validateStatus: (status) => status != null && status < 600,
      headers: {
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/137.0.0.0 Safari/537.36',
      },
    ),
  );

  static const String _userAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/137.0.0.0 Safari/537.36';

  final Map<String, Future<int?>> _anilistCache = {};

  Future<int?> _resolveAnilistId(String tmdbId, String title) async {
    final parsed = int.tryParse(tmdbId);
    if (parsed != null && parsed > 0) return parsed;

    if (title.isEmpty) return null;
    try {
      const query = '''
        query (\$search: String) {
          Page(page: 1, perPage: 5) {
            media(search: \$search, type: ANIME, isAdult: false) {
              id
              title { romaji english native }
            }
          }
        }
      ''';
      final res = await _dio.post(
        'https://graphql.anilist.co',
        data: {'query': query, 'variables': {'search': title}},
        options: Options(
          headers: {
            'Content-Type': 'application/json',
            'Accept': 'application/json',
            'User-Agent': _userAgent,
          },
        ),
      );
      if (res.statusCode == 200 && res.data != null) {
        final data = res.data is String ? jsonDecode(res.data) : res.data;
        final mediaList = data['data']?['Page']?['media'] as List<dynamic>?;
        if (mediaList != null && mediaList.isNotEmpty) {
          return mediaList.first['id'] as int?;
        }
      }
    } catch (e) {
      appDebugLog('Animetsu: AniList ID search failed: $e');
    }
    return null;
  }

  Future<StreamResult?> _fetchBee(int anilistId, int episode, String category, bool isDub) async {
    final url = 'https://api.aniclover.cc/api/watch/$anilistId/$category/$episode';
    final res = await _dio.get(
      url,
      options: Options(headers: {
        'Referer': 'https://beta.zanora.xyz/',
        'Origin': 'https://beta.zanora.xyz',
        'User-Agent': _userAgent,
      }),
    );
    if (res.statusCode != 200 || res.data == null) return null;
    final data = res.data is String ? jsonDecode(res.data) : res.data;
    if (data is! Map<String, dynamic> || data['success'] != true) return null;

    final rawStreamUrl = data['streamUrl'] ??
        (data['streams'] is List && (data['streams'] as List).isNotEmpty
            ? data['streams'][0]['url']
            : null);
    if (rawStreamUrl == null || rawStreamUrl.toString().isEmpty) return null;

    final String streamUrl = rawStreamUrl.toString();
    final bool isHls = streamUrl.contains('.m3u8') || streamUrl.contains('m3u8');
    final proxiedUrl = HlsProxyService.instance.getProxyUrl(
      streamUrl,
      _userAgent,
      {},
      referer: 'https://beta.zanora.xyz/',
      origin: 'https://beta.zanora.xyz',
      extension: isHls ? '.m3u8' : '',
    );

    final subtitles = <StreamSubtitleTrack>[];
    final rawSubs = (data['subtitles'] ?? data['tracks']) as List<dynamic>?;
    if (rawSubs != null) {
      for (final sub in rawSubs) {
        final u = (sub['url'] ?? sub['file'])?.toString().trim() ?? '';
        var l = (sub['label'] ?? sub['lang'] ?? '').toString().trim();
        if (l.isEmpty || l.toLowerCase() == 'auto' || l.toLowerCase() == 'und') {
          l = 'English';
        }
        if (u.isNotEmpty) {
          subtitles.add(StreamSubtitleTrack(url: u, lang: l));
        }
      }
    }

    final skipTimes = <SkipTime>[];
    if (data['intro'] is Map) {
      final intro = data['intro'];
      final start = intro['start'] as int?;
      final end = intro['end'] as int?;
      if (start != null && end != null && end > start) {
        skipTimes.add(SkipTime(type: 'op', startTime: Duration(seconds: start), endTime: Duration(seconds: end)));
      }
    }
    if (data['outro'] is Map) {
      final outro = data['outro'];
      final start = outro['start'] as int?;
      final end = outro['end'] as int?;
      if (start != null && end != null && end > start) {
        skipTimes.add(SkipTime(type: 'ed', startTime: Duration(seconds: start), endTime: Duration(seconds: end)));
      }
    }

    return StreamResult(
      url: proxiedUrl,
      quality: 'Auto',
      provider: 'Animetsu (Bee)',
      sources: [
        StreamSource(url: proxiedUrl, quality: 'Auto', isM3U8: isHls, isDub: isDub),
      ],
      subtitles: subtitles,
      skipTimes: skipTimes,
      availableQualities: ['Auto', '1080p'],
      availableAudios: ['Default', 'English'],
      selectedAudio: isDub ? 'English' : 'Default',
      isM3U8: isHls,
      headers: {
        'Referer': 'https://beta.zanora.xyz/',
        'Origin': 'https://beta.zanora.xyz',
        'User-Agent': _userAgent,
      },
    );
  }

  Future<StreamResult?> _fetchAnikoto(int anilistId, int episode, String category, bool isDub) async {
    final url = 'https://anshu.screenscape.me/watch/anikoto/$anilistId/$category/anikoto-$episode';
    final res = await _dio.get(
      url,
      options: Options(headers: {
        'Referer': 'https://animetsu.site/',
        'Origin': 'https://animetsu.site',
        'User-Agent': _userAgent,
      }),
    );
    if (res.statusCode != 200 || res.data == null) return null;
    final data = res.data is String ? jsonDecode(res.data) : res.data;
    if (data is! Map<String, dynamic>) return null;

    final streamsList = (data['streams'] as List<dynamic>?) ?? [];
    final hlsStreams = streamsList
        .where((s) => s['type'] == 'hls' && s['url'] != null && s['url'].toString().isNotEmpty)
        .toList();

    if (hlsStreams.isEmpty) {
      final fallbackUrl = data['proxied_stream_url'] ?? data['stream_url'];
      if (fallbackUrl != null && fallbackUrl.toString().isNotEmpty) {
        hlsStreams.add({
          'url': fallbackUrl.toString(),
          'type': 'hls',
          'server': 'HD-1',
          'referer': 'https://megaplay.buzz/',
        });
      }
    }
    if (hlsStreams.isEmpty) return null;

    final sources = <StreamSource>[];
    for (final s in hlsStreams) {
      final u = s['url'].toString();
      final ref = s['referer']?.toString() ?? 'https://megaplay.buzz/';
      final orig = ref.endsWith('/') ? ref.substring(0, ref.length - 1) : ref;
      final serverName = s['server']?.toString() ?? 'HD';
      final proxied = HlsProxyService.instance.getProxyUrl(
        u,
        _userAgent,
        {},
        referer: ref,
        origin: orig,
        extension: '.m3u8',
      );
      sources.add(StreamSource(
        url: proxied,
        quality: serverName,
        isM3U8: true,
        isDub: isDub,
      ));
    }

    final subtitles = <StreamSubtitleTrack>[];
    final rawSubs = (hlsStreams.first['subtitles'] ?? data['subtitles']) as List<dynamic>?;
    if (rawSubs != null) {
      for (final sub in rawSubs) {
        final u = (sub['url'] ?? sub['file'])?.toString().trim() ?? '';
        var l = (sub['label'] ?? sub['lang'] ?? '').toString().trim();
        if (l.isEmpty || l.toLowerCase() == 'auto' || l.toLowerCase() == 'und') {
          l = 'English';
        }
        if (u.isNotEmpty) {
          subtitles.add(StreamSubtitleTrack(url: u, lang: l));
        }
      }
    }

    final skipTimes = <SkipTime>[];
    final introMap = hlsStreams.first['intro'] ?? data['intro'];
    if (introMap is Map) {
      final start = introMap['start'] as int?;
      final end = introMap['end'] as int?;
      if (start != null && end != null && end > start) {
        skipTimes.add(SkipTime(type: 'op', startTime: Duration(seconds: start), endTime: Duration(seconds: end)));
      }
    }
    final outroMap = hlsStreams.first['outro'] ?? data['outro'];
    if (outroMap is Map) {
      final start = outroMap['start'] as int?;
      final end = outroMap['end'] as int?;
      if (start != null && end != null && end > start) {
        skipTimes.add(SkipTime(type: 'ed', startTime: Duration(seconds: start), endTime: Duration(seconds: end)));
      }
    }

    final ref = hlsStreams.first['referer']?.toString() ?? 'https://megaplay.buzz/';
    final orig = ref.endsWith('/') ? ref.substring(0, ref.length - 1) : ref;

    return StreamResult(
      url: sources.first.url,
      quality: sources.first.quality,
      provider: 'Animetsu (Koto)',
      sources: sources,
      subtitles: subtitles,
      skipTimes: skipTimes,
      availableQualities: sources.map((s) => s.quality).toList(),
      availableAudios: ['Default', 'English'],
      selectedAudio: isDub ? 'English' : 'Default',
      isM3U8: true,
      headers: {
        'Referer': ref,
        'Origin': orig,
        'User-Agent': _userAgent,
      },
    );
  }

  Future<StreamResult?> _fetchAniwaves(int anilistId, int episode, String category, bool isDub) async {
    final url = 'https://anshu.screenscape.me/watch/aniwaves/$anilistId/$category/aniwaves-$episode';
    final res = await _dio.get(
      url,
      options: Options(headers: {
        'Referer': 'https://animetsu.site/',
        'Origin': 'https://animetsu.site',
        'User-Agent': _userAgent,
      }),
    );
    if (res.statusCode != 200 || res.data == null) return null;
    final data = res.data is String ? jsonDecode(res.data) : res.data;
    if (data is! Map<String, dynamic>) return null;

    final streamsList = (data['streams'] as List<dynamic>?) ?? [];
    final hlsStreams = streamsList
        .where((s) => s['type'] == 'hls' && s['url'] != null && s['url'].toString().isNotEmpty)
        .toList();
    if (hlsStreams.isEmpty) return null;

    final sources = <StreamSource>[];
    for (final s in hlsStreams) {
      final u = s['url'].toString();
      final ref = s['referer']?.toString() ?? 'https://play.echovideo.ru/';
      final orig = ref.endsWith('/') ? ref.substring(0, ref.length - 1) : ref;
      final serverName = s['server']?.toString() ?? 'Vidplay';
      final proxied = HlsProxyService.instance.getProxyUrl(
        u,
        _userAgent,
        {},
        referer: ref,
        origin: orig,
        extension: '.m3u8',
      );
      sources.add(StreamSource(
        url: proxied,
        quality: serverName,
        isM3U8: true,
        isDub: isDub,
      ));
    }

    final ref = hlsStreams.first['referer']?.toString() ?? 'https://play.echovideo.ru/';
    final orig = ref.endsWith('/') ? ref.substring(0, ref.length - 1) : ref;

    return StreamResult(
      url: sources.first.url,
      quality: sources.first.quality,
      provider: 'Animetsu (Wave)',
      sources: sources,
      subtitles: [],
      skipTimes: [],
      availableQualities: sources.map((s) => s.quality).toList(),
      availableAudios: ['Default', 'English'],
      selectedAudio: isDub ? 'English' : 'Default',
      isM3U8: true,
      headers: {
        'Referer': ref,
        'Origin': orig,
        'User-Agent': _userAgent,
      },
    );
  }

  Future<StreamResult?> _fetchAnimeGG(int anilistId, int episode, String category, bool isDub) async {
    final url = 'https://api.animetsu.site/watch/animegg/$anilistId/$category/animegg-$episode';
    final res = await _dio.get(
      url,
      options: Options(headers: {
        'Referer': 'https://animetsu.site/',
        'Origin': 'https://animetsu.site',
        'User-Agent': _userAgent,
      }),
    );
    if (res.statusCode != 200 || res.data == null) return null;
    final data = res.data is String ? jsonDecode(res.data) : res.data;
    if (data is! Map<String, dynamic>) return null;

    final streamsList = (data['streams'] as List<dynamic>?) ?? [];
    final mp4Streams = streamsList
        .where((s) => s['type'] == 'mp4' && s['url'] != null && s['url'].toString().isNotEmpty)
        .toList();
    if (mp4Streams.isEmpty) return null;

    final sources = <StreamSource>[];
    for (final s in mp4Streams) {
      final u = s['url'].toString();
      final q = s['quality']?.toString() ?? '1080p';
      final proxied = HlsProxyService.instance.getProxyUrl(
        u,
        _userAgent,
        {},
        referer: 'https://www.animegg.org/',
        origin: 'https://www.animegg.org',
        extension: '.mp4',
      );
      sources.add(StreamSource(
        url: proxied,
        quality: q,
        isM3U8: false,
        isDub: isDub,
      ));
    }

    return StreamResult(
      url: sources.first.url,
      quality: sources.first.quality,
      provider: 'Animetsu (GG)',
      sources: sources,
      subtitles: [],
      skipTimes: [],
      availableQualities: sources.map((s) => s.quality).toList(),
      availableAudios: ['Default', 'English'],
      selectedAudio: isDub ? 'English' : 'Default',
      isM3U8: false,
      headers: {
        'Referer': 'https://www.animegg.org/',
        'Origin': 'https://www.animegg.org',
        'User-Agent': _userAgent,
      },
    );
  }

  Future<StreamResult?> fetchStreamUrl({
    required String tmdbId, // Actually Anilist ID for anime
    required String title,
    required String mediaType,
    String? year,
    String? preferredAudio,
    int season = 1,
    int episode = 1,
    String server = 'auto',
  }) async {
    try {
      if (mediaType != 'anime') {
        appDebugLog('Animetsu: Only supports anime');
        return null;
      }

      final cacheKey = '$tmdbId:$title';
      if (!_anilistCache.containsKey(cacheKey)) {
        _anilistCache[cacheKey] = _resolveAnilistId(tmdbId, title);
        Future.delayed(const Duration(minutes: 5), () { _anilistCache.remove(cacheKey); });
      }
      final anilistId = await _anilistCache[cacheKey];
      
      if (anilistId == null) {
        appDebugLog('Animetsu: Missing Anilist ID for $title ($tmdbId)');
        return null;
      }

      final prefLower = (preferredAudio ?? '').toLowerCase();
      final isDub = prefLower == 'english' || prefLower == 'dub' || prefLower.contains('english (dub)');
      final category = isDub ? 'dub' : 'sub';

      final requested = server.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
      final List<String> serversToTry;
      if (requested == 'bee') {
        serversToTry = ['bee', 'koto', 'wave', 'gg'];
      } else if (requested == 'koto' || requested == 'anikoto') {
        serversToTry = ['koto', 'bee', 'wave', 'gg'];
      } else if (requested == 'wave' || requested == 'aniwaves') {
        serversToTry = ['wave', 'bee', 'koto', 'gg'];
      } else if (requested == 'gg' || requested == 'animegg') {
        serversToTry = ['gg', 'bee', 'koto', 'wave'];
      } else {
        // 'auto' or legacy names ('db', 'kari', 'flow', 'zuri', 'gojo', 'mega')
        serversToTry = ['bee', 'koto', 'wave', 'gg'];
      }

      for (final s in serversToTry) {
        try {
          StreamResult? result;
          if (s == 'bee') {
            result = await _fetchBee(anilistId, episode, category, isDub);
          } else if (s == 'koto') {
            result = await _fetchAnikoto(anilistId, episode, category, isDub);
          } else if (s == 'wave') {
            result = await _fetchAniwaves(anilistId, episode, category, isDub);
          } else if (s == 'gg') {
            result = await _fetchAnimeGG(anilistId, episode, category, isDub);
          }

          if (result != null && result.sources.isNotEmpty) {
            appDebugLog('Animetsu ($s): Successfully retrieved stream for $title Ep $episode');
            return result;
          }
        } catch (e) {
          appDebugLog('Animetsu ($s): Error during fetch: $e');
        }
      }

      appDebugLog('Animetsu: All servers failed for $title');
      return null;
    } catch (e) {
      appDebugLog('Animetsu Scraper Error: $e');
      return null;
    }
  }
}
