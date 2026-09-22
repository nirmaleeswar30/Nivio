import 'dart:async';
import 'dart:math' as math;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:hive/hive.dart';
import '../models/watchlist_item.dart';
import 'auth_service.dart';
import 'package:nivio/services/anime_tracking_coordinator.dart';
import 'package:nivio/core/debug_log.dart';

/// Service for managing user's watchlist with status categories and cloud sync.
class WatchlistService {
  final AuthService _authService;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static const String _boxName = 'watchlist';

  WatchlistService(this._authService);

  /// Get watchlist box
  Box<WatchlistItem> get _box => Hive.box<WatchlistItem>(_boxName);

  /// Initialize watchlist box
  static Future<void> init() async {
    await Hive.openBox<WatchlistItem>(_boxName);
  }

  /// Check if item is in watchlist
  bool isInWatchlist(int mediaId) {
    return _box.containsKey(mediaId);
  }

  /// Get single item from watchlist
  WatchlistItem? getItem(int mediaId) {
    return _box.get(mediaId);
  }

  /// Get all watchlist items
  List<WatchlistItem> getAllItems() {
    return _box.values.toList()
      ..sort((a, b) {
        final bTime = b.updatedAt ?? b.addedAt;
        final aTime = a.updatedAt ?? a.addedAt;
        return bTime.compareTo(aTime);
      });
  }

  /// Get items filtered by status
  List<WatchlistItem> getItemsByStatus(WatchStatus status) {
    return getAllItems().where((item) => item.watchStatus == status).toList();
  }

  /// Add item to watchlist with specified initial status (defaults to planning)
  Future<void> addToWatchlist(
    WatchlistItem item, {
    WatchStatus status = WatchStatus.planning,
  }) async {
    try {
      final finalItem = item.copyWith(
        watchStatus: status,
        updatedAt: DateTime.now(),
      );

      appDebugLog('📝 Adding to watchlist:  ()');

      // Save locally
      await _box.put(finalItem.id, finalItem);

      // Sync to cloud if user is signed in
      if (_authService.isSignedIn) {
        await _syncToCloud(finalItem);
      }

      // Sync to AniList & MAL if anime
      if (finalItem.mediaType == 'anime') {
        unawaited(
          AnimeTrackingCoordinator.instance.syncWatchStatus(
            anilistId: finalItem.anilistId ?? finalItem.id,
            malId: finalItem.malId,
            status: finalItem.watchStatus,
            episode: finalItem.currentEpisode,
          ),
        );
      }

      appDebugLog('✅ Added to watchlist successfully');
    } catch (e) {
      appDebugLog('❌ Error adding to watchlist: ');
      rethrow;
    }
  }

  /// Update watch status of an existing watchlist item (or create if not present)
  Future<void> updateWatchStatus(
    int mediaId,
    WatchStatus status, {
    int? currentEpisode,
    int? totalEpisodes,
    int? anilistId,
    int? malId,
  }) async {
    try {
      final existing = _box.get(mediaId);
      if (existing == null) {
        appDebugLog('⚠️ updateWatchStatus: Item  not in watchlist');
        return;
      }

      final updated = existing.copyWith(
        watchStatus: status,
        currentEpisode: currentEpisode ?? existing.currentEpisode,
        totalEpisodes: totalEpisodes ?? existing.totalEpisodes,
        anilistId: anilistId ?? existing.anilistId,
        malId: malId ?? existing.malId,
        updatedAt: DateTime.now(),
      );

      await _box.put(mediaId, updated);

      if (_authService.isSignedIn) {
        await _syncToCloud(updated);
      }

      if (updated.mediaType == 'anime') {
        unawaited(
          AnimeTrackingCoordinator.instance.syncWatchStatus(
            anilistId: updated.anilistId ?? updated.id,
            malId: updated.malId,
            status: status,
            episode: updated.currentEpisode,
          ),
        );
      }

      appDebugLog('✅ Updated watch status for  → ');
    } catch (e) {
      appDebugLog('❌ Error updating watch status: ');
    }
  }

  /// Remove item from watchlist
  Future<void> removeFromWatchlist(int mediaId) async {
    try {
      appDebugLog('🗑️ Removing from watchlist: ');

      final existingItem = _box.get(mediaId);

      // Remove locally
      await _box.delete(mediaId);

      // Remove from cloud if user is signed in
      if (_authService.isSignedIn) {
        await _removeFromCloud(mediaId);
      }

      // Sync removal to AniList & MAL if anime
      if (existingItem?.mediaType == 'anime') {
        unawaited(
          AnimeTrackingCoordinator.instance.syncWatchlistRemoval(
            anilistId: existingItem?.anilistId ?? mediaId,
            malId: existingItem?.malId,
          ),
        );
      }

      appDebugLog('✅ Removed from watchlist successfully');
    } catch (e) {
      appDebugLog('❌ Error removing from watchlist: ');
      rethrow;
    }
  }

  /// Toggle watchlist status (planning vs removed)
  Future<void> toggleWatchlist(
    WatchlistItem item, {
    WatchStatus defaultStatus = WatchStatus.planning,
  }) async {
    if (isInWatchlist(item.id)) {
      await removeFromWatchlist(item.id);
    } else {
      await addToWatchlist(item, status: defaultStatus);
    }
  }

  /// Sync item to cloud (Firestore)
  Future<void> _syncToCloud(WatchlistItem item) async {
    try {
      final user = _authService.currentUser;
      if (user?.isAnonymous == true) return;

      final uid = _authService.uid;
      if (uid == null) return;

      await _firestore
          .collection('users')
          .doc(uid)
          .collection('watchlist')
          .doc(item.id.toString())
          .set(item.toJson(), SetOptions(merge: true));

      appDebugLog('☁️ Synced to cloud:  ()');
    } catch (e) {
      appDebugLog('❌ Error syncing to cloud: ');
    }
  }

  /// Remove item from cloud
  Future<void> _removeFromCloud(int mediaId) async {
    try {
      final user = _authService.currentUser;
      if (user?.isAnonymous == true) return;

      final uid = _authService.uid;
      if (uid == null) return;

      await _firestore
          .collection('users')
          .doc(uid)
          .collection('watchlist')
          .doc(mediaId.toString())
          .delete();

      appDebugLog('☁️ Removed from cloud: ');
    } catch (e) {
      appDebugLog('❌ Error removing from cloud: ');
    }
  }

  /// Sync all local items to cloud
  Future<void> syncAllToCloud() async {
    if (!_authService.isSignedIn) return;
    final user = _authService.currentUser;
    if (user?.isAnonymous == true) return;

    appDebugLog('🔄 Syncing all items to cloud...');
    final items = getAllItems();
    for (final item in items) {
      await _syncToCloud(item);
    }
    appDebugLog('✅ Sync complete:  items');
  }

  /// Download watchlist from cloud and merge with local
  Future<void> downloadFromCloud() async {
    if (!_authService.isSignedIn) return;
    final user = _authService.currentUser;
    if (user?.isAnonymous == true) return;

    try {
      appDebugLog('⬇️ Downloading watchlist from cloud...');
      final uid = _authService.uid;
      if (uid == null) return;

      final snapshot = await _firestore
          .collection('users')
          .doc(uid)
          .collection('watchlist')
          .get();

      int merged = 0;
      for (final doc in snapshot.docs) {
        final cloudItem = WatchlistItem.fromJson(doc.data());
        final localItem = _box.get(cloudItem.id);
        if (localItem == null) {
          await _box.put(cloudItem.id, cloudItem);
          merged++;
        } else {
          // Cloud item has newer timestamp or status
          final cloudTime = cloudItem.updatedAt ?? cloudItem.addedAt;
          final localTime = localItem.updatedAt ?? localItem.addedAt;
          if (cloudTime.isAfter(localTime)) {
            await _box.put(cloudItem.id, cloudItem);
            merged++;
          }
        }
      }

      appDebugLog('✅ Download complete: $merged items merged');
    } catch (e) {
      appDebugLog('❌ Failed to pull from cloud: ');
    }
  }

  /// Clear all watchlist items (local only)
  Future<void> clearAll() async {
    await _box.clear();
    appDebugLog('🗑️ Watchlist cleared');
  }

  /// Get watchlist count
  int get count => _box.length;

  /// Bidirectionally syncs anime watchlist with AniList and MyAnimeList.
  /// 1. Pushes any local changes made offline (items with updatedAt > lastSyncedAt).
  /// 2. Pulls user's remote library from AniList & MAL.
  /// 3. Merges remote entries into local Watchlist and syncs to cloud Firestore.
  /// Returns the number of imported/updated items.
  Future<int> importFromAnimeTracking({bool pushOfflineChanges = true}) async {
    final coordinator = AnimeTrackingCoordinator.instance;
    if (!coordinator.hasAnyAccountConnected) {
      appDebugLog('[WatchlistService] No anime tracking account connected to sync.');
      return 0;
    }

    final lastSync = coordinator.lastSyncedAt;
    int processedCount = 0;

    // Resolved changes are collected here and flushed once at the very end, so
    // AniList gets a single batched request instead of one write per show
    // (which is what was previously exhausting the rate limit).
    final pushes = <TrackingPush>[];
    // Local items already reconciled against a remote entry, so PHASE 3 can tell
    // which local-only items still need to be created on the remote.
    final matchedLocalIds = <int>{};

    // --- PHASE 1: Pull remote library FIRST so we can diff before pushing ---
    try {
      final remoteItems = await coordinator.fetchAllSyncedItems();
      final localItems = _box.values.toList();

      // --- PHASE 2: Merge remote → local, collecting only real diffs to push ---
      for (final synced in remoteItems) {
        // Find existing matching local item
        WatchlistItem? existing;
        for (final loc in localItems) {
          final isSameAniList = synced.anilistId != null &&
              (loc.anilistId == synced.anilistId || loc.id == synced.anilistId);
          final isSameMal = synced.malId != null &&
              (loc.malId == synced.malId || loc.id == synced.malId);
          final isSameTitle = loc.mediaType == 'anime' &&
              loc.title.trim().toLowerCase() == synced.title.trim().toLowerCase();

          if (isSameAniList || isSameMal || isSameTitle) {
            existing = loc;
            break;
          }
        }

        final targetStatus = synced.status.toWatchStatus();

        if (existing != null) {
          matchedLocalIds.add(existing.id);
          final localEp = existing.currentEpisode ?? 0;
          final remoteEp = synced.episodesWatched;

          // Highest progress wins: never downgrade watched episode progress
          final resolvedEpisode = math.max(localEp, remoteEp);

          // Status resolution: if completed on either, stay completed.
          // Only auto-upgrade Planning → Watching when it's a genuine conflict,
          // i.e. the remote is a stale "Planning" but the local side already
          // shows Watching with progress. If the user deliberately set Planning
          // locally (local == Planning too), respect it — never force it back.
          WatchStatus resolvedStatus = targetStatus;
          if (existing.watchStatus == WatchStatus.completed ||
              targetStatus == WatchStatus.completed) {
            resolvedStatus = WatchStatus.completed;
          } else if (resolvedEpisode > 0 &&
              targetStatus == WatchStatus.planning &&
              existing.watchStatus != WatchStatus.planning) {
            resolvedStatus = WatchStatus.watching;
          }

          // Only queue a push when the remote is actually out of date — i.e. the
          // resolved episode/status differs from what AniList/MAL already has.
          // This is what stops the app from re-writing every show on each open.
          final remoteNeedsUpdate =
              resolvedEpisode != remoteEp || resolvedStatus != targetStatus;
          if (pushOfflineChanges && remoteNeedsUpdate) {
            pushes.add(
              TrackingPush(
                anilistId: existing.anilistId ??
                    synced.anilistId ??
                    (existing.id > 0 ? existing.id : null),
                malId: existing.malId ?? synced.malId,
                status: resolvedStatus,
                episode: resolvedEpisode,
              ),
            );
            appDebugLog(
                '📥 Queued remote update for ${existing.title} (Ep $remoteEp → $resolvedEpisode, ${resolvedStatus.label})');
          }

          // Compute the merged values with the same `?? keep-existing` semantics
          // copyWith uses, so we can tell whether anything actually changed.
          final mergedTotal = synced.totalEpisodes ?? existing.totalEpisodes;
          final mergedAnilist = synced.anilistId ?? existing.anilistId;
          final mergedMal = synced.malId ?? existing.malId;
          final mergedPoster =
              (existing.posterPath == null || existing.posterPath!.isEmpty)
                  ? (synced.posterUrl ?? existing.posterPath)
                  : existing.posterPath;
          final mergedVote = synced.score ?? existing.voteAverage;
          final mergedEpisode =
              resolvedEpisode > 0 ? resolvedEpisode : existing.currentEpisode;

          // Only touch local storage (and therefore cloud + updatedAt ordering)
          // when a field genuinely changed. This stops every synced anime from
          // being rewritten — and jumping ahead of manually-added items — on
          // each app open when nothing actually differs.
          final localNeedsUpdate = existing.watchStatus != resolvedStatus ||
              existing.currentEpisode != mergedEpisode ||
              existing.totalEpisodes != mergedTotal ||
              existing.anilistId != mergedAnilist ||
              existing.malId != mergedMal ||
              existing.posterPath != mergedPoster ||
              existing.voteAverage != mergedVote;

          if (localNeedsUpdate) {
            final updated = existing.copyWith(
              watchStatus: resolvedStatus,
              currentEpisode: mergedEpisode,
              totalEpisodes: mergedTotal,
              anilistId: mergedAnilist,
              malId: mergedMal,
              posterPath: mergedPoster,
              voteAverage: mergedVote,
              updatedAt: DateTime.now(),
            );
            await _box.put(existing.id, updated);
            if (_authService.isSignedIn) {
              unawaited(_syncToCloud(updated));
            }
            processedCount++;
          }
        } else {
          // New item from remote - create new WatchlistItem
          final itemId = synced.anilistId ??
              synced.malId ??
              (synced.title.hashCode.abs());

          final newItem = WatchlistItem(
            id: itemId,
            title: synced.title,
            posterPath: synced.posterUrl,
            mediaType: 'anime',
            voteAverage: synced.score,
            releaseDate: null,
            addedAt: DateTime.now(),
            watchStatus: targetStatus,
            currentEpisode: synced.episodesWatched > 0 ? synced.episodesWatched : null,
            totalEpisodes: synced.totalEpisodes,
            anilistId: synced.anilistId,
            malId: synced.malId,
            updatedAt: DateTime.now(),
          );

          await _box.put(newItem.id, newItem);
          if (_authService.isSignedIn) {
            unawaited(_syncToCloud(newItem));
          }
          processedCount++;
        }
      }

      // --- PHASE 3: Queue local-only anime the remote doesn't have yet ---
      // These weren't matched to any remote entry above, so push them (once,
      // and only if they're new/changed since the last sync) to create them.
      if (pushOfflineChanges) {
        for (final loc in localItems) {
          if (loc.mediaType != 'anime') continue;
          if (matchedLocalIds.contains(loc.id)) continue;
          final itemTime = loc.updatedAt ?? loc.addedAt;
          if (lastSync == null || itemTime.isAfter(lastSync)) {
            pushes.add(
              TrackingPush(
                anilistId: loc.anilistId ?? (loc.id > 0 ? loc.id : null),
                malId: loc.malId,
                status: loc.watchStatus,
                episode: loc.currentEpisode ?? 1,
              ),
            );
          }
        }
      }

      // --- PHASE 4: Flush every collected change in as few requests as
      // possible (AniList batched into ~1 request per 40 items; MAL one-by-one).
      if (pushes.isNotEmpty) {
        await coordinator.pushBatch(pushes);
        appDebugLog('📤 Pushed ${pushes.length} change(s) to tracking (batched).');
      }

      // Update sync timestamp
      await coordinator.updateLastSyncedAt(DateTime.now());
      appDebugLog('✅ Anime library tracking sync complete: $processedCount items processed.');
    } catch (e) {
      appDebugLog('❌ Error importing from anime tracking: $e');
    }

    return processedCount;
  }
}
