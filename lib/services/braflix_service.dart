import 'package:nivio/models/search_result.dart';
import 'package:nivio/models/stream_result.dart';

class BraflixService {
  BraflixService();

  /// Base URLs for streaming services (in priority order)
  static const List<Map<String, String>> _providers = [
    {'name': 'vidsrc.cc', 'url': 'https://vidsrc.cc/v2/embed'},
    {'name': 'vidsrc.to', 'url': 'https://vidsrc.to/embed'},
    {'name': 'vidlink', 'url': 'https://vidlink.pro'},
  ];

  /// Constructs streaming URLs from available providers
  /// 
  /// Tries providers in order: vidsrc.cc → vidsrc.to → vidlink.pro
  Future<StreamResult?> fetchStreamUrl({
    required SearchResult media,
    int season = 1,
    int episode = 1,
    String? preferredQuality,
    int providerIndex = 0,
  }) async {
    try {
      if (providerIndex >= _providers.length) {
        print('❌ All providers exhausted');
        return null;
      }

      final provider = _providers[providerIndex];
      final String streamUrl;
      
      // Construct URL based on media type and provider
      if (media.mediaType == 'movie') {
        // Movie URL formats:
        // vidsrc.cc: https://vidsrc.cc/v2/embed/movie/{tmdbId}
        // vidsrc.to: https://vidsrc.to/embed/movie/{tmdbId}
        // vidlink: https://vidlink.pro/movie/{tmdbId}?nextbutton=true
        if (provider['name'] == 'vidlink') {
          streamUrl = '${provider['url']}/movie/${media.id}?nextbutton=true';
        } else {
          streamUrl = '${provider['url']}/movie/${media.id}';
        }
        print('🎬 Provider: ${provider['name']} | Movie URL: $streamUrl');
      } else {
        // TV show URL formats:
        // vidsrc.cc: https://vidsrc.cc/v2/embed/tv/{tmdbId}/{season}/{episode}
        // vidsrc.to: https://vidsrc.to/embed/tv/{tmdbId}/{season}/{episode}
        // vidlink: https://vidlink.pro/tv/{tmdbId}/{season}/{episode}?nextbutton=true
        if (provider['name'] == 'vidlink') {
          streamUrl = '${provider['url']}/tv/${media.id}/$season/$episode?nextbutton=true';
        } else {
          streamUrl = '${provider['url']}/tv/${media.id}/$season/$episode';
        }
        print('📺 Provider: ${provider['name']} | TV URL: $streamUrl (S${season}E${episode})');
      }

      return StreamResult(
        url: streamUrl,
        quality: preferredQuality ?? 'auto',
        provider: provider['name']!,
        subtitles: [],
        availableQualities: ['auto'],
      );
    } catch (e) {
      print('❌ Error constructing stream URL: $e');
      return null;
    }
  }
}

// StreamResult model moved to `lib/models/stream_result.dart`


