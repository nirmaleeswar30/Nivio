import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../../../core/config/app_environment.dart';
import '../../../core/constants/constants.dart';
import '../../auth/desktop_cloud_sync_service.dart';
import '../models/library_models.dart';
import 'desktop_download_service.dart';
import 'library_persistence.dart';

class LibrarySectionResult<T> {
  const LibrarySectionResult._({this.data, this.error, this.isOffline = false});

  const LibrarySectionResult.loaded(T data) : this._(data: data);

  const LibrarySectionResult.error(Object error, {bool isOffline = false})
    : this._(error: error, isOffline: isOffline);

  final T? data;
  final Object? error;
  final bool isOffline;

  bool get hasError => error != null;
}

class LibraryWatchlistService {
  Box<LibraryWatchlistItem> get _box => LibraryPersistence.watchlistBox;

  Future<LibrarySectionResult<List<LibraryWatchlistItem>>> getItems() async {
    try {
      if (!LibraryPersistence.isReady) {
        return const LibrarySectionResult.loaded([]);
      }
      final items = _box.values.toList()
        ..sort((a, b) => b.addedAt.compareTo(a.addedAt));
      return LibrarySectionResult.loaded(items);
    } catch (error) {
      return LibrarySectionResult.error(error);
    }
  }

  Future<void> remove(int mediaId) async {
    if (!LibraryPersistence.isReady) return;
    await _box.delete(mediaId);
    await DesktopCloudSyncService.instance.removeWatchlistItem(mediaId);
  }

  Future<void> add(LibraryWatchlistItem item) {
    if (!LibraryPersistence.isReady) return Future<void>.value();
    return _box.put(item.id, item).then((_) {
      unawaited(DesktopCloudSyncService.instance.syncWatchlistItem(item));
    });
  }

  Future<void> toggle(LibraryWatchlistItem item) async {
    if (!LibraryPersistence.isReady) return;
    if (_box.containsKey(item.id)) {
      await remove(item.id);
    } else {
      await add(item);
    }
  }

  bool isInWatchlist(int mediaId) {
    if (!LibraryPersistence.isReady) return false;
    return _box.containsKey(mediaId);
  }

  ValueListenable<Box<LibraryWatchlistItem>> listenable() => _box.listenable();
}

class LibraryDownloadsService {
  Box<LibraryDownloadItem> get _box => LibraryPersistence.downloadsBox;

  Future<LibrarySectionResult<List<LibraryDownloadItem>>> getItems() async {
    try {
      if (!LibraryPersistence.isReady) {
        return const LibrarySectionResult.loaded([]);
      }
      final items = _box.values.toList()
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return LibrarySectionResult.loaded(items);
    } catch (error) {
      return LibrarySectionResult.error(error);
    }
  }

  Future<void> delete(String id) {
    if (!LibraryPersistence.isReady) return Future<void>.value();
    return DesktopDownloadService.instance.deleteDownload(id);
  }

  Future<void> pause(String id) async {
    if (!LibraryPersistence.isReady) return;
    await DesktopDownloadService.instance.pauseDownload(id);
  }

  Future<void> resume(String id) async {
    if (!LibraryPersistence.isReady) return;
    await DesktopDownloadService.instance.resumeDownload(id);
  }

  Future<void> retry(String id) {
    if (!LibraryPersistence.isReady) return Future<void>.value();
    return DesktopDownloadService.instance.retryDownload(id);
  }

  bool fileExists(LibraryDownloadItem item) {
    if (item.savePath.isEmpty) return false;
    try {
      return File(item.savePath).existsSync();
    } catch (_) {
      return false;
    }
  }

  int? fileSizeBytes(LibraryDownloadItem item) {
    if (item.savePath.isEmpty) return null;
    try {
      final file = File(item.savePath);
      if (!file.existsSync()) return null;
      return file.lengthSync();
    } catch (_) {
      return null;
    }
  }

  ValueListenable<Box<LibraryDownloadItem>> listenable() => _box.listenable();
}

class LibraryScheduleService {
  LibraryScheduleService({Dio? dio, Dio? aniListDio})
    : _dio =
          dio ??
          Dio(
            BaseOptions(
              baseUrl: tmdbBaseUrl,
              connectTimeout: const Duration(seconds: 30),
              receiveTimeout: const Duration(seconds: 30),
              queryParameters: {'api_key': tmdbApiKey},
            ),
          ),
      _aniListDio =
          aniListDio ??
          Dio(
            BaseOptions(
              baseUrl: AppEnvironment.anilistApiUrl,
              connectTimeout: const Duration(seconds: 30),
              receiveTimeout: const Duration(seconds: 30),
            ),
          );

  final Dio _dio;
  final Dio _aniListDio;
  final Map<String, List<LibraryScheduleItem>> _cache = {};

  Future<LibrarySectionResult<List<LibraryScheduleItem>>> fetchForDate(
    DateTime date, {
    required bool watchlistOnly,
  }) async {
    final cacheKey = '${date.year}-${date.month}-${date.day}_$watchlistOnly';
    final cached = _cache[cacheKey];
    if (cached != null) return LibrarySectionResult.loaded(cached);

    try {
      final watchlist = LibraryPersistence.isReady
          ? LibraryPersistence.watchlistBox.values.toList()
          : <LibraryWatchlistItem>[];
      final results = await Future.wait([
        _fetchAniList(date, watchlistOnly, watchlist),
        _fetchTmdb(date, watchlistOnly, watchlist),
      ]);
      final rawItems = [...results[0], ...results[1]];
      final items = <LibraryScheduleItem>[];
      final uniqueItems = <int, LibraryScheduleItem>{};

      for (final item in rawItems) {
        if (item.id == -1) {
          items.add(item);
          continue;
        }
        final existing = uniqueItems[item.id];
        if (existing == null ||
            (!existing.hasPreciseTime && item.hasPreciseTime)) {
          uniqueItems[item.id] = item;
        }
      }

      items
        ..addAll(uniqueItems.values)
        ..sort((a, b) => a.releaseDate.compareTo(b.releaseDate));
      _cache[cacheKey] = items;
      return LibrarySectionResult.loaded(items);
    } catch (error) {
      return LibrarySectionResult.error(
        error,
        isOffline: error is DioException,
      );
    }
  }

  Future<List<LibraryScheduleItem>> _fetchAniList(
    DateTime date,
    bool watchlistOnly,
    List<LibraryWatchlistItem> watchlist,
  ) async {
    final items = <LibraryScheduleItem>[];
    try {
      final startOfDay =
          DateTime(date.year, date.month, date.day).millisecondsSinceEpoch ~/
          1000;
      final endOfDay =
          DateTime(
            date.year,
            date.month,
            date.day,
            23,
            59,
            59,
          ).millisecondsSinceEpoch ~/
          1000;
      final query =
          '''
        query {
          Page(page: 1, perPage: 50) {
            airingSchedules(airingAt_greater: $startOfDay, airingAt_lesser: $endOfDay, sort: TIME) {
              airingAt
              episode
              media {
                id
                title {
                  romaji
                  english
                }
                coverImage {
                  large
                }
              }
            }
          }
        }
      ''';

      final response = await _aniListDio.post('', data: {'query': query});
      final schedules =
          response.data['data']['Page']['airingSchedules'] as List<dynamic>? ??
          const [];

      for (final schedule in schedules) {
        final media = schedule['media'] as Map<String, dynamic>;
        final titleMap = media['title'] as Map<String, dynamic>;
        final title =
            titleMap['english'] as String? ??
            titleMap['romaji'] as String? ??
            'Unknown Anime';
        final airingAt = schedule['airingAt'] as int;
        final episode = schedule['episode'] as int?;
        final aniListId = media['id'] as int? ?? -1;
        int? tmdbId;
        String? tmdbPoster;
        var isInWatchlist = false;

        if (watchlistOnly) {
          final match = _findAnimeWatchlistMatch(media, title, watchlist);
          if (match != null) {
            isInWatchlist = true;
            tmdbId = match.id;
            tmdbPoster = match.posterPath;
          }
        } else {
          isInWatchlist = true;
        }

        if (isInWatchlist) {
          items.add(
            LibraryScheduleItem(
              id: tmdbId ?? aniListId,
              title: title,
              mediaType: 'anime',
              releaseDate: DateTime.fromMillisecondsSinceEpoch(airingAt * 1000),
              seasonNumber: 1,
              episodeNumber: episode,
              posterPath:
                  tmdbPoster ??
                  (media['coverImage'] as Map<String, dynamic>?)?['large']
                      as String?,
              hasPreciseTime: true,
            ),
          );
        }
      }
    } catch (_) {
      return items;
    }
    return items;
  }

  Future<List<LibraryScheduleItem>> _fetchTmdb(
    DateTime date,
    bool watchlistOnly,
    List<LibraryWatchlistItem> watchlist,
  ) async {
    final items = <LibraryScheduleItem>[];
    try {
      if (watchlistOnly) {
        final tvShows = watchlist
            .where(
              (item) =>
                  item.mediaType == 'tv' &&
                  !item.title.toLowerCase().contains('anime'),
            )
            .toList();
        final results = await Future.wait(
          tvShows.map((show) async {
            try {
              final response = await _dio.get('/3/tv/${show.id}');
              final nextEpisode = response.data['next_episode_to_air'];
              final airDateText = nextEpisode?['air_date'] as String?;
              final airDate = DateTime.tryParse(airDateText ?? '');
              if (airDate == null ||
                  airDate.year != date.year ||
                  airDate.month != date.month ||
                  airDate.day != date.day) {
                return null;
              }
              return LibraryScheduleItem(
                id: show.id,
                title: show.title,
                mediaType: 'tv',
                releaseDate: DateTime(date.year, date.month, date.day, 12),
                seasonNumber: nextEpisode['season_number'] as int?,
                episodeNumber: nextEpisode['episode_number'] as int?,
                posterPath: show.posterPath,
              );
            } catch (_) {
              return null;
            }
          }),
        );
        items.addAll(results.whereType<LibraryScheduleItem>());
      } else {
        final response = await _dio.get('/3/tv/airing_today');
        final shows = response.data['results'] as List<dynamic>? ?? const [];
        for (final show in shows) {
          items.add(
            LibraryScheduleItem(
              id: show['id'] as int,
              title: show['name'] as String? ?? 'Untitled',
              mediaType: 'tv',
              releaseDate: DateTime(date.year, date.month, date.day, 12),
              posterPath: show['poster_path'] as String?,
            ),
          );
        }
      }
    } catch (_) {
      return items;
    }
    return items;
  }

  LibraryWatchlistItem? _findAnimeWatchlistMatch(
    Map<String, dynamic> media,
    String englishTitle,
    List<LibraryWatchlistItem> watchlist,
  ) {
    final mediaId = media['id'] as int?;
    final romajiTitle = (media['title'] as Map<String, dynamic>?)?['romaji']
        ?.toString()
        .toLowerCase();
    final english = englishTitle.toLowerCase();

    for (final item in watchlist) {
      if (item.mediaType == 'anime' && item.id == mediaId) return item;
      if (item.mediaType != 'tv') continue;
      final title = item.title.toLowerCase();
      if (_isTitleMatch(title, english)) return item;
      if (romajiTitle != null && _isTitleMatch(title, romajiTitle)) return item;
      final titleBase = title.split(RegExp(r'[:\-]')).first.trim();
      final englishBase = english.split(RegExp(r'[:\-]')).first.trim();
      if (titleBase.isNotEmpty &&
          englishBase.isNotEmpty &&
          _isTitleMatch(titleBase, englishBase)) {
        return item;
      }
      if (romajiTitle != null) {
        final romajiBase = romajiTitle.split(RegExp(r'[:\-]')).first.trim();
        if (titleBase.isNotEmpty &&
            romajiBase.isNotEmpty &&
            _isTitleMatch(titleBase, romajiBase)) {
          return item;
        }
      }
    }
    return null;
  }

  bool _isTitleMatch(String first, String second) {
    if (first == second) return true;
    if (first.length <= 4) return false;
    return second.startsWith('$first ') ||
        first.startsWith('$second ') ||
        second.startsWith('$first:') ||
        first.startsWith('$second:');
  }
}
