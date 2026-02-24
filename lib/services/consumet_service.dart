import 'package:dio/dio.dart';
import 'package:nivio/core/constants.dart';
import 'package:nivio/models/stream_result.dart';

/// Service for fetching streaming data from Consumet API
/// Uses TMDB meta provider as primary, FlixHQ as fallback
class ConsumetService {
  final Dio _dio = Dio(
    BaseOptions(
      baseUrl: consumetBaseUrl,
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 15),
    ),
  );

  /// Cache for show info to avoid repeated API calls
  final Map<String, ConsumetShowInfo> _infoCache = {};

  /// Get show/movie info from Consumet TMDB meta provider
  /// Returns internal episode IDs needed for streaming
  Future<ConsumetShowInfo?> getInfo(int tmdbId, String type) async {
    final cacheKey = '${tmdbId}_$type';
    if (_infoCache.containsKey(cacheKey)) {
      return _infoCache[cacheKey];
    }

    try {
      print('🔍 Consumet: Fetching info for TMDB ID: $tmdbId, type: $type');
      final response = await _dio.get(
        '/meta/tmdb/info/$tmdbId',
        queryParameters: {'type': type},
      );

      if (response.statusCode == 200 && response.data != null) {
        final info = ConsumetShowInfo.fromJson(response.data);
        _infoCache[cacheKey] = info;
        print(
          '✅ Consumet: Got info - ${info.title}, ${info.episodes.length} episodes',
        );
        return info;
      }
    } catch (e) {
      print('❌ Consumet TMDB info error: $e');
    }

    return null;
  }

  /// Get streaming sources for an episode/movie
  /// [episodeId] is from ConsumetEpisode.id
  /// [showId] is from ConsumetShowInfo.id
  Future<StreamResult?> getStreamingSources(
    String episodeId,
    String showId, {
    String subDubPreference = 'sub',
  }) async {
    try {
      print(
        '🎬 Consumet: Fetching stream for episode: $episodeId, show: $showId',
      );
      final response = await _dio.get(
        '/meta/tmdb/watch/$episodeId',
        queryParameters: {'id': showId},
        options: Options(
          validateStatus: (status) => status != null && status < 500,
        ),
      );

      if (response.statusCode == 200 && response.data != null) {
        return _parseStreamResponse(
          response.data,
          'consumet-tmdb',
          subDubPreference: subDubPreference,
        );
      }
      print(
        '⚠️ Consumet TMDB watch unavailable (status: ${response.statusCode}), trying FlixHQ fallback...',
      );
    } catch (e) {
      print('❌ Consumet TMDB stream error: $e');
    }

    // Fallback to FlixHQ
    return await _getFlixHQStream(
      episodeId,
      showId,
      subDubPreference: subDubPreference,
    );
  }

  /// FlixHQ fallback
  Future<StreamResult?> _getFlixHQStream(
    String episodeId,
    String showId, {
    String subDubPreference = 'sub',
  }) async {
    try {
      print('🔄 Consumet: Trying FlixHQ fallback...');
      final response = await _dio.get(
        '/movies/flixhq/watch',
        queryParameters: {'episodeId': episodeId, 'mediaId': showId},
        options: Options(
          validateStatus: (status) => status != null && status < 500,
        ),
      );

      if (response.statusCode == 200 && response.data != null) {
        return _parseStreamResponse(
          response.data,
          'consumet-flixhq',
          subDubPreference: subDubPreference,
        );
      }
      print('⚠️ Consumet FlixHQ unavailable (status: ${response.statusCode})');
    } catch (e) {
      print('❌ Consumet FlixHQ stream error: $e');
    }
    return null;
  }

  /// Parse Consumet stream response into StreamResult
  StreamResult? _parseStreamResponse(
    Map<String, dynamic> data,
    String provider, {
    String subDubPreference = 'sub',
  }) {
    try {
      final sourcesJson = data['sources'] as List<dynamic>? ?? [];
      final subtitlesJson = data['subtitles'] as List<dynamic>? ?? [];
      final headersJson = data['headers'] as Map<String, dynamic>? ?? {};

      final sources = sourcesJson
          .map((s) => StreamSource.fromJson(s as Map<String, dynamic>))
          .toList();

      final subtitles = subtitlesJson
          .map((s) => SubtitleTrack.fromJson(s as Map<String, dynamic>))
          .toList();

      final headers = headersJson.map(
        (key, value) => MapEntry(key, value.toString()),
      );

      if (sources.isEmpty) {
        print('❌ No sources in Consumet response');
        return null;
      }

      // Pick best quality source
      final bestSource = _pickBestSource(
        sources,
        subDubPreference: subDubPreference,
      );
      final availableQualities = sources.map((s) => s.quality).toSet().toList();
      final selectedHost = _extractHost(bestSource.url);

      print(
        '✅ Consumet: Got ${sources.length} sources, ${subtitles.length} subtitles',
      );
      print('   Best: ${bestSource.quality} (M3U8: ${bestSource.isM3U8})');
      print('   Source host: $selectedHost');

      return StreamResult(
        url: bestSource.url,
        quality: bestSource.quality,
        provider: provider,
        subtitles: subtitles,
        availableQualities: availableQualities,
        isM3U8: bestSource.isM3U8,
        headers: headers,
        sources: sources,
      );
    } catch (e) {
      print('❌ Error parsing Consumet stream response: $e');
      return null;
    }
  }

  /// Pick the best quality stream source
  StreamSource _pickBestSource(
    List<StreamSource> sources, {
    String subDubPreference = 'sub',
  }) {
    final preferDub = subDubPreference.toLowerCase() == 'dub';
    final preferredSources = preferDub
        ? sources.where((s) => s.isDub).toList()
        : sources.where((s) => !s.isDub).toList();
    final candidateSources = preferredSources.isNotEmpty
        ? preferredSources
        : sources;

    // Prefer auto/highest quality
    for (final quality in qualityPriority) {
      final match = candidateSources
          .where((s) => s.quality == quality)
          .firstOrNull;
      if (match != null) return match;
    }
    // Fallback to first source
    return candidateSources.first;
  }

  String _extractHost(String url) {
    try {
      final uri = Uri.parse(url);
      return uri.host.isNotEmpty ? uri.host : 'unknown-host';
    } catch (_) {
      return 'invalid-url';
    }
  }

  Future<StreamResult?> _fetchAnimePaheStream({
    required String title,
    String? year,
    required int episode,
    String subDubPreference = 'sub',
  }) async {
    try {
      print('🗾 AnimePahe: searching for "$title"...');

      final searchResults = await _searchAnimePahe(title);
      if (searchResults.isEmpty) {
        print('❌ AnimePahe: no search results for "$title"');
        return null;
      }

      final bestMatch = _pickBestAnimePaheMatch(
        searchResults,
        queryTitle: title,
        queryYear: year,
      );
      if (bestMatch == null) {
        print('❌ AnimePahe: no match selected');
        return null;
      }

      final animeSessionId = bestMatch['id']?.toString() ?? '';
      if (animeSessionId.isEmpty) {
        print('❌ AnimePahe: invalid anime id');
        return null;
      }

      print(
        '✅ AnimePahe: selected "${bestMatch['title'] ?? 'unknown'}" (id: $animeSessionId)',
      );

      final infoResponse = await _dio.get(
        '/anime/animepahe/info/$animeSessionId',
      );
      if (infoResponse.statusCode != 200 || infoResponse.data == null) {
        print('❌ AnimePahe: info request failed');
        return null;
      }

      final infoData = Map<String, dynamic>.from(
        infoResponse.data as Map<String, dynamic>,
      );
      final episodesJson = infoData['episodes'] as List<dynamic>? ?? [];
      if (episodesJson.isEmpty) {
        print('❌ AnimePahe: no episodes in info response');
        return null;
      }

      Map<String, dynamic>? selectedEpisode;
      for (final rawEpisode in episodesJson) {
        if (rawEpisode is! Map) continue;
        final episodeMap = Map<String, dynamic>.from(rawEpisode);
        final number = episodeMap['number'];
        final numberInt = number is int ? number : int.tryParse('$number');
        if (numberInt == episode) {
          selectedEpisode = episodeMap;
          break;
        }
      }

      selectedEpisode ??= Map<String, dynamic>.from(episodesJson.first as Map);
      final selectedEpisodeId = selectedEpisode['id']?.toString() ?? '';
      if (selectedEpisodeId.isEmpty) {
        print('❌ AnimePahe: invalid episode id');
        return null;
      }

      print(
        '🎬 AnimePahe: fetching watch sources for episode $episode (id: $selectedEpisodeId)',
      );
      final watchData = await _fetchAnimePaheWatch(selectedEpisodeId);
      if (watchData == null) {
        print('❌ AnimePahe: watch request failed');
        return null;
      }

      final parsed = _parseStreamResponse(
        watchData,
        'consumet-animepahe',
        subDubPreference: subDubPreference,
      );

      if (parsed != null) {
        print('✅ AnimePahe stream acquired: ${parsed.quality}');
      }
      return parsed;
    } catch (e) {
      print('❌ AnimePahe flow error: $e');
      return null;
    }
  }

  Future<List<Map<String, dynamic>>> _searchAnimePahe(String title) async {
    try {
      final encodedTitle = Uri.encodeComponent(title);
      final response = await _dio.get('/anime/animepahe/$encodedTitle');

      if (response.statusCode != 200 || response.data == null) {
        return const [];
      }

      final data = Map<String, dynamic>.from(
        response.data as Map<String, dynamic>,
      );
      final results = data['results'] as List<dynamic>? ?? [];
      return results
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList();
    } catch (_) {
      return const [];
    }
  }

  Future<Map<String, dynamic>?> _fetchAnimePaheWatch(String episodeId) async {
    try {
      final queryResponse = await _dio.get(
        '/anime/animepahe/watch',
        queryParameters: {'episodeId': episodeId},
      );
      if (queryResponse.statusCode == 200 && queryResponse.data != null) {
        return Map<String, dynamic>.from(
          queryResponse.data as Map<String, dynamic>,
        );
      }
    } catch (_) {}

    // Compatibility fallback for mirrors that expose watch as path param.
    try {
      final pathResponse = await _dio.get(
        '/anime/animepahe/watch/${Uri.encodeComponent(episodeId)}',
      );
      if (pathResponse.statusCode == 200 && pathResponse.data != null) {
        return Map<String, dynamic>.from(
          pathResponse.data as Map<String, dynamic>,
        );
      }
    } catch (_) {}

    return null;
  }

  Map<String, dynamic>? _pickBestAnimePaheMatch(
    List<Map<String, dynamic>> results, {
    required String queryTitle,
    String? queryYear,
  }) {
    if (results.isEmpty) return null;

    final normalizedQuery = _normalize(queryTitle);
    final queryYearInt = queryYear != null ? int.tryParse(queryYear) : null;

    Map<String, dynamic>? best;
    var bestScore = -1;

    for (final item in results) {
      final title = _normalize(item['title']?.toString() ?? '');
      var score = 0;

      if (title == normalizedQuery) score += 1000;
      if (title.startsWith(normalizedQuery)) score += 400;
      if (title.contains(normalizedQuery)) score += 250;

      for (final token in normalizedQuery.split(' ')) {
        if (token.isEmpty) continue;
        if (title.contains(token)) score += 60;
      }

      final releaseYearRaw = item['releaseDate'];
      final releaseYear = releaseYearRaw is int
          ? releaseYearRaw
          : int.tryParse('$releaseYearRaw');
      if (queryYearInt != null && releaseYear != null) {
        final diff = (queryYearInt - releaseYear).abs();
        score += diff == 0 ? 250 : (diff <= 1 ? 120 : 0);
      }

      if (score > bestScore) {
        bestScore = score;
        best = item;
      }
    }

    return best;
  }

  String _normalize(String value) {
    return value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
  }

  /// Find the Consumet episode ID for a specific season/episode
  String? findEpisodeId(
    ConsumetShowInfo info, {
    required int season,
    required int episode,
  }) {
    for (final ep in info.episodes) {
      if (ep.season == season && ep.episode == episode) {
        return ep.id;
      }
    }
    // Fallback: for movies or single-season shows, try matching just episode number
    for (final ep in info.episodes) {
      if (ep.episode == episode && (ep.season == 0 || ep.season == season)) {
        return ep.id;
      }
    }
    // Last resort: try by index
    final idx = episode - 1;
    if (idx >= 0 && idx < info.episodes.length) {
      return info.episodes[idx].id;
    }
    return null;
  }

  /// Get streaming result for a TMDB media item
  Future<StreamResult?> fetchStream({
    required int tmdbId,
    required String mediaType,
    String title = '',
    String? year,
    bool isAnimeCandidate = false,
    int season = 1,
    int episode = 1,
    String subDubPreference = 'sub',
  }) async {
    final type = mediaType == 'movie' ? 'movie' : 'tv';

    if (isAnimeCandidate && title.trim().isNotEmpty) {
      final animePaheResult = await _fetchAnimePaheStream(
        title: title,
        year: year,
        episode: mediaType == 'movie' ? 1 : episode,
        subDubPreference: subDubPreference,
      );
      if (animePaheResult != null) {
        return animePaheResult;
      }
      print('⚠️ AnimePahe failed, falling back to TMDB meta path...');
    }

    // Step 1: Get show info (with episode IDs)
    final info = await getInfo(tmdbId, type);
    if (info == null) {
      print('❌ Could not get Consumet info for TMDB ID: $tmdbId');
      return null;
    }

    // Step 2: Find the right episode ID
    String? episodeId;
    if (type == 'movie') {
      // For movies, use top-level episodeId field
      episodeId = info.episodeId;
      if (episodeId == null || episodeId.isEmpty) {
        // Fallback: try episodes array or raw TMDB ID
        episodeId = info.episodes.isNotEmpty
            ? info.episodes.first.id
            : tmdbId.toString();
      }
      print('🎬 Movie episodeId: $episodeId, showId: ${info.id}');
    } else {
      episodeId = findEpisodeId(info, season: season, episode: episode);
    }

    if (episodeId == null || episodeId.isEmpty) {
      print(
        '❌ Could not find episode ID for S${season}E$episode in Consumet data (${info.episodes.length} episodes parsed)',
      );
      return null;
    }

    // Step 3: Get streaming sources
    return await getStreamingSources(
      episodeId,
      info.id,
      subDubPreference: subDubPreference,
    );
  }
}

/// Consumet show/movie info
class ConsumetShowInfo {
  final String id;
  final String title;
  final String? image;
  final String? cover;
  final String? episodeId; // Top-level episodeId for movies
  final List<ConsumetEpisode> episodes;

  ConsumetShowInfo({
    required this.id,
    required this.title,
    this.image,
    this.cover,
    this.episodeId,
    required this.episodes,
  });

  factory ConsumetShowInfo.fromJson(Map<String, dynamic> json) {
    // Collect episodes from multiple sources
    final List<ConsumetEpisode> allEpisodes = [];

    // 1) Try flat "episodes" array (some responses have this)
    final flatEpisodes = json['episodes'] as List<dynamic>? ?? [];
    for (final e in flatEpisodes) {
      if (e is Map<String, dynamic>) {
        allEpisodes.add(ConsumetEpisode.fromJson(e));
      }
    }

    // 2) Try nested "seasons" array (TV shows have episodes inside seasons)
    if (allEpisodes.isEmpty) {
      final seasonsJson = json['seasons'] as List<dynamic>? ?? [];
      for (final s in seasonsJson) {
        if (s is Map<String, dynamic>) {
          final seasonEpisodes = s['episodes'] as List<dynamic>? ?? [];
          for (final e in seasonEpisodes) {
            if (e is Map<String, dynamic>) {
              allEpisodes.add(ConsumetEpisode.fromJson(e));
            }
          }
        }
      }
    }

    return ConsumetShowInfo(
      id: json['id']?.toString() ?? '',
      title: json['title']?.toString() ?? json['name']?.toString() ?? '',
      image: json['image']?.toString(),
      cover: json['cover']?.toString(),
      episodeId: json['episodeId']?.toString(),
      episodes: allEpisodes,
    );
  }
}

/// Consumet episode info
class ConsumetEpisode {
  final String id;
  final int season;
  final int episode;
  final String? title;
  final String? image;

  ConsumetEpisode({
    required this.id,
    required this.season,
    required this.episode,
    this.title,
    this.image,
  });

  factory ConsumetEpisode.fromJson(Map<String, dynamic> json) {
    return ConsumetEpisode(
      id: json['id']?.toString() ?? '',
      season: json['season'] ?? 0,
      episode: json['episode'] ?? json['number'] ?? 0,
      title: json['title']?.toString() ?? json['name']?.toString(),
      image: json['img']?.toString() ?? json['image']?.toString(),
    );
  }
}
