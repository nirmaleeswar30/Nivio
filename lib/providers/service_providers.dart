import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nivio/services/tmdb_service.dart';
import 'package:nivio/services/scrapers/animepahe/animepahe_scraper.dart';
import 'package:nivio/services/streaming_service.dart';
import 'package:nivio/services/watch_history_service.dart';
import 'package:nivio/services/cache_service.dart';
import 'package:nivio/services/scrapers/newtv/newtv_scraper.dart';
import 'package:nivio/services/anilist_service.dart';

// Cache service provider
final cacheServiceProvider = Provider((ref) {
  final cache = CacheService();
  // Note: init() must be called before use, handled in main.dart
  return cache;
});

// Service Providers
final tmdbServiceProvider = Provider((ref) {
  final cache = ref.watch(cacheServiceProvider);
  return TmdbService(cache);
});

final aniListServiceProvider = Provider((ref) => AniListService());


// Streaming service provider (direct primary, embed fallback)
final streamingServiceProvider = Provider((ref) => StreamingService(
  tmdbService: ref.read(tmdbServiceProvider),
  animepaheScraper: ref.read(animepaheScraperProvider),
  newTvNetflixScraper: ref.read(newTvNetflixScraperProvider),
  newTvPrimeScraper: ref.read(newTvPrimeScraperProvider),
  newTvHotstarScraper: ref.read(newTvHotstarScraperProvider),
  newTvDisneyScraper: ref.read(newTvDisneyScraperProvider),
));

final watchHistoryServiceProvider = Provider((ref) => WatchHistoryService());
