import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nivio/core/debug_log.dart';
import 'package:nivio/models/stream_result.dart';
import 'package:nivio/services/skip_times_models.dart';

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
        'Referer': 'https://animetsu.site/',
        'Origin': 'https://animetsu.site',
      },
    ),
  );

  final String defaultServer = 'auto';

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

  final Map<String, Future<int?>> _anilistCache = {};
  final Map<String, Future<dynamic>> _serversCache = {};

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

      final requestedServer = server.toLowerCase();
      final List<String> serversToTry;
      if (requestedServer == 'auto' || requestedServer == 'meg' || requestedServer == 'mega') {
        serversToTry = ['anichan', 'animekai', 'anidb'];
      } else if (requestedServer == 'koto' || requestedServer == 'anichan' || requestedServer == 'kite') {
        serversToTry = ['anichan', 'animekai', 'anidb'];
      } else if (requestedServer == 'db' || requestedServer == 'anidb' || requestedServer == 'anidbapp' || requestedServer == 'sage') {
        serversToTry = ['anidb', 'anichan', 'animekai'];
      } else if (requestedServer == 'kari' || requestedServer == 'flow' || requestedServer == 'zuri' || requestedServer == 'gojo') {
        serversToTry = ['anichan', 'animekai', 'anidb'];
      } else if (requestedServer == 'animekai' || requestedServer == 'dio') {
        serversToTry = ['animekai', 'anichan', 'anidb'];
      } else {
        serversToTry = [requestedServer, 'anichan', 'animekai', 'anidb'];
      }

      Map<String, dynamic>? anichanData;

      for (final currentServer in serversToTry) {
        try {
          if (currentServer == 'anichan' || currentServer == 'animekai' || currentServer == 'animesuge') {
            if (anichanData == null) {
              final srvKey = '$anilistId:$episode:$category';
              if (!_serversCache.containsKey(srvKey)) {
                final url = 'https://anichan.net/api/watch/servers?anilistId=$anilistId&ep=$episode&category=$category&tier=rest';
                _serversCache[srvKey] = _dio.get(url, options: Options(headers: {'Referer': 'https://animetsu.site/', 'Origin': 'https://animetsu.site'})).then((response) {
                  return (response.statusCode == 200 && response.data != null) 
                      ? (response.data is String ? jsonDecode(response.data) : response.data)
                      : null;
                });
                Future.delayed(const Duration(seconds: 15), () { _serversCache.remove(srvKey); });
              }
              anichanData = await _serversCache[srvKey];
            }

            if (anichanData != null && anichanData['servers'] is List) {
              final serversList = anichanData['servers'] as List;
              dynamic targetServerObj;
              if (currentServer == 'anichan') {
                targetServerObj = serversList.firstWhere(
                  (s) => s['name'] == 'anichan',
                  orElse: () => serversList.firstOrNull,
                );
              } else if (currentServer == 'animekai' || currentServer == 'animesuge') {
                targetServerObj = serversList.firstWhere(
                  (s) => s['name'] == 'animekai' || s['name'] == 'animesuge',
                  orElse: () => serversList.length > 1 ? serversList[1] : null,
                );
              }

              if (targetServerObj != null && targetServerObj['stream'] != null) {
                String streamUrl = targetServerObj['stream'].toString();
                if (streamUrl.startsWith('/')) {
                  streamUrl = 'https://anichan.net$streamUrl';
                }

                final List<StreamSubtitleTrack> subtitles = [];
                if (targetServerObj['subtitles'] is List) {
                  for (final sub in targetServerObj['subtitles']) {
                    final u = sub['url']?.toString().trim() ?? '';
                    var l = (sub['lang'] ?? sub['language'] ?? sub['label'] ?? sub['name'] ?? '').toString().trim();
                    if (l.isEmpty || l.toLowerCase() == 'auto' || l.toLowerCase() == 'und' || l.toLowerCase() == 'unknown') {
                      l = 'Default Subtitle';
                    }
                    if (u.isNotEmpty) {
                      subtitles.add(StreamSubtitleTrack(url: u, lang: l));
                    }
                  }
                }

                final List<SkipTime> skipTimes = [];
                if (targetServerObj['intro'] is Map) {
                  final intro = targetServerObj['intro'];
                  final start = intro['start'] as int?;
                  final end = intro['end'] as int?;
                  if (start != null && end != null && end > start) {
                    skipTimes.add(SkipTime(
                      type: 'op',
                      startTime: Duration(seconds: start),
                      endTime: Duration(seconds: end),
                    ));
                  }
                }
                if (targetServerObj['outro'] is Map) {
                  final outro = targetServerObj['outro'];
                  final start = outro['start'] as int?;
                  final end = outro['end'] as int?;
                  if (start != null && end != null && end > start) {
                    skipTimes.add(SkipTime(
                      type: 'ed',
                      startTime: Duration(seconds: start),
                      endTime: Duration(seconds: end),
                    ));
                  }
                }

                final sources = [
                  StreamSource(
                    url: streamUrl,
                    quality: 'Auto',
                    isM3U8: true,
                    isDub: isDub,
                  ),
                ];

                final serverNameStr = targetServerObj['name']?.toString().toLowerCase() ?? currentServer;
                final String referer;
                final String origin;
                if (serverNameStr == 'anichan') {
                  referer = 'https://anichan.net/';
                  origin = 'https://anichan.net';
                } else {
                  referer = 'https://megaplay.buzz/';
                  origin = 'https://megaplay.buzz';
                }

                final serverLabel = targetServerObj['label']?.toString() ?? currentServer;

                return StreamResult(
                  url: streamUrl,
                  quality: 'Auto',
                  provider: 'Animetsu ($serverLabel)',
                  sources: sources,
                  subtitles: subtitles,
                  skipTimes: skipTimes,
                  availableQualities: ['Auto', '1080p'],
                  availableAudios: ['Default', 'English'],
                  selectedAudio: isDub ? 'English' : 'Default',
                  isM3U8: true,
                  headers: {
                    'Referer': referer,
                    'Origin': origin,
                    'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/137.0.0.0 Safari/537.36',
                  },
                );
              }
            }
          } else if (currentServer == 'anidb') {
            final url = 'https://anivexa.pages.dev/watch/anidbapp/$anilistId/$category/anidbapp-$episode';
            final response = await _dio.get(
              url,
              options: Options(
                headers: {
                  'Referer': 'https://anidb.app/',
                },
              ),
            );

            if (response.statusCode == 200 && response.data != null) {
              final anidbData = response.data is String ? jsonDecode(response.data) : response.data;
              if (anidbData is Map<String, dynamic> && anidbData['streams'] is List) {
                final streamsList = anidbData['streams'] as List;
                final hlsStream = streamsList.firstWhere(
                  (s) => s['type'] == 'hls' && s['url'] != null,
                  orElse: () => streamsList.firstOrNull,
                );
                if (hlsStream != null && hlsStream['url'] != null) {
                  final streamUrl = hlsStream['url'].toString();
                  final sources = [
                    StreamSource(
                      url: streamUrl,
                      quality: 'Auto',
                      isM3U8: true,
                      isDub: isDub,
                    ),
                  ];

                  return StreamResult(
                    url: streamUrl,
                    quality: 'Auto',
                    provider: 'Animetsu (AniDB)',
                    sources: sources,
                    subtitles: [],
                    skipTimes: [],
                    availableQualities: ['Auto', '1080p'],
                    availableAudios: ['Default', 'English'],
                    selectedAudio: isDub ? 'English' : 'Default',
                    isM3U8: true,
                    headers: {
                      'Referer': 'https://anidb.app/',
                      'Origin': 'https://anidb.app',
                      'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/137.0.0.0 Safari/537.36',
                    },
                  );
                }
              }
            }
          }
        } catch (e) {
          appDebugLog('Animetsu ($currentServer): Error during fetch: $e');
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
