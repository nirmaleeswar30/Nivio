import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:nivio/models/season_info.dart';
import 'package:nivio/models/search_result.dart';
import 'package:dio/dio.dart';

import 'package:nivio/core/debug_log.dart';
import 'package:nivio/services/cache_service.dart';

class AniListResult {
  final int id;
  final int? idMal;

  AniListResult({required this.id, this.idMal});
}

/// Service for interacting with AniList API
/// Converts TMDB IDs to AniList IDs for anime content
class AniListService {
  final Dio _dio;
  final CacheService _cache;
  static const String _baseUrl = 'https://graphql.anilist.co';

  AniListService(this._cache)
    : _dio = Dio(
        BaseOptions(
          baseUrl: _baseUrl,
          connectTimeout: const Duration(seconds: 25),
          receiveTimeout: const Duration(seconds: 25),
        ),
      );

  /// Search for anime by title and year to find AniList ID
  /// Returns null if no match found
  Future<AniListResult?> getAniListIdFromTMDB({
    required String title,
    String? year,
    int? tmdbId,
  }) async {
    final cacheKey = 'anilist_mapping_${tmdbId ?? ''}_$title\_$year';
    final cached = await _cache.get<AniListResult>(
      cacheKey,
      (json) => AniListResult(
        id: json['id'] as int,
        idMal: json['idMal'] as int?,
      ),
    );
    if (cached != null) return cached;

    try {
      // GraphQL query to search for anime
      const query = '''
        query (\$search: String, \$season: MediaSeason, \$seasonYear: Int) {
          Media(search: \$search, type: ANIME, season: \$season, seasonYear: \$seasonYear, sort: POPULARITY_DESC) {
            id
            idMal
            title {
              romaji
              english
              native
            }
            startDate {
              year
            }
            season
            seasonYear
          }
        }
      ''';

      final variables = {
        'search': title,
        if (year != null) 'seasonYear': int.tryParse(year),
      };

      appDebugLog('🔍 Searching AniList for: $title ${year ?? ''}');

      final response = await _dio.post(
        '',
        data: {'query': query, 'variables': variables},
      );

      if (response.statusCode == 200 &&
          response.data['data']['Media'] != null) {
        final anilistId = response.data['data']['Media']['id'] as int;
        final idMal = response.data['data']['Media']['idMal'] as int?;
        appDebugLog('✅ Found AniList ID: $anilistId, MAL ID: $idMal for $title');
        final result = AniListResult(id: anilistId, idMal: idMal);
        
        await _cache.set(
          cacheKey,
          {'id': anilistId, 'idMal': idMal},
          ttl: CacheService.extraLongCache,
        );
        
        return result;
      }

      appDebugLog('❌ No AniList match found for: $title');
      return null;
    } on DioException catch (e) {
      appDebugLog('❌ DioException fetching AniList ID: ${e.message}');
      return null;
    } catch (e) {
      appDebugLog('❌ Error fetching AniList ID: $e');
      return null;
    }
  }

  /// Check if a title is likely anime by searching AniList
  Future<bool> isAnime(String title, String? year) async {
    final result = await getAniListIdFromTMDB(title: title, year: year);
    return result != null;
  }
  Future<Map<String, dynamic>> getAnimeDetailsWithExtras(int id) async {
    final cacheKey = 'anilist_details_$id';
    final cached = await _cache.get<Map<String, dynamic>>(
      cacheKey,
      (json) => json,
    );
    if (cached != null) return cached;

    const String query = '''
      query (\$id: Int) {
        Media(id: \$id) {
          id
          idMal
          title {
            romaji
            english
          }
          description
          coverImage {
            extraLarge
            large
          }
          bannerImage
          averageScore
          status
          format
          episodes
          seasonYear
          genres
          trailer {
            id
            site
          }
          characters(sort: [ROLE, RELEVANCE], perPage: 15) {
            edges {
              role
              node {
                id
                name {
                  full
                }
                image {
                  large
                }
              }
              voiceActors(language: JAPANESE) {
                id
                name {
                  full
                }
                image {
                  large
                }
              }
            }
          }
        }
      }
    ''';

    try {
      final response = await _dio.post('', data: {
        'query': query,
        'variables': {'id': id},
      });

      final data = response.data['data']['Media'] as Map<String, dynamic>;
      await _cache.set(cacheKey, data, ttl: CacheService.longCache);
      return data;
    } catch (e) {
      appDebugLog('AniList getAnimeDetailsWithExtras error: $e');
      throw Exception('Failed to load anime details');
    }
  }

  SearchResult mapToSearchResult(Map<String, dynamic> media) {
    return SearchResult(
      id: media['id'],
      malId: media['idMal'],
      title: media['title']?['english'] ?? media['title']?['romaji'] ?? 'Unknown',
      name: media['title']?['english'] ?? media['title']?['romaji'] ?? 'Unknown',
      posterPath: media['coverImage']?['extraLarge'] ?? media['coverImage']?['large'],
      backdropPath: media['bannerImage'],
      overview: media['description']?.replaceAll(RegExp(r'<[^>]*>'), ''),
      voteAverage: (media['averageScore'] as num?)?.toDouble() != null ? media['averageScore'] / 10.0 : 0.0,
      firstAirDate: media['seasonYear']?.toString(),
      mediaType: 'anime',
    );
  }
  Future<List<SearchResult>> getAnimeRecommendations(int id) async {
    const String query = '''
      query (\$id: Int) {
        Media(id: \$id) {
          recommendations(sort: [RATING_DESC], perPage: 20) {
            edges {
              node {
                mediaRecommendation {
                  id
                  idMal
                  title {
                    romaji
                    english
                  }
                  description
                  coverImage {
                    extraLarge
                    large
                  }
                  bannerImage
                  averageScore
                  status
                  format
                  episodes
                  seasonYear
                  genres
                }
              }
            }
          }
        }
      }
    ''';

    try {
      final response = await _dio.post('', data: {
        'query': query,
        'variables': {'id': id},
      });

      final data = response.data['data']['Media']['recommendations']['edges'] as List<dynamic>?;
      if (data == null) return [];

      return data
          .map((edge) => edge['node']?['mediaRecommendation'])
          .where((media) => media != null)
          .map((media) => mapToSearchResult(media))
          .toList();
    } catch (e) {
      appDebugLog('AniList getAnimeRecommendations error: $e');
      return [];
    }
  }

  /// Get latest released anime episodes (episodes aired within the last 14 days, deduplicated by show)
  Future<List<Map<String, dynamic>>> getLatestAiringAnime() async {
    const cacheKey = 'latest_airing_anime';
    final cached = await _cache.getRaw(cacheKey);
    if (cached != null && cached['results'] is List) {
      return (cached['results'] as List).cast<Map<String, dynamic>>();
    }

    try {
      final now = DateTime.now();
      final nowSec = now.millisecondsSinceEpoch ~/ 1000;
      final fourteenDaysAgoSec = now.subtract(const Duration(days: 14)).millisecondsSinceEpoch ~/ 1000;

      const String query = '''
        query (\$greater: Int, \$lesser: Int) {
          Page(page: 1, perPage: 50) {
            airingSchedules(airingAt_greater: \$greater, airingAt_lesser: \$lesser, sort: TIME_DESC) {
              id
              airingAt
              episode
              media {
                id
                idMal
                title {
                  romaji
                  english
                  userPreferred
                }
                format
                status
                episodes
                bannerImage
                coverImage {
                  extraLarge
                  large
                }
                averageScore
                popularity
                genres
                season
                seasonYear
              }
            }
          }
        }
      ''';

      final response = await _dio.post('', data: {
        'query': query,
        'variables': {
          'greater': fourteenDaysAgoSec,
          'lesser': nowSec,
        },
      });

      final schedules = response.data['data']?['Page']?['airingSchedules'] as List<dynamic>? ?? [];
      final seenMediaIds = <int>{};
      final results = <Map<String, dynamic>>[];

      for (final schedule in schedules) {
        if (schedule is! Map) continue;
        final media = schedule['media'];
        if (media is! Map) continue;
        final mediaId = media['id'] as int?;
        if (mediaId == null || seenMediaIds.contains(mediaId)) continue;
        seenMediaIds.add(mediaId);

        final titleMap = media['title'] as Map? ?? {};
        final title = (titleMap['english'] ?? titleMap['romaji'] ?? titleMap['userPreferred'] ?? 'Anime').toString();
        final episode = schedule['episode'] as int?;
        final airingAtSec = schedule['airingAt'] as int?;
        final coverImage = media['coverImage'] as Map? ?? {};
        final poster = coverImage['extraLarge'] ?? coverImage['large'];
        final backdrop = media['bannerImage'] ?? poster;
        final averageScore = (media['averageScore'] as num?)?.toDouble();
        final voteAverage = averageScore != null ? averageScore / 10.0 : null;

        results.add({
          'id': mediaId,
          'mal_id': media['idMal'],
          'title': title,
          'name': title,
          'media_type': 'anime',
          'poster_path': poster,
          'backdrop_path': backdrop,
          'vote_average': voteAverage,
          'episode_number': episode,
          'airing_at': airingAtSec,
          'format': media['format'] ?? 'TV',
          'release_date': airingAtSec != null 
              ? DateTime.fromMillisecondsSinceEpoch(airingAtSec * 1000).toIso8601String() 
              : null,
          'first_air_date': airingAtSec != null 
              ? DateTime.fromMillisecondsSinceEpoch(airingAtSec * 1000).toIso8601String() 
              : null,
        });
      }

      results.sort((a, b) {
        final timeA = (a['airing_at'] as num?) ?? 0;
        final timeB = (b['airing_at'] as num?) ?? 0;
        return timeB.compareTo(timeA);
      });

      await _cache.set(cacheKey, {'results': results}, ttl: CacheService.shortCache);
      return results;
    } catch (e) {
      appDebugLog('AniList getLatestAiringAnime error: $e');
      return [];
    }
  }

  Future<SearchResults> getTrendingAnime({int page = 1}) async {
    const String query = '''
      query (\$page: Int) {
        Page(page: \$page, perPage: 20) {
          pageInfo { total currentPage lastPage }
          media(type: ANIME, sort: TRENDING_DESC) {
            id
            idMal
            title { romaji english }
            description
            coverImage { extraLarge large }
            bannerImage
            averageScore
            seasonYear
          }
        }
      }
    ''';
    try {
      final response = await _dio.post('', data: {'query': query, 'variables': {'page': page}});
      final pageInfo = response.data['data']['Page']['pageInfo'];
      final data = response.data['data']['Page']['media'] as List<dynamic>;
      return SearchResults(
        page: pageInfo['currentPage'] ?? page,
        results: data.map((e) => mapToSearchResult(e)).toList(),
        totalPages: pageInfo['lastPage'] ?? 1,
        totalResults: pageInfo['total'] ?? data.length,
      );
    } catch (e) {
      appDebugLog('getTrendingAnime error: $e');
      return const SearchResults(page: 1, results: [], totalPages: 1, totalResults: 0);
    }
  }

  Future<List<Map<String, dynamic>>> getTrendingAnimeForFeatured() async {
    const String query = '''
      query {
        Page(page: 1, perPage: 10) {
          media(type: ANIME, sort: TRENDING_DESC) {
            id
            idMal
            title { romaji english }
            description
            coverImage { extraLarge large }
            bannerImage
            averageScore
            season
            seasonYear
            genres
            format
            status
            episodes
          }
        }
      }
    ''';
    try {
      final response = await _dio.post('', data: {'query': query});
      final data = response.data['data']['Page']['media'] as List<dynamic>;
      return data.map((e) => e as Map<String, dynamic>).toList();
    } catch (e) {
      print('\n\n--- ANILIST HERO BANNER ERROR: $e ---\n\n');
      appDebugLog('getTrendingAnimeForFeatured error: $e');
      return [];
    }
  }

  Future<SearchResults> getPopularAnime({int page = 1}) async {
    const String query = '''
      query (\$page: Int) {
        Page(page: \$page, perPage: 20) {
          pageInfo { total currentPage lastPage }
          media(type: ANIME, sort: POPULARITY_DESC) {
            id
            idMal
            title { romaji english }
            description
            coverImage { extraLarge large }
            bannerImage
            averageScore
            seasonYear
          }
        }
      }
    ''';
    try {
      final response = await _dio.post('', data: {'query': query, 'variables': {'page': page}});
      final pageInfo = response.data['data']['Page']['pageInfo'];
      final data = response.data['data']['Page']['media'] as List<dynamic>;
      return SearchResults(
        page: pageInfo['currentPage'] ?? page,
        results: data.map((e) => mapToSearchResult(e)).toList(),
        totalPages: pageInfo['lastPage'] ?? 1,
        totalResults: pageInfo['total'] ?? data.length,
      );
    } catch (e) {
      appDebugLog('getPopularAnime error: $e');
      return const SearchResults(page: 1, results: [], totalPages: 1, totalResults: 0);
    }
  }

  Future<SearchResults> searchAnime(String queryStr, {int page = 1}) async {
    const String query = '''
      query (\$search: String, \$page: Int) {
        Page(page: \$page, perPage: 20) {
          pageInfo { total currentPage lastPage }
          media(search: \$search, type: ANIME, sort: POPULARITY_DESC) {
            id
            idMal
            title { romaji english }
            description
            coverImage { extraLarge large }
            bannerImage
            averageScore
            seasonYear
          }
        }
      }
    ''';
    try {
      final response = await _dio.post('', data: {'query': query, 'variables': {'search': queryStr, 'page': page}});
      final pageInfo = response.data['data']['Page']['pageInfo'];
      final data = response.data['data']['Page']['media'] as List<dynamic>;
      return SearchResults(
        page: pageInfo['currentPage'] ?? page,
        results: data.map((e) => mapToSearchResult(e)).toList(),
        totalPages: pageInfo['lastPage'] ?? 1,
        totalResults: pageInfo['total'] ?? data.length,
      );
    } catch (e) {
      appDebugLog('searchAnime error: $e');
      return const SearchResults(page: 1, results: [], totalPages: 1, totalResults: 0);
    }
  }

  Future<SearchResult> getAnimeDetails(int id) async {
    const String query = '''
      query (\$id: Int) {
        Media(id: \$id) {
          id
          idMal
          title { romaji english }
          description
          coverImage { extraLarge large }
          bannerImage
          averageScore
          seasonYear
        }
      }
    ''';
    try {
      final response = await _dio.post('', data: {'query': query, 'variables': {'id': id}});
      final data = response.data['data']['Media'];
      return mapToSearchResult(data);
    } catch (e) {
      appDebugLog('getAnimeDetails error: $e');
      throw Exception('Failed to get anime details');
    }
  }

  int _parseSeasonNumber(String title) {
    final seasonMatch = RegExp(r'\b(?:Season|Cour|Part)\s*(\d+)\b', caseSensitive: false).firstMatch(title) ??
        RegExp(r'\b(\d+)(?:st|nd|rd|th)\s+Season\b', caseSensitive: false).firstMatch(title);
    if (seasonMatch != null) {
      return int.tryParse(seasonMatch.group(1) ?? '') ?? 1;
    }
    final romanMatch = RegExp(r'\b(?:Season\s+)?(II|III|IV|V|VI|VII|VIII|IX|X)\b').firstMatch(title);
    if (romanMatch != null) {
      const romanMap = {'II': 2, 'III': 3, 'IV': 4, 'V': 5, 'VI': 6, 'VII': 7, 'VIII': 8, 'IX': 9, 'X': 10};
      return romanMap[romanMatch.group(1)!] ?? 1;
    }
    return 1;
  }

  Future<SeriesInfo> getAnimeSeriesInfo(int id) async {
    const String query = '''
      query (\$id: Int) {
        Media(id: \$id) {
          id
          title { romaji english }
          episodes
          format
          relations {
            edges {
              relationType
              node {
                id
                title { romaji english }
                format
                type
                episodes
              }
            }
          }
        }
      }
    ''';
    try {
      final response = await _dio.post('', data: {'query': query, 'variables': {'id': id}});
      final media = response.data['data']['Media'];
      if (media == null) {
        return const SeriesInfo(numberOfSeasons: 1, seasons: []);
      }

      final titleMap = media['title'] as Map? ?? {};
      final title = titleMap['english'] ?? titleMap['romaji'] ?? '';
      final curSeasonNum = _parseSeasonNumber(title);
      final epCount = media['episodes'] ?? 12;

      final seasonsMap = <int, SeasonInfo>{};
      seasonsMap[curSeasonNum] = SeasonInfo(
        id: media['id'],
        name: 'Season $curSeasonNum',
        seasonNumber: curSeasonNum,
        episodeCount: epCount,
      );

      final relations = media['relations']?['edges'] as List? ?? [];
      for (final rel in relations) {
        final node = rel['node'];
        if (node == null || node['type'] != 'ANIME') continue;
        final format = node['format'];
        if (format != 'TV' && format != 'TV_SHORT' && format != 'ONA') continue;

        final relType = rel['relationType'];
        final relTitleMap = node['title'] as Map? ?? {};
        final relTitle = relTitleMap['english'] ?? relTitleMap['romaji'] ?? '';
        var relSeasonNum = _parseSeasonNumber(relTitle);

        if (relType == 'PREQUEL' && relSeasonNum == 1 && curSeasonNum > 1) {
          relSeasonNum = curSeasonNum - 1;
        } else if (relType == 'SEQUEL' && relSeasonNum == 1) {
          relSeasonNum = curSeasonNum + 1;
        }

        if (!seasonsMap.containsKey(relSeasonNum)) {
          seasonsMap[relSeasonNum] = SeasonInfo(
            id: node['id'],
            name: 'Season $relSeasonNum',
            seasonNumber: relSeasonNum,
            episodeCount: node['episodes'] ?? 12,
          );
        }
      }

      // Check if we can expand prequels back to Season 1
      int checkPrequelId = 0;
      int checkPrequelSeason = 0;
      for (final rel in relations) {
        if (rel['relationType'] == 'PREQUEL' && rel['node']?['type'] == 'ANIME') {
          checkPrequelId = rel['node']['id'];
          final pTitleMap = rel['node']['title'] as Map? ?? {};
          final pTitle = pTitleMap['english'] ?? pTitleMap['romaji'] ?? '';
          checkPrequelSeason = _parseSeasonNumber(pTitle);
          if (checkPrequelSeason == 1 && curSeasonNum > 1) checkPrequelSeason = curSeasonNum - 1;
          break;
        }
      }

      while (checkPrequelId > 0 && checkPrequelSeason > 1) {
        try {
          final pRes = await _dio.post('', data: {
            'query': '''
              query (\$id: Int) {
                Media(id: \$id) {
                  relations {
                    edges {
                      relationType
                      node {
                        id
                        title { romaji english }
                        format
                        type
                        episodes
                      }
                    }
                  }
                }
              }
            ''',
            'variables': {'id': checkPrequelId}
          });
          final pEdges = pRes.data['data']?['Media']?['relations']?['edges'] as List? ?? [];
          int nextPrequelId = 0;
          for (final edge in pEdges) {
            if (edge['relationType'] == 'PREQUEL' && edge['node']?['type'] == 'ANIME') {
              final pNode = edge['node'];
              final format = pNode['format'];
              if (format != 'TV' && format != 'TV_SHORT' && format != 'ONA') continue;
              final pTitleMap = pNode['title'] as Map? ?? {};
              final pTitle = pTitleMap['english'] ?? pTitleMap['romaji'] ?? '';
              var pNum = _parseSeasonNumber(pTitle);
              if (pNum >= checkPrequelSeason) pNum = checkPrequelSeason - 1;
              if (pNum < 1) pNum = 1;

              if (!seasonsMap.containsKey(pNum)) {
                seasonsMap[pNum] = SeasonInfo(
                  id: pNode['id'],
                  name: 'Season $pNum',
                  seasonNumber: pNum,
                  episodeCount: pNode['episodes'] ?? 12,
                );
              }
              nextPrequelId = pNode['id'];
              checkPrequelSeason = pNum;
              break;
            }
          }
          checkPrequelId = nextPrequelId;
        } catch (_) {
          break;
        }
      }

      final sortedSeasons = seasonsMap.values.toList()
        ..sort((a, b) => a.seasonNumber.compareTo(b.seasonNumber));

      return SeriesInfo(
        numberOfSeasons: sortedSeasons.length,
        seasons: sortedSeasons,
      );
    } catch (e) {
      appDebugLog('getAnimeSeriesInfo error: $e');
      return const SeriesInfo(numberOfSeasons: 1, seasons: []);
    }
  }

  Future<SeasonData> getAnimeSeasonData(int id) async {
    // Try to fetch real episode metadata from AniZip
    try {
      final zipReq = await http.get(Uri.parse('https://api.ani.zip/mappings?anilist_id=$id')).timeout(const Duration(seconds: 5));
      if (zipReq.statusCode == 200) {
        final zipData = jsonDecode(zipReq.body);
        final episodesMap = zipData['episodes'] as Map<String, dynamic>?;
        if (episodesMap != null && episodesMap.isNotEmpty) {
          List<EpisodeData> episodes = [];
          
          // Convert map values to list and sort by episode key (which represents AniList episode number)
          final sortedKeys = episodesMap.keys.where((k) => int.tryParse(k) != null).toList()
            ..sort((a, b) => int.parse(a).compareTo(int.parse(b)));

          for (final key in sortedKeys) {
            final ep = episodesMap[key];
            if (ep is Map) {
              final titleObj = ep['title'];
              String? name;
              if (titleObj is Map) {
                name = titleObj['en'] ?? titleObj['x-jat'] ?? titleObj['ja'];
              }
              
              final ratingStr = ep['rating'];
              double? rating;
              if (ratingStr != null) {
                rating = double.tryParse(ratingStr.toString());
              }

              episodes.add(EpisodeData(
                episodeNumber: int.parse(key),
                episodeName: name ?? 'Episode $key',
                overview: ep['overview'] ?? ep['summary'],
                stillPath: ep['image'],
                voteAverage: rating,
                runtime: ep['runtime'] ?? ep['length'],
                airDate: ep['airDateUtc'] ?? ep['airDate'] ?? ep['airdate'],
              ));
            }
          }
          
          if (episodes.isNotEmpty) {
            return SeasonData(episodes: episodes);
          }
        }
      }
    } catch (e) {
      appDebugLog('AniZip episode fetch failed for anime $id: $e');
    }

    // Fallback to GraphQL if AniZip fails
    const String query = '''
      query (\$id: Int) {
        Media(id: \$id) {
          episodes
          nextAiringEpisode { episode airingAt }
          airingSchedule(perPage: 50) {
            nodes {
              airingAt
              episode
            }
          }
        }
      }
    ''';
    try {
      final response = await _dio.post('', data: {'query': query, 'variables': {'id': id}});
      final media = response.data['data']['Media'];
      int totalEpisodes = media['episodes'] ?? 0;
      final nextAiring = media['nextAiringEpisode'];
      if (totalEpisodes == 0) {
        if (nextAiring != null) {
          totalEpisodes = (nextAiring['episode'] as int) - 1;
        } else {
          totalEpisodes = 12;
        }
      }

      final airingMap = <int, String>{};
      final schedules = media['airingSchedule']?['nodes'] as List<dynamic>? ?? [];
      for (final s in schedules) {
        if (s is Map && s['episode'] != null && s['airingAt'] != null) {
          final epNum = s['episode'] as int;
          final airSec = s['airingAt'] as int;
          airingMap[epNum] = DateTime.fromMillisecondsSinceEpoch(airSec * 1000, isUtc: true).toIso8601String();
        }
      }
      if (nextAiring != null && nextAiring['episode'] != null && nextAiring['airingAt'] != null) {
        final epNum = nextAiring['episode'] as int;
        final airSec = nextAiring['airingAt'] as int;
        airingMap[epNum] = DateTime.fromMillisecondsSinceEpoch(airSec * 1000, isUtc: true).toIso8601String();
      }

      List<EpisodeData> episodes = [];
      for (int i = 1; i <= totalEpisodes; i++) {
        episodes.add(EpisodeData(
          episodeNumber: i,
          episodeName: 'Episode $i',
          airDate: airingMap[i],
        ));
      }
      return SeasonData(episodes: episodes);
    } catch (e) {
      appDebugLog('getAnimeSeasonData fallback error: $e');
      return const SeasonData(episodes: []);
    }
  }

}
