import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nivio/services/tmdb_service.dart';
import 'package:nivio/services/scrapers/animetsu/animetsu_scraper.dart';
import 'package:nivio/services/scrapers/miruro/miruro_scraper.dart';
import 'package:nivio/services/scrapers/animex/animex_scraper.dart';
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
final miruroScraperProvider = Provider<MiruroScraperService>((ref) {
  return MiruroScraperService();
});

final animexScraperProvider = Provider<AnimexScraperService>((ref) {
  return AnimexScraperService();
});

final streamingServiceProvider = Provider<StreamingService>((ref) => StreamingService(
  tmdbService: ref.read(tmdbServiceProvider),
  animetsuScraper: ref.read(animetsuScraperProvider),
  netMirrorScraper: ref.read(netMirrorScraperProvider),
  miruroScraper: ref.read(miruroScraperProvider),
  animexScraper: ref.read(animexScraperProvider),
  ref: ref,
));

final watchHistoryServiceProvider = Provider((ref) => WatchHistoryService());
