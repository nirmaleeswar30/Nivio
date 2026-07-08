import 'package:dio/dio.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:nivio/core/constants.dart';
import 'package:nivio/core/debug_log.dart';
import 'package:nivio/models/watchlist_item.dart';

class ScheduleItem {
  final int id;
  final String title;
  final String mediaType; // 'anime', 'tv', 'movie'
  final DateTime releaseDate;
  final int? seasonNumber;
  final int? episodeNumber;
  final String? posterPath;
  final bool hasPreciseTime; // true for AniList, false for TMDB

  ScheduleItem({
    required this.id,
    required this.title,
    required this.mediaType,
    required this.releaseDate,
    this.seasonNumber,
    this.episodeNumber,
    this.posterPath,
    this.hasPreciseTime = false,
  });
}

class ScheduleApiService {
  static final Dio _dio = Dio(
    BaseOptions(
      baseUrl: tmdbBaseUrl,
      connectTimeout: const Duration(seconds: 30),
      receiveTimeout: const Duration(seconds: 30),
      queryParameters: {'api_key': tmdbApiKey},
    ),
  );

  static final Dio _aniListDio = Dio(
    BaseOptions(
      baseUrl: 'https://graphql.anilist.co',
      connectTimeout: const Duration(seconds: 30),
      receiveTimeout: const Duration(seconds: 30),
    ),
  );

  static final Map<String, List<ScheduleItem>> _cache = {};

  static Future<List<ScheduleItem>> fetchScheduleForDate(
    DateTime date, {
    bool watchlistOnly = true,
  }) async {
    final cacheKey = '${date.year}-${date.month}-${date.day}_$watchlistOnly';

    if (_cache.containsKey(cacheKey)) {
      return _cache[cacheKey]!;
    }

    final List<ScheduleItem> items = [];

    // Ensure Hive box is open for watchlist
    if (!Hive.isBoxOpen('watchlist')) {
      await Hive.openBox<WatchlistItem>('watchlist');
    }
    final box = Hive.box<WatchlistItem>('watchlist');
    final watchlist = box.values.toList();

    try {
      final results = await Future.wait([
        _fetchAniList(date, watchlistOnly, watchlist),
        _fetchTmdb(date, watchlistOnly, watchlist),
      ]);

      final List<ScheduleItem> rawItems = [];
      rawItems.addAll(results[0]);
      rawItems.addAll(results[1]);
      
      // Deduplicate by ID (TMDB ID). If both AniList and TMDB return the same show, 
      // prioritize the one with hasPreciseTime == true (AniList).
      final Map<int, ScheduleItem> uniqueItems = {};
      for (var item in rawItems) {
        if (item.id != -1) {
           if (!uniqueItems.containsKey(item.id) || (!uniqueItems[item.id]!.hasPreciseTime && item.hasPreciseTime)) {
             uniqueItems[item.id] = item;
           }
        } else {
           // If ID is -1 (unmatched AniList), just add it with a pseudo-ID or keep it
           items.add(item);
        }
      }
      
      items.addAll(uniqueItems.values);
      items.sort((a, b) => a.releaseDate.compareTo(b.releaseDate));
      
      _cache[cacheKey] = items;
    } catch (e) {
      appDebugLog('⚠️ Error in fetchScheduleForDate: $e');
    }

    return items;
  }

  static Future<List<ScheduleItem>> _fetchAniList(DateTime date, bool watchlistOnly, List<WatchlistItem> watchlist) async {
    final List<ScheduleItem> items = [];
    try {
      final startOfDay = DateTime(date.year, date.month, date.day).millisecondsSinceEpoch ~/ 1000;
      final endOfDay = DateTime(date.year, date.month, date.day, 23, 59, 59).millisecondsSinceEpoch ~/ 1000;

      final query = '''
        query {
          Page(page: 1, perPage: 50) {
            airingSchedules(airingAt_greater: $startOfDay, airingAt_lesser: $endOfDay, sort: TIME) {
              airingAt
              episode
              media {
                id
                idMal
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
      final schedules = response.data['data']['Page']['airingSchedules'] as List<dynamic>? ?? [];

      for (var schedule in schedules) {
        final media = schedule['media'];
        final title = media['title']['english'] ?? media['title']['romaji'] ?? 'Unknown Anime';
        final airingAt = schedule['airingAt'] as int;
        final episode = schedule['episode'] as int;
        
        int? tmdbId;
        String? tmdbPoster;
        bool isInWatchlist = false;

        if (watchlistOnly) {
           final String englishTitle = title.toLowerCase();
           final String? romajiTitle = media['title']['romaji']?.toString().toLowerCase();
           
           final match = watchlist.where((w) {
             if (w.mediaType == 'anime' && w.id == media['id']) return true;
             if (w.mediaType != 'tv') return false;
             final wTitle = w.title.toLowerCase();
             bool isMatch(String name1, String name2) {
               if (name1 == name2) return true;
               if (name1.length > 4) {
                 if (name2.startsWith(name1 + ' ') || name1.startsWith(name2 + ' ')) return true;
                 if (name2.startsWith(name1 + ':') || name1.startsWith(name2 + ':')) return true;
               }
               return false;
             }
             
             if (isMatch(wTitle, englishTitle)) return true;
             if (romajiTitle != null && isMatch(wTitle, romajiTitle)) return true;
             
             // Try matching just the first part before a colon or hyphen
             if (wTitle.length > 4) {
               final wBase = wTitle.split(RegExp(r'[:\-]')).first.trim();
               final englishBase = englishTitle.split(RegExp(r'[:\-]')).first.trim();
               if (wBase.isNotEmpty && englishBase.isNotEmpty && isMatch(wBase, englishBase)) return true;
               
               if (romajiTitle != null) {
                  final romajiBase = romajiTitle.split(RegExp(r'[:\-]')).first.trim();
                  if (wBase.isNotEmpty && romajiBase.isNotEmpty && isMatch(wBase, romajiBase)) return true;
               }
             }
             
             return false;
           }).firstOrNull;

           if (match != null) {
             isInWatchlist = true;
             tmdbId = match.id;
             tmdbPoster = match.posterPath;
           }
        } else {
           isInWatchlist = true;
        }

        if (isInWatchlist) {
           items.add(ScheduleItem(
             id: tmdbId ?? -1,
             title: title,
             mediaType: 'anime',
             releaseDate: DateTime.fromMillisecondsSinceEpoch(airingAt * 1000),
             seasonNumber: 1,
             episodeNumber: episode,
             posterPath: tmdbPoster ?? media['coverImage']['large'],
             hasPreciseTime: true,
           ));
        }
      }
    } catch (e) {
      appDebugLog('⚠️ Error fetching AniList schedule: $e');
    }
    return items;
  }

  static Future<List<ScheduleItem>> _fetchTmdb(DateTime date, bool watchlistOnly, List<WatchlistItem> watchlist) async {
    final List<ScheduleItem> items = [];
    try {
      if (watchlistOnly) {
         final tvShows = watchlist.where((w) => w.mediaType == 'tv' && !w.title.toLowerCase().contains('anime')).toList();
         
         // Parallelize TMDB detail requests
         final futures = tvShows.map((show) async {
            try {
               final res = await _dio.get('/3/tv/${show.id}');
               final nextEp = res.data['next_episode_to_air'];
               if (nextEp != null) {
                  final airDateStr = nextEp['air_date'] as String?;
                  if (airDateStr != null) {
                     final airDate = DateTime.tryParse(airDateStr);
                     if (airDate != null && airDate.year == date.year && airDate.month == date.month && airDate.day == date.day) {
                        return ScheduleItem(
                          id: show.id,
                          title: show.title,
                          mediaType: 'tv',
                          releaseDate: DateTime(date.year, date.month, date.day, 12, 0),
                          seasonNumber: nextEp['season_number'] as int?,
                          episodeNumber: nextEp['episode_number'] as int?,
                          posterPath: show.posterPath,
                          hasPreciseTime: false,
                        );
                     }
                  }
               }
            } catch (e) {
               // ignore failures for individual shows
            }
            return null;
         });

         final results = await Future.wait(futures);
         items.addAll(results.whereType<ScheduleItem>());
      } else {
         final res = await _dio.get('/3/tv/airing_today');
         final shows = res.data['results'] as List<dynamic>? ?? [];
         for (var show in shows) {
           items.add(ScheduleItem(
             id: show['id'],
             title: show['name'],
             mediaType: 'tv',
             releaseDate: DateTime(date.year, date.month, date.day, 12, 0),
             posterPath: show['poster_path'],
             hasPreciseTime: false,
           ));
         }
      }
    } catch (e) {
      appDebugLog('⚠️ Error fetching TMDB TV schedule: $e');
    }
    return items;
  }
}
