import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:nivio/core/constants.dart';
import 'package:nivio/models/search_result.dart';
import 'package:nivio/models/season_info.dart';
import 'package:nivio/services/cache_service.dart';

class TmdbService {
  final Dio _dio;
  final CacheService _cache;

  TmdbService(this._cache)
    : _dio = Dio(
        BaseOptions(
          baseUrl: tmdbBaseUrl,
          connectTimeout: const Duration(seconds: 15),
          receiveTimeout: const Duration(seconds: 15),
          headers: {
            'User-Agent': 'Nivio/1.0 (compatible; +https://example.com)',
          },
          queryParameters: {'api_key': tmdbApiKey},
        ),
      );

  /// Search movies + TV globally, then rank/filter locally for relevance.
  Future<SearchResults> search(
    String query, {
    int page = 1,
    String? language,
    String? sortBy,
  }) async {
    final normalizedQuery = _normalizeSearchText(query);
    final normalizedSort = sortBy == 'rating' ? 'popularity' : sortBy;
    final cacheKey =
        'search_v2_${normalizedQuery}_${page}_${language ?? 'all'}_${normalizedSort ?? 'relevance'}';

    if (normalizedQuery.isEmpty) {
      return const SearchResults(
        page: 0,
        results: [],
        totalPages: 0,
        totalResults: 0,
      );
    }

    // Try cache first.
    final cached = await _cache.getRaw(cacheKey);
    if (cached != null) {
      // Cache key already includes query + language + sort, so cached payload
      // is already post-processed for this exact request.
      return SearchResults.fromJson(cached);
    }

    try {
      final queryParams = <String, dynamic>{
        'query': normalizedQuery,
        'page': page,
        'include_adult': false,
      };

      // Search movies + TV separately so paging/relevance isn't diluted by people.
      final responses = await Future.wait([
        _dio.get('/3/search/movie', queryParameters: queryParams),
        _dio.get('/3/search/tv', queryParameters: queryParams),
      ]);

      final movieResponse = Map<String, dynamic>.from(
        responses[0].data as Map<String, dynamic>,
      );
      final tvResponse = Map<String, dynamic>.from(
        responses[1].data as Map<String, dynamic>,
      );

      final movieResults = _parseTypedSearchResultMaps(
        movieResponse['results'],
        mediaType: 'movie',
      );
      final tvResults = _parseTypedSearchResultMaps(
        tvResponse['results'],
        mediaType: 'tv',
      );
      final combined = <Map<String, dynamic>>[...movieResults, ...tvResults];

      final processedMaps = await _postProcessSearchResultMaps(
        combined,
        query: normalizedQuery,
        language: language,
        sortBy: normalizedSort,
      );
      final processed = processedMaps.map(SearchResult.fromJson).toList();

      final moviePages = (movieResponse['total_pages'] as num?)?.toInt() ?? 0;
      final tvPages = (tvResponse['total_pages'] as num?)?.toInt() ?? 0;
      final movieTotal = (movieResponse['total_results'] as num?)?.toInt() ?? 0;
      final tvTotal = (tvResponse['total_results'] as num?)?.toInt() ?? 0;

      final merged = SearchResults(
        page: page,
        results: processed,
        totalPages: moviePages > tvPages ? moviePages : tvPages,
        totalResults: movieTotal + tvTotal,
      );

      await _cache.set(
        cacheKey,
        merged.toJson(),
        ttl: CacheService.mediumCache,
      );
      return merged;
    } catch (e) {
      throw Exception('Failed to search: $e');
    }
  }

  List<Map<String, dynamic>> _parseTypedSearchResultMaps(
    dynamic rawResults, {
    required String mediaType,
  }) {
    if (rawResults is! List) return const [];

    final parsed = <Map<String, dynamic>>[];
    for (final item in rawResults) {
      if (item is! Map) continue;
      final json = item.map((key, value) => MapEntry(key.toString(), value));
      json['media_type'] = mediaType;
      
      if (mediaType == 'tv') {
        final isJa = json['original_language'] == 'ja' || (json['origin_country'] is List && json['origin_country'].contains('JP'));
        final genreIds = (json['genre_ids'] as List?)?.cast<int>() ?? [];
        if (isJa && genreIds.contains(16)) continue;
      }
      
      parsed.add(json);
    }
    return parsed;
  }

  List<dynamic> _filterAndMapResults(List<dynamic>? results, {String? defaultMediaType, bool bypassAnimeFilter = false}) {
    if (results == null) return [];
    return results.where((item) {
      if (item is! Map) return false;
      if (bypassAnimeFilter) return true;
      final type = item['media_type'] ?? defaultMediaType;
      if (type == 'tv') {
        final isJa = item['original_language'] == 'ja' || (item['origin_country'] is List && item['origin_country'].contains('JP'));
        final genreIds = (item['genre_ids'] as List?)?.cast<int>() ?? [];
        if (isJa && genreIds.contains(16)) return false;
      }
      return true;
    }).map((item) {
      if (item is Map && defaultMediaType != null && item['media_type'] == null) {
        return {...item, 'media_type': defaultMediaType};
      }
      return item;
    }).toList();
  }

  Future<List<Map<String, dynamic>>> _postProcessSearchResultMaps(
    List<Map<String, dynamic>> results, {
    required String query,
    String? language,
    String? sortBy,
  }) {
    return compute(_postProcessSearchResultMapsCompute, {
      'results': results,
      'query': query,
      'language': language,
      'sortBy': sortBy,
    });
  }

  String _normalizeSearchText(String text) {
    return text.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
  }

  Future<bool> checkWatchProviders(int id, String mediaType, int targetProviderId) async {
    final cacheKey = 'watch_providers_${mediaType}_$id';
    
    Map<String, dynamic>? data;
    final cached = await _cache.getRaw(cacheKey);
    if (cached != null) {
      data = cached;
    } else {
      try {
        final response = await _dio.get('/3/$mediaType/$id/watch/providers');
        data = response.data['results'] as Map<String, dynamic>?;
        await _cache.set(cacheKey, data ?? {}, ttl: CacheService.longCache);
      } catch (e) {
        return false;
      }
    }

    if (data == null) return false;

    // Check globally across all countries
    for (final countryData in data.values) {
      if (countryData is Map) {
        final flatrate = countryData['flatrate'] as List?;
        final free = countryData['free'] as List?;
        final ads = countryData['ads'] as List?;
        final rent = countryData['rent'] as List?;
        final buy = countryData['buy'] as List?;
        
        final allProviders = [
          ...?flatrate,
          ...?free,
          ...?ads,
          ...?rent,
          ...?buy,
        ];
        
        for (final provider in allProviders) {
          if (provider is Map && provider['provider_id'] == targetProviderId) {
            return true;
          }
        }
      }
    }
    
    return false;
  }

  Future<String?> getPrimaryNewTvProvider(int id, String mediaType) async {
    final cacheKey = 'watch_providers_${mediaType}_$id';
    
    Map<String, dynamic>? data;
    final cached = await _cache.getRaw(cacheKey);
    if (cached != null) {
      data = cached;
    } else {
      try {
        final response = await _dio.get('/3/$mediaType/$id/watch/providers');
        data = response.data['results'] as Map<String, dynamic>?;
        await _cache.set(cacheKey, data ?? {}, ttl: CacheService.longCache);
      } catch (e) {
        return null;
      }
    }

    if (data == null) return null;

    // We check the US region first as it's the most canonical, then IN, then fallback to any
    final regionsToCheck = ['US', 'IN'];
    final otherRegions = data.keys.where((k) => !regionsToCheck.contains(k)).toList();
    
    for (final region in [...regionsToCheck, ...otherRegions]) {
      final countryData = data[region];
      if (countryData is Map) {
        final flatrate = countryData['flatrate'] as List?;
        final free = countryData['free'] as List?;
        
        final allProviders = [
          ...?flatrate,
          ...?free,
        ];
        
        for (final provider in allProviders) {
          if (provider is Map) {
            final providerId = provider['provider_id'];
            if (providerId == 8 || providerId == 175) return 'nf'; // Netflix
            if (providerId == 337 || providerId == 390) return 'dp'; // Disney+
            if (providerId == 9 || providerId == 119) return 'pv'; // Prime Video
            if (providerId == 122) return 'hs'; // Hotstar
          }
        }
      }
    }
    
    return null;
  }

  Future<String?> getSeasonName(int id, int seasonNumber) async {
    final cacheKey = 'tv_${id}_season_$seasonNumber';
    final cached = await _cache.getRaw(cacheKey);
    if (cached != null) {
      return cached['name'] as String?;
    }
    
    try {
      final response = await _dio.get('/3/tv/$id/season/$seasonNumber');
      await _cache.set(cacheKey, response.data, ttl: CacheService.longCache);
      return response.data['name'] as String?;
    } catch (e) {
      return null;
    }
  }

  Future<List<SearchResult>> getRecommendations(int mediaId, String mediaType) async {
    final cacheKey = 'recommendations_${mediaType}_$mediaId';
    final cached = await _cache.getRaw(cacheKey);
    if (cached != null) {
      final results = cached['results'] as List?;
      if (results != null) {
        return results.map((item) {
          if (item is Map<String, dynamic>) {
            item['media_type'] = mediaType;
            return SearchResult.fromJson(item);
          }
          return null;
        }).whereType<SearchResult>().toList();
      }
    }

    try {
      final response = await _dio.get('/3/$mediaType/$mediaId/recommendations');
      final data = response.data;
      await _cache.set(cacheKey, data, ttl: CacheService.longCache);
      
      final results = data['results'] as List?;
      if (results != null) {
        return results.map((item) {
          if (item is Map<String, dynamic>) {
            item['media_type'] = mediaType;
            return SearchResult.fromJson(item);
          }
          return null;
        }).whereType<SearchResult>().toList();
      }
      return [];
    } catch (e) {
      return [];
    }
  }

  Future<List<SearchResult>> searchByProvider(
    String query,
    int providerId,
    String mediaType,
  ) async {
    final normalizedQuery = _normalizeSearchText(query);
    if (normalizedQuery.isEmpty) return [];

    try {
      final queryParams = <String, dynamic>{
        'query': normalizedQuery,
        'include_adult': false,
      };

      // Fetch first 3 pages of search (up to 60 items)
      final responses = await Future.wait([
        _dio.get('/3/search/$mediaType', queryParameters: {...queryParams, 'page': 1}),
        _dio.get('/3/search/$mediaType', queryParameters: {...queryParams, 'page': 2}),
        _dio.get('/3/search/$mediaType', queryParameters: {...queryParams, 'page': 3}),
      ]);

      final allResults = <Map<String, dynamic>>[];
      for (final response in responses) {
        final data = response.data['results'] as List?;
        if (data != null) {
          for (var item in data) {
            if (item is Map<String, dynamic>) {
              allResults.add(item);
            }
          }
        }
      }

      // Remove duplicates
      final seen = <int>{};
      allResults.retainWhere((item) => seen.add(item['id'] as int));

      // Check providers concurrently
      final validResults = <SearchResult>[];
      await Future.wait(allResults.map((item) async {
        final id = item['id'] as int;
        final hasProvider = await checkWatchProviders(id, mediaType, providerId);
        if (hasProvider) {
          item['media_type'] = mediaType;
          validResults.add(SearchResult.fromJson(item));
        }
      }));

      // Sort valid results by voteAverage
      validResults.sort((a, b) => (b.voteAverage ?? 0).compareTo(a.voteAverage ?? 0));

      return validResults;
    } catch (e) {
      return [];
    }
  }

  /// Get series information (seasons, etc.)
  Future<SeriesInfo> getSeriesInfo(int showId) async {
    final cacheKey = 'series_info_$showId';

    // Try to get from cache first
    final cached = await _cache.get<SeriesInfo>(
      cacheKey,
      (json) => SeriesInfo.fromJson(json),
    );
    if (cached != null) return cached;

    try {
      final response = await _dio.get('/3/tv/$showId');

      // Cache the response
      await _cache.set(cacheKey, response.data, ttl: CacheService.longCache);

      return SeriesInfo.fromJson(response.data);
    } catch (e) {
      throw Exception('Failed to get series info: $e');
    }
  }

  /// Get season information (episodes)
  Future<SeasonData> getSeasonInfo(int showId, int seasonNumber) async {
    final cacheKey = 'season_info_${showId}_$seasonNumber';

    // Try to get from cache first
    final cached = await _cache.get<SeasonData>(
      cacheKey,
      (json) => SeasonData.fromJson(json),
    );
    if (cached != null) return cached;

    try {
      final response = await _dio.get('/3/tv/$showId/season/$seasonNumber');

      // Cache the response
      await _cache.set(cacheKey, response.data, ttl: CacheService.longCache);

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
    if (posterPath.startsWith('http')) return posterPath;
    return '$tmdbImageBaseUrl/$size$posterPath';
  }

  /// Get backdrop URL
  String getBackdropUrl(String? backdropPath, {String size = backdropSize}) {
    if (backdropPath == null || backdropPath.isEmpty) {
      return '';
    }
    if (backdropPath.startsWith('http')) return backdropPath;
    return '$tmdbImageBaseUrl/$size$backdropPath';
  }

  /// Get trending content - with stale-while-revalidate


  Future<List<dynamic>> getByProvider(int providerId, {String mediaType = 'movie', int page = 1}) async {
    try {
      final response = await _dio.get(
        '/3/discover/$mediaType',
        queryParameters: {
          'with_watch_providers': providerId.toString(),
          'watch_region': 'US',
          'sort_by': 'popularity.desc',
          'page': page.toString(),
        },
      );
      if (response.statusCode == 200) {
        return _filterAndMapResults(response.data['results'] as List<dynamic>?, defaultMediaType: 'tv', bypassAnimeFilter: true);
      }
      return [];
    } catch (e) {
      return [];
    }
  }

  Future<List<dynamic>> getByProviderAndGenre(int providerId, int genreId, {String mediaType = 'movie', int page = 1}) async {
    try {
      final response = await _dio.get(
        '/3/discover/$mediaType',
        queryParameters: {
          'with_watch_providers': providerId.toString(),
          'with_genres': genreId.toString(),
          'watch_region': 'US',
          'sort_by': 'popularity.desc',
          'page': page.toString(),
        },
      );
      if (response.statusCode == 200) {
        return _filterAndMapResults(response.data['results'] as List<dynamic>?, defaultMediaType: 'tv', bypassAnimeFilter: true);
      }
      return [];
    } catch (e) {
      return [];
    }
  }

  Future<List<dynamic>> getTrending(String mediaType, String timeWindow) async {
    final cacheKey = 'trending_${mediaType}_$timeWindow';

    // Stale-while-revalidate: Get stale cache first
    final staleCache = await _cache.getStaleRaw(cacheKey);

    // If cache is expired or missing, trigger background refresh
    if (_cache.isExpired(cacheKey)) {
      // Don't await - let it run in background
      _cache.updateInBackground(cacheKey, () async {
        final response = await _dio.get(
          '/3/trending/$mediaType/$timeWindow',
          queryParameters: {'language': 'en'},
        );
        return response.data;
      }, CacheService.shortCache);
    }

    // Return stale data immediately if available
    if (staleCache != null) {
      return _filterAndMapResults(staleCache['results'] as List<dynamic>?, defaultMediaType: mediaType);
    }

    // Only if no cache at all, wait for network
    try {
      final response = await _dio.get(
        '/3/trending/$mediaType/$timeWindow',
        queryParameters: {'language': 'en'},
      );
      await _cache.set(cacheKey, response.data, ttl: CacheService.shortCache);
      return _filterAndMapResults(response.data['results'] as List<dynamic>?, defaultMediaType: mediaType);
    } catch (e) {
      throw Exception('Failed to get trending: $e');
    }
  }

  /// Get popular content - with stale-while-revalidate
  Future<List<dynamic>> getPopular(String mediaType) async {
    final cacheKey = 'popular_$mediaType';

    // Stale-while-revalidate: Get stale cache first
    final staleCache = await _cache.getStaleRaw(cacheKey);

    // If cache is expired or missing, trigger background refresh
    if (_cache.isExpired(cacheKey)) {
      _cache.updateInBackground(cacheKey, () async {
        final response = await _dio.get(
          '/3/$mediaType/popular',
          queryParameters: {'language': 'en', 'page': 1},
        );
        return response.data;
      }, CacheService.shortCache);
    }

    // Return stale data immediately if available
    if (staleCache != null) {
      return _filterAndMapResults(staleCache['results'] as List<dynamic>?, defaultMediaType: mediaType);
    }

    // Only if no cache at all, wait for network
    try {
      final response = await _dio.get(
        '/3/$mediaType/popular',
        queryParameters: {'language': 'en', 'page': 1},
      );
      await _cache.set(cacheKey, response.data, ttl: CacheService.shortCache);
      return _filterAndMapResults(response.data['results'] as List<dynamic>?, defaultMediaType: mediaType);
    } catch (e) {
      throw Exception('Failed to get popular: $e');
    }
  }

  /// Get top rated content - with stale-while-revalidate
  Future<List<dynamic>> getTopRated(String mediaType) async {
    final cacheKey = 'top_rated_$mediaType';

    // Stale-while-revalidate: Get stale cache first
    final staleCache = await _cache.getStaleRaw(cacheKey);

    // If cache is expired or missing, trigger background refresh
    if (_cache.isExpired(cacheKey)) {
      _cache.updateInBackground(cacheKey, () async {
        final response = await _dio.get(
          '/3/$mediaType/top_rated',
          queryParameters: {'language': 'en', 'page': 1},
        );
        return response.data;
      }, CacheService.mediumCache);
    }

    // Return stale data immediately if available
    if (staleCache != null) {
      return _filterAndMapResults(staleCache['results'] as List<dynamic>?, defaultMediaType: mediaType);
    }

    // Only if no cache at all, wait for network
    try {
      final response = await _dio.get(
        '/3/$mediaType/top_rated',
        queryParameters: {'language': 'en', 'page': 1},
      );
      await _cache.set(cacheKey, response.data, ttl: CacheService.mediumCache);
      return _filterAndMapResults(response.data['results'] as List<dynamic>?, defaultMediaType: mediaType);
    } catch (e) {
      throw Exception('Failed to get top rated: $e');
    }
  }

  /// Get latest Tamil OTT releases (movies released on streaming platforms in last 6 months)
  Future<List<dynamic>> getLatestTamilOTT() async {
    final cacheKey = 'latest_tamil_ott';

    // Try to get from cache first
    final cached = await _cache.getRaw(cacheKey);
    if (cached != null) {
      return (cached['results'] as List<dynamic>?) ?? [];
    }

    try {
      final sixMonthsAgo = DateTime.now().subtract(const Duration(days: 180));
      final response = await _dio.get(
        '/3/discover/movie',
        queryParameters: {
          'with_original_language': 'ta', // Tamil
          'sort_by': 'release_date.desc', // Latest first
          'release_date.gte': sixMonthsAgo.toIso8601String().split('T')[0],
          'with_release_type':
              '4|5|6', // 4=Digital, 5=Physical, 6=TV (includes OTT)
          'vote_count.gte': 5, // At least 5 votes to filter out unreleased
          'page': 1,
        },
      );

      // Cache the response with short TTL since it's date-based
      await _cache.set(cacheKey, response.data, ttl: CacheService.shortCache);

      return _filterAndMapResults(response.data['results'] as List<dynamic>?, defaultMediaType: 'movie');
    } catch (e) {
      throw Exception('Failed to get latest Tamil OTT releases: $e');
    }
  }

  /// Get content by language (e.g., 'te' for Telugu, 'hi' for Hindi, 'ko' for Korean)
  Future<List<dynamic>> getByLanguage(String mediaType, String language) async {
    final cacheKey = 'by_language_${mediaType}_$language';
    debugPrint('🌍 getByLanguage called: mediaType=$mediaType, language=$language, cacheKey=$cacheKey');

    // Try to get from cache first
    final cached = await _cache.getRaw(cacheKey);
    if (cached != null) {
      debugPrint('🌍 getByLanguage: CACHE HIT for $cacheKey, resultCount=${(cached['results'] as List?)?.length}');
      final results = _filterAndMapResults(cached['results'] as List<dynamic>?, defaultMediaType: mediaType);
      if (results.isNotEmpty) {
        final first = results[0];
        debugPrint('🌍 getByLanguage: First cached item: id=${first['id']}, media_type=${first['media_type']}, title=${first['title']}, name=${first['name']}');
      }
      return results;
    }

    debugPrint('🌍 getByLanguage: CACHE MISS for $cacheKey, fetching from network...');
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

      debugPrint('🌍 getByLanguage: Network response status=${response.statusCode}, resultCount=${(response.data['results'] as List?)?.length}');

      // Cache the response
      await _cache.set(cacheKey, response.data, ttl: CacheService.mediumCache);

      final results = _filterAndMapResults(response.data['results'] as List<dynamic>?, defaultMediaType: mediaType);
      if (results.isNotEmpty) {
        final first = results[0];
        debugPrint('🌍 getByLanguage: First network item: id=${first['id']}, media_type=${first['media_type']}, title=${first['title']}, name=${first['name']}');
      }
      return results;
    } catch (e) {
      debugPrint('🌍 getByLanguage: ERROR: $e');
      throw Exception('Failed to get content by language: $e');
    }
  }

  /// Get trending content by language - with stale-while-revalidate
  Future<List<dynamic>> getTrendingByLanguage(
    String mediaType,
    String language,
  ) async {
    final cacheKey = 'trending_by_language_${mediaType}_$language';

    // Stale-while-revalidate: Get stale cache first
    final staleCache = await _cache.getStaleRaw(cacheKey);

    // If cache is expired or missing, trigger background refresh
    if (_cache.isExpired(cacheKey)) {
      _cache.updateInBackground(cacheKey, () async {
        final response = await _dio.get(
          '/3/discover/$mediaType',
          queryParameters: {
            'with_original_language': language,
            'sort_by': 'popularity.desc',
            'primary_release_date.gte': DateTime.now()
                .subtract(const Duration(days: 730))
                .toIso8601String()
                .split('T')[0],
            'vote_count.gte': 10,
            'page': 1,
          },
        );
        return response.data;
      }, CacheService.shortCache);
    }

    // Return stale data immediately if available
    if (staleCache != null) {
      return _filterAndMapResults(staleCache['results'] as List<dynamic>?, defaultMediaType: mediaType);
    }

    // Only if no cache at all, wait for network
    try {
      final response = await _dio.get(
        '/3/discover/$mediaType',
        queryParameters: {
          'with_original_language': language,
          'sort_by': 'popularity.desc',
          'primary_release_date.gte': DateTime.now()
              .subtract(const Duration(days: 730))
              .toIso8601String()
              .split('T')[0],
          'vote_count.gte': 10,
          'page': 1,
        },
      );
      await _cache.set(cacheKey, response.data, ttl: CacheService.shortCache);
      return _filterAndMapResults(response.data['results'] as List<dynamic>?, defaultMediaType: mediaType);
    } catch (e) {
      throw Exception('Failed to get trending by language: $e');
    }
  }

  /// Get anime (Japanese animation TV shows)
  Future<List<dynamic>> getAnime() async {
    final cacheKey = 'anime';

    // Try to get from cache first
    final cached = await _cache.getRaw(cacheKey);
    if (cached != null) {
      return (cached['results'] as List<dynamic>?) ?? [];
    }

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

      // Cache the response
      await _cache.set(cacheKey, response.data, ttl: CacheService.mediumCache);

      return _filterAndMapResults(response.data['results'] as List<dynamic>?, defaultMediaType: 'tv');
    } catch (e) {
      throw Exception('Failed to get anime: $e');
    }
  }

  /// Get trending anime - with stale-while-revalidate
  Future<List<dynamic>> getTrendingAnime() async {
    final cacheKey = 'trending_anime';

    // Stale-while-revalidate: Get stale cache first
    final staleCache = await _cache.getStaleRaw(cacheKey);

    // If cache is expired or missing, trigger background refresh
    if (_cache.isExpired(cacheKey)) {
      _cache.updateInBackground(cacheKey, () async {
        final response = await _dio.get(
          '/3/discover/tv',
          queryParameters: {
            'with_genres': '16',
            'with_original_language': 'ja',
            'sort_by': 'popularity.desc',
            'vote_average.gte': 6.0,
            'vote_count.gte': 50,
            'first_air_date.gte': DateTime.now()
                .subtract(const Duration(days: 1825))
                .toIso8601String()
                .split('T')[0],
            'page': 1,
          },
        );
        return response.data;
      }, CacheService.shortCache);
    }

    // Return stale data immediately if available
    if (staleCache != null) {
      return _filterAndMapResults(staleCache['results'] as List<dynamic>?, defaultMediaType: 'tv');
    }

    // Only if no cache at all, wait for network
    try {
      final response = await _dio.get(
        '/3/discover/tv',
        queryParameters: {
          'with_genres': '16',
          'with_original_language': 'ja',
          'sort_by': 'popularity.desc',
          'vote_average.gte': 6.0,
          'vote_count.gte': 50,
          'first_air_date.gte': DateTime.now()
              .subtract(const Duration(days: 1825))
              .toIso8601String()
              .split('T')[0],
          'page': 1,
        },
      );
      await _cache.set(cacheKey, response.data, ttl: CacheService.shortCache);
      return _filterAndMapResults(response.data['results'] as List<dynamic>?, defaultMediaType: 'tv');
    } catch (e) {
      throw Exception('Failed to get trending anime: $e');
    }
  }

  /// Get movie details by ID
  Future<SearchResult> getMovieDetails(int movieId) async {
    final cacheKey = 'movie_details_$movieId';

    // Try to get from cache first
    final cached = await _cache.get<SearchResult>(
      cacheKey,
      (json) => SearchResult.fromJson(json),
    );
    if (cached != null) return cached;

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

      // Cache the response
      await _cache.set(cacheKey, data, ttl: CacheService.longCache);

      return SearchResult.fromJson(data);
    } catch (e) {
      throw Exception('Failed to get movie details: $e');
    }
  }

  /// Get movie details with videos (for trailer)
  Future<Map<String, dynamic>> getMovieDetailsWithVideos(int movieId) async {
    final cacheKey = 'movie_details_full_$movieId';

    // Check for stale cache
    final staleCache = await _cache.getStaleRaw(cacheKey);

    // If we have stale cache AND it's expired, refresh in background
    if (staleCache != null && _cache.isExpired(cacheKey)) {
      _cache.updateInBackground(cacheKey, () async {
        final response = await _dio.get(
          '/3/movie/$movieId',
          queryParameters: {'language': 'en', 'append_to_response': 'credits,videos'},
        );
        return response.data;
      }, CacheService.longCache);
      // Return stale cache immediately
      return staleCache;
    }

    // Return fresh cache if available
    if (staleCache != null) return staleCache;

    // No cache at all - fetch synchronously
    try {
      final response = await _dio.get(
        '/3/movie/$movieId',
        queryParameters: {'language': 'en', 'append_to_response': 'credits,videos'},
      );

      // Cache the response
      await _cache.set(cacheKey, response.data, ttl: CacheService.longCache);

      return response.data;
    } catch (e) {
      throw Exception('Failed to get movie details: $e');
    }
  }

  /// Get TV show details by ID
  Future<SearchResult> getTVShowDetails(int tvId) async {
    final cacheKey = 'tv_details_$tvId';

    // Try to get from cache first
    final cached = await _cache.get<SearchResult>(
      cacheKey,
      (json) => SearchResult.fromJson(json),
    );
    if (cached != null) return cached;

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

      // Cache the response
      await _cache.set(cacheKey, data, ttl: CacheService.longCache);

      return SearchResult.fromJson(data);
    } catch (e) {
      throw Exception('Failed to get TV show details: $e');
    }
  }

  /// Get TV show details with videos (for trailer)
  Future<Map<String, dynamic>> getTVShowDetailsWithVideos(int tvId) async {
    final cacheKey = 'tv_details_full_$tvId';

    // Check for stale cache
    final staleCache = await _cache.getStaleRaw(cacheKey);

    // If we have stale cache AND it's expired, refresh in background
    if (staleCache != null && _cache.isExpired(cacheKey)) {
      _cache.updateInBackground(cacheKey, () async {
        final response = await _dio.get(
          '/3/tv/$tvId',
          queryParameters: {'language': 'en', 'append_to_response': 'credits,videos'},
        );
        return response.data;
      }, CacheService.longCache);
      // Return stale cache immediately
      return staleCache;
    }

    // Return fresh cache if available
    if (staleCache != null) return staleCache;

    // No cache at all - fetch synchronously
    try {
      final response = await _dio.get(
        '/3/tv/$tvId',
        queryParameters: {'language': 'en', 'append_to_response': 'credits,videos'},
      );

      // Cache the response
      await _cache.set(cacheKey, response.data, ttl: CacheService.longCache);

      return response.data;
    } catch (e) {
      throw Exception('Failed to get TV show details: $e');
    }
  }
}

List<Map<String, dynamic>> _postProcessSearchResultMapsCompute(
  Map<String, dynamic> input,
) {
  final rawResults = input['results'];
  final query = (input['query'] ?? '').toString();
  final language = input['language']?.toString();
  final sortBy = input['sortBy']?.toString();

  if (rawResults is! List) return const [];

  var processed = rawResults
      .whereType<Map>()
      .map((item) => item.map((k, v) => MapEntry(k.toString(), v)))
      .toList();

  processed = processed.where((item) {
    final mediaType = (item['media_type'] ?? '').toString();
    return mediaType == 'movie' || mediaType == 'tv';
  }).toList();

  if (language != null && language.isNotEmpty) {
    final languageCode = language.toLowerCase();
    processed = processed
        .where(
          (item) =>
              ((item['original_language'] ?? '').toString().toLowerCase() ==
              languageCode),
        )
        .toList();
  }

  final seen = <String>{};
  processed = processed.where((item) {
    final mediaType = (item['media_type'] ?? '').toString();
    final id = (item['id'] ?? '').toString();
    return seen.add('${mediaType}_$id');
  }).toList();

  switch (sortBy) {
    case 'popularity':
    case 'rating':
      processed.sort((a, b) {
        final ratingCompare = _mapVoteAverage(b).compareTo(_mapVoteAverage(a));
        if (ratingCompare != 0) return ratingCompare;
        return _compareByYearDescMap(a, b);
      });
      break;
    case 'title':
      processed.sort((a, b) {
        final titleA = _normalizeSearchTextMap(_mapTitle(a));
        final titleB = _normalizeSearchTextMap(_mapTitle(b));
        return titleA.compareTo(titleB);
      });
      break;
    case 'year':
      processed.sort(_compareByYearDescMap);
      break;
    default:
      processed.sort((a, b) {
        final scoreA = _relevanceScoreMap(a, query);
        final scoreB = _relevanceScoreMap(b, query);
        final relevanceCompare = scoreB.compareTo(scoreA);
        if (relevanceCompare != 0) return relevanceCompare;
        return _mapVoteAverage(b).compareTo(_mapVoteAverage(a));
      });
  }

  return processed;
}

int _compareByYearDescMap(Map<String, dynamic> a, Map<String, dynamic> b) {
  final yearA = _extractYearMap(a) ?? 0;
  final yearB = _extractYearMap(b) ?? 0;
  final yearCompare = yearB.compareTo(yearA);
  if (yearCompare != 0) return yearCompare;
  return _mapVoteAverage(b).compareTo(_mapVoteAverage(a));
}

int _relevanceScoreMap(Map<String, dynamic> item, String query) {
  final title = _normalizeSearchTextMap(_mapTitle(item));
  final overview = _normalizeSearchTextMap((item['overview'] ?? '').toString());
  if (title.isEmpty) return -1;

  var score = 0;
  if (title == query) score += 1000;
  if (title.startsWith(query)) score += 400;
  if (title.contains(query)) score += 250;

  final tokens = query.split(' ').where((token) => token.isNotEmpty).toList();
  for (final token in tokens) {
    if (title.contains(token)) score += 70;
    if (title.startsWith(token)) score += 20;
    if (overview.contains(token)) score += 10;
  }

  score += (_mapVoteAverage(item) * 8).round();
  final year = _extractYearMap(item);
  if (year != null) {
    score += year ~/ 100;
  }

  return score;
}

int? _extractYearMap(Map<String, dynamic> item) {
  final date = (item['release_date'] ?? item['first_air_date'])?.toString();
  if (date == null || date.length < 4) return null;
  return int.tryParse(date.substring(0, 4));
}

double _mapVoteAverage(Map<String, dynamic> item) {
  final vote = item['vote_average'];
  if (vote is num) return vote.toDouble();
  return double.tryParse(vote?.toString() ?? '') ?? 0;
}

String _mapTitle(Map<String, dynamic> item) {
  return (item['title'] ?? item['name'] ?? '').toString();
}

String _normalizeSearchTextMap(String text) {
  return text.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
}
