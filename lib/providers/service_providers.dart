import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nivio/services/tmdb_service.dart';
import 'package:nivio/services/streaming_service.dart';
import 'package:nivio/services/watch_history_service.dart';

// Service Providers
final tmdbServiceProvider = Provider((ref) => TmdbService());

// Streaming service provider (vidsrc.cc, vidsrc.to, vidlink.pro)
final streamingServiceProvider = Provider((ref) => StreamingService());

final watchHistoryServiceProvider = Provider((ref) => WatchHistoryService());
