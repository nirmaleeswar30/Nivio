import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nivio/models/watch_history.dart';
import 'package:nivio/providers/service_providers.dart';

// Watch history list provider (with auto-refresh)
final watchHistoryProvider = StreamProvider<List<WatchHistory>>((ref) async* {
  final service = ref.watch(watchHistoryServiceProvider);
  await service.init();
  
  // Initial load
  yield await service.getAllHistory();
  
  // Refresh every 2 seconds to pick up new additions
  while (true) {
    await Future.delayed(const Duration(seconds: 2));
    yield await service.getAllHistory();
  }
});

// Continue watching provider (with auto-refresh)
final continueWatchingProvider = StreamProvider<List<WatchHistory>>((ref) async* {
  final service = ref.watch(watchHistoryServiceProvider);
  await service.init();
  
  // Initial load
  yield await service.getContinueWatching();
  
  // Refresh every 2 seconds to pick up new additions
  while (true) {
    await Future.delayed(const Duration(seconds: 2));
    yield await service.getContinueWatching();
  }
});

// Get history for specific media
final mediaHistoryProvider = FutureProvider.family<WatchHistory?, int>((ref, tmdbId) async {
  final service = ref.watch(watchHistoryServiceProvider);
  await service.init();
  return await service.getHistory(tmdbId);
});
