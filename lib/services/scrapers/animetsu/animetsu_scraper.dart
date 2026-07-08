import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nivio/core/debug_log.dart';
import 'package:nivio/models/stream_result.dart';
import 'package:nivio/services/skip_times_models.dart';

final animetsuScraperProvider = Provider((ref) => AnimetsuScraperService(providerName: 'Nivio-anime'));

class AnimetsuScraperService {
  final String providerName;

  AnimetsuScraperService({this.providerName = 'Nivio-anime'});

  final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 20),
      validateStatus: (status) => status != null && status < 600,
      headers: {
        'User-Agent': 'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/147.0.0.0 Safari/537.36',
        'Referer': 'https://animetsu.live/',
        'Origin': 'https://animetsu.live'
      }
    ),
  );

  // We default to auto which checks kite, dio, sage, meg sequentially
  final String defaultServer = 'auto';

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
      if (tmdbId.isEmpty) {
        appDebugLog('Animetsu: Missing Anilist ID');
        return null;
      }

      final isDub = preferredAudio != null && preferredAudio.toLowerCase() == 'english';
      final sourceType = isDub ? 'dub' : 'sub';
      
      // Step 1: Find the internal MongoDB ID
      String? internalId;
      try {
        final searchUrl = 'https://animetsu.live/v2/api/anime/search?query=${Uri.encodeQueryComponent(title)}';
        final searchRes = await _dio.get(searchUrl);
        if (searchRes.statusCode == 200 && searchRes.data != null && searchRes.data['results'] != null) {
          final results = searchRes.data['results'] as List;
          for (final result in results) {
            final cover = result['cover_image']?['large']?.toString() ?? '';
            final banner = result['banner']?.toString() ?? '';
            // Match against Anilist ID embedded in cover/banner
            if (cover.contains('bx$tmdbId') || banner.contains('/$tmdbId-') || banner.contains('/$tmdbId.')) {
              internalId = result['id']?.toString();
              break;
            }
          }
        }
      } catch (e) {
        appDebugLog('Animetsu: Search failed: $e');
      }

      if (internalId == null) {
        appDebugLog('Animetsu: Could not find internal ID for $title (AniList $tmdbId)');
        return null;
      }
      
      // If we made it here, we have the internal ID.
      // Implement server fallback logic
      List<String> serversToTry = [];
      if (server == 'auto') {
        serversToTry = ['kite', 'dio', 'sage', 'meg'];
      } else {
        serversToTry = [server];
      }

      for (String currentServer in serversToTry) {
        final url = 'https://animetsu.live/v2/api/anime/oppai/$internalId/$episode?server=$currentServer&source_type=$sourceType';
        
        try {
          final response = await _dio.get(url);
          
          if (response.statusCode != 200 || response.data == null) {
            appDebugLog('Animetsu ($currentServer): Failed to fetch stream (HTTP ${response.statusCode})');
            continue;
          }
          
          final data = response.data;
          if (data is! Map<String, dynamic>) {
            appDebugLog('Animetsu ($currentServer): Invalid response format');
            continue;
          }
          
          final sourcesData = data['sources'] as List<dynamic>? ?? [];
          if (sourcesData.isEmpty) {
            appDebugLog('Animetsu ($currentServer): No sources found in response');
            continue;
          }
          
          // Parse sources
          final List<StreamSource> sources = [];
          for (final src in sourcesData) {
            final srcUrl = src['url'] as String? ?? '';
            final quality = src['quality'] as String? ?? 'auto';
            final isM3U8 = srcUrl.contains('.m3u8') || src['type'] == 'hls' || src['type'] == 'video/mpegurl' || src['type'] == 'application/x-mpegURL' || src['type'] == 'application/vnd.apple.mpegurl';
            final needProxy = src['need_proxy'] == true;
            
            String finalUrl = srcUrl;
            if (!finalUrl.startsWith('http')) {
              finalUrl = finalUrl.startsWith('/') ? finalUrl : '/$finalUrl';
              finalUrl = 'https://swiftstream.top/proxy$finalUrl';
            } else if (needProxy && !finalUrl.contains('swiftstream.top/proxy')) {
               finalUrl = 'https://swiftstream.top/proxy?url=${Uri.encodeQueryComponent(finalUrl)}';
            }
            
            sources.add(StreamSource(
              url: finalUrl,
              quality: quality,
              isM3U8: isM3U8,
              isDub: isDub,
            ));
          }
          
          final primarySource = sources.firstWhere(
            (s) => s.quality == 'auto' || s.quality == '1080p',
            orElse: () => sources.first,
          );
          
          final List<SubtitleTrack> subtitles = [];
          final subsData = data['subs'] as List<dynamic>? ?? [];
          for (final sub in subsData) {
            subtitles.add(SubtitleTrack(
              url: sub['url'] ?? '',
              lang: sub['lang'] ?? 'Unknown',
            ));
          }
          
          final List<SkipTime> skipTimes = [];
          if (data['skips'] != null) {
            final skips = data['skips'];
            if (skips['intro'] != null) {
              skipTimes.add(SkipTime(
                type: 'op',
                startTime: Duration(seconds: skips['intro']['start'] ?? 0),
                endTime: Duration(seconds: skips['intro']['end'] ?? 0),
              ));
            }
            if (skips['outro'] != null) {
              skipTimes.add(SkipTime(
                type: 'ed',
                startTime: Duration(seconds: skips['outro']['start'] ?? 0),
                endTime: Duration(seconds: skips['outro']['end'] ?? 0),
              ));
            }
          }

          return StreamResult(
            url: primarySource.url,
            quality: primarySource.quality,
            provider: 'Nivio-anime (${currentServer[0].toUpperCase()}${currentServer.substring(1)})',
            sources: sources,
            subtitles: subtitles,
            skipTimes: skipTimes,
            availableQualities: sources.map((s) => s.quality).toSet().toList(),
            availableAudios: ['Default', 'English'],
            selectedAudio: isDub ? 'English' : 'Default',
            isM3U8: primarySource.isM3U8,
            headers: {
              'Referer': 'https://animetsu.live/',
              'User-Agent': 'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/147.0.0.0 Safari/537.36'
            },
          );
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
