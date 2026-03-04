import 'package:dio/dio.dart';
import 'package:nivio/models/search_result.dart';
import 'package:nivio/models/stream_result.dart';
import 'package:nivio/services/aimi_anime_service.dart';
import 'package:nivio/services/flixhq_scraper_service.dart';
import 'package:nivio/services/net22_scraper_service.dart';

import 'package:nivio/core/debug_log.dart';

/// Service for fetching streaming URLs.
/// Anime primary: aimi_lib direct providers.
/// Non-anime primary: native Net22 scraper.
/// Next direct fallback: native FlixHQ scraper.
/// Fallback: vidsrc.cc, vidsrc.to, vidlink.pro (embed/WebView).
class StreamingService {
  final AimiAnimeService _aimiAnimeService = AimiAnimeService();
  final Net22ScraperService _net22ScraperService = Net22ScraperService();
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
  static const List<String> _animeDirectProviders = [
    'animepahe',
    'net22 (direct)',
    'flix (direct)',
  ];
  static const List<String> _defaultDirectProviders = [
    'net22 (direct)',
    'flix (direct)',
  ];

  /// Fetch streaming URL - tries direct chain first, then embeds.
  Future<StreamResult?> fetchStreamUrl({
    required SearchResult media,
    int season = 1,
    int episode = 1,
    String? preferredQuality,
    String? preferredNet22Audio,
    int providerIndex = 0,
    bool autoSkipIntro = true,
    String subDubPreference = 'sub',
  }) async {
    try {
      appDebugLog(
        'fetchStreamUrl: media=${media.id}, S${season}E$episode, providerIdx=$providerIndex',
      );
      final isAnime = _isAnimeCandidate(media);
      final directProviders = isAnime
          ? _animeDirectProviders
          : _defaultDirectProviders;
      final directCount = directProviders.length;

      // Direct providers are listed as independent selectable indices.
      if (providerIndex < directCount) {
        // Map selected index to canonical direct slot:
        // anime: 0=animepahe, 1=net22, 2=flix
        // non-anime: 0=net22, 1=flix
        final directSlot = isAnime ? providerIndex : providerIndex + 1;

        if (directSlot == 0) {
          final animeResult = await _aimiAnimeService.fetchAnimeStream(
            media: media,
            episode: media.mediaType == 'movie' ? 1 : episode,
            subDubPreference: subDubPreference,
            preferredQuality: preferredQuality,
          );

          if (animeResult != null) {
            appDebugLog('AIMI anime stream acquired: ${animeResult.quality}');
            return animeResult;
          }

          appDebugLog('AIMI anime failed');
          return null;
        }

        if (directSlot == 1) {
          final net22Result = await _net22ScraperService.fetchStream(
            mediaType: media.mediaType,
            season: season,
            episode: episode,
            title: media.title ?? media.name ?? '',
            year: _extractYear(media),
            preferredAudio: preferredNet22Audio,
          );

          if (net22Result != null) {
            final normalizedHeaders = _buildDirectHeaders(net22Result.headers);
            final normalizedResult = StreamResult(
              url: net22Result.url,
              quality: net22Result.quality,
              provider: net22Result.provider,
              subtitles: net22Result.subtitles,
              availableQualities: net22Result.availableQualities,
              availableAudios: net22Result.availableAudios,
              selectedAudio: net22Result.selectedAudio,
              isM3U8: net22Result.isM3U8,
              headers: normalizedHeaders,
              sources: net22Result.sources,
            );

            final isPlayable = await _probeDirectHls(normalizedResult);
            if (!isPlayable) {
              appDebugLog(
                'Net22 source probe failed, attempting direct playback anyway...',
              );
            }

            appDebugLog('Net22 stream acquired: ${normalizedResult.quality}');
            return normalizedResult;
          }

          appDebugLog('Net22 failed');
          return null;
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

          final isPlayable = await _probeDirectHls(normalizedResult);
          if (!isPlayable) {
            appDebugLog(
              'FlixHQ source probe failed, attempting direct playback anyway...',
            );
          }

          appDebugLog('FlixHQ stream acquired: ${normalizedResult.quality}');
          return normalizedResult;
        }

        appDebugLog('FlixHQ failed');
        return null;
      }

      // Fallback to embed providers after direct providers.
      final embedIdx = providerIndex - directCount;
      if (embedIdx >= _embedProviders.length) {
        appDebugLog('All providers exhausted');
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

      appDebugLog('Embed fallback: ${provider['name']} -> $streamUrl');

      return StreamResult(
        url: streamUrl,
        quality: preferredQuality ?? 'auto',
        provider: provider['name']!,
      );
    } catch (e) {
      appDebugLog('Error in fetchStreamUrl: $e');
      return null;
    }
  }

  /// Get the total number of available providers (direct + embeds).
  static int totalProvidersFor({required bool isAnime}) {
    final directCount = isAnime
        ? _animeDirectProviders.length
        : _defaultDirectProviders.length;
    return directCount + _embedProviders.length;
  }

  /// Get provider name by index.
  static String getProviderName(int index, {required bool isAnime}) {
    final directProviders = isAnime
        ? _animeDirectProviders
        : _defaultDirectProviders;
    if (index >= 0 && index < directProviders.length) {
      return directProviders[index];
    }

    final embedIdx = index - directProviders.length;
    if (embedIdx < _embedProviders.length) {
      return _embedProviders[embedIdx]['name']!;
    }
    return 'Unknown';
  }

  /// Check if a provider index uses direct streaming (vs embed/WebView).
  static bool isDirectStream(int providerIndex, {required bool isAnime}) {
    final directCount = isAnime
        ? _animeDirectProviders.length
        : _defaultDirectProviders.length;
    return providerIndex < directCount;
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

      appDebugLog(
        'Direct probe status=${response.statusCode}, playlistValid=${response.data?.contains('#EXTM3U') ?? false}',
      );
      return false;
    } catch (e) {
      appDebugLog('Direct probe exception: $e');
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
