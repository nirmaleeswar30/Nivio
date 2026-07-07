import 'package:nivio/models/search_result.dart';
import 'package:nivio/models/stream_result.dart';
import 'package:nivio/core/debug_log.dart';
import 'package:nivio/services/scrapers/animetsu/animetsu_scraper.dart';
import 'package:nivio/services/scrapers/newtv/newtv_scraper.dart';

import 'package:nivio/services/tmdb_service.dart';

class StreamingService {
  final TmdbService tmdbService;
  final AnimetsuScraperService animetsuScraper;
  final NetMirrorScraperService netMirrorScraper;

  StreamingService({
    required this.tmdbService,
    required this.animetsuScraper,
    required this.netMirrorScraper,
  });

  static const List<String> _premiumProviders = [
    'NetMirror',
    'VidUp (FAST)',
    'VidLink',
    'VidCore (ACTIVE)',
    'VidPlus',
  ];

  static const List<String> _standardProviders = [];

  // For anime, Animepahe is the primary (index 0) provider
  static const List<String> _animeProviders = [
    'Animetsu',
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
    String? preferredAudio,
    void Function(String)? onStatusUpdate,
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
      
            // Handle Animetsu
      if (providerName == 'Animetsu') {
        final streamResult = await animetsuScraper.fetchStreamUrl(
          tmdbId: media.id.toString(), // Anime media ID from Anilist
          title: media.title ?? media.name ?? '',
          mediaType: _isAnimeMedia(media) ? 'anime' : media.mediaType,
          year: media.releaseDate?.split('-').firstOrNull ?? media.firstAirDate?.split('-').firstOrNull,
          season: season,
          episode: episode,
          preferredAudio: preferredAudio ?? (subDubPreference == 'dub' ? 'english' : 'japanese'),
        );
        return streamResult;
      }

      // Handle NewTV
      // Handle NetMirror
      if (providerName == 'NetMirror') {
        final tmdbId = media.id.toString();
        final title = media.title ?? media.name ?? '';
        final type = _isAnimeMedia(media) ? 'tv' : media.mediaType;
        final year = media.releaseDate?.split('-').firstOrNull ?? media.firstAirDate?.split('-').firstOrNull;
        
        // Use preferredAudio if provided, else fallback to Anime's subDub logic for english/japanese
        final audio = preferredAudio ?? (subDubPreference == 'dub' ? 'english' : 'japanese');

        return await netMirrorScraper.fetchStreamUrl(
          tmdbId: tmdbId, 
          title: title, 
          mediaType: type, 
          year: year, 
          season: season, 
          episode: episode, 
          preferredAudio: audio
        );
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
    if (media.mediaType == 'anime') return true;
    if (media.mediaType == 'tv' && media.originalLanguage == 'ja') return true;
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
    if (providerName == 'NetMirror') return true;
    if (providerName == 'Animetsu') return true;
    return false; // All other providers use WebView fallback
  }

  static bool isDownloadable(int providerIndex, {required bool isAnime}) {
    final providerName = getProviderName(providerIndex, isAnime: isAnime);
    // NewTV provides M3U8 streams which our custom downloader can parse and concatenate
    if (providerName == 'NetMirror') return true;
    if (providerName == 'Animetsu') return true;
    
    // Iframe providers cannot be natively downloaded because we don't have the raw stream URL
    return false;
  }
}
