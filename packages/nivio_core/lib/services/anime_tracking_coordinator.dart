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

  // Per-service presence, refreshed by [fetchAllSyncedItems]. Used to backfill a
  // service that's missing items (e.g. MAL connected after AniList already had
  // the whole library) without re-pushing what a service already has.
  final Set<int> _anilistPresentIds = {};
  final Set<int> _malPresentIds = {};
  // Titles (lowercased) present on each service, so an item still counts as
  // present when a service returns it under a different id than the one we
  // pushed (AniList's idMal can mismatch MAL's canonical id for S2 entries).
  final Set<String> _anilistPresentTitles = {};
  final Set<String> _malPresentTitles = {};

  DateTime? get lastSyncedAt => _lastSyncedAt;
  bool get isSyncing => _isSyncing;

  bool get aniListConnected => _aniList.isAuthenticated;
  bool get malConnected => _mal.isAuthenticated;

  bool anilistHas(int? anilistId, [String? title]) =>
      (anilistId != null && _anilistPresentIds.contains(anilistId)) ||
      (title != null && _anilistPresentTitles.contains(title.trim().toLowerCase()));
  bool malHas(int? malId, [String? title]) =>
      (malId != null && _malPresentIds.contains(malId)) ||
      (title != null && _malPresentTitles.contains(title.trim().toLowerCase()));

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

  /// Pushes a set of resolved changes to the connected services in as few
  /// requests as possible. AniList updates are sent as a single batched
  /// (aliased) GraphQL request via [AniListAuthService.updateWatchProgressBatch];
  /// MAL has no batch endpoint, so those are sent one at a time.
  Future<void> pushBatch(List<TrackingPush> pushes) async {
    if (!hasAnyAccountConnected || pushes.isEmpty) return;

    if (_aniList.isAuthenticated) {
      final aniUpdates = <AniListProgressUpdate>[];
      for (final p in pushes) {
        if (p.anilistId != null && p.anilistId! > 0) {
          aniUpdates.add(
            AniListProgressUpdate(
              anilistId: p.anilistId!,
              episode: p.episode,
              status: AnimeWatchStatus.fromWatchStatus(p.status),
            ),
          );
        }
      }
      if (aniUpdates.isNotEmpty) {
        try {
          await _aniList.updateWatchProgressBatch(aniUpdates);
        } catch (e) {
          appDebugLog('[AnimeTrackingCoordinator] AniList batch push error: $e');
        }
      }
    }

    if (_mal.isAuthenticated) {
      for (final p in pushes) {
        if (p.malId != null && p.malId! > 0) {
          try {
            await _mal.updateWatchProgress(
              malId: p.malId!,
              episode: p.episode,
              status: AnimeWatchStatus.fromWatchStatus(p.status),
            );
          } catch (e) {
            appDebugLog('[AnimeTrackingCoordinator] MAL push error: $e');
          }
        }
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
    _anilistPresentIds.clear();
    _malPresentIds.clear();
    _anilistPresentTitles.clear();
    _malPresentTitles.clear();

    try {
      if (_aniList.isAuthenticated) {
        final anilistItems = await _aniList.fetchUserAnimeList();
        results.addAll(anilistItems);
        for (final it in anilistItems) {
          if (it.anilistId != null) _anilistPresentIds.add(it.anilistId!);
          _anilistPresentTitles.add(it.title.trim().toLowerCase());
        }
      }

      if (_mal.isAuthenticated) {
        final malItems = await _mal.fetchUserAnimeList();
        for (final it in malItems) {
          if (it.malId != null) _malPresentIds.add(it.malId!);
          _malPresentTitles.add(it.title.trim().toLowerCase());
        }
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

/// A single resolved change to push to tracking services, collected during a
/// sync pass and flushed together via [AnimeTrackingCoordinator.pushBatch].
class TrackingPush {
  final int? anilistId;
  final int? malId;
  final WatchStatus status;
  final int episode;

  const TrackingPush({
    this.anilistId,
    this.malId,
    required this.status,
    required this.episode,
  });
}

