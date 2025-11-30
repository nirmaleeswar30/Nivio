import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/watchlist_item.dart';
import '../services/watchlist_service.dart';
import 'auth_provider.dart';

/// Provider for WatchlistService
final watchlistServiceProvider = Provider<WatchlistService>((ref) {
  final authService = ref.watch(authServiceProvider);
  return WatchlistService(authService);
});

/// State notifier for watchlist changes to trigger UI updates
class WatchlistNotifier extends StateNotifier<int> {
  WatchlistNotifier() : super(0);
  
  void refresh() => state++;
}

final watchlistRefreshProvider = StateNotifierProvider<WatchlistNotifier, int>((ref) {
  return WatchlistNotifier();
});

/// Provider for all watchlist items
final watchlistProvider = Provider<List<WatchlistItem>>((ref) {
  // Watch the refresh provider to rebuild when watchlist changes
  ref.watch(watchlistRefreshProvider);
  final service = ref.watch(watchlistServiceProvider);
  return service.getAllItems();
});

/// Provider to check if a specific item is in watchlist
final isInWatchlistProvider = Provider.family<bool, int>((ref, mediaId) {
  // Watch the refresh provider to rebuild when watchlist changes
  ref.watch(watchlistRefreshProvider);
  final service = ref.watch(watchlistServiceProvider);
  return service.isInWatchlist(mediaId);
});

/// Provider for watchlist count
final watchlistCountProvider = Provider<int>((ref) {
  // Watch the refresh provider to rebuild when watchlist changes
  ref.watch(watchlistRefreshProvider);
  final service = ref.watch(watchlistServiceProvider);
  return service.count;
});
