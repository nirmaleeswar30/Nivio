import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nivio/services/tmdb_service.dart';
import 'package:nivio/services/streaming_service.dart';
import 'package:nivio/services/watch_history_service.dart';
import 'package:nivio/services/cache_service.dart';

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

// Streaming service provider (vidsrc.cc, vidsrc.to, vidlink.pro)
final streamingServiceProvider = Provider((ref) => StreamingService());

final watchHistoryServiceProvider = Provider((ref) => WatchHistoryService());
