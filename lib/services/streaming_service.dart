import 'package:dio/dio.dart';
import 'package:nivio/models/search_result.dart';
import 'package:nivio/models/stream_result.dart';
import 'package:nivio/services/aimi_anime_service.dart';
import 'package:nivio/services/consumet_service.dart';

/// Service for fetching streaming URLs.
/// Anime primary: aimi_lib direct providers.
/// Non-anime primary: Consumet API.
/// Fallback: vidsrc.cc, vidsrc.to, vidlink.pro (embed/WebView).
class StreamingService {
  final AimiAnimeService _aimiAnimeService = AimiAnimeService();
  final ConsumetService _consumetService = ConsumetService();
  final Dio _probeDio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 8),
      receiveTimeout: const Duration(seconds: 8),
    ),
  );

  StreamingService();

  /// Embed fallback providers (used only if Consumet fails)
  static final List<Map<String, String>> _embedProviders = [
    {'name': 'vidsrc.cc', 'url': 'https://vidsrc.cc/v2/embed'},
    {'name': 'vidsrc.to', 'url': 'https://vidsrc.to/embed'},
    {'name': 'vidlink', 'url': 'https://vidlink.pro'},
  ];

  /// Fetch streaming URL - tries Consumet first, then embeds
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
        '🔍 fetchStreamUrl: media=${media.id}, S${season}E$episode, providerIdx=$providerIndex',
      );

      // Provider 0 = direct source chain (AIMI for anime, Consumet otherwise)
      if (providerIndex == 0) {
        final isAnime = _isAnimeCandidate(media);

        if (isAnime) {
          final animeResult = await _aimiAnimeService.fetchAnimeStream(
            media: media,
            episode: media.mediaType == 'movie' ? 1 : episode,
            subDubPreference: subDubPreference,
          );

          if (animeResult != null) {
            print('✅ AIMI anime stream acquired: ${animeResult.quality}');
            return animeResult;
          }

          print('⚠️ AIMI anime failed, trying Consumet fallback for anime...');
        }

        final consumetResult = await _consumetService.fetchStream(
          tmdbId: media.id,
          mediaType: media.mediaType,
          season: season,
          episode: episode,
          title: media.title ?? media.name ?? '',
          year: _extractYear(media),
          isAnimeCandidate: _isAnimeCandidate(media),
          subDubPreference: subDubPreference,
        );

        if (consumetResult != null) {
          final normalizedHeaders = _buildDirectHeaders(consumetResult.headers);
          final normalizedResult = StreamResult(
            url: consumetResult.url,
            quality: consumetResult.quality,
            provider: consumetResult.provider,
            subtitles: consumetResult.subtitles,
            availableQualities: consumetResult.availableQualities,
            isM3U8: consumetResult.isM3U8,
            headers: normalizedHeaders,
            sources: consumetResult.sources,
          );
          if (consumetResult.provider == 'consumet-flixhq' &&
              !_isAnimeCandidate(media)) {
            final isPlayable = await _probeDirectHls(normalizedResult);
            if (!isPlayable) {
              print(
                '⚠️ Consumet FlixHQ source probe failed, attempting direct playback anyway...',
              );
            }
          }
          print('✅ Consumet stream acquired: ${normalizedResult.quality}');
          return normalizedResult;
        }
        // Return null so player auto-advances to next provider (embed).
        print(
          '⚠️ Direct stream chain failed, returning null to advance provider',
        );
        return null;
      }

      // Fallback to embed providers (index 1=vidsrc.cc, 2=vidsrc.to, 3=vidlink)
      final embedIdx = providerIndex - 1;
      if (embedIdx >= _embedProviders.length) {
        print('❌ All providers exhausted');
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

      print('📺 Embed fallback: ${provider['name']} → $streamUrl');

      return StreamResult(
        url: streamUrl,
        quality: preferredQuality ?? 'auto',
        provider: provider['name']!,
      );
    } catch (e) {
      print('❌ Error in fetchStreamUrl: $e');
      return null;
    }
  }

  /// Get the total number of available providers (Consumet + embeds)
  static int get totalProviders =>
      1 + _embedProviders.length; // Consumet + 3 embeds

  /// Get provider name by index
  static String getProviderName(int index) {
    if (index == 0) return 'Direct';
    final embedIdx = index - 1;
    if (embedIdx < _embedProviders.length) {
      return _embedProviders[embedIdx]['name']!;
    }
    return 'Unknown';
  }

  /// Check if a provider index uses direct streaming (vs embed/WebView)
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
        '⚠️ Direct probe status=${response.statusCode}, playlistValid=${response.data?.contains('#EXTM3U') ?? false}',
      );
      return false;
    } catch (e) {
      print('⚠️ Direct probe exception: $e');
      return false;
    }
  }

  Map<String, String> _buildDirectHeaders(Map<String, String> incoming) {
    final headers = <String, String>{
      'User-Agent':
          'Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36',
      ...incoming,
    };

    final refererEntry = headers.entries.where(
      (e) => e.key.toLowerCase() == 'referer',
    );
    final hasOrigin = headers.keys.any((k) => k.toLowerCase() == 'origin');
    if (refererEntry.isNotEmpty && !hasOrigin) {
      final referer = refererEntry.first.value;
      final refUri = Uri.tryParse(referer);
      if (refUri != null &&
          refUri.scheme.isNotEmpty &&
          refUri.host.isNotEmpty) {
        headers['Origin'] = '${refUri.scheme}://${refUri.host}';
      }
    }

    headers.putIfAbsent('Accept', () => '*/*');
    return headers;
  }
}
