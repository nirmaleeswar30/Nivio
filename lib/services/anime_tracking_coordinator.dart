import 'package:shared_preferences/shared_preferences.dart';

import 'package:nivio/core/debug_log.dart';
import 'package:nivio/models/anime_tracking_models.dart';
import 'package:nivio/models/watchlist_item.dart';
import 'package:nivio/services/anilist_auth_service.dart';
import 'package:nivio/services/mal_auth_service.dart';

/// Central coordinator managing anime synchronization across AniList and MyAnimeList.
class AnimeTrackingCoordinator {
  static final AnimeTrackingCoordinator instance =
      AnimeTrackingCoordinator._();
  AnimeTrackingCoordinator._();

  final AniListAuthService _aniList = AniListAuthService.instance;
  final MalAuthService _mal = MalAuthService.instance;

  DateTime? _lastSyncedAt;
  bool _isSyncing = false;

  DateTime? get lastSyncedAt => _lastSyncedAt;
  bool get isSyncing => _isSyncing;

  bool get hasAnyAccountConnected =>
      _aniList.isAuthenticated || _mal.isAuthenticated;

  /// Initialize underlying services and load sync metadata.
  Future<void> init() async {
    await _aniList.init();
    await _mal.init();

    try {
      final prefs = await SharedPreferences.getInstance();
      final lastSyncStr = prefs.getString('anime_tracking_last_synced_at');
      if (lastSyncStr != null && lastSyncStr.isNotEmpty) {
        _lastSyncedAt = DateTime.tryParse(lastSyncStr);
      }
    } catch (_) {}
  }

  /// Sync an anime episode watch progress to all connected services.
  Future<void> syncWatchProgress({
    int? anilistId,
    int? malId,
    required int episode,
    bool isCompleted = false,
  }) async {
    if (!hasAnyAccountConnected) return;

    try {
      final prefs = await SharedPreferences.getInstance();
      final autoSync = prefs.getBool('anime_auto_sync_progress') ?? true;
      if (!autoSync) return;
    } catch (_) {}

    final status = isCompleted
        ? AnimeWatchStatus.completed
        : AnimeWatchStatus.watching;

    if (_aniList.isAuthenticated && anilistId != null && anilistId > 0) {
      try {
        await _aniList.updateWatchProgress(
          anilistId: anilistId,
          episode: episode,
          status: status,
        );
      } catch (e) {
        appDebugLog('[AnimeTrackingCoordinator] AniList progress error: ');
      }
    }

    if (_mal.isAuthenticated && malId != null && malId > 0) {
      try {
        await _mal.updateWatchProgress(
          malId: malId,
          episode: episode,
          status: status,
        );
      } catch (e) {
        appDebugLog('[AnimeTrackingCoordinator] MAL progress error: ');
      }
    }
  }

  /// Sync explicit watch status (e.g. Watching, Completed, Paused, Dropped, Plan to Watch)
  Future<void> syncWatchStatus({
    int? anilistId,
    int? malId,
    required WatchStatus status,
    int? episode,
  }) async {
    if (!hasAnyAccountConnected) return;

    final animeStatus = AnimeWatchStatus.fromWatchStatus(status);
    final ep = episode ?? (status == WatchStatus.completed ? 1 : 0);

    if (_aniList.isAuthenticated && anilistId != null && anilistId > 0) {
      try {
        await _aniList.updateWatchProgress(
          anilistId: anilistId,
          episode: ep,
          status: animeStatus,
        );
      } catch (e) {
        appDebugLog('[AnimeTrackingCoordinator] AniList status error: ');
      }
    }

    if (_mal.isAuthenticated && malId != null && malId > 0) {
      try {
        await _mal.updateWatchProgress(
          malId: malId,
          episode: ep,
          status: animeStatus,
        );
      } catch (e) {
        appDebugLog('[AnimeTrackingCoordinator] MAL status error: ');
      }
    }
  }

  /// Sync watchlist addition to connected services as Plan to Watch.
  Future<void> syncWatchlistAddition({
    int? anilistId,
    int? malId,
  }) async {
    if (!hasAnyAccountConnected) return;

    try {
      final prefs = await SharedPreferences.getInstance();
      final autoSync = prefs.getBool('anime_auto_sync_watchlist') ?? true;
      if (!autoSync) return;
    } catch (_) {}

    if (_aniList.isAuthenticated && anilistId != null && anilistId > 0) {
      try {
        await _aniList.addToWatchlist(anilistId);
      } catch (e) {
        appDebugLog('[AnimeTrackingCoordinator] AniList watchlist add error: ');
      }
    }

    if (_mal.isAuthenticated && malId != null && malId > 0) {
      try {
        await _mal.addToWatchlist(malId);
      } catch (e) {
        appDebugLog('[AnimeTrackingCoordinator] MAL watchlist add error: ');
      }
    }
  }

  /// Sync watchlist removal from connected services.
  Future<void> syncWatchlistRemoval({
    int? anilistId,
    int? malId,
  }) async {
    if (!hasAnyAccountConnected) return;

    try {
      final prefs = await SharedPreferences.getInstance();
      final autoSync = prefs.getBool('anime_auto_sync_watchlist') ?? true;
      if (!autoSync) return;
    } catch (_) {}

    if (_aniList.isAuthenticated && anilistId != null && anilistId > 0) {
      try {
        await _aniList.removeFromList(anilistId);
      } catch (e) {
        appDebugLog('[AnimeTrackingCoordinator] AniList watchlist remove error: ');
      }
    }

    if (_mal.isAuthenticated && malId != null && malId > 0) {
      try {
        await _mal.removeFromList(malId);
      } catch (e) {
        appDebugLog('[AnimeTrackingCoordinator] MAL watchlist remove error: ');
      }
    }
  }

  /// Fetch all user anime items from connected accounts.
  Future<List<SyncedAnimeItem>> fetchAllSyncedItems() async {
    final results = <SyncedAnimeItem>[];
    _isSyncing = true;

    try {
      if (_aniList.isAuthenticated) {
        final anilistItems = await _aniList.fetchUserAnimeList();
        results.addAll(anilistItems);
      }

      if (_mal.isAuthenticated) {
        final malItems = await _mal.fetchUserAnimeList();
        // Avoid duplicate items if both services have the same anime (match by malId or title)
        for (final malItem in malItems) {
          final alreadyPresent = results.any((existing) =>
              (existing.malId != null && existing.malId == malItem.malId) ||
              existing.title.toLowerCase() == malItem.title.toLowerCase());
          if (!alreadyPresent) {
            results.add(malItem);
          }
        }
      }

      _lastSyncedAt = DateTime.now();
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        'anime_tracking_last_synced_at',
        _lastSyncedAt!.toIso8601String(),
      );
    } catch (e) {
      appDebugLog('[AnimeTrackingCoordinator] Error during full sync: $e');
    } finally {
      _isSyncing = false;
    }

    return results;
  }

  /// Update the last sync timestamp in memory and shared preferences
  Future<void> updateLastSyncedAt(DateTime dt) async {
    _lastSyncedAt = dt;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('anime_tracking_last_synced_at', dt.toIso8601String());
    } catch (_) {}
  }
}

