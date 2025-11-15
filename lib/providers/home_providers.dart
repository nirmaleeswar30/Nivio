import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nivio/providers/service_providers.dart';

// Featured Content Provider (mixed regional + general trending for hero slider)
final featuredContentProvider = FutureProvider<List<dynamic>>((ref) async {
  final tmdbService = ref.watch(tmdbServiceProvider);
  
  // Fetch all content types in parallel
  final results = await Future.wait([
    tmdbService.getTrending('all', 'day'),           // General trending
    tmdbService.getTrendingAnime(),                   // Trending anime
    tmdbService.getTrendingByLanguage('movie', 'ta'), // Trending Tamil
    tmdbService.getTrendingByLanguage('movie', 'te'), // Trending Telugu
    tmdbService.getTrendingByLanguage('movie', 'hi'), // Trending Hindi
    tmdbService.getTrendingByLanguage('tv', 'ko'),    // Trending Korean
  ]);
  
  // Combine all results and shuffle for variety
  final allContent = <dynamic>[];
  for (final list in results) {
    allContent.addAll(list.take(3)); // Take top 3 from each category
  }
  
  // Shuffle to mix regional and general content
  allContent.shuffle();
  
  return allContent.take(10).toList(); // Return top 10 for slider
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
