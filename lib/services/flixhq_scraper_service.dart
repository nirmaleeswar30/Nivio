import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:nivio/core/constants.dart';
import 'package:nivio/models/stream_result.dart';

/// Native FlixHQ scraper for movies/TV stream extraction.
class FlixhqScraperService {
  static const String _baseUrl = 'https://flixhq.tw';
  static const String _defaultUserAgent =
      'Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36';

  final Dio _dio = Dio(
    BaseOptions(
      baseUrl: _baseUrl,
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
    int season = 1,
    int episode = 1,
  }) async {
    final cleanTitle = title.trim();
    if (cleanTitle.isEmpty) return null;

    try {
      final match = await _findBestMatch(
        title: cleanTitle,
        mediaType: mediaType,
        year: year,
      );
      if (match == null) {
        print('FlixHQ scraper: no search match for "$cleanTitle"');
        return null;
      }

      final serverIds = mediaType == 'movie'
          ? await _resolveMovieServerIds(match.id)
          : await _resolveTvServerIds(
              showId: match.id,
              season: season,
              episode: episode,
            );

      if (serverIds.isEmpty) {
        print('FlixHQ scraper: no server ids found for ${match.href}');
        return null;
      }

      final prioritizedServerIds = _prioritizeServerIds(serverIds);

      for (final serverId in prioritizedServerIds) {
        try {
          final embedUrl = await _resolveEmbedUrl(serverId);
          if (embedUrl == null) continue;

          final stream = await _extractFromEmbed(embedUrl);
          if (stream == null || stream.url.trim().isEmpty) continue;

          final playable = await _isLikelyPlayable(stream);
          if (playable) {
            return stream;
          }

          print(
            'FlixHQ scraper: server $serverId returned non-playable source, trying next',
          );
        } catch (e) {
          print('FlixHQ scraper: server $serverId failed: $e');
        }
      }
    } catch (e) {
      print('FlixHQ scraper error: $e');
    }

    return null;
  }

  Future<_FlixhqMatch?> _findBestMatch({
    required String title,
    required String mediaType,
    String? year,
  }) async {
    final slug = title
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'-+'), '-')
        .replaceAll(RegExp(r'^-|-$'), '');

    final searchQueries = <String>{
      if (slug.isNotEmpty) slug,
      // Keep encoded fallback for potential upstream changes.
      Uri.encodeComponent(title),
    };

    final matches = <_FlixhqMatch>[];
    final seen = <String>{};
    final hrefRegex = RegExp(r'href="(/(movie|tv)/watch-[^"]+-(\d+))"');

    for (final query in searchQueries) {
      final response = await _dio.get('/search/$query');
      if (response.statusCode != 200) continue;

      final html = response.data?.toString() ?? '';
      if (html.isEmpty) continue;

      for (final m in hrefRegex.allMatches(html)) {
        final href = m.group(1);
        final kind = m.group(2);
        final idRaw = m.group(3);
        if (href == null || kind == null || idRaw == null) continue;
        if (!seen.add(href)) continue;

        final id = int.tryParse(idRaw);
        if (id == null) continue;

        matches.add(
          _FlixhqMatch(
            href: href,
            id: id,
            isTv: kind == 'tv',
            titleGuess: _titleFromHref(href),
          ),
        );
      }

      if (matches.isNotEmpty) break;
    }

    if (matches.isEmpty) return null;

    final queryNorm = _normalize(title);
    final wantTv = mediaType != 'movie';
    final queryYear = year != null ? int.tryParse(year) : null;

    _FlixhqMatch? best;
    var bestScore = -1;

    for (final candidate in matches) {
      var score = 0;
      if (candidate.isTv == wantTv) score += 900;

      final candidateNorm = _normalize(candidate.titleGuess);
      if (candidateNorm == queryNorm) score += 500;
      if (candidateNorm.startsWith(queryNorm)) score += 250;
      if (candidateNorm.contains(queryNorm)) score += 150;

      for (final token in queryNorm.split(' ')) {
        if (token.isEmpty) continue;
        if (candidateNorm.contains(token)) score += 35;
      }

      if (queryYear != null) {
        final candidateYear = _extractYearFromHref(candidate.href);
        if (candidateYear != null) {
          final diff = (queryYear - candidateYear).abs();
          score += diff == 0 ? 120 : (diff <= 1 ? 60 : 0);
        }
      }

      if (score > bestScore) {
        bestScore = score;
        best = candidate;
      }
    }

    return best;
  }

  Future<List<int>> _resolveMovieServerIds(int movieId) async {
    final response = await _dio.get('/ajax/episode/list/$movieId');
    if (response.statusCode != 200) return const [];
    return _extractServerIds(response.data?.toString() ?? '');
  }

  Future<List<int>> _resolveTvServerIds({
    required int showId,
    required int season,
    required int episode,
  }) async {
    final seasonResponse = await _dio.get('/ajax/season/list/$showId');
    if (seasonResponse.statusCode != 200) return const [];

    final seasonHtml = seasonResponse.data?.toString() ?? '';
    final seasonId = _pickSeasonId(seasonHtml, season);
    if (seasonId == null) return const [];

    final episodesResponse = await _dio.get('/ajax/season/episodes/$seasonId');
    if (episodesResponse.statusCode != 200) return const [];

    final episodesHtml = episodesResponse.data?.toString() ?? '';
    final episodeId = _pickEpisodeId(episodesHtml, episode);
    if (episodeId == null) return const [];

    final serversResponse = await _dio.get('/ajax/episode/servers/$episodeId');
    if (serversResponse.statusCode != 200) return const [];

    return _extractServerIds(serversResponse.data?.toString() ?? '');
  }

  int? _pickSeasonId(String html, int seasonNumber) {
    final seasonRegex = RegExp(
      r'data-id="(\d+)"[^>]*>\s*Season\s+(\d+)',
      caseSensitive: false,
    );

    int? firstSeasonId;
    for (final m in seasonRegex.allMatches(html)) {
      final seasonId = int.tryParse(m.group(1) ?? '');
      final number = int.tryParse(m.group(2) ?? '');
      if (seasonId == null) continue;
      firstSeasonId ??= seasonId;
      if (number == seasonNumber) return seasonId;
    }

    if (firstSeasonId != null) return firstSeasonId;

    final loose = RegExp(r'data-id="(\d+)"').firstMatch(html);
    return int.tryParse(loose?.group(1) ?? '');
  }

  int? _pickEpisodeId(String html, int episodeNumber) {
    final episodeRegex = RegExp(
      r'data-id="(\d+)"[^>]*>.*?<strong>\s*Eps\s*(\d+):',
      caseSensitive: false,
      dotAll: true,
    );

    int? firstEpisodeId;
    for (final m in episodeRegex.allMatches(html)) {
      final episodeId = int.tryParse(m.group(1) ?? '');
      final number = int.tryParse(m.group(2) ?? '');
      if (episodeId == null) continue;
      firstEpisodeId ??= episodeId;
      if (number == episodeNumber) return episodeId;
    }

    if (firstEpisodeId != null) return firstEpisodeId;

    final loose = RegExp(r'data-id="(\d+)"').firstMatch(html);
    return int.tryParse(loose?.group(1) ?? '');
  }

  List<int> _extractServerIds(String html) {
    final ids = <int>[];
    final seen = <int>{};
    final idRegex = RegExp(r'data-(?:linkid|id)="(\d+)"');

    for (final m in idRegex.allMatches(html)) {
      final id = int.tryParse(m.group(1) ?? '');
      if (id == null || !seen.add(id)) continue;
      ids.add(id);
    }

    return ids;
  }

  List<int> _prioritizeServerIds(List<int> serverIds) {
    if (serverIds.length < 3) return serverIds;

    // FlixHQ frequently returns dead links in the first two slots.
    // Try the 3rd server first, then keep original 1st/2nd as fallback.
    return <int>[
      serverIds[2],
      serverIds[0],
      serverIds[1],
      ...serverIds.skip(3),
    ];
  }

  Future<String?> _resolveEmbedUrl(int serverId) async {
    final response = await _dio.get('/ajax/episode/sources/$serverId');
    if (response.statusCode != 200 || response.data == null) return null;

    final data = _asMap(response.data);
    final link = data?['link']?.toString().trim() ?? '';
    if (link.isEmpty) return null;

    if (link.startsWith('http://') || link.startsWith('https://')) {
      return link;
    }
    return '$_baseUrl$link';
  }

  Future<StreamResult?> _extractFromEmbed(String embedUrl) async {
    final embedUri = Uri.tryParse(embedUrl);
    if (embedUri == null || embedUri.host.isEmpty) return null;

    final embedResponse = await _dio.getUri<String>(
      embedUri,
      options: Options(
        responseType: ResponseType.plain,
        headers: {'Referer': '$_baseUrl/'},
      ),
    );

    if (embedResponse.statusCode != 200) return null;
    final embedHtml = embedResponse.data ?? '';
    if (embedHtml.isEmpty) return null;

    final pathMatch = RegExp(
      r'/(embed-\d+)/v\d+/(e-\d+)/([^/?#]+)',
      caseSensitive: false,
    ).firstMatch(embedUri.path);

    final embedPart = pathMatch?.group(1) ?? 'embed-1';
    final episodePart = pathMatch?.group(2) ?? 'e-1';
    final mediaId = pathMatch?.group(3) ?? _extractMediaIdFromHtml(embedHtml);
    if (mediaId == null || mediaId.isEmpty) return null;

    final key = _extractClientKey(embedHtml);
    if (key == null || key.isEmpty) {
      print('FlixHQ scraper: missing client key for embed');
      return null;
    }

    final keyEncoded = Uri.encodeQueryComponent(key);
    final getSourcesUrl =
        '${embedUri.scheme}://${embedUri.host}/$embedPart/v3/$episodePart/getSources?id=$mediaId&_k=$keyEncoded';

    final sourceResponse = await _dio.getUri<String>(
      Uri.parse(getSourcesUrl),
      options: Options(
        responseType: ResponseType.plain,
        headers: {
          'Referer': embedUrl,
          'Origin': '${embedUri.scheme}://${embedUri.host}',
          'Accept': '*/*',
          'X-Requested-With': 'XMLHttpRequest',
        },
      ),
    );

    if (sourceResponse.statusCode != 200) return null;

    final payload = sourceResponse.data?.trim() ?? '';
    if (payload.isEmpty) return null;

    Map<String, dynamic>? data;
    try {
      data = jsonDecode(payload) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }

    final rawSourceCandidates = <dynamic>[
      data['sources'],
      data['sources_bk'],
      data['sourcesBackup'],
      data['backup'],
      data['source'],
      data['file'],
    ];
    final sources = <StreamSource>[];
    final seenUrls = <String>{};
    for (final rawSource in rawSourceCandidates) {
      for (final source in _parseSources(rawSource)) {
        if (!seenUrls.add(source.url)) continue;
        sources.add(source);
      }
    }

    if (sources.isEmpty) {
      print('FlixHQ scraper: getSources returned no playable sources');
      return null;
    }

    final subtitles = _parseSubtitles(data['tracks'] ?? data['subtitles']);
    final bestSource = _pickBestSource(sources);
    final availableQualities = sources.map((s) => s.quality).toSet().toList();

    return StreamResult(
      url: bestSource.url,
      quality: bestSource.quality,
      provider: 'flixhq.tw',
      subtitles: subtitles,
      availableQualities: availableQualities,
      isM3U8: bestSource.isM3U8,
      headers: {'User-Agent': _defaultUserAgent, 'Referer': embedUrl},
      sources: sources,
    );
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
      final ok =
          response.statusCode != null &&
          response.statusCode! >= 200 &&
          response.statusCode! < 300 &&
          (response.data?.contains('#EXTM3U') ?? false);
      return ok;
    } catch (_) {
      return false;
    }
  }

  String? _extractMediaIdFromHtml(String html) {
    final direct = RegExp(r'data-id="([^"]+)"').firstMatch(html)?.group(1);
    if (direct != null && direct.isNotEmpty) return direct;
    return null;
  }

  String? _extractClientKey(String html) {
    // Priority mirrors the embed script resolver.
    final meta = RegExp(
      r'''<meta[^>]+name=["']_gg_fb["'][^>]+content=["']([^"']+)["']''',
      caseSensitive: false,
    ).firstMatch(html)?.group(1);
    if (meta != null && meta.isNotEmpty) return meta;

    final comment = RegExp(
      r'<!--\s*_is_th:([^\r\n\u2028\u2029<]+)\s*-->',
      caseSensitive: false,
    ).firstMatch(html)?.group(1);
    if (comment != null && comment.isNotEmpty) return comment.trim();

    final dpi = RegExp(
      r'''data-dpi=["']([^"']+)["']''',
      caseSensitive: false,
    ).firstMatch(html)?.group(1);
    if (dpi != null && dpi.isNotEmpty) return dpi;

    final lkDb = RegExp(
      r'window\._lk_db\s*=\s*\{\s*x:\s*"([^"]+)"\s*,\s*y:\s*"([^"]+)"\s*,\s*z:\s*"([^"]+)"\s*\}',
      caseSensitive: false,
    ).firstMatch(html);
    if (lkDb != null) {
      final x = lkDb.group(1) ?? '';
      final y = lkDb.group(2) ?? '';
      final z = lkDb.group(3) ?? '';
      final combined = '$x$y$z';
      if (combined.isNotEmpty) return combined;
    }

    final nonce = RegExp(
      r'''<script[^>]+nonce=["']([^"']{32,})["']''',
      caseSensitive: false,
    ).firstMatch(html)?.group(1);
    if (nonce != null && nonce.isNotEmpty) return nonce;

    final xyWs = RegExp(
      r'window\._xy_ws\s*=\s*"([^"]+)"',
      caseSensitive: false,
    ).firstMatch(html)?.group(1);
    if (xyWs != null && xyWs.isNotEmpty) return xyWs;

    return null;
  }

  List<StreamSource> _parseSources(dynamic raw) {
    final out = <StreamSource>[];

    if (raw is List) {
      for (final item in raw) {
        final source = _sourceFromDynamic(item);
        if (source != null) out.add(source);
      }
      return out;
    }

    if (raw is Map) {
      final source = _sourceFromDynamic(raw);
      if (source != null) out.add(source);
      return out;
    }

    if (raw is String) {
      // Some responses provide sources as encoded string. Decryption path is
      // intentionally skipped for now; direct URL payloads are still accepted.
      final trimmed = raw.trim();
      if (trimmed.startsWith('http')) {
        out.add(
          StreamSource(
            url: trimmed,
            quality: 'auto',
            isM3U8: trimmed.contains('.m3u8'),
          ),
        );
      }
      return out;
    }

    return out;
  }

  StreamSource? _sourceFromDynamic(dynamic item) {
    if (item is! Map) return null;
    final map = item.map((key, value) => MapEntry(key.toString(), value));

    final url = (map['url'] ?? map['file'] ?? map['src'] ?? '')
        .toString()
        .trim();
    if (url.isEmpty) return null;

    final quality = (map['quality'] ?? map['label'] ?? 'auto').toString();
    final type = (map['type'] ?? '').toString().toLowerCase();
    final isM3U8 = url.contains('.m3u8') || type.contains('hls');

    return StreamSource(url: url, quality: quality, isM3U8: isM3U8);
  }

  List<SubtitleTrack> _parseSubtitles(dynamic raw) {
    if (raw is! List) return const [];

    final tracks = <SubtitleTrack>[];
    for (final item in raw) {
      if (item is! Map) continue;
      final map = item.map((key, value) => MapEntry(key.toString(), value));
      final url = (map['file'] ?? map['url'] ?? '').toString().trim();
      if (url.isEmpty) continue;
      final lang = (map['label'] ?? map['lang'] ?? 'Unknown').toString();
      tracks.add(SubtitleTrack(url: url, lang: lang));
    }
    return tracks;
  }

  StreamSource _pickBestSource(List<StreamSource> sources) {
    for (final quality in qualityPriority) {
      final match = sources.where((s) => s.quality == quality).firstOrNull;
      if (match != null) return match;
    }
    return sources.first;
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
          return decoded.map((k, v) => MapEntry(k.toString(), v));
        }
      } catch (_) {}
    }
    return null;
  }

  String _normalize(String value) {
    return value
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9\s]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  String _titleFromHref(String href) {
    final cleaned = href
        .replaceFirst(RegExp(r'^/(movie|tv)/watch-'), '')
        .replaceFirst(RegExp(r'-movies-free-\d+$'), '')
        .replaceAll('-', ' ')
        .trim();
    return cleaned;
  }

  int? _extractYearFromHref(String href) {
    final yearMatch = RegExp(r'-(19|20)\d{2}\b').firstMatch(href);
    if (yearMatch == null) return null;
    return int.tryParse(yearMatch.group(0)?.replaceFirst('-', '') ?? '');
  }
}

class _FlixhqMatch {
  final String href;
  final int id;
  final bool isTv;
  final String titleGuess;

  _FlixhqMatch({
    required this.href,
    required this.id,
    required this.isTv,
    required this.titleGuess,
  });
}
