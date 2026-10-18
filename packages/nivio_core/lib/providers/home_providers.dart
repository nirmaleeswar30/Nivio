import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nivio/providers/service_providers.dart';
import 'dart:ui';

const Map<int, String> _genreMap = {
  28: 'Action',
  12: 'Adventure',
  16: 'Animation',
  35: 'Comedy',
  80: 'Crime',
  99: 'Documentary',
  18: 'Drama',
  10751: 'Family',
  14: 'Fantasy',
  36: 'History',
  27: 'Horror',
  10402: 'Music',
  9648: 'Mystery',
  10749: 'Romance',
  878: 'Sci-Fi',
  10770: 'TV Movie',
  53: 'Thriller',
  10752: 'War',
  37: 'Western',
  10759: 'Action & Adventure',
  10762: 'Kids',
  10763: 'News',
  10764: 'Reality',
  10765: 'Sci-Fi & Fantasy',
  10766: 'Soap',
  10767: 'Talk',
  10768: 'War & Politics',
};

// Featured Content Provider (mixed regional + general trending for hero slider)
// OPTIMIZED: Just use trending 'all' for instant load, let stale-while-revalidate handle freshness
final featuredContentProvider = FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final tmdbService = ref.watch(tmdbServiceProvider);
  final anilist = ref.watch(aniListServiceProvider);

  // Fast path: Just get general trending and anime trending
  final results = await Future.wait([
    tmdbService.getTrending('all', 'day'),
    anilist.getTrendingAnimeForFeatured(),
  ]);
  
  final trending = results[0];
  final animeTrending = results[1] as List<Map<String, dynamic>>;

  final interleaved = <Map<String, dynamic>>[];
  for (int i = 0; i < 5; i++) {
    if (i < trending.length) {
      final item = trending[i];
      if (item is Map) {
        final id = item['id'] as int? ?? 0;
        final mediaType = (item['media_type'] ?? (item['title'] != null ? 'movie' : 'tv')).toString();
        
        // Resolve genres
        final genreIds = item['genre_ids'] as List<dynamic>? ?? [];
        final genresList = genreIds
            .whereType<num>()
            .map((gid) => _genreMap[gid.toInt()])
            .whereType<String>()
            .toList();

        final year = ((item['first_air_date'] ?? item['release_date'])?.toString().split('-').first ?? '').trim();

        interleaved.add({
          'id': id,
          'tmdb_id': id,
          'media_type': mediaType,
          'title': (item['title'] ?? item['name'] ?? 'Featured').toString(),
          'overview': (item['overview'] ?? '').toString(),
          'backdrop_path': (item['backdrop_path'] ?? item['poster_path'])?.toString(),
          'poster_path': (item['poster_path'] ?? item['backdrop_path'])?.toString(),
          'vote_average': (item['vote_average'] as num?)?.toDouble() ?? 0.0,
          'year': year,
          'genres': genresList,
          'format': mediaType == 'tv' ? 'TV Series' : 'Movie',
          'status': mediaType == 'tv' ? 'Releasing' : 'Released',
          'episodes': null,
          'season': null,
          'season_number': 1,
        });
      }
    }
    if (i < animeTrending.length) {
      final item = animeTrending[i];
      final titleMap = item['title'] as Map? ?? {};
      final title = titleMap['english'] ?? titleMap['romaji'] ?? 'Featured';
      
      final coverImage = item['coverImage'] as Map? ?? {};
      final backdrop = item['bannerImage'] as String? ?? coverImage['extraLarge'] ?? coverImage['large'];
      final poster = coverImage['extraLarge'] ?? coverImage['large'];
      
      final formatRaw = item['format'] as String? ?? 'TV';
      final format = formatRaw == 'MOVIE' ? 'Anime Movie' : 'Anime';
      
      final statusRaw = item['status'] as String? ?? '';
      final status = statusRaw == 'RELEASING' ? 'Releasing' : (statusRaw == 'FINISHED' ? 'Finished' : statusRaw);
      
      final seasonRaw = item['season'] as String? ?? '';
      final seasonYear = item['seasonYear'];
      
      final capitalizedSeason = seasonRaw.isNotEmpty 
          ? '${seasonRaw[0].toUpperCase()}${seasonRaw.substring(1).toLowerCase()}' 
          : '';
      
      final season = (capitalizedSeason.isNotEmpty && seasonYear != null)
          ? '$capitalizedSeason $seasonYear'
          : (seasonYear?.toString());

      int seasonNumber = 1;
      final fullTitleStr = title.toString();
      final seasonMatch = RegExp(r'\b(?:Season|Cour|Part)\s*(\d+)\b', caseSensitive: false).firstMatch(fullTitleStr) ??
          RegExp(r'\b(\d+)(?:st|nd|rd|th)\s+Season\b', caseSensitive: false).firstMatch(fullTitleStr);
      if (seasonMatch != null) {
        seasonNumber = int.tryParse(seasonMatch.group(1) ?? '') ?? 1;
      } else {
        final romanMatch = RegExp(r'\b(?:Season\s+)?(II|III|IV|V|VI|VII|VIII|IX|X)\b').firstMatch(fullTitleStr);
        if (romanMatch != null) {
          const romanMap = {'II': 2, 'III': 3, 'IV': 4, 'V': 5, 'VI': 6, 'VII': 7, 'VIII': 8, 'IX': 9, 'X': 10};
          seasonNumber = romanMap[romanMatch.group(1)!] ?? 1;
        }
      }

      final seasonBadge = seasonNumber > 1
          ? (season != null && season.isNotEmpty ? 'Season $seasonNumber · $season' : 'Season $seasonNumber')
          : season;

      interleaved.add({
        'id': item['id'] as int? ?? 0,
        'tmdb_id': null, // We'll search for logo using title
        'media_type': 'anime',
        'title': title.toString(),
        'overview': (item['description'] ?? '').toString().replaceAll(RegExp(r'<[^>]*>'), ''),
        'backdrop_path': backdrop,
        'poster_path': poster,
        'vote_average': (item['averageScore'] as num?)?.toDouble() != null ? item['averageScore'] / 10.0 : 0.0,
        'year': seasonYear?.toString() ?? '',
        'genres': (item['genres'] as List<dynamic>? ?? []).whereType<String>().toList(),
        'format': format,
        'status': status,
        'episodes': item['episodes'] as int?,
        'season': seasonBadge,
        'season_number': seasonNumber,
      });
    }
  }

  // Resolve logos and high-quality TMDB info for all items concurrently
  final enhancedItems = await Future.wait(interleaved.map((item) async {
    final mediaType = item['media_type'] as String;
    final id = item['id'] as int;
    final title = item['title'] as String;
    final year = item['year'] as String;
    
    if (mediaType == 'anime') {
      final tmdbInfo = await tmdbService.getMediaInfoByTitle(title, year: year);
      return {
        ...item,
        'logo_url': tmdbInfo?['logo_url'],
        if (tmdbInfo?['backdrop_path'] != null) 'backdrop_path': tmdbInfo!['backdrop_path'],
        if (tmdbInfo?['poster_path'] != null) 'poster_path': tmdbInfo!['poster_path'],
        if (tmdbInfo?['tmdb_id'] != null) 'tmdb_id': int.tryParse(tmdbInfo!['tmdb_id']!),
        // AniList banner/cover art carries no title text.
        'clean_backdrop': item['backdrop_path'],
      };
    } else {
      final images = await tmdbService.getMediaLogoAndBackdrop(id, mediaType);
      return {
        ...item,
        'logo_url': images['logo_url'],
        'clean_backdrop': images['clean_backdrop'],
      };
    }
  }));

  return enhancedItems;
});

// Trending Movies Provider
final trendingMoviesProvider = FutureProvider<List<dynamic>>((ref) async {
  final tmdbService = ref.watch(tmdbServiceProvider);
  return await tmdbService.getTrending('movie', 'day');
});

// Trending TV Shows Provider
final trendingTVShowsProvider = FutureProvider<List<dynamic>>((ref) async {
  final tmdbService = ref.watch(tmdbServiceProvider);
  return await tmdbService.getTrending('tv', 'day');
});

// Popular Movies Provider
final popularMoviesProvider = FutureProvider<List<dynamic>>((ref) async {
  final tmdbService = ref.watch(tmdbServiceProvider);
  return await tmdbService.getPopular('movie');
});

// Popular TV Shows Provider
final popularTVShowsProvider = FutureProvider<List<dynamic>>((ref) async {
  final tmdbService = ref.watch(tmdbServiceProvider);
  return await tmdbService.getPopular('tv');
});

// Top Rated Movies Provider
final topRatedMoviesProvider = FutureProvider<List<dynamic>>((ref) async {
  final tmdbService = ref.watch(tmdbServiceProvider);
  return await tmdbService.getTopRated('movie');
});

// Anime Provider (Popular Japanese Animation)
final animeProvider = FutureProvider<List<dynamic>>((ref) async {
  final anilist = ref.watch(aniListServiceProvider);
  final res = await anilist.getPopularAnime();
  return res.results;
});

// Trending Anime Provider
final trendingAnimeProvider = FutureProvider<List<dynamic>>((ref) async {
  final anilist = ref.watch(aniListServiceProvider);
  final res = await anilist.getTrendingAnime();
  return res.results;
});

// Latest Tamil OTT Releases Provider
final tamilMoviesProvider = FutureProvider<List<dynamic>>((ref) async {
  final tmdbService = ref.watch(tmdbServiceProvider);
  return await tmdbService.getLatestTamilOTT();
});

// Trending Tamil Movies Provider
final trendingTamilMoviesProvider = FutureProvider<List<dynamic>>((ref) async {
  final tmdbService = ref.watch(tmdbServiceProvider);
  return await tmdbService.getTrendingByLanguage('movie', 'ta');
});

// Popular Telugu Movies Provider
final teluguMoviesProvider = FutureProvider<List<dynamic>>((ref) async {
  final tmdbService = ref.watch(tmdbServiceProvider);
  return await tmdbService.getByLanguage('movie', 'te');
});

// Trending Telugu Movies Provider
final trendingTeluguMoviesProvider = FutureProvider<List<dynamic>>((ref) async {
  final tmdbService = ref.watch(tmdbServiceProvider);
  return await tmdbService.getTrendingByLanguage('movie', 'te');
});

// Popular Hindi Movies Provider
final hindiMoviesProvider = FutureProvider<List<dynamic>>((ref) async {
  final tmdbService = ref.watch(tmdbServiceProvider);
  return await tmdbService.getByLanguage('movie', 'hi');
});

// Trending Hindi Movies Provider
final trendingHindiMoviesProvider = FutureProvider<List<dynamic>>((ref) async {
  final tmdbService = ref.watch(tmdbServiceProvider);
  return await tmdbService.getTrendingByLanguage('movie', 'hi');
});

// Popular Korean Dramas Provider
final koreanDramasProvider = FutureProvider<List<dynamic>>((ref) async {
  final tmdbService = ref.watch(tmdbServiceProvider);
  return await tmdbService.getByLanguage('tv', 'ko');
});

// Trending Korean Dramas Provider
final trendingKoreanDramasProvider = FutureProvider<List<dynamic>>((ref) async {
  final tmdbService = ref.watch(tmdbServiceProvider);
  return await tmdbService.getTrendingByLanguage('tv', 'ko');
});

// Popular Malayalam Movies Provider
final malayalamMoviesProvider = FutureProvider<List<dynamic>>((ref) async {
  final tmdbService = ref.watch(tmdbServiceProvider);
  return await tmdbService.getByLanguage('movie', 'ml');
});

// Trending Malayalam Movies Provider
final trendingMalayalamMoviesProvider = FutureProvider<List<dynamic>>((ref) async {
  final tmdbService = ref.watch(tmdbServiceProvider);
  return await tmdbService.getTrendingByLanguage('movie', 'ml');
});

// Latest OTT Movies Provider (verified digital streaming releases)
final latestMoviesOttProvider = FutureProvider<List<dynamic>>((ref) async {
  final tmdbService = ref.watch(tmdbServiceProvider);
  return await tmdbService.getLatestMovieOTT();
});

// Latest OTT / TV Shows Provider (verified fresh digital TV releases)
final latestTvOttProvider = FutureProvider<List<dynamic>>((ref) async {
  final tmdbService = ref.watch(tmdbServiceProvider);
  return await tmdbService.getLatestTvOTT();
});

// Latest Anime Releases Provider (recently aired episodes in Japan)
final latestAnimeReleasesProvider = FutureProvider<List<dynamic>>((ref) async {
  final anilist = ref.watch(aniListServiceProvider);
  return await anilist.getLatestAiringAnime();
});

final ambientColorProvider = StateProvider<Color>((ref) => const Color(0xFF0D0F14));
