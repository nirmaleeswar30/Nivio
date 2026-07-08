import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:nivio/models/season_info.dart';
import 'package:nivio/models/search_result.dart';
import 'package:dio/dio.dart';

import 'package:nivio/core/debug_log.dart';

class AniListResult {
  final int id;
  final int? idMal;

  AniListResult({required this.id, this.idMal});
}

/// Service for interacting with AniList API
/// Converts TMDB IDs to AniList IDs for anime content
class AniListService {
  final Dio _dio;
  static const String _baseUrl = 'https://graphql.anilist.co';

  AniListService()
    : _dio = Dio(
        BaseOptions(
          baseUrl: _baseUrl,
          connectTimeout: const Duration(seconds: 10),
          receiveTimeout: const Duration(seconds: 10),
        ),
      );

  /// Search for anime by title and year to find AniList ID
  /// Returns null if no match found
  Future<AniListResult?> getAniListIdFromTMDB({
    required String title,
    String? year,
    int? tmdbId,
  }) async {
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
        return AniListResult(id: anilistId, idMal: idMal);
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

      return response.data['data']['Media'] as Map<String, dynamic>;
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

  Future<SeriesInfo> getAnimeSeriesInfo(int id) async {
    const String query = '''
      query (\$id: Int) {
        Media(id: \$id) {
          id
          title { romaji english }
          episodes
        }
      }
    ''';
    try {
      final response = await _dio.post('', data: {'query': query, 'variables': {'id': id}});
      final media = response.data['data']['Media'];
      final epCount = media['episodes'] ?? 12;
      return SeriesInfo(
        numberOfSeasons: 1,
        seasons: [
          SeasonInfo(
            id: media['id'],
            name: 'Season 1',
            seasonNumber: 1,
            episodeCount: epCount,
          )
        ],
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
                airDate: ep['airDate'] ?? ep['airdate'],
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
          nextAiringEpisode { episode }
        }
      }
    ''';
    try {
      final response = await _dio.post('', data: {'query': query, 'variables': {'id': id}});
      final media = response.data['data']['Media'];
      int totalEpisodes = media['episodes'] ?? 0;
      if (totalEpisodes == 0) {
        final nextAiring = media['nextAiringEpisode'];
        if (nextAiring != null) {
          totalEpisodes = (nextAiring['episode'] as int) - 1;
        } else {
          totalEpisodes = 12;
        }
      }
      List<EpisodeData> episodes = [];
      for (int i = 1; i <= totalEpisodes; i++) {
        episodes.add(EpisodeData(episodeNumber: i, episodeName: 'Episode $i', airDate: null));
      }
      return SeasonData(episodes: episodes);
    } catch (e) {
      appDebugLog('getAnimeSeasonData fallback error: $e');
      return const SeasonData(episodes: []);
    }
  }

}
