import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:nivio/models/watch_history.dart';

class WatchHistoryService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  late Box<String> _historyBox;

  bool _initialized = false;

  /// Initialize Hive box
  Future<void> init() async {
    if (_initialized) return;

    await Hive.initFlutter();
    _historyBox = await Hive.openBox<String>('watch_history');
    _initialized = true;

    // Start background sync
    _startBackgroundSync();
  }

  /// Get current user ID
  String? get _userId => _auth.currentUser?.uid;

  /// Save watch progress (local-first, then sync to cloud)
  Future<void> updateProgress({
    required int tmdbId,
    required String mediaType,
    required String title,
    String? posterPath,
    required int currentSeason,
    required int currentEpisode,
    required int totalSeasons,
    int? totalEpisodes,
    required Duration lastPosition,
    required Duration totalDuration,
  }) async {
    if (!_initialized) await init();

    final id = '${_userId}_$tmdbId';
    final progressPercent = lastPosition.inSeconds / totalDuration.inSeconds;

    // Get existing history or create new
    WatchHistory history;
    final existingJson = _historyBox.get(id);
    if (existingJson != null) {
      final existingData = WatchHistory.fromJson(
        Map<String, dynamic>.from(
          // Simple JSON decode (Hive stores as String)
          _parseJson(existingJson),
        ),
      );
      history = existingData.copyWith(
        currentSeason: currentSeason,
        currentEpisode: currentEpisode,
        totalSeasons: totalSeasons,
        totalEpisodes: totalEpisodes,
        lastPositionSeconds: lastPosition.inSeconds,
        totalDurationSeconds: totalDuration.inSeconds,
        progressPercent: progressPercent,
        lastWatchedAt: DateTime.now(),
        isCompleted: progressPercent >= 0.95,
      );
    } else {
      history = WatchHistory(
        id: id,
        tmdbId: tmdbId,
        mediaType: mediaType,
        title: title,
        posterPath: posterPath,
        currentSeason: currentSeason,
        currentEpisode: currentEpisode,
        totalSeasons: totalSeasons,
        totalEpisodes: totalEpisodes,
        lastPositionSeconds: lastPosition.inSeconds,
        totalDurationSeconds: totalDuration.inSeconds,
        progressPercent: progressPercent,
        lastWatchedAt: DateTime.now(),
        createdAt: DateTime.now(),
        isCompleted: false,
        episodes: {},
      );
    }

    // Update episode progress for TV shows
    if (mediaType == 'tv') {
      final episodeKey = 's${currentSeason}e$currentEpisode';
      final episodeProgress = EpisodeProgress(
        season: currentSeason,
        episode: currentEpisode,
        lastPositionSeconds: lastPosition.inSeconds,
        totalDurationSeconds: totalDuration.inSeconds,
        isCompleted: progressPercent >= 0.95,
        watchedAt: DateTime.now(),
      );

      final updatedEpisodes = Map<String, EpisodeProgress>.from(history.episodes);
      updatedEpisodes[episodeKey] = episodeProgress;
      history = history.copyWith(episodes: updatedEpisodes);
    }

    // Save locally first (instant UI update)
    await _historyBox.put(id, _toJsonString(history.toJson()));

    // Queue cloud sync
    _syncToCloud(history);
  }

  /// Get all watch history
  Future<List<WatchHistory>> getAllHistory() async {
    if (!_initialized) await init();

    final histories = <WatchHistory>[];
    for (final key in _historyBox.keys) {
      final json = _historyBox.get(key);
      if (json != null) {
        histories.add(WatchHistory.fromJson(
          Map<String, dynamic>.from(_parseJson(json)),
        ));
      }
    }

    // Sort by last watched (newest first)
    histories.sort((a, b) => b.lastWatchedAt.compareTo(a.lastWatchedAt));
    return histories;
  }

  /// Get continue watching (incomplete items, including newly added with 0% progress)
  Future<List<WatchHistory>> getContinueWatching() async {
    final all = await getAllHistory();
    return all
        .where((h) => !h.isCompleted) // Show all incomplete items (including 0% progress)
        .take(10)
        .toList();
  }

  /// Get history for specific media
  Future<WatchHistory?> getHistory(int tmdbId) async {
    if (!_initialized) await init();

    final id = '${_userId}_$tmdbId';
    final json = _historyBox.get(id);
    if (json != null) {
      return WatchHistory.fromJson(
        Map<String, dynamic>.from(_parseJson(json)),
      );
    }
    return null;
  }

  /// Delete watch history
  Future<void> deleteHistory(int tmdbId) async {
    if (!_initialized) await init();

    final id = '${_userId}_$tmdbId';
    await _historyBox.delete(id);

    // Delete from cloud
    if (_userId != null) {
      await _firestore
          .collection('users')
          .doc(_userId)
          .collection('watchHistory')
          .doc(tmdbId.toString())
          .delete();
    }
  }

  /// Clear all watch history (local and cloud)
  Future<void> clearAllHistory() async {
    if (!_initialized) await init();

    // Clear local Hive box
    await _historyBox.clear();
    print('✅ Cleared local watch history');

    // Clear from Firestore cloud if user is logged in
    if (_userId != null) {
      try {
        final snapshot = await _firestore
            .collection('users')
            .doc(_userId)
            .collection('watchHistory')
            .get();

        // Delete all documents in batch
        final batch = _firestore.batch();
        for (final doc in snapshot.docs) {
          batch.delete(doc.reference);
        }
        await batch.commit();
        print('✅ Cleared cloud watch history');
      } catch (e) {
        print('❌ Failed to clear cloud history: $e');
      }
    }
  }

  /// Sync to Firestore (background)
  Future<void> _syncToCloud(WatchHistory history) async {
    if (_userId == null) return;

    try {
      await _firestore
          .collection('users')
          .doc(_userId)
          .collection('watchHistory')
          .doc(history.tmdbId.toString())
          .set(history.toJson(), SetOptions(merge: true));
    } catch (e) {
      print('❌ Failed to sync to cloud: $e');
      // Will retry on next sync cycle
    }
  }

  /// Background sync from Firestore (pull latest)
  Future<void> _pullFromCloud() async {
    if (_userId == null) return;

    try {
      final snapshot = await _firestore
          .collection('users')
          .doc(_userId)
          .collection('watchHistory')
          .get();

      for (final doc in snapshot.docs) {
        final cloudHistory = WatchHistory.fromJson(doc.data());
        final id = '${_userId}_${cloudHistory.tmdbId}';
        final localJson = _historyBox.get(id);

        // Merge: keep newer version
        if (localJson == null) {
          // No local version, use cloud
          await _historyBox.put(id, _toJsonString(cloudHistory.toJson()));
        } else {
          final localHistory = WatchHistory.fromJson(
            Map<String, dynamic>.from(_parseJson(localJson)),
          );

          // Compare timestamps, keep newer
          if (cloudHistory.lastWatchedAt.isAfter(localHistory.lastWatchedAt)) {
            await _historyBox.put(id, _toJsonString(cloudHistory.toJson()));
          }
        }
      }
    } catch (e) {
      print('❌ Failed to pull from cloud: $e');
    }
  }

  /// Start background sync (every 30 seconds)
  void _startBackgroundSync() {
    Future.delayed(const Duration(seconds: 30), () async {
      await _pullFromCloud();
      _startBackgroundSync(); // Recursive call
    });
  }

  /// Helper: Parse JSON string
  Map<String, dynamic> _parseJson(String jsonString) {
    return Map<String, dynamic>.from(jsonDecode(jsonString));
  }

  /// Helper: Convert to JSON string
  String _toJsonString(Map<String, dynamic> json) {
    return jsonEncode(json);
  }
}
