import 'package:dio/dio.dart';
import 'package:nivio/models/search_result.dart';
import 'package:nivio/models/stream_result.dart';
import 'package:nivio/services/aimi_anime_service.dart';
import 'package:nivio/services/flixhq_scraper_service.dart';

/// Service for fetching streaming URLs.
/// Anime primary: aimi_lib direct providers.
/// Non-anime primary: native FlixHQ scraper.
/// Fallback: vidsrc.cc, vidsrc.to, vidlink.pro (embed/WebView).
class StreamingService {
  final AimiAnimeService _aimiAnimeService = AimiAnimeService();
  final FlixhqScraperService _flixhqScraperService = FlixhqScraperService();
  final Dio _probeDio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 8),
      receiveTimeout: const Duration(seconds: 8),
    ),
  );

  StreamingService();

  /// Embed fallback providers (used only if direct extraction fails)
  static final List<Map<String, String>> _embedProviders = [
    {'name': 'vidsrc.cc', 'url': 'https://vidsrc.cc/v2/embed'},
    {'name': 'vidsrc.to', 'url': 'https://vidsrc.to/embed'},
    {'name': 'vidlink', 'url': 'https://vidlink.pro'},
  ];

  /// Fetch streaming URL - tries direct chain first, then embeds.
  Future<StreamResult?> fetchStreamUrl({
    required SearchResult media,
    int season = 1,
    int episode = 1,
    String? preferredQuality,
    int providerIndex = 0,
    bool autoSkipIntro = true,
    String subDubPreference = 'sub',
  }) async {
    try {
      print(
        'fetchStreamUrl: media=${media.id}, S${season}E$episode, providerIdx=$providerIndex',
      );

      // Provider 0 = direct source chain (AIMI for anime, FlixHQ otherwise)
      if (providerIndex == 0) {
        final isAnime = _isAnimeCandidate(media);

        if (isAnime) {
          final animeResult = await _aimiAnimeService.fetchAnimeStream(
            media: media,
            episode: media.mediaType == 'movie' ? 1 : episode,
            subDubPreference: subDubPreference,
          );

          if (animeResult != null) {
            print('AIMI anime stream acquired: ${animeResult.quality}');
            return animeResult;
          }

          print('AIMI anime failed, trying FlixHQ fallback...');
        }

        final flixhqResult = await _flixhqScraperService.fetchStream(
          mediaType: media.mediaType,
          season: season,
          episode: episode,
          title: media.title ?? media.name ?? '',
          year: _extractYear(media),
        );

        if (flixhqResult != null) {
          final normalizedHeaders = _buildDirectHeaders(flixhqResult.headers);
          final normalizedResult = StreamResult(
            url: flixhqResult.url,
            quality: flixhqResult.quality,
            provider: flixhqResult.provider,
            subtitles: flixhqResult.subtitles,
            availableQualities: flixhqResult.availableQualities,
            isM3U8: flixhqResult.isM3U8,
            headers: normalizedHeaders,
            sources: flixhqResult.sources,
          );

          if (normalizedResult.provider.toLowerCase().contains('flixhq') &&
              !_isAnimeCandidate(media)) {
            final isPlayable = await _probeDirectHls(normalizedResult);
            if (!isPlayable) {
              print(
                'FlixHQ source probe failed, attempting direct playback anyway...',
              );
            }
          }

          print('FlixHQ stream acquired: ${normalizedResult.quality}');
          return normalizedResult;
        }

        // Return null so player auto-advances to next provider (embed).
        print('Direct stream chain failed, returning null to advance provider');
        return null;
      }

      // Fallback to embed providers (index 1=vidsrc.cc, 2=vidsrc.to, 3=vidlink)
      final embedIdx = providerIndex - 1;
      if (embedIdx >= _embedProviders.length) {
        print('All providers exhausted');
        return null;
      }

      final provider = _embedProviders[embedIdx];
      final String streamUrl;

      if (media.mediaType == 'movie') {
        if (provider['name'] == 'vidlink') {
          streamUrl = '${provider['url']}/movie/${media.id}?nextbutton=true';
        } else if (provider['name'] == 'vidsrc.cc') {
          streamUrl = '${provider['url']}/movie/${media.id}?autoPlay=true';
        } else {
          streamUrl = '${provider['url']}/movie/${media.id}';
        }
      } else {
        if (provider['name'] == 'vidsrc.cc') {
          streamUrl =
              '${provider['url']}/tv/${media.id}/$season/$episode?autoPlay=true';
        } else if (provider['name'] == 'vidlink') {
          streamUrl =
              '${provider['url']}/tv/${media.id}/$season/$episode?nextbutton=true';
        } else {
          streamUrl = '${provider['url']}/tv/${media.id}/$season/$episode';
        }
      }

      print('Embed fallback: ${provider['name']} -> $streamUrl');

      return StreamResult(
        url: streamUrl,
        quality: preferredQuality ?? 'auto',
        provider: provider['name']!,
      );
    } catch (e) {
      print('Error in fetchStreamUrl: $e');
      return null;
    }
  }

  /// Get the total number of available providers (direct + embeds).
  static int get totalProviders => 1 + _embedProviders.length;

  /// Get provider name by index.
  static String getProviderName(int index) {
    if (index == 0) return 'Direct';
    final embedIdx = index - 1;
    if (embedIdx < _embedProviders.length) {
      return _embedProviders[embedIdx]['name']!;
    }
    return 'Unknown';
  }

  /// Check if a provider index uses direct streaming (vs embed/WebView).
  static bool isDirectStream(int providerIndex) {
    return providerIndex == 0;
  }

  bool _isAnimeCandidate(SearchResult media) {
    final language = (media.originalLanguage ?? '').toLowerCase();
    return media.mediaType == 'tv' && language == 'ja';
  }

  String? _extractYear(SearchResult media) {
    final date = media.releaseDate ?? media.firstAirDate;
    if (date == null || date.length < 4) return null;
    return date.substring(0, 4);
  }

  Future<bool> _probeDirectHls(StreamResult result) async {
    if (!result.isM3U8 || result.url.trim().isEmpty) {
      return true;
    }

    final requestHeaders = _buildDirectHeaders(result.headers);

    try {
      final response = await _probeDio.get<String>(
        result.url,
        options: Options(
          headers: requestHeaders,
          responseType: ResponseType.plain,
          followRedirects: true,
          validateStatus: (status) => status != null && status < 500,
        ),
      );

      if (response.statusCode != null &&
          response.statusCode! >= 200 &&
          response.statusCode! < 300 &&
          (response.data?.contains('#EXTM3U') ?? false)) {
        return true;
      }

      print(
        'Direct probe status=${response.statusCode}, playlistValid=${response.data?.contains('#EXTM3U') ?? false}',
      );
      return false;
    } catch (e) {
      print('Direct probe exception: $e');
      return false;
    }
  }

  Map<String, String> _buildDirectHeaders(Map<String, String> incoming) {
    final headers = <String, String>{
      'User-Agent':
          'Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36',
      ...incoming,
    };

    headers.putIfAbsent('Accept', () => '*/*');
    return headers;
  }
}
