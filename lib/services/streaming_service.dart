import 'package:nivio/models/search_result.dart';
import 'package:nivio/models/stream_result.dart';
import 'package:nivio/core/debug_log.dart';
import 'package:nivio/services/scrapers/animepahe/animepahe_scraper.dart';
import 'package:nivio/services/scrapers/newtv/newtv_scraper.dart';

class StreamingService {
  final AnimepaheScraperService animepaheScraper;
  final NewTvScraperService newTvNetflixScraper;
  final NewTvScraperService newTvPrimeScraper;
  final NewTvScraperService newTvHotstarScraper;
  final NewTvScraperService newTvDisneyScraper;

  StreamingService({
    required this.animepaheScraper,
    required this.newTvNetflixScraper,
    required this.newTvPrimeScraper,
    required this.newTvHotstarScraper,
    required this.newTvDisneyScraper,
  });

  static const List<String> _premiumProviders = [
    'NewTV (Auto)',
    'NewTV (Netflix)',
    'NewTV (Hotstar)',
    'NewTV (Prime Video)',
    'NewTV (Disney+)',
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
        final streamResult = await animepaheScraper.fetchStreamUrl(
          media.title ?? media.name ?? '', 
          season, 
          episode,
          subDub: subDubPreference,
        );
        
        return streamResult; // AnimepaheScraper natively returns StreamResult
      }

      // Handle NewTV
      if (providerName.startsWith('NewTV')) {
        final tmdbId = media.id.toString();
        final title = media.title ?? media.name ?? '';
        final type = _isAnimeMedia(media) ? 'tv' : media.mediaType;
        final year = media.releaseDate?.split('-').firstOrNull ?? media.firstAirDate?.split('-').firstOrNull;
        final audio = subDubPreference == 'dub' ? 'english' : 'japanese';

        if (providerName == 'NewTV (Auto)') {
          // Parallel fetch from all 4 providers
          final results = await Future.wait([
            newTvNetflixScraper.fetchStreamUrl(tmdbId: tmdbId, title: title, mediaType: type, year: year, season: season, episode: episode, preferredAudio: audio),
            newTvHotstarScraper.fetchStreamUrl(tmdbId: tmdbId, title: title, mediaType: type, year: year, season: season, episode: episode, preferredAudio: audio),
            newTvPrimeScraper.fetchStreamUrl(tmdbId: tmdbId, title: title, mediaType: type, year: year, season: season, episode: episode, preferredAudio: audio),
            newTvDisneyScraper.fetchStreamUrl(tmdbId: tmdbId, title: title, mediaType: type, year: year, season: season, episode: episode, preferredAudio: audio),
          ]);
          // Return the first successful result
          return results.firstWhere((r) => r != null, orElse: () => null);
        } else if (providerName == 'NewTV (Netflix)') {
          return await newTvNetflixScraper.fetchStreamUrl(tmdbId: tmdbId, title: title, mediaType: type, year: year, season: season, episode: episode, preferredAudio: audio);
        } else if (providerName == 'NewTV (Hotstar)') {
          return await newTvHotstarScraper.fetchStreamUrl(tmdbId: tmdbId, title: title, mediaType: type, year: year, season: season, episode: episode, preferredAudio: audio);
        } else if (providerName == 'NewTV (Prime Video)') {
          return await newTvPrimeScraper.fetchStreamUrl(tmdbId: tmdbId, title: title, mediaType: type, year: year, season: season, episode: episode, preferredAudio: audio);
        } else if (providerName == 'NewTV (Disney+)') {
          return await newTvDisneyScraper.fetchStreamUrl(tmdbId: tmdbId, title: title, mediaType: type, year: year, season: season, episode: episode, preferredAudio: audio);
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
    final providerName = getProviderName(providerIndex, isAnime: isAnime);
    if (providerName.startsWith('NewTV')) return true;
    if (providerName == 'Animepahe (NATIVE)') return true;
    return false; // All other providers use WebView fallback
  }

  static bool isDownloadable(int providerIndex, {required bool isAnime}) {
    final providerName = getProviderName(providerIndex, isAnime: isAnime);
    // NewTV provides M3U8 streams which our custom downloader can parse and concatenate
    if (providerName.startsWith('NewTV')) return true;
    
    // Animepahe returns Kwik embed URLs which we can extract via WebView
    if (providerName == 'Animepahe (NATIVE)') return true;
    
    // Iframe providers cannot be natively downloaded because we don't have the raw stream URL
    return false;
  }
}
