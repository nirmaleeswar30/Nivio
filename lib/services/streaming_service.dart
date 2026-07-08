import 'package:nivio/models/search_result.dart';
import 'package:nivio/models/stream_result.dart';
import 'package:nivio/core/debug_log.dart';
import 'package:nivio/services/scrapers/animetsu/animetsu_scraper.dart';
import 'package:nivio/services/scrapers/newtv/newtv_scraper.dart';

import 'package:nivio/services/tmdb_service.dart';
import 'package:nivio/services/scrapers/miruro/miruro_scraper.dart';
import 'package:nivio/services/scrapers/animex/animex_scraper.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nivio/providers/settings_providers.dart';

class StreamingService {
  final TmdbService tmdbService;
  final AnimetsuScraperService animetsuScraper;
  final NetMirrorScraperService netMirrorScraper;
  final MiruroScraperService miruroScraper;
  final AnimexScraperService animexScraper;
  final Ref ref;

  StreamingService({
    required this.tmdbService,
    required this.animetsuScraper,
    required this.netMirrorScraper,
    required this.miruroScraper,
    required this.animexScraper,
    required this.ref,
  });

  static const List<String> _premiumProviders = [
    'Nivio',
    'VidUp (FAST)',
    'VidLink',
    'VidCore (ACTIVE)',
    'VidPlus',
  ];

  static const List<String> _standardProviders = [];

  List<String> _dynamicAnimexServers = ['Animex (Auto)'];
  List<String> _dynamicMiruroServers = ['Miruro (Auto)'];

  Future<void> prepareProviders({
    required SearchResult media,
    required int season,
    required int episode,
    required String subDubPreference,
  }) async {
    if (!isAnimeMedia(media)) return;

    final tmdbId = media.id.toString();
    
    // Fetch dynamically in parallel
    final results = await Future.wait([
      miruroScraper.fetchAvailableServers(tmdbId: tmdbId),
      animexScraper.fetchAvailableServers(
        tmdbId: tmdbId,
        episode: episode,
        preferredAudio: subDubPreference == 'dub' ? 'english' : 'japanese',
      ),
    ]);

    final miruroResult = results[0];
    final animexResult = results[1];

    if (miruroResult.isNotEmpty) {
      miruroResult.sort((a, b) {
        if (a.toLowerCase() == 'bonk') return -1;
        if (b.toLowerCase() == 'bonk') return 1;
        return 0;
      });
      _dynamicMiruroServers = miruroResult.map((id) => 'Miruro ($id)').toList();
    }
    if (animexResult.isNotEmpty) {
      animexResult.sort((a, b) {
        if (a.toLowerCase() == 'bonk') return -1;
        if (b.toLowerCase() == 'bonk') return 1;
        return 0;
      });
      _dynamicAnimexServers = animexResult.map((id) => 'Animex ($id)').toList();
    }
  }

  // Dynamic getter for anime providers based on user preference
  List<String> get _animeProviders {
    final pref = ref.read(preferredAnimeSourceProvider);
    
    final miruroServers = _dynamicMiruroServers; 
    final animexServers = _dynamicAnimexServers;
    final animetsuServers = [
      'Animetsu (Auto)',
      'Animetsu (Kite)',
      'Animetsu (Dio)',
      'Animetsu (Sage)',
      'Animetsu (Meg)',
    ];

    if (pref == 'Miruro') {
      return [...miruroServers, ...animexServers, ...animetsuServers];
    } else if (pref == 'Animex') {
      return [...animexServers, ...miruroServers, ...animetsuServers];
    } else { // Animetsu
      return [...animetsuServers, ...miruroServers, ...animexServers];
    }
  }

  List<String> get _allProviders => [..._premiumProviders, ..._standardProviders];

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

      final isAnime = isAnimeMedia(media);
      final providersList = isAnime ? _animeProviders : _allProviders;

      if (providerIndex < 0 || providerIndex >= providersList.length) {
        appDebugLog('All providers exhausted or removed');
        return null;
      }

      final providerName = providersList[providerIndex];
      
      // Handle Miruro
      if (providerName.startsWith('Miruro (')) {
        String server = providerName.substring('Miruro ('.length);
        if (server.endsWith(')')) server = server.substring(0, server.length - 1);
        
        if (server == 'Auto') server = 'zoro'; // Fallback if Auto

        final streamResult = await miruroScraper.fetchStreamUrl(
          tmdbId: media.id.toString(), // Anime media ID from Anilist
          season: season,
          episode: episode,
          preferredAudio: preferredAudio ?? (subDubPreference == 'dub' ? 'english' : 'japanese'),
          providerName: server,
        );
        return streamResult;
      }

      // Handle Animex
      if (providerName.startsWith('Animex (')) {
        String server = providerName.substring('Animex ('.length);
        if (server.endsWith(')')) server = server.substring(0, server.length - 1);
        
        if (server == 'Auto') server = 'mimi'; // Fallback if Auto

        final streamResult = await animexScraper.fetchStreamUrl(
          tmdbId: media.id.toString(), // Anime media ID from Anilist
          season: season,
          episode: episode,
          preferredAudio: preferredAudio ?? (subDubPreference == 'dub' ? 'english' : 'japanese'),
          providerName: server,
        );
        return streamResult;
      }

      // Handle Animetsu
      if (providerName.startsWith('Animetsu')) {
        String server = 'auto';
        if (providerName.contains('Kite')) server = 'kite';
        else if (providerName.contains('Dio')) server = 'dio';
        else if (providerName.contains('Sage')) server = 'sage';
        else if (providerName.contains('Meg')) server = 'meg';

        final streamResult = await animetsuScraper.fetchStreamUrl(
          tmdbId: media.id.toString(), // Anime media ID from Anilist
          title: media.title ?? media.name ?? '',
          mediaType: isAnimeMedia(media) ? 'anime' : media.mediaType,
          year: media.releaseDate?.split('-').firstOrNull ?? media.firstAirDate?.split('-').firstOrNull,
          season: season,
          episode: episode,
          preferredAudio: preferredAudio ?? (subDubPreference == 'dub' ? 'english' : 'japanese'),
          server: server,
        );
        return streamResult;
      }

      // Handle NewTV
      // Handle NetMirror
      if (providerName == 'Nivio') {
        final tmdbId = media.id.toString();
        final title = media.title ?? media.name ?? '';
        final type = isAnimeMedia(media) ? 'tv' : media.mediaType;
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
  
  static bool isAnimeMedia(SearchResult media) {
    if (media.mediaType == 'anime') return true;
    if ((media.mediaType == 'tv' || media.mediaType == 'movie') && media.originalLanguage == 'ja') return true;
    return false;
  }

  int totalProvidersFor({required bool isAnime}) {
    return isAnime ? _animeProviders.length : _allProviders.length;
  }

  String getProviderName(int index, {required bool isAnime}) {
    final list = isAnime ? _animeProviders : _allProviders;
    if (index >= 0 && index < list.length) {
      return list[index];
    }
    return 'Unknown';
  }

  bool isDirectStream(int providerIndex, {required bool isAnime}) {
    final providerName = getProviderName(providerIndex, isAnime: isAnime);
    if (providerName == 'Nivio') return true;
    if (providerName.startsWith('Animetsu') || providerName.startsWith('Miruro') || providerName.startsWith('Animex')) return true;
    return false; // All other providers use WebView fallback
  }

  bool isDownloadable(int providerIndex, {required bool isAnime}) {
    final providerName = getProviderName(providerIndex, isAnime: isAnime);
    // NewTV provides M3U8 streams which our custom downloader can parse and concatenate
    if (providerName == 'Nivio') return true;
    if (providerName.startsWith('Animetsu') || providerName.startsWith('Miruro') || providerName.startsWith('Animex')) return true;
    
    // Iframe providers cannot be natively downloaded because we don't have the raw stream URL
    return false;
  }
}
