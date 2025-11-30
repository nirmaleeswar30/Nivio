import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:nivio/models/search_result.dart';
import 'package:nivio/models/stream_result.dart';
import 'package:nivio/services/anilist_service.dart';

/// Service for fetching streaming URLs from various providers
/// Supports: vidsrc.cc, vidsrc.to, vidlink.pro
class StreamingService {
  final AniListService _anilistService = AniListService();
  
  StreamingService();

  /// Get vidsrc.cc base URL based on platform
  /// Windows/Linux use v3, mobile uses v2
  static String get _vidsrcBaseUrl {
    if (kIsWeb) return 'https://vidsrc.cc/v2/embed';
    if (Platform.isWindows || Platform.isLinux) {
      return 'https://vidsrc.cc/v3/embed'; // v3 for desktop
    }
    return 'https://vidsrc.cc/v2/embed'; // v2 for mobile
  }

  /// Base URLs for streaming services (in priority order)
  List<Map<String, String>> get _providers => [
    {'name': 'vidsrc.cc', 'url': _vidsrcBaseUrl},
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
    bool autoSkipIntro = true, // Enable auto-skip for anime intros/outros
    String subDubPreference = 'sub', // 'sub' or 'dub' for anime
  }) async {
    try {
      if (providerIndex >= _providers.length) {
        print('❌ All providers exhausted');
        return null;
      }

      final provider = _providers[providerIndex];
      final String streamUrl;
      
      print('🔍 fetchStreamUrl called: media=${media.id}, season=$season, episode=$episode, provider=${provider['name']}');
      
      int? anilistId;
      
      // For vidsrc.cc TV shows, try to get AniList ID (only succeeds if it's actually anime)
      if (provider['name'] == 'vidsrc.cc' && media.mediaType == 'tv') {
        final title = media.name ?? media.title ?? '';
        final year = media.firstAirDate?.split('-').first ?? 
                     media.releaseDate?.split('-').first;
        
        // AniList will only return a result if it's actually anime in their database
        anilistId = await _anilistService.getAniListIdFromTMDB(
          title: title,
          year: year,
          tmdbId: media.id,
        );
        
        if (anilistId != null) {
          print('🎌 Anime detected! Using AniList ID: $anilistId');
        } else {
          print('📺 Not anime or not found in AniList, using regular TV format');
        }
      }
      
      // Construct URL based on media type and provider
      if (media.mediaType == 'movie') {
        // Movie URL formats:
        // vidsrc.cc: https://vidsrc.cc/v2/embed/movie/{tmdbId}?autoPlay=true
        // vidsrc.to: https://vidsrc.to/embed/movie/{tmdbId}
        // vidlink: https://vidlink.pro/movie/{tmdbId}?nextbutton=true
        if (provider['name'] == 'vidlink') {
          streamUrl = '${provider['url']}/movie/${media.id}?nextbutton=true';
        } else if (provider['name'] == 'vidsrc.cc') {
          streamUrl = '${provider['url']}/movie/${media.id}?autoPlay=true';
        } else {
          streamUrl = '${provider['url']}/movie/${media.id}';
        }
        print('🎬 Provider: ${provider['name']} | Movie URL: $streamUrl');
      } else {
        // TV show URL formats:
        // vidsrc.cc anime: https://vidsrc.cc/v2/embed/anime/ani{anilistId}/{episode}/sub?autoPlay=true
        // vidsrc.cc tv: https://vidsrc.cc/v2/embed/tv/{tmdbId}/{season}/{episode}?autoPlay=true
        // vidsrc.to: https://vidsrc.to/embed/tv/{tmdbId}/{season}/{episode}
        // vidlink: https://vidlink.pro/tv/{tmdbId}/{season}/{episode}?nextbutton=true
        if (provider['name'] == 'vidsrc.cc') {
          if (anilistId != null) {
            // Anime-specific URL with episode and sub/dub preference
            streamUrl = '${provider['url']}/anime/ani$anilistId/$episode/$subDubPreference?autoPlay=true';
            print('🎌 Provider: ${provider['name']} | Anime URL: $streamUrl (E$episode $subDubPreference)');
          } else {
            // Regular TV - include season and episode
            streamUrl = '${provider['url']}/tv/${media.id}/$season/$episode?autoPlay=true';
            print('📺 Provider: ${provider['name']} | TV URL: $streamUrl (S${season}E${episode})');
          }
        } else if (provider['name'] == 'vidlink') {
          streamUrl = '${provider['url']}/tv/${media.id}/$season/$episode?nextbutton=true';
          print('📺 Provider: ${provider['name']} | TV URL: $streamUrl (S${season}E${episode})');
        } else {
          streamUrl = '${provider['url']}/tv/${media.id}/$season/$episode';
          print('📺 Provider: ${provider['name']} | TV URL: $streamUrl (S${season}E${episode})');
        }
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


