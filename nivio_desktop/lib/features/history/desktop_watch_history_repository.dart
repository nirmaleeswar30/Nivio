import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../../core/interfaces/watch_history_repository.dart';
import '../auth/desktop_cloud_sync_service.dart';
import 'watch_history_storage.dart';

/// Android-compatible, local-first watch history backed by Hive.
class DesktopWatchHistoryRepository extends ChangeNotifier
    implements WatchHistoryRepository {
  DesktopWatchHistoryRepository._();

  @visibleForTesting
  DesktopWatchHistoryRepository.withStorage(WatchHistoryStorage storage)
    : _storage = storage {
    _listenToStorage();
  }

  static final DesktopWatchHistoryRepository instance =
      DesktopWatchHistoryRepository._();

  WatchHistoryStorage? _storage;
  bool _opening = false;
  Future<void>? _openFuture;
  Listenable? _storageChanges;

  Future<void> initialize() => _ensureStorage();

  Future<void> _ensureStorage() async {
    if (_storage != null) return;
    if (_opening) return _openFuture!;
    _opening = true;
    final future = HiveWatchHistoryStorage.open()
        .then((storage) {
          _storage = storage;
          _listenToStorage();
        })
        .whenComplete(() => _opening = false);
    _openFuture = future;
    await future;
  }

  void _listenToStorage() {
    final next = _storage?.changes;
    if (identical(next, _storageChanges)) return;
    _storageChanges?.removeListener(_onStorageChanged);
    _storageChanges = next;
    next?.addListener(_onStorageChanged);
  }

  void _onStorageChanged() => notifyListeners();

  @override
  Future<List<Map<String, dynamic>>> getWatchHistory() async {
    await _ensureStorage();
    final entries = <Map<String, dynamic>>[];
    for (final encoded in _storage!.values) {
      final decoded = _decode(encoded);
      if (decoded != null) entries.add(decoded);
    }
    entries.sort(
      (a, b) => _date(b['lastWatchedAt']).compareTo(_date(a['lastWatchedAt'])),
    );
    return entries;
  }

  @override
  Future<Map<String, dynamic>?> getWatchProgress({
    required int mediaId,
    required String mediaType,
    int? seasonNumber,
    int? episodeNumber,
  }) async {
    await _ensureStorage();
    final direct = _decode(_storage!.read(_key(mediaId)));
    if (direct != null) return direct;

    // Read legacy/authenticated Android records if this Hive directory was
    // migrated, while new Desktop writes remain anonymous-local like Android.
    for (final encoded in _storage!.values) {
      final entry = _decode(encoded);
      if (_integer(entry?['tmdbId']) == mediaId) return entry;
    }
    return null;
  }

  @override
  Future<void> saveWatchProgress(Map<String, dynamic> progress) async {
    await _ensureStorage();
    final mediaId = _integer(progress['tmdbId'] ?? progress['mediaId']);
    final duration = _integer(
      progress['totalDurationSeconds'] ?? progress['durationSeconds'],
    );
    final position = _integer(
      progress['lastPositionSeconds'] ?? progress['positionSeconds'],
    );
    if (mediaId == null ||
        duration == null ||
        duration <= 0 ||
        position == null) {
      return;
    }

    final key = _key(mediaId);
    final existing = _decode(_storage!.read(key));
    final now = DateTime.now().millisecondsSinceEpoch;
    final mediaType =
        (progress['mediaType'] ?? existing?['mediaType'] ?? 'movie').toString();
    final season =
        _integer(progress['currentSeason'] ?? progress['season']) ?? 1;
    final episode =
        _integer(progress['currentEpisode'] ?? progress['episode']) ?? 1;
    final totalSeasons = _integer(progress['totalSeasons']) ?? 1;
    final totalEpisodes = _integer(progress['totalEpisodes']);
    final percent = position / duration;
    final completed = mediaType == 'tv'
        ? percent >= 0.95 &&
              totalSeasons > 0 &&
              season >= totalSeasons &&
              totalEpisodes != null &&
              episode >= totalEpisodes
        : percent >= 0.95;

    final episodes = _stringMap(existing?['episodes']);
    if (mediaType == 'tv') {
      episodes['s${season}e$episode'] = <String, dynamic>{
        'season': season,
        'episode': episode,
        'lastPositionSeconds': position,
        'totalDurationSeconds': duration,
        'isCompleted': percent >= 0.95,
        'watchedAt': now,
        if (existing != null)
          ..._preservedEpisodePreferences(
            _stringMap(existing['episodes'])['s${season}e$episode'],
          ),
      };
    }

    final record = <String, dynamic>{
      'id': key,
      'tmdbId': mediaId,
      'mediaType': mediaType,
      'title': (progress['title'] ?? existing?['title'] ?? 'Unknown')
          .toString(),
      'posterPath': progress['posterPath'] ?? existing?['posterPath'],
      'currentSeason': season,
      'currentEpisode': episode,
      'totalSeasons': totalSeasons,
      'totalEpisodes': totalEpisodes,
      'lastPositionSeconds': position,
      'totalDurationSeconds': duration,
      'progressPercent': percent,
      'lastWatchedAt': now,
      'createdAt': existing?['createdAt'] ?? now,
      'isCompleted': completed,
      'episodes': episodes,
      ..._resolvedPreferences(progress, existing),
    };
    await _storage!.write(key, jsonEncode(record));
    unawaited(DesktopCloudSyncService.instance.syncHistoryEntry(record));
  }

  @override
  Future<void> removeWatchProgress({
    required int mediaId,
    required String mediaType,
  }) async {
    await _ensureStorage();
    await _storage!.delete(_key(mediaId));
    await DesktopCloudSyncService.instance.removeHistoryEntry(mediaId);
  }

  @override
  Future<void> clearWatchHistory() async {
    await _ensureStorage();
    await _storage!.clear();
    await DesktopCloudSyncService.instance.clearCloudHistory();
  }

  static String _key(int mediaId) => 'null_$mediaId';

  static Map<String, dynamic>? _decode(String? encoded) {
    if (encoded == null) return null;
    try {
      final value = jsonDecode(encoded);
      if (value is Map) {
        return value.map((key, value) => MapEntry(key.toString(), value));
      }
    } catch (_) {}
    return null;
  }

  static int? _integer(Object? value) {
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '');
  }

  static DateTime _date(Object? value) {
    if (value is num) return DateTime.fromMillisecondsSinceEpoch(value.toInt());
    return DateTime.tryParse(value?.toString() ?? '') ?? DateTime(1970);
  }

  static Map<String, dynamic> _stringMap(Object? value) {
    if (value is! Map) return <String, dynamic>{};
    return value.map((key, value) => MapEntry(key.toString(), value));
  }

  static Map<String, dynamic> _preservedPreferences(
    Map<String, dynamic>? existing,
  ) => <String, dynamic>{
    if (existing?['preferredAudioTrack'] != null)
      'preferredAudioTrack': existing!['preferredAudioTrack'],
    if (existing?['preferredSubtitleTrack'] != null)
      'preferredSubtitleTrack': existing!['preferredSubtitleTrack'],
    if (existing?['preferredResolution'] != null)
      'preferredResolution': existing!['preferredResolution'],
    if (existing?['preferredProviderIndex'] != null)
      'preferredProviderIndex': existing!['preferredProviderIndex'],
  };

  static Map<String, dynamic> _resolvedPreferences(
    Map<String, dynamic> progress,
    Map<String, dynamic>? existing,
  ) => <String, dynamic>{
    ..._preservedPreferences(existing),
    if (progress['preferredAudioTrack'] != null)
      'preferredAudioTrack': progress['preferredAudioTrack'],
    if (progress['preferredSubtitleTrack'] != null)
      'preferredSubtitleTrack': progress['preferredSubtitleTrack'],
    if (progress['preferredResolution'] != null)
      'preferredResolution': progress['preferredResolution'],
    if (progress['preferredProviderIndex'] != null)
      'preferredProviderIndex': progress['preferredProviderIndex'],
  };

  static Map<String, dynamic> _preservedEpisodePreferences(Object? value) {
    final existing = _stringMap(value);
    return _preservedPreferences(existing);
  }

  @override
  void dispose() {
    _storageChanges?.removeListener(_onStorageChanged);
    super.dispose();
  }
}
