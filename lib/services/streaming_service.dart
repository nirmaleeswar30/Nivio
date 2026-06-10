import 'package:nivio/models/search_result.dart';
import 'package:nivio/models/stream_result.dart';
import 'package:nivio/core/debug_log.dart';
import 'package:nivio/services/scrapers/animepahe/animepahe_scraper.dart';

class StreamingService {
  final AnimepaheScraperService animepaheScraper;

  StreamingService(this.animepaheScraper);

  static const List<String> _premiumProviders = [
    'VidUp (FAST)',
    'VidLink',
    'VidCore (ACTIVE)',
    'VidPlus',
  ];

  static const List<String> _standardProviders = [];

  // For anime, Animepahe is the primary (index 0) provider
  static const List<String> _animeProviders = [
    'Animepahe (NATIVE)',
    ..._premiumProviders,
  ];

  static List<String> get _allProviders => [..._premiumProviders, ..._standardProviders];

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
      appDebugLog(
        'fetchStreamUrl: media=${media.id}, S${season}E$episode, providerIdx=$providerIndex',
      );

      final isAnime = _isAnimeMedia(media);
      final providersList = isAnime ? _animeProviders : _allProviders;

      if (providerIndex < 0 || providerIndex >= providersList.length) {
        appDebugLog('All providers exhausted or removed');
        return null;
      }

      final providerName = providersList[providerIndex];
      
      // Handle Native Animepahe
      if (providerName == 'Animepahe (NATIVE)') {
        final streamUrl = await animepaheScraper.fetchStreamUrl(
          media.title ?? media.name ?? '', 
          season, 
          episode,
          subDub: subDubPreference,
        );
        
        if (streamUrl != null) {
          return StreamResult(
            url: streamUrl,
            quality: 'Auto',
            provider: providerName,
            isM3U8: streamUrl.contains('.m3u8'),
            headers: {
              'Referer': 'https://kwik.cx/',
              'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36'
            },
          );
        } else {
          return null; // Fallback to next provider handled by PlayerScreen
        }
      }

      // Handle standard 7reels providers
      final isTv = media.mediaType.toLowerCase() == 'tv' || 
                   media.firstAirDate != null || 
                   (media.name != null && media.name!.isNotEmpty && (media.title == null || media.title!.isEmpty));
      final id = media.id.toString();

      String url = '';

      switch (providerName) {
        case 'VidUp (FAST)':
          url = isTv ? 'https://vidup.to/tv/$id/$season/$episode' : 'https://vidup.to/movie/$id';
          break;
        case 'VidCore (ACTIVE)':
          url = isTv ? 'https://vidcore.net/tv/$id/$season/$episode' : 'https://vidcore.net/movie/$id';
          break;
        case 'VidEasy (HD)':
          url = isTv ? 'https://videasy.net/tv/$id/$season/$episode' : 'https://videasy.net/movie/$id';
          break;
        case 'VidPlus':
          url = isTv ? 'https://player.vidplus.to/embed/tv/$id/$season/$episode' : 'https://player.vidplus.to/embed/movie/$id';
          break;
        case 'VidsrcO':
          url = isTv ? 'https://vidsrco.net/embed/tv?tmdb=$id&season=$season&episode=$episode' : 'https://vidsrco.net/embed/movie?tmdb=$id';
          break;
        case 'AdRock':
          url = isTv ? 'https://vidrock.net/embed/tv/$id/$season/$episode' : 'https://vidrock.net/embed/movie/$id';
          break;
        case 'VidNest':
          url = isTv ? 'https://vidnest.fun/embed/tv/$id/$season/$episode' : 'https://vidnest.fun/embed/movie/$id';
          break;
        case 'VidLink':
          url = isTv ? 'https://vidlink.pro/tv/$id/$season/$episode' : 'https://vidlink.pro/movie/$id';
          break;
        case 'Vidify':
          url = isTv ? 'https://vidify.top/embed/tv/$id/$season/$episode' : 'https://vidify.top/embed/movie/$id';
          break;
        case 'Vidzee':
          url = isTv ? 'https://player.vidzee.net/embed/tv/$id/$season/$episode' : 'https://player.vidzee.net/embed/movie/$id';
          break;
        case 'MoviesClub':
          url = isTv ? 'https://moviesapi.club/tv/$id-$season-$episode' : 'https://moviesapi.club/movie/$id';
          break;
        case '2Embed':
          url = isTv ? 'https://www.2embed.cc/embedtv/$id&s=$season&e=$episode' : 'https://www.2embed.cc/embed/$id';
          break;
        case 'MultiEmbed':
          url = isTv ? 'https://multiembed.mo/embed/tv/$id/$season/$episode' : 'https://multiembed.mo/embed/movie/$id';
          break;
        default:
          return null;
      }

      appDebugLog('Generated Iframe URL: $url');

      return StreamResult(
        url: url,
        quality: 'Auto',
        provider: providerName,
        headers: {},
      );

    } catch (e) {
      appDebugLog('Error in fetchStreamUrl: $e');
      return null;
    }
  }
  
  static bool _isAnimeMedia(SearchResult media) {
    if (media.originalLanguage == 'ja') return true;
    return false;
  }

  static int totalProvidersFor({required bool isAnime}) {
    return isAnime ? _animeProviders.length : _allProviders.length;
  }

  static String getProviderName(int index, {required bool isAnime}) {
    final list = isAnime ? _animeProviders : _allProviders;
    if (index >= 0 && index < list.length) {
      return list[index];
    }
    return 'Unknown';
  }

  static bool isDirectStream(int providerIndex, {required bool isAnime}) {
    return false; // All providers, including Animepahe, now use WebView fallback for stability
  }
}
