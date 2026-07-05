import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nivio/providers/service_providers.dart';

// Featured Content Provider (mixed regional + general trending for hero slider)
// OPTIMIZED: Just use trending 'all' for instant load, let stale-while-revalidate handle freshness
final featuredContentProvider = FutureProvider<List<dynamic>>((ref) async {
  final tmdbService = ref.watch(tmdbServiceProvider);
  final anilist = ref.watch(aniListServiceProvider);

  // Fast path: Just get general trending and anime trending
  final results = await Future.wait([
    tmdbService.getTrending('all', 'day'),
    anilist.getTrendingAnime().then((r) => r.results),
  ]);
  
  final trending = results[0];
  final animeTrending = results[1];

  final interleaved = <dynamic>[];
  for (int i = 0; i < 5; i++) {
    if (i < trending.length) interleaved.add(trending[i]);
    if (i < animeTrending.length) interleaved.add(animeTrending[i]);
  }

  return interleaved;
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
