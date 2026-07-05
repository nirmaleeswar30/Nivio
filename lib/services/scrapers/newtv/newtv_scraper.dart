import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nivio/core/debug_log.dart';
import 'package:nivio/models/stream_result.dart';
import 'package:nivio/services/scrapers/newtv/newtv_bypass_service.dart';

final newTvNetflixScraperProvider = Provider((ref) => NewTvScraperService(ref.read(newTvBypassProvider), ott: 'nf', providerName: 'NewTV (Netflix)'));
final newTvPrimeScraperProvider = Provider((ref) => NewTvScraperService(ref.read(newTvBypassProvider), ott: 'pv', providerName: 'NewTV (Prime Video)'));
final newTvHotstarScraperProvider = Provider((ref) => NewTvScraperService(ref.read(newTvBypassProvider), ott: 'hs', providerName: 'NewTV (Hotstar)'));
final newTvDisneyScraperProvider = Provider((ref) => NewTvScraperService(ref.read(newTvBypassProvider), ott: 'dp', providerName: 'NewTV (Disney+)'));



class NewTvScraperService {
  final NewTvBypassService bypassService;
  final String ott;
  final String providerName;

  NewTvScraperService(this.bypassService, {this.ott = 'nf', this.providerName = 'NewTV (Netflix)'});

  static const String _apiUrl = 'https://net52.cc';
  static const String _defaultUserAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:136.0) Gecko/20100101 Firefox/136.0 /OS.GatuNewTV v1.0';

  final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 20),
      headers: {'User-Agent': _defaultUserAgent},
      validateStatus: (status) => status != null && status < 600,
    ),
  );

  final List<String> _newTvDomains = [
    "aHR0cHM6Ly9tb2JpbGVkZXRlY3RzLmNvbQ==",
    "aHR0cHM6Ly9tb2JpbGVkZXRlY3QuYXBw",
    "aHR0cHM6Ly9tb2JpZGV0ZWN0LmFydA==",
    "aHR0cHM6Ly9tb2JpZGV0ZWN0LmNj",
    "aHR0cHM6Ly9tb2JpZGV0ZWN0LmNsaWNr",
    "aHR0cHM6Ly9tb2JpZGV0ZWN0Lmluaw==",
    "aHR0cHM6Ly9tb2JpZGV0ZWN0LmxpdmU=",
    "aHR0cHM6Ly9tb2JpZGV0ZWN0LnBybw==",
    "aHR0cHM6Ly9tb2JpZGV0ZWN0LnNob3A=",
    "aHR0cHM6Ly9tb2JpZGV0ZWN0LnNpdGU=",
    "aHR0cHM6Ly9tb2JpZGV0ZWN0LnNwYWNl",
    "aHR0cHM6Ly9tb2JpZGV0ZWN0LnN0b3Jl",
    "aHR0cHM6Ly9tb2JpZGV0ZWN0LnZpcA==",
    "aHR0cHM6Ly9tb2JpZGV0ZWN0Lndpa2k=",
    "aHR0cHM6Ly9tb2JpZGV0ZWN0Lnh5eg==",
    "aHR0cHM6Ly9tb2JpZGV0ZWN0cy5hcnQ=",
    "aHR0cHM6Ly9tb2JpZGV0ZWN0cy5jYw==",
    "aHR0cHM6Ly9tb2JpZGV0ZWN0cy5pbmZv",
    "aHR0cHM6Ly9tb2JpZGV0ZWN0cy5pbms=",
    "aHR0cHM6Ly9tb2JpZGV0ZWN0cy5saXZl",
    "aHR0cHM6Ly9tb2JpZGV0ZWN0cy5wcm8=",
    "aHR0cHM6Ly9tb2JpZGV0ZWN0cy5zdG9yZQ==",
    "aHR0cHM6Ly9tb2JpZGV0ZWN0cy50b3A=",
    "aHR0cHM6Ly9tb2JpZGV0ZWN0cy54eXo="
  ];

  static String _resolvedApiUrl = '';
  String get _basePath {
    if (ott == 'nf') return '/mobile';
    if (ott == 'dp') return '/mobile/hs';
    return '/mobile/$ott';
  }

  Future<String> _resolveNewTvApi() async {
    if (_resolvedApiUrl.isNotEmpty) return _resolvedApiUrl;

    final headers = {
      "Cache-Control": "no-cache, no-store, must-revalidate",
      "Pragma": "no-cache",
      "Expires": "0",
      "X-Requested-With": "NetmirrorNewTV v1.0",
      "User-Agent": _defaultUserAgent,
      "Accept": "application/json, text/plain, */*"
    };

    for (final encoded in _newTvDomains) {
      try {
        final base = utf8.decode(base64Decode(encoded)).replaceAll(RegExp(r'/$'), '');
        final response = await _dio.get(
          '$base/checknewtv.php',
          options: Options(headers: headers),
        );

        if (response.statusCode == 200) {
          final data = _asMap(response.data);
          final tokenHash = data?['token_hash']?.toString() ?? '';
          if (tokenHash.isNotEmpty) {
            _resolvedApiUrl = utf8.decode(base64Decode(tokenHash)).replaceAll(RegExp(r'/$'), '');
            appDebugLog('NewTvScraper: Resolved NewTV API to $_resolvedApiUrl');
            return _resolvedApiUrl;
          }
        }
      } catch (e) {
        // Try next domain
      }
    }
    throw Exception('Failed to resolve NewTV API base URL');
  }

  Future<StreamResult?> fetchStreamUrl({
    required String tmdbId,
    required String title,
    required String mediaType,
    String? year,
    String? preferredAudio,
    int season = 1,
    int episode = 1,
  }) async {
    final cleanTitle = title.trim();
    if (cleanTitle.isEmpty) {
      appDebugLog('NewTvScraper: Title is empty, returning null');
      return null;
    }

    try {
      if (!bypassService.isReady) {
        appDebugLog('NewTvScraper: Waiting for NewTV cookies/auth to be ready...');
        return null;
      }

      final sessionCookie = bypassService.cookieString;
      if (sessionCookie.isEmpty) {
        appDebugLog('NewTvScraper: No cookies available from bypass service');
        return null;
      }

      appDebugLog('NewTvScraper: Searching candidates for "$cleanTitle"');
      final candidates = await _searchCandidates(cleanTitle, sessionCookie, _defaultUserAgent, season);
      if (candidates.isEmpty) {
        appDebugLog('NewTvScraper: No search match for "$cleanTitle"');
        return null;
      }

      final ranked = _rankCandidates(candidates, cleanTitle, year);
      appDebugLog('NewTvScraper: Found ${ranked.length} ranked candidates');

      for (final candidate in ranked.take(10)) {
        try {
          final result = await _tryCandidate(
            candidate: candidate,
            mediaType: mediaType,
            year: year,
            season: season,
            episode: episode,
            sessionCookie: sessionCookie,
            userAgent: _defaultUserAgent,
          );
          if (result != null) {
            return result;
          }
        } catch (e) {
          appDebugLog('NewTvScraper: Candidate ${candidate.id} failed: $e');
        }
      }
      appDebugLog('NewTvScraper: All candidates exhausted, returning null');
    } catch (e) {
      appDebugLog('NewTvScraper error: $e');
    }

    return null;
  }

  Future<List<_Candidate>> _searchCandidates(
    String title,
    String cookie,
    String userAgent,
    int season,
  ) async {
    final variants = <String>{
      if (season > 1) '$title Season $season',
      title,
      _stripTrailingYear(title),
      title.replaceAll(':', ' '),
    }.where((query) => query.trim().isNotEmpty);

    final out = <_Candidate>[];
    final seenIds = <String>{};

    for (final query in variants) {
      final response = await _dio.get(
        '$_apiUrl$_basePath/search.php',
        queryParameters: {'s': query, 't': _unixTime()},
        options: Options(
          headers: _ajaxHeaders(cookie: cookie, referer: '$_apiUrl/tv/home', userAgent: userAgent),
        ),
      );
      if (response.statusCode != 200) continue;

      final map = _asMap(response.data);
      if (map == null) continue;
      final rawResults = map['searchResult'];
      if (rawResults is! List) continue;

      for (final item in rawResults) {
        final row = _asMap(item);
        if (row == null) continue;
        final id = row['id']?.toString().trim() ?? '';
        final name = row['t']?.toString().trim() ?? '';
        if (id.isEmpty || name.isEmpty || !seenIds.add(id)) continue;
        out.add(_Candidate(id: id, title: name));
      }

      if (out.isNotEmpty) {
        break;
      }
    }

    return out;
  }

  List<_Candidate> _rankCandidates(
    List<_Candidate> input,
    String query,
    String? year,
  ) {
    final queryNorm = _normalize(query);
    final queryYear = year != null ? int.tryParse(year) : null;

    final scored = input.map((candidate) {
      final candidateNorm = _normalize(candidate.title);
      var score = 0;

      if (candidateNorm == queryNorm) score += 500;
      if (candidateNorm.startsWith(queryNorm)) score += 250;
      if (candidateNorm.contains(queryNorm)) score += 140;

      for (final token in queryNorm.split(' ')) {
        if (token.length < 2) continue;
        if (candidateNorm.contains(token)) score += 25;
      }

      if (queryYear != null) {
        final candidateYear = _extractYearFromText(candidate.title);
        if (candidateYear != null) {
          final diff = (queryYear - candidateYear).abs();
          score += diff == 0 ? 100 : (diff == 1 ? 40 : 0);
        }
      }

      return (candidate: candidate, score: score);
    }).toList()..sort((a, b) => b.score.compareTo(a.score));

    return scored.map((entry) => entry.candidate).toList();
  }

  Future<StreamResult?> _tryCandidate({
    required _Candidate candidate,
    required String mediaType,
    required String? year,
    required int season,
    required int episode,
    required String sessionCookie,
    required String userAgent,
  }) async {
    appDebugLog('NewTvScraper: Trying candidate ${candidate.id} - ${candidate.title}');
    final wantMovie = mediaType == 'movie';
    String contentId = candidate.id;

    if (!wantMovie) {
      final postData = await _fetchPostData(candidate.id, sessionCookie, userAgent);
      if (postData == null) {
        appDebugLog('NewTvScraper: _fetchPostData returned null for ${candidate.id}');
        return null;
      }

      bool isSplitSeasonEntry = false;
      final candidateNorm = _normalize(candidate.title);
      if (candidateNorm.contains('season $season') || candidateNorm.contains('s$season')) {
        isSplitSeasonEntry = true;
      }

      final queryYear = year != null ? int.tryParse(year) : null;
      if (queryYear != null && postData.year != null) {
        final diff = (queryYear - postData.year!).abs();
        if (diff > 1) {
          if (postData.isTv && season > 1) {
            appDebugLog('NewTvScraper: year mismatch ($diff) but it is TV Season $season, treating as split season entry');
            isSplitSeasonEntry = true;
          } else {
            appDebugLog('NewTvScraper: skipping ${candidate.id} due to year mismatch');
            return null;
          }
        }
      }

      if (!postData.isTv && postData.episodes.isEmpty) {
        appDebugLog('NewTvScraper: want TV but got movie/empty for ${candidate.id}');
        return null;
      }

      final episodeId = await _resolveEpisodeId(
        seriesId: candidate.id,
        postData: postData,
        season: season,
        episode: episode,
        sessionCookie: sessionCookie,
        userAgent: userAgent,
        isSplitSeasonEntry: isSplitSeasonEntry,
      );
      if (episodeId == null) {
        appDebugLog('NewTvScraper: _resolveEpisodeId returned null for ${candidate.id} S${season}E${episode}');
        return null;
      }
      contentId = episodeId;
    } else {
      // For movies, we skip `post.php` entirely because `search.php` gives us the exact movie ID.
      // This saves a full HTTP request!
      // We can also double check the year extracted from the candidate title if needed.
      final queryYear = year != null ? int.tryParse(year) : null;
      final candidateYear = _extractYearFromText(candidate.title);
      if (queryYear != null && candidateYear != null) {
        final diff = (queryYear - candidateYear).abs();
        if (diff > 1) {
           appDebugLog('NewTvScraper: skipping ${candidate.id} due to year mismatch (movie mode)');
           return null;
        }
      }
    }

    appDebugLog('NewTvScraper: Fetching NewTV API for contentId $contentId');
    final apiBase = await _resolveNewTvApi();

    final response = await _dio.get(
      '$apiBase/newtv/player.php',
      queryParameters: {'id': contentId},
      options: Options(
        headers: {
          "Cache-Control": "no-cache, no-store, must-revalidate",
          "Pragma": "no-cache",
          "Expires": "0",
          "X-Requested-With": "NetmirrorNewTV v1.0",
          "User-Agent": userAgent,
          "Accept": "application/json, text/plain, */*",
          "Ott": ott == 'dp' ? 'hs' : ott,
          "Usertoken": "",
        },
      ),
    );

    if (response.statusCode != 200) {
      appDebugLog('NewTvScraper: NewTV API failed with status ${response.statusCode}');
      return null;
    }

    final data = _asMap(response.data);
    final status = data?['status']?.toString();
    final videoLink = data?['video_link']?.toString().trim();
    final referer = data?['referer']?.toString().trim() ?? apiBase;

    if ((status != 'ok' && status != 'otp') || videoLink == null || videoLink.isEmpty) {
      appDebugLog('NewTvScraper: NewTV API returned invalid response: $data');
      return null;
    }

    appDebugLog('NewTvScraper: SUCCESS! Found NewTV m3u8: $videoLink');

    return StreamResult(
      url: videoLink,
      quality: 'auto',
      provider: providerName,
      subtitles: [], // Subtitles are embedded in the NewTV m3u8
      availableQualities: const ['auto'],
      availableAudios: const [],
      selectedAudio: '',
      isM3U8: true,
      headers: _ajaxHeaders(
        cookie: sessionCookie,
        referer: referer,
        userAgent: userAgent,
      ),
      sources: [
        StreamSource(
          url: videoLink,
          quality: 'auto',
          isM3U8: true,
        ),
      ],
    );
  }

  Future<_PostData?> _fetchPostData(String id, String sessionCookie, String userAgent) async {
    final response = await _dio.get(
      '$_apiUrl$_basePath/post.php',
      queryParameters: {'id': id, 't': _unixTime()},
      options: Options(
        headers: _ajaxHeaders(
          cookie: sessionCookie,
          referer: '$_apiUrl/tv/home',
          userAgent: userAgent,
        ),
      ),
    );
    if (response.statusCode != 200) {
      return null;
    }

    final data = _asMap(response.data);
    if (data == null) {
      return null;
    }
    


    final title = data['title']?.toString() ?? '';
    final year = int.tryParse(data['year']?.toString() ?? '');
    final type = (data['type']?.toString() ?? '').toLowerCase();

    final episodes = <_EpisodeInfo>[];
    final rawEpisodes = data['episodes'];
    if (rawEpisodes is List) {
      for (final raw in rawEpisodes) {
        final row = _asMap(raw);
        if (row == null) continue;
        final epId = row['id']?.toString().trim() ?? '';
        if (epId.isEmpty) continue;

        episodes.add(
          _EpisodeInfo(
            id: epId,
            season: _extractNumber(row['s']?.toString()),
            episode: _extractNumber(row['ep']?.toString()),
          ),
        );
      }
    }

    final seasons = <_SeasonInfo>[];
    final rawSeasons = data['season'];
    if (rawSeasons is List) {
      for (final raw in rawSeasons) {
        final row = _asMap(raw);
        if (row == null) continue;
        final seasonId = row['id']?.toString().trim() ?? '';
        if (seasonId.isEmpty) continue;

        seasons.add(
          _SeasonInfo(
            id: seasonId,
            season: _extractNumber(row['s']?.toString()),
          ),
        );
      }
    }

    return _PostData(
      title: title,
      year: year,
      type: type,
      episodes: episodes,
      seasons: seasons,
      nextPageShow: (data['nextPageShow'] as num?)?.toInt() ?? 0,
    );
  }

  Future<String?> _resolveEpisodeId({
    required String seriesId,
    required _PostData postData,
    required int season,
    required int episode,
    required String sessionCookie,
    required String userAgent,
    required bool isSplitSeasonEntry,
  }) async {
    for (final row in postData.episodes) {
      if (row.season == season && row.episode == episode) {
        return row.id;
      }
    }

    int effectiveSeason = season;
    if (season > 1 && isSplitSeasonEntry) {
      final hasOnlySeason1 = postData.seasons.length <= 1; // 0 or 1
      if (hasOnlySeason1) {
        appDebugLog('NewTvScraper: Fallback - split season entry detected, trying S1 E$episode');
        for (final row in postData.episodes) {
          if ((row.season == 1 || row.season == null) && row.episode == episode) {
            return row.id;
          }
        }
        effectiveSeason = 1;
      }
    }

    final seasonEntry = postData.seasons.firstWhere(
      (row) => row.season == effectiveSeason,
      orElse: () => const _SeasonInfo(id: '', season: null),
    );
    if (seasonEntry.id.isEmpty) {
      return null;
    }

    var page = 1;
    while (page <= 50) {
      final response = await _dio.get(
        '$_apiUrl$_basePath/episodes.php',
        queryParameters: {
          's': seasonEntry.id,
          'series': seriesId,
          't': _unixTime(),
          'page': page,
        },
        options: Options(
          headers: _ajaxHeaders(
            cookie: sessionCookie,
            referer: '$_apiUrl/tv/home',
            userAgent: userAgent,
          ),
        ),
      );
      if (response.statusCode != 200) return null;

      final map = _asMap(response.data);
      if (map == null) return null;
      final rawEpisodes = map['episodes'];
      if (rawEpisodes is! List) return null;

      for (final raw in rawEpisodes) {
        final row = _asMap(raw);
        if (row == null) continue;
        final episodeId = row['id']?.toString().trim() ?? '';
        if (episodeId.isEmpty) continue;

        final seasonNum = _extractNumber(row['s']?.toString());
        final episodeNum = _extractNumber(row['ep']?.toString());
        if (seasonNum == effectiveSeason && episodeNum == episode) {
          return episodeId;
        }
      }

      final nextPageShow = (map['nextPageShow'] as num?)?.toInt() ?? 0;
      if (nextPageShow != 1) {
        break;
      }
      page++;
    }

    return null;
  }

  int? _extractNumber(String? value) {
    if (value == null || value.isEmpty) return null;
    final match = RegExp(r'\d+').firstMatch(value);
    if (match == null) return null;
    return int.tryParse(match.group(0) ?? '');
  }

  String _normalize(String value) {
    return value
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9\s]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  String _stripTrailingYear(String value) {
    return value.replaceFirst(RegExp(r'\s*\((19|20)\d{2}\)\s*$'), '').trim();
  }

  int? _extractYearFromText(String value) {
    final match = RegExp(r'\b(19|20)\d{2}\b').firstMatch(value);
    if (match == null) return null;
    return int.tryParse(match.group(0) ?? '');
  }

  int _unixTime() => DateTime.now().millisecondsSinceEpoch ~/ 1000;

  Map<String, String> _ajaxHeaders({
    required String cookie,
    required String referer,
    required String userAgent,
  }) {
    // Append the required cookies as done in the Kotlin extension.
    // The Kotlin extension uses: mapOf("t_hash_t" to cookie_value, "hd" to "on", "ott" to ott)
    final finalCookie = '$cookie; hd=on; ott=$ott';

    return {
      'X-Requested-With': 'XMLHttpRequest',
      'Referer': referer,
      'Cookie': finalCookie,
      'User-Agent': userAgent,
    };
  }

  Map<String, dynamic>? _asMap(dynamic value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) {
      return value.map((key, val) => MapEntry(key.toString(), val));
    }
    if (value is String) {
      try {
        final decoded = jsonDecode(value);
        if (decoded is Map<String, dynamic>) return decoded;
        if (decoded is Map) {
          return decoded.map((key, val) => MapEntry(key.toString(), val));
        }
      } catch (_) {}
    }
    return null;
  }
}

class _Candidate {
  final String id;
  final String title;

  const _Candidate({required this.id, required this.title});
}

class _PostData {
  final String title;
  final int? year;
  final String type;
  final List<_EpisodeInfo> episodes;
  final List<_SeasonInfo> seasons;
  final int nextPageShow;

  const _PostData({
    required this.title,
    required this.year,
    required this.type,
    required this.episodes,
    required this.seasons,
    required this.nextPageShow,
  });

  bool get isTv => type == 'w' || episodes.isNotEmpty || seasons.isNotEmpty;
}

class _EpisodeInfo {
  final String id;
  final int? season;
  final int? episode;

  const _EpisodeInfo({
    required this.id,
    required this.season,
    required this.episode,
  });
}

class _SeasonInfo {
  final String id;
  final int? season;

  const _SeasonInfo({required this.id, required this.season});
}


