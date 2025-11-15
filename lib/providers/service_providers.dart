import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nivio/services/tmdb_service.dart';
import 'package:nivio/services/braflix_service.dart';
import 'package:nivio/services/watch_history_service.dart';

// Service Providers
final tmdbServiceProvider = Provider((ref) => TmdbService());

// Generic video source service provider (placeholder for future implementations)
final videoServiceProvider = Provider((ref) => BraflixService());

final watchHistoryServiceProvider = Provider((ref) => WatchHistoryService());
