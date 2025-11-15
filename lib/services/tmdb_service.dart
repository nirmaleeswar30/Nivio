import 'package:dio/dio.dart';
import 'package:nivio/core/constants.dart';
import 'package:nivio/models/search_result.dart';
import 'package:nivio/models/season_info.dart';

class TmdbService {
  final Dio _dio;

  TmdbService()
      : _dio = Dio(
          BaseOptions(
            baseUrl: tmdbBaseUrl,
            headers: {
              'User-Agent': 'Nivio/1.0 (compatible; +https://example.com)'
            },
            queryParameters: {
              'api_key': tmdbApiKey,
            },
          ),
        );

  /// Search for movies and TV shows (all languages) with pagination
  Future<SearchResults> search(String query, {int page = 1, String? language, String? sortBy}) async {
    try {
      final queryParams = {
        'query': query,
        'page': page,
        'include_adult': false,
        // NO default language parameter - searches all languages
        // NO region parameter - searches all regions
      };
      
      // Add optional language filter
      if (language != null && language.isNotEmpty) {
        queryParams['language'] = language;
      }
      
      final response = await _dio.get(
        '/3/search/multi',
        queryParameters: queryParams,
      );
      
      final results = SearchResults.fromJson(response.data);
      
      // Filter out 'person' type results, only keep movies and TV shows
      var filteredResults = results.results
          .where((item) => item.mediaType == 'movie' || item.mediaType == 'tv')
          .toList();
      
      // Apply sorting if specified
      if (sortBy != null) {
        switch (sortBy) {
          case 'popularity':
            filteredResults.sort((a, b) => (b.voteAverage ?? 0).compareTo(a.voteAverage ?? 0));
            break;
          case 'title':
            filteredResults.sort((a, b) {
              final titleA = (a.title ?? a.name ?? '').toLowerCase();
              final titleB = (b.title ?? b.name ?? '').toLowerCase();
              return titleA.compareTo(titleB);
            });
            break;
          case 'year':
            filteredResults.sort((a, b) {
              final yearA = a.releaseDate ?? a.firstAirDate ?? '';
              final yearB = b.releaseDate ?? b.firstAirDate ?? '';
              return yearB.compareTo(yearA); // Newest first
            });
            break;
        }
      }
      
      // Note: We can't accurately adjust totalPages after filtering because we don't know
      // how many people will be in future pages. The page count may be higher than actual content.
      return results.copyWith(results: filteredResults);
    } catch (e) {
      throw Exception('Failed to search: $e');
    }
  }

  /// Get series information (seasons, etc.)
  Future<SeriesInfo> getSeriesInfo(int showId) async {
    try {
      final response = await _dio.get('/3/tv/$showId');
      return SeriesInfo.fromJson(response.data);
    } catch (e) {
      throw Exception('Failed to get series info: $e');
    }
  }

  /// Get season information (episodes)
  Future<SeasonData> getSeasonInfo(int showId, int seasonNumber) async {
    try {
      final response = await _dio.get('/3/tv/$showId/season/$seasonNumber');
      return SeasonData.fromJson(response.data);
    } catch (e) {
      throw Exception('Failed to get season info: $e');
    }
  }

  /// Get poster URL
  String getPosterUrl(String? posterPath, {String size = posterSize}) {
    if (posterPath == null || posterPath.isEmpty) {
      return '';
    }
    return '$tmdbImageBaseUrl/$size$posterPath';
  }

  /// Get backdrop URL
  String getBackdropUrl(String? backdropPath, {String size = backdropSize}) {
    if (backdropPath == null || backdropPath.isEmpty) {
      return '';
    }
    return '$tmdbImageBaseUrl/$size$backdropPath';
  }

  /// Get trending content
  Future<List<dynamic>> getTrending(String mediaType, String timeWindow) async {
    try {
      final response = await _dio.get(
        '/3/trending/$mediaType/$timeWindow',
        queryParameters: {
          'language': 'en',
        },
      );
      return (response.data['results'] as List<dynamic>?) ?? [];
    } catch (e) {
      throw Exception('Failed to get trending: $e');
    }
  }

  /// Get popular content
  Future<List<dynamic>> getPopular(String mediaType) async {
    try {
      final response = await _dio.get(
        '/3/$mediaType/popular',
        queryParameters: {
          'language': 'en',
          'page': 1,
        },
      );
      return (response.data['results'] as List<dynamic>?) ?? [];
    } catch (e) {
      throw Exception('Failed to get popular: $e');
    }
  }

  /// Get top rated content
  Future<List<dynamic>> getTopRated(String mediaType) async {
    try {
      final response = await _dio.get(
        '/3/$mediaType/top_rated',
        queryParameters: {
          'language': 'en',
          'page': 1,
        },
      );
      return (response.data['results'] as List<dynamic>?) ?? [];
    } catch (e) {
      throw Exception('Failed to get top rated: $e');
    }
  }

  /// Get latest Tamil OTT releases (movies released on streaming platforms in last 6 months)
  Future<List<dynamic>> getLatestTamilOTT() async {
    try {
      final sixMonthsAgo = DateTime.now().subtract(const Duration(days: 180));
      final response = await _dio.get(
        '/3/discover/movie',
        queryParameters: {
          'with_original_language': 'ta', // Tamil
          'sort_by': 'release_date.desc', // Latest first
          'release_date.gte': sixMonthsAgo.toIso8601String().split('T')[0],
          'with_release_type': '4|5|6', // 4=Digital, 5=Physical, 6=TV (includes OTT)
          'vote_count.gte': 5, // At least 5 votes to filter out unreleased
          'page': 1,
        },
      );
      return (response.data['results'] as List<dynamic>?) ?? [];
    } catch (e) {
      throw Exception('Failed to get latest Tamil OTT releases: $e');
    }
  }

  /// Get content by language (e.g., 'te' for Telugu, 'hi' for Hindi, 'ko' for Korean)
  Future<List<dynamic>> getByLanguage(String mediaType, String language) async {
    try {
      final response = await _dio.get(
        '/3/discover/$mediaType',
        queryParameters: {
          'with_original_language': language,
          'sort_by': 'popularity.desc',
          'vote_count.gte': 10, // At least 10 votes
          'page': 1,
        },
      );
      return (response.data['results'] as List<dynamic>?) ?? [];
    } catch (e) {
      throw Exception('Failed to get content by language: $e');
    }
  }

  /// Get trending content by language
  Future<List<dynamic>> getTrendingByLanguage(String mediaType, String language) async {
    try {
      final response = await _dio.get(
        '/3/discover/$mediaType',
        queryParameters: {
          'with_original_language': language,
          'sort_by': 'popularity.desc',
          'primary_release_date.gte': DateTime.now().subtract(const Duration(days: 730)).toIso8601String().split('T')[0], // Last 2 years instead of 1
          'vote_count.gte': 10, // Reduced from 50 to 10
          'page': 1,
        },
      );
      return (response.data['results'] as List<dynamic>?) ?? [];
    } catch (e) {
      throw Exception('Failed to get trending by language: $e');
    }
  }

  /// Get anime (Japanese animation TV shows)
  Future<List<dynamic>> getAnime() async {
    try {
      final response = await _dio.get(
        '/3/discover/tv',
        queryParameters: {
          'with_genres': '16', // 16 = Animation genre
          'with_original_language': 'ja', // Japanese
          'sort_by': 'popularity.desc',
          'vote_count.gte': 20, // Reduced from 100 to 20
          'page': 1,
        },
      );
      return (response.data['results'] as List<dynamic>?) ?? [];
    } catch (e) {
      throw Exception('Failed to get anime: $e');
    }
  }

  /// Get trending anime
  Future<List<dynamic>> getTrendingAnime() async {
    try {
      final response = await _dio.get(
        '/3/discover/tv',
        queryParameters: {
          'with_genres': '16',
          'with_original_language': 'ja',
          'sort_by': 'popularity.desc', // Changed from vote_count.desc to popularity.desc
          'vote_average.gte': 6.0, // Reduced from 7.5 to 6.0
          'vote_count.gte': 50, // Reduced from 500 to 50
          'first_air_date.gte': DateTime.now().subtract(const Duration(days: 1825)).toIso8601String().split('T')[0], // Last 5 years instead of 2
          'page': 1,
        },
      );
      return (response.data['results'] as List<dynamic>?) ?? [];
    } catch (e) {
      throw Exception('Failed to get trending anime: $e');
    }
  }


  /// Get movie details by ID
  Future<SearchResult> getMovieDetails(int movieId) async {
    try {
      final response = await _dio.get(
        '/3/movie/$movieId',
        queryParameters: {
          'language': 'en',
          'append_to_response': 'credits,videos',
        },
      );
      
      // Add media_type to response data since it's not in the API response
      final data = Map<String, dynamic>.from(response.data);
      data['media_type'] = 'movie';
      
      return SearchResult.fromJson(data);
    } catch (e) {
      throw Exception('Failed to get movie details: $e');
    }
  }

  /// Get movie details with videos (for trailer)
  Future<Map<String, dynamic>> getMovieDetailsWithVideos(int movieId) async {
    try {
      final response = await _dio.get(
        '/3/movie/$movieId',
        queryParameters: {
          'language': 'en',
          'append_to_response': 'videos',
        },
      );
      return response.data;
    } catch (e) {
      throw Exception('Failed to get movie details: $e');
    }
  }

  /// Get TV show details by ID
  Future<SearchResult> getTVShowDetails(int tvId) async {
    try {
      final response = await _dio.get(
        '/3/tv/$tvId',
        queryParameters: {
          'language': 'en',
          'append_to_response': 'credits,videos',
        },
      );
      
      // Add media_type to response data since it's not in the API response
      final data = Map<String, dynamic>.from(response.data);
      data['media_type'] = 'tv';
      
      return SearchResult.fromJson(data);
    } catch (e) {
      throw Exception('Failed to get TV show details: $e');
    }
  }

  /// Get TV show details with videos (for trailer)
  Future<Map<String, dynamic>> getTVShowDetailsWithVideos(int tvId) async {
    try {
      final response = await _dio.get(
        '/3/tv/$tvId',
        queryParameters: {
          'language': 'en',
          'append_to_response': 'videos',
        },
      );
      return response.data;
    } catch (e) {
      throw Exception('Failed to get TV show details: $e');
    }
  }
}
