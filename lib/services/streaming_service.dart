import 'package:nivio/models/search_result.dart';
import 'package:nivio/models/stream_result.dart';
import 'package:nivio/services/consumet_service.dart';

/// Service for fetching streaming URLs
/// Primary: Consumet API (direct M3U8 streams)
/// Fallback: vidsrc.cc, vidsrc.to, vidlink.pro (embed/WebView)
class StreamingService {
  final ConsumetService _consumetService = ConsumetService();

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

      // Provider 0 = Consumet API (direct M3U8)
      if (providerIndex == 0) {
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
          print('✅ Consumet stream acquired: ${consumetResult.quality}');
          return consumetResult;
        }
        // Return null so player auto-advances to next provider (embed)
        print('⚠️ Consumet failed, returning null to advance provider');
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
    if (index == 0) return 'Consumet';
    final embedIdx = index - 1;
    if (embedIdx < _embedProviders.length) {
      return _embedProviders[embedIdx]['name']!;
    }
    return 'Unknown';
  }

  /// Check if a provider index uses direct streaming (vs embed/WebView)
  static bool isDirectStream(int providerIndex) {
    return providerIndex == 0; // Consumet provides direct M3U8
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
}
