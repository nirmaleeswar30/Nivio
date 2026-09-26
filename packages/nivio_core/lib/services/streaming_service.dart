import 'package:flutter/material.dart';
import 'package:nivio/widgets/torrent_picker_sheet.dart';
import 'package:nivio/models/search_result.dart';
import 'package:nivio/models/stream_result.dart';
import 'package:nivio/core/debug_log.dart';
import 'package:nivio/services/scrapers/animetsu/animetsu_scraper.dart';
import 'package:nivio/services/scrapers/newtv/newtv_scraper.dart';

import 'package:nivio/services/scrapers/streamflix/streamflix_scraper.dart';
import 'package:nivio/services/scrapers/moviebox/moviebox_scraper.dart';
import 'package:nivio/services/scrapers/castletv/castletv_scraper.dart';
import 'package:nivio/services/scrapers/vidrock/vidrock_scraper.dart';
import 'package:nivio/services/tmdb_service.dart';
import 'package:nivio/services/scrapers/miruro/miruro_scraper.dart';
import 'package:nivio/services/scrapers/animex/animex_scraper.dart';
import 'package:nivio/services/torrent/torrent_stream_service.dart';
import 'package:nivio/services/torrent/torrent_models.dart';
import 'package:nivio/services/torrent/media_torrent_models.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nivio/providers/settings_providers.dart';

class StreamingService {
  final TmdbService tmdbService;
  final AnimetsuScraperService animetsuScraper;
  final NetMirrorScraperService netMirrorScraper;
  final MiruroScraperService miruroScraper;
  final AnimexScraperService animexScraper;
  final StreamFlixScraperService streamFlixScraper;
  final MovieBoxScraperService movieBoxScraper;
  final CastleTvScraperService castleTvScraper;
  final VidRockScraperService vidRockScraper;
  final TorrentStreamService torrentStreamService;
  final Ref ref;

  StreamingService({
    required this.tmdbService,
    required this.animetsuScraper,
    required this.netMirrorScraper,
    required this.miruroScraper,
    required this.animexScraper,
    required this.streamFlixScraper,
    required this.movieBoxScraper,
    required this.castleTvScraper,
    required this.vidRockScraper,
    required this.torrentStreamService,
    required this.ref,
  });

  static const List<String> _premiumProviders = [
    'Nivio',
    'StreamFlix',
    'MovieBox',
    'CastleTV',
    'VidRock',
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
    
    appDebugLog('🔧 [FLOW] prepareProviders START (tmdbId=$tmdbId, S${season}E$episode, audio=$subDubPreference)');
    // Fetch dynamically in parallel
    final results = await Future.wait([
      miruroScraper.fetchAvailableServers(tmdbId: tmdbId),
      animexScraper.fetchAvailableServers(
        tmdbId: tmdbId,
        episode: episode,
        preferredAudio: subDubPreference == 'dub' ? 'english' : 'japanese',
      ),
    ]);
    appDebugLog('🔧 [FLOW] prepareProviders Future.wait DONE');

    final miruroResult = results[0];
    final animexResult = results[1];

    appDebugLog('🔧 [FLOW] Miruro servers: $miruroResult');
    appDebugLog('🔧 [FLOW] Animex servers: $animexResult');

    if (miruroResult.isNotEmpty) {
      const preferredMiruroOrder = ['zoro', 'gogo', 'pahe', 'marin'];
      miruroResult.sort((a, b) {
        final aLower = a.toLowerCase();
        final bLower = b.toLowerCase();
        if (aLower == 'bonk') return 1;
        if (bLower == 'bonk') return -1;
        final aIdx = preferredMiruroOrder.indexOf(aLower);
        final bIdx = preferredMiruroOrder.indexOf(bLower);
        if (aIdx != -1 && bIdx != -1) return aIdx.compareTo(bIdx);
        if (aIdx != -1) return -1;
        if (bIdx != -1) return 1;
        return aLower.compareTo(bLower);
      });
      _dynamicMiruroServers = miruroResult.map((id) => 'Miruro ($id)').toList();
    }
    if (animexResult.isNotEmpty) {
      const preferredAnimexOrder = ['mimi', 'zoro', 'gogo', 'pahe'];
      animexResult.sort((a, b) {
        final aLower = a.toLowerCase();
        final bLower = b.toLowerCase();
        if (aLower == 'bonk') return 1;
        if (bLower == 'bonk') return -1;
        final aIdx = preferredAnimexOrder.indexOf(aLower);
        final bIdx = preferredAnimexOrder.indexOf(bLower);
        if (aIdx != -1 && bIdx != -1) return aIdx.compareTo(bIdx);
        if (aIdx != -1) return -1;
        if (bIdx != -1) return 1;
        return aLower.compareTo(bLower);
      });
      _dynamicAnimexServers = animexResult.map((id) => 'Animex ($id)').toList();
    }
    final ordered = _animeProviders;
    appDebugLog(
      '🔧 [FLOW] prepareProviders END — pref=${ref.read(preferredAnimeSourceProvider)} '
      'total providers: ${ordered.length} → '
      '${[for (var i = 0; i < ordered.length; i++) '$i:${ordered[i]}'].join(', ')}',
    );
  }

  // Dynamic getter for anime providers based on user preference
  List<String> get _animeProviders {
    final pref = ref.read(preferredAnimeSourceProvider);
    
    final miruroServers = _dynamicMiruroServers; 
    final animexServers = _dynamicAnimexServers;
    final animetsuServers = [
      'Animetsu (Auto)',
      'Animetsu (Koto)',
      'Animetsu (DB)',
      'Animetsu (Kari)',
      'Animetsu (Flow)',
      'Animetsu (Zuri)',
      'Animetsu (Gojo)',
      'Animetsu (Mega)',
    ];

    // P2P torrent streaming (Hayase-style) is offered first for anime — it
    // yields the highest-quality releases when peers are available.
    final torrentEnabled = ref.read(enableTorrentsProvider);
    final nyaaEnabled = ref.read(torrentNyaaEnabledProvider);
    final torrent = (torrentEnabled && nyaaEnabled) ? ['Nivio Torrents'] : <String>[];

    if (pref == 'Miruro') {
      return [...torrent, ...miruroServers, ...animexServers, ...animetsuServers];
    } else if (pref == 'Animex') {
      return [...torrent, ...animexServers, ...miruroServers, ...animetsuServers];
    } else { // Animetsu
      return [...torrent, ...animetsuServers, ...miruroServers, ...animexServers];
    }
  }

  List<String> get _allProviders {
    final torrentEnabled = ref.read(enableTorrentsProvider);
    final torrentioEnabled = ref.read(torrentTorrentioEnabledProvider);
    final pirateBayEnabled = ref.read(torrentPirateBayEnabledProvider);
    final hasSource = torrentioEnabled || pirateBayEnabled;
    final torrent = (torrentEnabled && hasSource) ? ['Nivio Torrents'] : <String>[];
    return [...torrent, ..._premiumProviders, ..._standardProviders];
  }

  /// Shows the torrent picker, starts the chosen release, and remembers its
  /// release group as the binge preference for the series. Returns null if the
  /// user cancels.
  Future<TorrentStreamHandle?> _pickTorrentInteractively(
    SearchResult media,
    int episode,
    int season,
    int? absoluteEpisode,
    String resolution,
    void Function(String)? onStatusUpdate,
    BuildContext context,
  ) async {
    final selection = await TorrentPickerSheet.show(
      context,
      media: media,
      initialEpisode: episode,
      initialSeason: season,
      initialAbsoluteEpisode: absoluteEpisode,
      initialResolution: resolution,
      torrentStreamService: torrentStreamService,
      onStatusUpdate: onStatusUpdate,
    );
    if (selection == null) return null;
    final ep = selection.$2 is AnimeQuery
        ? (selection.$2 as AnimeQuery).episode
        : (selection.$2 as MediaTorrentQuery).episode ?? 1;
    final handle = await torrentStreamService.startTorrent(
      selection.$1,
      selection.$2,
      ep,
      onStatusUpdate,
    );
    await torrentStreamService.rememberReleaseGroup(media.id, selection.$1);
    return handle;
  }

  Future<StreamResult?> fetchStreamUrl({
    required SearchResult media,
    int season = 1,
    int episode = 1,
    int? absoluteEpisode,
    String? preferredQuality,
    int providerIndex = 0,
    bool autoSkipIntro = true,
    String subDubPreference = 'sub',
    String? preferredAudio,
    void Function(String)? onStatusUpdate,
    BuildContext? context,
    bool binge = false,
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
      appDebugLog('fetchStreamUrl: providerIdx=$providerIndex → "$providerName"');

      // Handle Nivio Torrents (embedded rqbit P2P streaming)
      if (providerName == 'Nivio Torrents') {
        final resMatch =
            preferredQuality == null ? null : RegExp(r'\d{3,4}').firstMatch(preferredQuality);
        final resolution = resMatch?.group(0) ?? '1080';

        TorrentStreamHandle? handle;
        if (binge) {
          // Binge mode: never show the picker. Use the prefetched next episode
          // if it's ready, else the season-pack fast path (next episode already
          // inside the streaming torrent), then a silent same-release-group
          // resolve; fall back to the picker only if all fail and we have a context.
          handle = torrentStreamService.consumePrefetch(episode);
          handle ??= await torrentStreamService.nextEpisodeInActiveTorrent(
            episode: episode,
            season: season,
            absoluteEpisode: absoluteEpisode,
          );
          if (handle == null) {
            final group = await torrentStreamService.recallReleaseGroup(media.id);
            handle = await torrentStreamService.resolveStream(
              media: media,
              episode: episode,
              season: season,
              resolution: resolution,
              absoluteEpisode: absoluteEpisode,
              preferredGroup: group,
              onStatus: onStatusUpdate,
            );
          }
          if (handle == null && context != null) {
            handle = await _pickTorrentInteractively(
              media, episode, season, absoluteEpisode, resolution, onStatusUpdate, context,
            );
          }
        } else if (context != null) {
          handle = await _pickTorrentInteractively(
            media, episode, season, absoluteEpisode, resolution, onStatusUpdate, context,
          );
          if (handle == null) return null; // user cancelled
        } else {
          // Silent / background mode
          handle = await torrentStreamService.resolveStream(
            media: media,
            episode: episode,
            season: season,
            resolution: resolution,
            absoluteEpisode: absoluteEpisode,
            onStatus: onStatusUpdate,
          );
        }

        if (handle == null) return null;
        return StreamResult(
          url: handle.url,
          quality: handle.resolution != null ? '${handle.resolution}p' : 'Auto',
          provider: 'Nivio Torrents',
          headers: const {},
        );
      }

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
        ).timeout(const Duration(seconds: 6), onTimeout: () => null);
        return streamResult;
      }


      // Handle Animetsu
      if (providerName.startsWith('Animetsu')) {
        String server = 'auto';
        if (providerName.contains('Koto')) {
          server = 'koto';
        } else if (providerName.contains('DB')) {
          server = 'db';
        } else if (providerName.contains('Kari')) {
          server = 'kari';
        } else if (providerName.contains('Flow')) {
          server = 'flow';
        } else if (providerName.contains('Zuri')) {
          server = 'zuri';
        } else if (providerName.contains('Gojo')) {
          server = 'gojo';
        } else if (providerName.contains('Mega')) {
          server = 'mega';
        } else if (providerName.contains('AniChan')) {
          server = 'koto';
        } else if (providerName.contains('AnimeKai')) {
          server = 'koto';
        } else if (providerName.contains('AniDB')) {
          server = 'db';
        }

        final streamResult = await animetsuScraper.fetchStreamUrl(
          tmdbId: media.id.toString(), // Anime media ID from Anilist
          title: media.title ?? media.name ?? '',
          mediaType: isAnimeMedia(media) ? 'anime' : media.mediaType,
          year: media.releaseDate?.split('-').firstOrNull ?? media.firstAirDate?.split('-').firstOrNull,
          season: season,
          episode: episode,
          preferredAudio: preferredAudio ?? (subDubPreference == 'dub' ? 'english' : 'japanese'),
          server: server,
        ).timeout(const Duration(seconds: 6), onTimeout: () => null);
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
        ).timeout(const Duration(seconds: 6), onTimeout: () => null);
      }

      // Handle StreamFlix
      if (providerName == 'StreamFlix') {
        final tmdbId = media.id.toString();
        final title = media.title ?? media.name ?? '';
        final type = isAnimeMedia(media) ? 'tv' : media.mediaType;
        final year = media.releaseDate?.split('-').firstOrNull ?? media.firstAirDate?.split('-').firstOrNull;
        return await streamFlixScraper.fetchStreamUrl(
          tmdbId: tmdbId,
          title: title,
          mediaType: type,
          year: year,
          season: season,
          episode: episode,
          preferredAudio: preferredAudio,
        ).timeout(const Duration(seconds: 6), onTimeout: () => null);
      }

      // Handle MovieBox
      if (providerName == 'MovieBox') {
        final tmdbId = media.id.toString();
        final title = media.title ?? media.name ?? '';
        final type = isAnimeMedia(media) ? 'tv' : media.mediaType;
        if (type == 'tv') {
          appDebugLog('MovieBox does not support TV shows.');
          return null;
        }
        final year = media.releaseDate?.split('-').firstOrNull ?? media.firstAirDate?.split('-').firstOrNull;
        return await movieBoxScraper.fetchStreamUrl(
          tmdbId: tmdbId,
          title: title,
          mediaType: type,
          year: year,
          season: season,
          episode: episode,
          preferredAudio: preferredAudio,
        ).timeout(const Duration(seconds: 6), onTimeout: () => null);
      }

      // Handle CastleTV
      if (providerName == 'CastleTV') {
        final tmdbId = media.id.toString();
        final title = media.title ?? media.name ?? '';
        final type = isAnimeMedia(media) ? 'tv' : media.mediaType;
        final year = media.releaseDate?.split('-').firstOrNull ?? media.firstAirDate?.split('-').firstOrNull;
        return await castleTvScraper.fetchStreamUrl(
          tmdbId: tmdbId,
          title: title,
          mediaType: type,
          year: year,
          season: season,
          episode: episode,
          preferredAudio: preferredAudio,
        ).timeout(const Duration(seconds: 6), onTimeout: () => null);
      }

      // Handle VidRock (direct HLS/MP4 via AES-GCM decrypted sources)
      if (providerName == 'VidRock') {
        final tmdbId = media.id.toString();
        final title = media.title ?? media.name ?? '';
        final type = isAnimeMedia(media) ? 'tv' : media.mediaType;
        final year = media.releaseDate?.split('-').firstOrNull ?? media.firstAirDate?.split('-').firstOrNull;
        return await vidRockScraper.fetchStreamUrl(
          tmdbId: tmdbId,
          title: title,
          mediaType: type,
          year: year,
          season: season,
          episode: episode,
          preferredAudio: preferredAudio,
        ).timeout(const Duration(seconds: 6), onTimeout: () => null);
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
    if (providerName == 'Nivio Torrents') return true; // localhost HLS-like stream
    if (['Nivio', 'StreamFlix', 'MovieBox', 'CastleTV', 'VidRock'].contains(providerName)) return true;
    if (providerName.startsWith('Animetsu') || providerName.startsWith('Miruro') || providerName.startsWith('Animex')) return true;
    return false; // All other providers use WebView fallback
  }

  bool isDownloadable(int providerIndex, {required bool isAnime}) {
    final providerName = getProviderName(providerIndex, isAnime: isAnime);
    // These providers yield raw direct streams which our custom downloader can parse and concatenate
    if (['Nivio', 'StreamFlix', 'MovieBox', 'CastleTV', 'VidRock'].contains(providerName)) return true;
    if (providerName.startsWith('Animetsu') || providerName.startsWith('Miruro') || providerName.startsWith('Animex')) return true;
    
    // Iframe providers cannot be natively downloaded because we don't have the raw stream URL
    return false;
  }
}
