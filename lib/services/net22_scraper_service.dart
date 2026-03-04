import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:nivio/core/constants.dart';
import 'package:nivio/core/debug_log.dart';
import 'package:nivio/models/stream_result.dart';

/// Native NetMirror scraper for movie/TV source extraction.
///
/// Current working flow:
/// 1) Bootstrap anti-bot cookie on net52.cc.
/// 2) Query metadata endpoints on net52.cc.
/// 3) Request playback hash from net22.cc.
/// 4) Resolve playlist from net52.cc.
class Net22ScraperService {
  static const String _mainUrl = 'https://net22.cc';
  static const String _apiUrl = 'https://net52.cc';
  static const String _defaultUserAgent =
      'Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36';
  static const Map<String, String> _audioAliasToCode = {
    'english': 'eng',
    'eng': 'eng',
    'en': 'eng',
    'hindi': 'hin',
    'hin': 'hin',
    'hi': 'hin',
    'tamil': 'tam',
    'tam': 'tam',
    'ta': 'tam',
    'telugu': 'tel',
    'tel': 'tel',
    'te': 'tel',
    'malayalam': 'mal',
    'mal': 'mal',
    'ml': 'mal',
    'kannada': 'kan',
    'kan': 'kan',
    'kn': 'kan',
    'japanese': 'jpn',
    'jpn': 'jpn',
    'ja': 'jpn',
    'korean': 'kor',
    'kor': 'kor',
    'ko': 'kor',
    'chinese': 'chi',
    'chi': 'chi',
    'zho': 'chi',
    'zh': 'chi',
    'spanish': 'spa',
    'spa': 'spa',
    'es': 'spa',
    'french': 'fre',
    'fre': 'fre',
    'fra': 'fre',
    'fr': 'fre',
    'german': 'ger',
    'ger': 'ger',
    'deu': 'ger',
    'de': 'ger',
    'italian': 'ita',
    'ita': 'ita',
    'it': 'ita',
    'portuguese': 'por',
    'por': 'por',
    'pt': 'por',
    'arabic': 'ara',
    'ara': 'ara',
    'ar': 'ara',
    'russian': 'rus',
    'rus': 'rus',
    'ru': 'rus',
    'bengali': 'ben',
    'ben': 'ben',
    'bn': 'ben',
    'marathi': 'mar',
    'mar': 'mar',
    'mr': 'mar',
    'urdu': 'urd',
    'urd': 'urd',
    'ur': 'urd',
  };

  final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 20),
      headers: {'User-Agent': _defaultUserAgent},
      validateStatus: (status) => status != null && status < 600,
    ),
  );

  final Dio _probeDio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 10),
      followRedirects: true,
      validateStatus: (status) => status != null && status < 500,
    ),
  );

  Future<StreamResult?> fetchStream({
    required String mediaType,
    required String title,
    String? year,
    String? preferredAudio,
    int season = 1,
    int episode = 1,
  }) async {
    final cleanTitle = title.trim();
    if (cleanTitle.isEmpty) return null;

    try {
      final session = await _bootstrapSession();
      if (session == null) {
        appDebugLog('Net22 scraper: failed to bootstrap anti-bot cookie');
        return null;
      }

      final candidates = await _searchCandidates(cleanTitle, session.cookie);
      if (candidates.isEmpty) {
        appDebugLog('Net22 scraper: no search match for "$cleanTitle"');
        return null;
      }

      final ranked = _rankCandidates(candidates, cleanTitle, year);
      for (final candidate in ranked.take(10)) {
        try {
          final result = await _tryCandidate(
            candidate: candidate,
            mediaType: mediaType,
            year: year,
            preferredAudio: preferredAudio,
            season: season,
            episode: episode,
            sessionCookie: session.cookie,
          );
          if (result == null) continue;

          final playable = await _isLikelyPlayable(result);
          if (playable) {
            return result;
          }

          appDebugLog(
            'Net22 scraper: non-playable source for ${candidate.id}, trying next',
          );
        } catch (e) {
          appDebugLog('Net22 scraper: candidate ${candidate.id} failed: $e');
        }
      }
    } catch (e) {
      appDebugLog('Net22 scraper error: $e');
    }

    return null;
  }

  Future<_Net22Session?> _bootstrapSession() async {
    for (var attempt = 0; attempt < 4; attempt++) {
      final response = await _dio.post<String>(
        '$_apiUrl/tv/p.php',
        options: Options(responseType: ResponseType.plain),
      );
      if (response.statusCode != 200) continue;
      final body = response.data?.toString() ?? '';
      if (!body.contains('"r":"n"')) continue;

      final cookie = _extractCookieValue(response.headers, 't_hash_t');
      if (cookie == null || cookie.isEmpty) continue;

      return _Net22Session(cookie: 't_hash_t=$cookie; ott=nf; hd=on');
    }
    return null;
  }

  String? _extractCookieValue(Headers headers, String key) {
    final setCookies = headers.map['set-cookie'];
    if (setCookies == null || setCookies.isEmpty) return null;

    final regex = RegExp('$key=([^;,\\s]+)');
    for (final raw in setCookies) {
      final match = regex.firstMatch(raw);
      if (match == null) continue;
      final value = match.group(1)?.trim();
      if (value != null && value.isNotEmpty) {
        return value;
      }
    }

    return null;
  }

  Future<List<_Candidate>> _searchCandidates(
    String title,
    String cookie,
  ) async {
    final variants = <String>{
      title,
      _stripTrailingYear(title),
      title.replaceAll(':', ' '),
    }.where((query) => query.trim().isNotEmpty);

    final out = <_Candidate>[];
    final seenIds = <String>{};

    for (final query in variants) {
      final response = await _dio.get(
        '$_apiUrl/search.php',
        queryParameters: {'s': query, 't': _unixTime()},
        options: Options(
          headers: _ajaxHeaders(cookie: cookie, referer: '$_apiUrl/tv/home'),
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
    required String? preferredAudio,
    required int season,
    required int episode,
    required String sessionCookie,
  }) async {
    final postData = await _fetchPostData(candidate.id, sessionCookie);
    if (postData == null) return null;

    final queryYear = year != null ? int.tryParse(year) : null;
    if (queryYear != null && postData.year != null) {
      final diff = (queryYear - postData.year!).abs();
      if (diff > 1) {
        appDebugLog(
          'Net22 scraper: skipping ${candidate.id} due to year mismatch',
        );
        return null;
      }
    }

    final wantMovie = mediaType == 'movie';
    if (wantMovie && postData.isTv) return null;
    if (!wantMovie && !postData.isTv && postData.episodes.isEmpty) return null;

    String contentId = candidate.id;
    var playlistTitle = postData.title.isNotEmpty
        ? postData.title
        : candidate.title;

    if (!wantMovie) {
      final episodeId = await _resolveEpisodeId(
        seriesId: candidate.id,
        postData: postData,
        season: season,
        episode: episode,
        sessionCookie: sessionCookie,
      );
      if (episodeId == null) return null;
      contentId = episodeId;
      playlistTitle = '$playlistTitle S$season E$episode';
    }

    final h = await _fetchPlaybackHash(
      contentId: contentId,
      sessionCookie: sessionCookie,
    );
    if (h == null || h.isEmpty) return null;

    final playlist = await _fetchPlaylist(
      contentId: contentId,
      title: playlistTitle,
      h: h,
      sessionCookie: sessionCookie,
    );
    if (playlist == null || playlist.variants.isEmpty) {
      return null;
    }

    final selectedVariant = _pickPlaylistVariant(
      playlist.variants,
      preferredAudio: preferredAudio,
    );
    if (selectedVariant == null || selectedVariant.sources.isEmpty) {
      return null;
    }

    final streamSources = selectedVariant.sources
        .map(
          (source) => StreamSource(
            url: _normalizeFileUrl(source.file),
            quality: _normalizeQuality(source.label),
            isM3U8: _isM3u8(source),
          ),
        )
        .where((source) => source.url.trim().isNotEmpty)
        .toList();
    if (streamSources.isEmpty) return null;

    final subtitleTracks = selectedVariant.tracks
        .where((track) => (track.kind ?? '').toLowerCase() == 'captions')
        .map((track) {
          final url = _normalizeFileUrl(track.file ?? '');
          return SubtitleTrack(
            url: url,
            lang: (track.label?.trim().isNotEmpty ?? false)
                ? track.label!.trim()
                : 'Unknown',
          );
        })
        .where((track) => track.url.trim().isNotEmpty)
        .toList();

    final best = _pickBestSource(streamSources);
    final availableQualities = streamSources
        .map((source) => source.quality)
        .toSet()
        .toList();
    final availableAudios = playlist.variants
        .map((variant) => _audioLabelFromVariant(variant.title))
        .where((label) => label.isNotEmpty)
        .toSet()
        .toList();
    final selectedAudio = _audioLabelFromVariant(selectedVariant.title);

    return StreamResult(
      url: best.url,
      quality: best.quality,
      provider: 'net22 (direct)',
      subtitles: subtitleTracks,
      availableQualities: availableQualities.isEmpty
          ? const ['auto']
          : availableQualities,
      availableAudios: availableAudios,
      selectedAudio: selectedAudio,
      isM3U8: best.isM3U8,
      headers: {
        'User-Agent': _defaultUserAgent,
        'Referer': '$_apiUrl/',
        'Cookie': 'hd=on',
        'Accept': '*/*',
      },
      sources: streamSources,
    );
  }

  Future<_PostData?> _fetchPostData(String id, String sessionCookie) async {
    final response = await _dio.get(
      '$_apiUrl/post.php',
      queryParameters: {'id': id, 't': _unixTime()},
      options: Options(
        headers: _ajaxHeaders(
          cookie: sessionCookie,
          referer: '$_apiUrl/tv/home',
        ),
      ),
    );
    if (response.statusCode != 200) return null;

    final data = _asMap(response.data);
    if (data == null) return null;
    if ((data['status']?.toString().toLowerCase() ?? '') == 'n') {
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
  }) async {
    for (final row in postData.episodes) {
      if (row.season == season && row.episode == episode) {
        return row.id;
      }
    }

    final seasonEntry = postData.seasons.firstWhere(
      (row) => row.season == season,
      orElse: () => const _SeasonInfo(id: '', season: null),
    );
    if (seasonEntry.id.isEmpty) {
      return null;
    }

    var page = 1;
    while (page <= 50) {
      final response = await _dio.get(
        '$_apiUrl/episodes.php',
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
        if (seasonNum == season && episodeNum == episode) {
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

  Future<String?> _fetchPlaybackHash({
    required String contentId,
    required String sessionCookie,
  }) async {
    final response = await _dio.post(
      '$_mainUrl/play.php',
      data: FormData.fromMap({'id': contentId}),
      options: Options(
        contentType: Headers.formUrlEncodedContentType,
        headers: {
          'X-Requested-With': 'XMLHttpRequest',
          'Referer': '$_mainUrl/',
          'Cookie': sessionCookie,
        },
      ),
    );
    if (response.statusCode != 200) return null;

    final map = _asMap(response.data);
    final h = map?['h']?.toString().trim() ?? '';
    return h.isEmpty ? null : h;
  }

  Future<_Playlist?> _fetchPlaylist({
    required String contentId,
    required String title,
    required String h,
    required String sessionCookie,
  }) async {
    final response = await _dio.get(
      '$_apiUrl/playlist.php',
      queryParameters: {'id': contentId, 't': title, 'h': h, 'tm': _unixTime()},
      options: Options(
        responseType: ResponseType.plain,
        headers: {
          'X-Requested-With': 'XMLHttpRequest',
          'Referer': '$_mainUrl/',
          'Cookie': sessionCookie,
        },
      ),
    );
    if (response.statusCode != 200) return null;

    final decoded = _decodeDynamicJson(response.data);
    if (decoded is! List || decoded.isEmpty) return null;
    final variants = <_PlaylistVariant>[];
    for (final entry in decoded) {
      final row = _asMap(entry);
      if (row == null) continue;

      final sources = <_PlaylistSource>[];
      final tracks = <_PlaylistTrack>[];

      final rawSources = row['sources'];
      if (rawSources is List) {
        for (final raw in rawSources) {
          final sourceMap = _asMap(raw);
          if (sourceMap == null) continue;
          final file = sourceMap['file']?.toString().trim() ?? '';
          if (file.isEmpty) continue;

          sources.add(
            _PlaylistSource(
              file: file,
              label: sourceMap['label']?.toString() ?? 'auto',
              type: sourceMap['type']?.toString() ?? '',
            ),
          );
        }
      }

      final rawTracks = row['tracks'];
      if (rawTracks is List) {
        for (final raw in rawTracks) {
          final trackMap = _asMap(raw);
          if (trackMap == null) continue;
          tracks.add(
            _PlaylistTrack(
              kind: trackMap['kind']?.toString(),
              file: trackMap['file']?.toString(),
              label: trackMap['label']?.toString(),
            ),
          );
        }
      }

      if (sources.isEmpty) continue;
      variants.add(
        _PlaylistVariant(
          title: row['title']?.toString() ?? '',
          sources: sources,
          tracks: tracks,
        ),
      );
    }

    if (variants.isEmpty) return null;
    return _Playlist(variants: variants);
  }

  _PlaylistVariant? _pickPlaylistVariant(
    List<_PlaylistVariant> variants, {
    required String? preferredAudio,
  }) {
    if (variants.isEmpty) return null;

    final preferredRaw = preferredAudio?.trim().toLowerCase() ?? '';
    if (preferredRaw.isEmpty || preferredRaw == 'auto') {
      return variants.first;
    }
    final preferredCanonical = _canonicalAudioValue(preferredRaw);
    final preferredToken = _normalizeAudioToken(preferredRaw);

    for (final variant in variants) {
      final labelRaw = _audioLabelFromVariant(variant.title).toLowerCase();
      if (labelRaw.isEmpty) continue;

      final labelCanonical = _canonicalAudioValue(labelRaw);
      final labelToken = _normalizeAudioToken(labelRaw);
      if (preferredCanonical.isNotEmpty &&
          preferredCanonical == labelCanonical) {
        return variant;
      }
      if (preferredToken.isNotEmpty &&
          (labelToken.contains(preferredToken) ||
              preferredToken.contains(labelToken))) {
        return variant;
      }
    }

    return variants.first;
  }

  String _audioLabelFromVariant(String rawTitle) {
    final title = rawTitle.trim();
    if (title.isEmpty) return '';

    final paren = RegExp(r'\(([^)]+)\)\s*$').firstMatch(title)?.group(1);
    if (paren != null && paren.trim().isNotEmpty) {
      return paren.trim();
    }

    return title;
  }

  StreamSource _pickBestSource(List<StreamSource> sources) {
    for (final quality in qualityPriority) {
      final match = sources
          .where((source) => source.quality == quality)
          .firstOrNull;
      if (match != null) return match;
    }
    return sources.first;
  }

  String _normalizeQuality(String label) {
    final raw = label.toLowerCase().trim();
    if (raw.contains('2160') || raw.contains('4k')) return '2160p';
    if (raw.contains('full') || raw.contains('1080')) return '1080p';
    if (raw.contains('mid') || raw.contains('720')) return '720p';
    if (raw.contains('low') || raw.contains('480')) return '480p';
    if (raw.contains('360')) return '360p';
    return 'auto';
  }

  bool _isM3u8(_PlaylistSource source) {
    final file = source.file.toLowerCase();
    final type = source.type.toLowerCase();
    return file.contains('.m3u8') ||
        type.contains('mpegurl') ||
        type.contains('hls');
  }

  String _normalizeAudioToken(String value) {
    return value.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
  }

  String _canonicalAudioValue(String value) {
    final token = _normalizeAudioToken(value.trim());
    if (token.isEmpty) return '';
    final alias = _audioAliasToCode[token];
    if (alias != null && alias.isNotEmpty) return alias;
    return token;
  }

  String _normalizeFileUrl(String raw) {
    final value = raw.trim().replaceAll('\\/', '/');
    if (value.isEmpty) return '';
    if (value.startsWith('http://') || value.startsWith('https://'))
      return value;
    if (value.startsWith('//')) return 'https:$value';
    if (value.startsWith('/')) return '$_apiUrl$value';
    return '$_apiUrl/$value';
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
  }) {
    return {
      'X-Requested-With': 'XMLHttpRequest',
      'Referer': referer,
      'Cookie': cookie,
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

  dynamic _decodeDynamicJson(dynamic input) {
    if (input is String) {
      try {
        return jsonDecode(input);
      } catch (_) {
        return null;
      }
    }
    return input;
  }

  Future<bool> _isLikelyPlayable(StreamResult result) async {
    if (!result.isM3U8 || result.url.trim().isEmpty) {
      return true;
    }

    try {
      final response = await _probeDio.get<String>(
        result.url,
        options: Options(
          headers: result.headers,
          responseType: ResponseType.plain,
        ),
      );
      return response.statusCode != null &&
          response.statusCode! >= 200 &&
          response.statusCode! < 300 &&
          (response.data?.contains('#EXTM3U') ?? false);
    } catch (_) {
      return false;
    }
  }
}

class _Net22Session {
  final String cookie;

  const _Net22Session({required this.cookie});
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

class _Playlist {
  final List<_PlaylistVariant> variants;

  const _Playlist({required this.variants});
}

class _PlaylistVariant {
  final String title;
  final List<_PlaylistSource> sources;
  final List<_PlaylistTrack> tracks;

  const _PlaylistVariant({
    required this.title,
    required this.sources,
    required this.tracks,
  });
}

class _PlaylistSource {
  final String file;
  final String label;
  final String type;

  const _PlaylistSource({
    required this.file,
    required this.label,
    required this.type,
  });
}

class _PlaylistTrack {
  final String? kind;
  final String? file;
  final String? label;

  const _PlaylistTrack({this.kind, this.file, this.label});
}
