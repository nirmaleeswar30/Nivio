import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nivio/models/search_result.dart';
import 'package:nivio/providers/service_providers.dart';
import 'package:nivio/providers/watch_history_provider.dart';

typedef HomeRecommendations = ({String basedOn, List<SearchResult> items});

final latestWatchedIdProvider = Provider<String?>((ref) {
  final history = ref.watch(watchHistoryProvider).valueOrNull;
  if (history == null || history.isEmpty) return null;
  
  final sortedHistory = [...history]
    ..sort((a, b) => b.lastWatchedAt.compareTo(a.lastWatchedAt));
    
  final top5 = sortedHistory.take(5).map((e) => e.tmdbId).join('-');
  return top5;
});

final homeRecommendationsProvider = FutureProvider<HomeRecommendations?>((ref) async {
  // Only trigger a rebuild when the *composition* of the top 5 watched media changes!
  // This prevents infinite loops caused by continuous watch progress updates.
  final latestIdsHash = ref.watch(latestWatchedIdProvider);
  if (latestIdsHash == null) return null;

  // Read the history once without subscribing to its continuous updates
  final history = ref.read(watchHistoryProvider).valueOrNull;
  if (history == null || history.isEmpty) return null;

  final sortedHistory = [...history]
    ..sort((a, b) => b.lastWatchedAt.compareTo(a.lastWatchedAt));
  
  final top5 = sortedHistory.take(5).toList();
  final tmdbService = ref.read(tmdbServiceProvider);
  
  // Fetch recommendations for all 5 concurrently
  final futures = top5.map((item) => tmdbService.getRecommendations(item.tmdbId, item.mediaType));
  final resultsList = await Future.wait(futures);
  
  // Interleave the results to mix genres
  final interleaved = <SearchResult>[];
  final seenIds = <int>{}; // Prevent duplicates
  
  int maxLength = 0;
  for (final list in resultsList) {
    if (list.length > maxLength) maxLength = list.length;
  }
  
  for (int i = 0; i < maxLength; i++) {
    for (final list in resultsList) {
      if (i < list.length) {
        final item = list[i];
        if (!seenIds.contains(item.id)) {
          seenIds.add(item.id);
          interleaved.add(item);
        }
      }
    }
  }
  
  if (interleaved.isEmpty) return null;

  return (basedOn: 'Top Picks For You', items: interleaved);
});
