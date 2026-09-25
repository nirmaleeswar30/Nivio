import 'dart:async';
import 'dart:math' as math;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:hive/hive.dart';
import '../models/watchlist_item.dart';
import 'auth_service.dart';
import 'package:nivio/services/anime_tracking_coordinator.dart';
import 'package:nivio/services/simkl_auth_service.dart';
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

      // Sync to Simkl (movies, TV & anime). No-op when Simkl isn't connected.
      unawaited(SimklAuthService.instance.syncItem(finalItem));

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

      // Sync status change to Simkl (movies, TV & anime).
      unawaited(SimklAuthService.instance.syncItem(updated));

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

      // Propagate the removal to Simkl (movies, TV & anime) so the next pull
      // doesn't resurrect it. No-op when Simkl isn't connected.
      if (existingItem != null) {
        unawaited(SimklAuthService.instance.removeItem(existingItem));
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
              // Preserve original timestamp: a background sync must not reorder
              // the watchlist. Only real user actions bump updatedAt.
              updatedAt: existing.updatedAt ?? existing.addedAt,
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

      // --- PHASE 5: Backfill a connected service that's MISSING local anime
      // (e.g. MAL connected after AniList already had the whole library). Each
      // push carries an id only for the service that lacks it, so a service
      // that already has the item isn't re-pushed. This converges: once a
      // service has an item, its presence set includes it next run.
      if (pushOfflineChanges) {
        final backfill = <TrackingPush>[];
        for (final loc in _box.values) {
          if (loc.mediaType != 'anime') continue;
          final aId = loc.anilistId ?? (loc.id > 0 ? loc.id : null);
          final mId = loc.malId;
          final missingAniList = coordinator.aniListConnected &&
              aId != null &&
              !coordinator.anilistHas(aId);
          final missingMal =
              coordinator.malConnected && mId != null && !coordinator.malHas(mId);
          if (missingAniList || missingMal) {
            backfill.add(
              TrackingPush(
                anilistId: missingAniList ? aId : null,
                malId: missingMal ? mId : null,
                status: loc.watchStatus,
                episode: loc.currentEpisode ??
                    (loc.watchStatus == WatchStatus.completed ? 1 : 0),
              ),
            );
          }
        }
        if (backfill.isNotEmpty) {
          await coordinator.pushBatch(backfill);
          appDebugLog('📤 Backfilled ${backfill.length} anime to missing service(s).');
        }
      }

      // Update sync timestamp
      await coordinator.updateLastSyncedAt(DateTime.now());
      appDebugLog('✅ Anime library tracking sync complete: $processedCount items processed.');
    } catch (e) {
      appDebugLog('❌ Error importing from anime tracking: $e');
    }

    return processedCount;
  }

  /// Bidirectionally syncs the watchlist (movies, TV & anime) with Simkl, using
  /// the same reconcile strategy as [importFromAnimeTracking], but the push is
  /// DETERMINISTIC — it compares each local item's status against what Simkl
  /// already has and pushes only genuine differences. Nothing is pushed when
  /// local and remote agree, so a no-change run sends no request (idempotent,
  /// independent of `updatedAt`/timestamps which the cloud merge bumps).
  Future<int> importFromSimkl({bool pushOfflineChanges = true}) async {
    final simkl = SimklAuthService.instance;
    if (!simkl.isAuthenticated) {
      appDebugLog('[WatchlistService] Simkl not connected to sync.');
      return 0;
    }

    int processedCount = 0;

    // The effective Simkl `to` status for a local item, accounting for movies
    // being atomic (Simkl silently rewrites a movie's `watching` → `completed`,
    // so treat it as completed here to avoid a phantom perpetual diff).
    String effStatus(WatchlistItem i) {
      var s = SimklAuthService.simklStatus(i.watchStatus);
      if (i.mediaType == 'movie' && s == 'watching') s = 'completed';
      return s;
    }

    try {
      // --- Pull remote library, then index it by every id we might match on ---
      final remoteItems = await simkl.fetchAllItems();
      final remoteByKey = <String, SimklSyncedItem>{};
      for (final r in remoteItems) {
        if (r.tmdbId != null) remoteByKey['tmdb:${r.mediaType}:${r.tmdbId}'] = r;
        if (r.malId != null) remoteByKey['mal:${r.malId}'] = r;
        if (r.anilistId != null) remoteByKey['anilist:${r.anilistId}'] = r;
        remoteByKey['title:${r.mediaType}:${r.title.trim().toLowerCase()}'] = r;
      }

      SimklSyncedItem? remoteFor(WatchlistItem loc) =>
          remoteByKey['tmdb:${loc.mediaType}:${loc.id}'] ??
          (loc.malId != null ? remoteByKey['mal:${loc.malId}'] : null) ??
          (loc.anilistId != null ? remoteByKey['anilist:${loc.anilistId}'] : null) ??
          remoteByKey['title:${loc.mediaType}:${loc.title.trim().toLowerCase()}'];

      final localItems = _box.values.toList();

      // --- PULL: merge remote → local (create missing, upgrade status/progress).
      //     This direction is idempotent: it only writes when a field changed. ---
      for (final r in remoteItems) {
        WatchlistItem? existing;
        for (final loc in localItems) {
          if (loc.mediaType != r.mediaType) continue;
          final sameTmdb = r.tmdbId != null && loc.id == r.tmdbId;
          final sameMal = r.malId != null && loc.malId == r.malId;
          final sameAnilist = r.anilistId != null && loc.anilistId == r.anilistId;
          final sameTitle =
              loc.title.trim().toLowerCase() == r.title.trim().toLowerCase();
          if (sameTmdb || sameMal || sameAnilist || sameTitle) {
            existing = loc;
            break;
          }
        }

        if (existing != null) {
          final resolvedEpisode =
              math.max(existing.currentEpisode ?? 0, r.watchedEpisodes);
          WatchStatus resolvedStatus = r.status;
          if (existing.watchStatus == WatchStatus.completed ||
              r.status == WatchStatus.completed) {
            resolvedStatus = WatchStatus.completed;
          } else if (resolvedEpisode > 0 &&
              r.status == WatchStatus.planning &&
              existing.watchStatus != WatchStatus.planning) {
            resolvedStatus = WatchStatus.watching;
          }

          final mergedTotal = r.totalEpisodes ?? existing.totalEpisodes;
          final mergedMal = existing.malId ?? r.malId;
          final mergedAnilist = existing.anilistId ?? r.anilistId;
          final mergedPoster =
              (existing.posterPath == null || existing.posterPath!.isEmpty)
                  ? (r.posterUrl ?? existing.posterPath)
                  : existing.posterPath;
          final mergedEpisode =
              resolvedEpisode > 0 ? resolvedEpisode : existing.currentEpisode;

          final localNeedsUpdate = existing.watchStatus != resolvedStatus ||
              existing.currentEpisode != mergedEpisode ||
              existing.totalEpisodes != mergedTotal ||
              existing.malId != mergedMal ||
              existing.anilistId != mergedAnilist ||
              existing.posterPath != mergedPoster;

          if (localNeedsUpdate) {
            // Preserve the original updatedAt: a background reconcile must not
            // reorder the user's watchlist (getAllItems sorts by updatedAt).
            // Only genuine user actions bump the timestamp.
            final updated = existing.copyWith(
              watchStatus: resolvedStatus,
              currentEpisode: mergedEpisode,
              totalEpisodes: mergedTotal,
              malId: mergedMal,
              anilistId: mergedAnilist,
              posterPath: mergedPoster,
              updatedAt: existing.updatedAt ?? existing.addedAt,
            );
            await _box.put(existing.id, updated);
            if (_authService.isSignedIn) unawaited(_syncToCloud(updated));
            processedCount++;
          }
        } else {
          final itemId = r.tmdbId ??
              r.malId ??
              r.anilistId ??
              r.simklId ??
              r.title.hashCode.abs();
          final newItem = WatchlistItem(
            id: itemId,
            title: r.title,
            posterPath: r.posterUrl,
            mediaType: r.mediaType,
            releaseDate: r.year?.toString(),
            addedAt: DateTime.now(),
            watchStatus: r.status,
            currentEpisode: r.watchedEpisodes > 0 ? r.watchedEpisodes : null,
            totalEpisodes: r.totalEpisodes,
            malId: r.malId,
            anilistId: r.anilistId,
            updatedAt: DateTime.now(),
          );
          await _box.put(newItem.id, newItem);
          if (_authService.isSignedIn) unawaited(_syncToCloud(newItem));
          processedCount++;
        }
      }

      // --- PUSH (deterministic): send a local item ONLY when Simkl is missing
      //     it or has a different status. No timestamps involved, so a run with
      //     no real changes produces an empty batch and makes no request. ---
      if (pushOfflineChanges) {
        final toPush = <WatchlistItem>[];
        for (final loc in _box.values) {
          final remote = remoteFor(loc);
          if (remote == null || effStatus(loc) != SimklAuthService.simklStatus(remote.status)) {
            toPush.add(loc);
          }
        }
        if (toPush.isNotEmpty) {
          await simkl.syncItems(toPush);
          appDebugLog('📤 Pushed ${toPush.length} change(s) to Simkl.');
        } else {
          appDebugLog('✅ Simkl already up to date — nothing to push.');
        }
      }

      await simkl.updateLastSyncedAt(DateTime.now());
      appDebugLog('✅ Simkl library sync complete: $processedCount items processed.');
    } catch (e) {
      appDebugLog('❌ Error importing from Simkl: $e');
    }

    return processedCount;
  }
}
