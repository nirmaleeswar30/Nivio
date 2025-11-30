import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nivio/providers/service_providers.dart';

// Featured Content Provider (mixed regional + general trending for hero slider)
// OPTIMIZED: Just use trending 'all' for instant load, let stale-while-revalidate handle freshness
final featuredContentProvider = FutureProvider<List<dynamic>>((ref) async {
  final tmdbService = ref.watch(tmdbServiceProvider);
  
  // Fast path: Just get general trending (single API call)
  // This loads instantly from cache with stale-while-revalidate
  final trending = await tmdbService.getTrending('all', 'day');
  
  // Return top 10 immediately - no need to wait for 6 API calls
  return trending.take(10).toList();
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
  final tmdbService = ref.watch(tmdbServiceProvider);
  return await tmdbService.getAnime();
});

// Trending Anime Provider
final trendingAnimeProvider = FutureProvider<List<dynamic>>((ref) async {
  final tmdbService = ref.watch(tmdbServiceProvider);
  return await tmdbService.getTrendingAnime();
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
