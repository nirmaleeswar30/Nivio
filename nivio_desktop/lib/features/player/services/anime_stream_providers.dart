import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:http/http.dart' as http;

import '../../../shared/models/stream_result.dart';
import '../../../shared/models/skip_times_models.dart';
import '../models/playback_request.dart';
import 'playback_runtime_diagnostics.dart';

abstract interface class AnimeStreamProvider {
  String get name;

  Future<List<String>> availableServers(PlaybackRequest request);

  Future<StreamResult?> resolve(
    PlaybackRequest request, {
    required String server,
  });
}

class XonStreamProvider implements AnimeStreamProvider {
  XonStreamProvider({Dio? dio})
    : _dio =
          dio ??
          Dio(
            BaseOptions(
              baseUrl: _baseUrl,
              connectTimeout: const Duration(seconds: 15),
              receiveTimeout: const Duration(seconds: 20),
              validateStatus: (status) => status != null && status < 600,
              headers: _headers,
            ),
          );

  final Dio _dio;
  List<Map<String, dynamic>> _shows = const [];
  List<Map<String, dynamic>> _episodes = const [];
  DateTime? _showsFetchedAt;
  DateTime? _episodesFetchedAt;

  static const _baseUrl = 'https://xon-avens.xyz/apis';
  static const _archiveBaseUrl = 'https://archive.org/download/';
  static const _cacheTtl = Duration(minutes: 30);
  static const _headers = {
    'Accept-Encoding': 'gzip',
    'API': '553y845hfhdlfhjkl438943943839443943fdhdkfjfj9834lnfd98',
    'CALLER': 'vion-official-app',
    'Connection': 'Keep-Alive',
    'Host': 'xon-avens.xyz',
    'User-Agent': 'okhttp/5.3.2',
  };

  @override
  String get name => 'Xon';

  @override
  Future<List<String>> availableServers(PlaybackRequest request) async {
    final candidates = await _matchingCandidates(
      request,
      includeEpisodes: request.episode != null,
    );
    final labels = <String>[];
    for (final candidate in candidates) {
      if (candidate.sources.isEmpty) continue;
      final label = candidate.languageLabel;
      if (label.isEmpty || labels.contains(label)) continue;
      labels.add(label);
    }
    return labels;
  }

  @override
  Future<StreamResult?> resolve(
    PlaybackRequest request, {
    required String server,
  }) async {
    final candidates = await _matchingCandidates(
      request,
      includeEpisodes: request.episode != null,
    );
    if (candidates.isEmpty) return null;

    final availableAudios = <String>[];
    for (final candidate in candidates) {
      if (candidate.sources.isEmpty) continue;
      final language = candidate.languageLabel;
      if (language.isNotEmpty && !availableAudios.contains(language)) {
        availableAudios.add(language);
      }
    }

    final selected = _selectCandidate(candidates, server, request);
    if (selected == null || selected.sources.isEmpty) return null;
    final source = _selectSource(selected.sources, request.preferredQuality);
    if (source == null) return null;

    return StreamResult(
      url: source.url,
      quality: source.quality,
      provider: '$name (${selected.languageLabel})',
      headers: const {'User-Agent': 'okhttp/5.3.2', 'Referer': _baseUrl},
      sources: selected.sources,
      availableQualities: selected.sources
          .map((source) => source.quality)
          .toSet()
          .toList(growable: false),
      availableAudios: availableAudios,
      selectedAudio: selected.languageLabel,
      isM3U8: source.isM3U8,
      isDirect: true,
      isIframe: false,
    );
  }

  Future<List<_XonCandidate>> _matchingCandidates(
    PlaybackRequest request, {
    required bool includeEpisodes,
  }) async {
    await _refreshShows();
    final title = _normalizeTitle(request.title);
    final candidates = <_XonCandidate>[];

    if (includeEpisodes) {
      try {
        await _refreshEpisodes();
        for (final episode in _episodes) {
          final episodeNo = _intValue(episode['no']);
          if (episodeNo != null && episodeNo != (request.episode ?? 1)) {
            continue;
          }
          if (!_matchesXonTitle(episode, title)) continue;
          final candidate = _XonCandidate.fromJson(episode);
          if (!_matchesRequestedXonSeason(candidate, request.season)) continue;
          if (candidate.sources.isNotEmpty) candidates.add(candidate);
        }
      } catch (_) {
        // The episode catalog is large; movie/cartoon specials can still be
        // resolved from the show catalog when this endpoint is slow.
      }
    }

    for (final show in _shows) {
      if (!_matchesXonTitle(show, title)) continue;
      final candidate = _XonCandidate.fromJson(show);
      if (candidate.sources.isNotEmpty) candidates.add(candidate);
    }

    candidates.sort((a, b) {
      final aScore = _candidateScore(a, request);
      final bScore = _candidateScore(b, request);
      if (aScore != bScore) return bScore.compareTo(aScore);
      return b.sources.length.compareTo(a.sources.length);
    });
    return candidates;
  }

  Future<void> _refreshShows() async {
    if (_showsFetchedAt case final fetched?
        when DateTime.now().difference(fetched) < _cacheTtl) {
      return;
    }
    final response = await _dio.get<Object?>('$_baseUrl/nzgetshows.php');
    _animeLog(
      name,
      'Request URL: ${response.realUri} HTTP ${response.statusCode} '
      'headers=${_dioHeaderSummary(response.headers)}',
    );
    if (response.statusCode != 200) return;
    final body = _decodeXonBody(response.data);
    final movies = body?['movies'];
    if (movies is! List) return;
    _shows = movies
        .map(_map)
        .whereType<Map<String, dynamic>>()
        .toList(growable: false);
    _showsFetchedAt = DateTime.now();
  }

  Future<void> _refreshEpisodes() async {
    if (_episodesFetchedAt case final fetched?
        when DateTime.now().difference(fetched) < _cacheTtl) {
      return;
    }
    final response = await _dio.get<Object?>('$_baseUrl/nzgetepisodes_v2.php');
    _animeLog(
      name,
      'Request URL: ${response.realUri} HTTP ${response.statusCode} '
      'headers=${_dioHeaderSummary(response.headers)}',
    );
    if (response.statusCode != 200) return;
    final body = _decodeXonBody(response.data);
    final episodes = body?['episodes'];
    if (episodes is! List) return;
    _episodes = episodes
        .map(_map)
        .whereType<Map<String, dynamic>>()
        .toList(growable: false);
    _episodesFetchedAt = DateTime.now();
  }

  _XonCandidate? _selectCandidate(
    List<_XonCandidate> candidates,
    String server,
    PlaybackRequest request,
  ) {
    final serverLanguage = _normalizedLanguage(server);
    if (serverLanguage.isNotEmpty && serverLanguage != 'auto') {
      for (final candidate in candidates) {
        if (_normalizedLanguage(candidate.languageLabel) == serverLanguage) {
          return candidate;
        }
      }
    }

    final preferred = _normalizedLanguage(request.preferredAudioTrack ?? '');
    if (preferred.isNotEmpty) {
      for (final candidate in candidates) {
        if (_normalizedLanguage(candidate.languageLabel) == preferred) {
          return candidate;
        }
      }
    }

    return candidates.first;
  }

  StreamSource? _selectSource(List<StreamSource> sources, String? quality) {
    if (sources.isEmpty) return null;
    final preferred = quality?.toLowerCase().trim() ?? '';
    if (preferred.isNotEmpty && preferred != 'auto') {
      for (final source in sources) {
        if (source.quality.toLowerCase() == preferred) return source;
      }
    }
    return sources.last;
  }

  bool _matchesXonTitle(Map<String, dynamic> json, String normalizedTitle) {
    if (normalizedTitle.isEmpty) return false;
    final names = [
      json['name'],
      json['show_name'],
      json['showName'],
      json['tags'],
    ].map((value) => _normalizeTitle(value?.toString() ?? ''));
    for (final name in names) {
      if (name.isEmpty) continue;
      if (name == normalizedTitle ||
          name.contains(normalizedTitle) ||
          normalizedTitle.contains(name)) {
        return true;
      }
    }
    return false;
  }

  int _candidateScore(_XonCandidate candidate, PlaybackRequest request) {
    var score = 0;
    final preferred = _normalizedLanguage(request.preferredAudioTrack ?? '');
    if (preferred.isNotEmpty &&
        _normalizedLanguage(candidate.languageLabel) == preferred) {
      score += 20;
    }
    if (candidate.kind == _XonCandidateKind.episode) {
      score += 10;
      if (request.season != null && candidate.seasonNumber == request.season) {
        score += 15;
      }
    }
    if (candidate.titleNormalized == _normalizeTitle(request.title)) score += 5;
    return score;
  }

  bool _matchesRequestedXonSeason(_XonCandidate candidate, int? season) {
    if (season == null || candidate.kind != _XonCandidateKind.episode) {
      return true;
    }
    final candidateSeason = candidate.seasonNumber;
    return candidateSeason == null || candidateSeason == season;
  }
}

/// Android's first anime provider. Its `auto` server preserves the Android
/// fallback order: Kite, Dio, Sage, then Meg.
class AnimetsuStreamProvider implements AnimeStreamProvider {
  AnimetsuStreamProvider({Dio? dio})
    : _dio =
          dio ??
          Dio(
            BaseOptions(
              connectTimeout: const Duration(seconds: 15),
              receiveTimeout: const Duration(seconds: 20),
              validateStatus: (status) => status != null && status < 600,
              headers: const {
                'User-Agent': _animetsuUserAgent,
                'Referer': 'https://animetsu.live/',
                'Origin': 'https://animetsu.live',
              },
            ),
          );

  final Dio _dio;

  @override
  String get name => 'Animetsu';

  @override
  Future<List<String>> availableServers(PlaybackRequest request) async =>
      const ['auto'];

  @override
  Future<StreamResult?> resolve(
    PlaybackRequest request, {
    required String server,
  }) async {
    final id = request.numericMediaId;
    if (id == null) return null;

    try {
      final searchResponse = await _dio.get<Object?>(
        'https://animetsu.live/v2/api/anime/search',
        queryParameters: {'query': request.title},
      );
      _animeLog(
        name,
        'Request URL: ${searchResponse.realUri} HTTP ${searchResponse.statusCode} '
        'headers=${_dioHeaderSummary(searchResponse.headers)}',
      );
      final searchData = _map(searchResponse.data);
      final results = searchData?['results'];
      if (results is! List) return null;

      String? internalId;
      for (final raw in results) {
        final item = _map(raw);
        final cover = _map(item?['cover_image'])?['large']?.toString() ?? '';
        final banner = item?['banner']?.toString() ?? '';
        if (cover.contains('bx$id') ||
            banner.contains('/$id-') ||
            banner.contains('/$id.')) {
          internalId = item?['id']?.toString();
          break;
        }
      }
      if (internalId == null) return null;

      final isDub = _prefersDub(request.preferredAudioTrack);
      final servers = server == 'auto'
          ? const ['kite', 'dio', 'sage', 'meg']
          : [server];
      for (final currentServer in servers) {
        final response = await _dio.get<Object?>(
          'https://animetsu.live/v2/api/anime/oppai/$internalId/${request.episode ?? 1}',
          queryParameters: {
            'server': currentServer,
            'source_type': isDub ? 'dub' : 'sub',
          },
        );
        _animeLog(
          name,
          'Request URL: ${response.realUri} HTTP ${response.statusCode} '
          'headers=${_dioHeaderSummary(response.headers)}',
        );
        if (response.statusCode != 200) continue;
        final data = _map(response.data);
        final rawSources = data?['sources'];
        if (rawSources is! List || rawSources.isEmpty) continue;

        final sources = <StreamSource>[];
        for (final raw in rawSources) {
          final source = _map(raw);
          var url = source?['url']?.toString() ?? '';
          if (url.isEmpty) continue;
          if (!url.startsWith('http')) {
            final path = url.startsWith('/') ? url : '/$url';
            url = 'https://swiftstream.top/proxy$path';
          } else if (source?['need_proxy'] == true &&
              !url.contains('swiftstream.top/proxy')) {
            url =
                'https://swiftstream.top/proxy?url=${Uri.encodeQueryComponent(url)}';
          }
          sources.add(
            StreamSource(
              url: url,
              quality: source?['quality']?.toString() ?? 'auto',
              isDub: isDub,
              isM3U8:
                  url.contains('.m3u8') ||
                  source?['type']?.toString().toLowerCase() == 'hls',
            ),
          );
        }
        if (sources.isEmpty) continue;

        final subtitles = <SubtitleTrack>[];
        final rawSubtitles = data?['subs'];
        if (rawSubtitles is List) {
          for (final raw in rawSubtitles) {
            final subtitle = _map(raw);
            final url = subtitle?['url']?.toString() ?? '';
            if (url.isNotEmpty) {
              subtitles.add(
                SubtitleTrack(
                  url: url,
                  lang: subtitle?['lang']?.toString() ?? 'Unknown',
                ),
              );
            }
          }
        }

        final skipTimes = <SkipTime>[];
        final skips = _map(data?['skips']);
        final intro = _map(skips?['intro']);
        final outro = _map(skips?['outro']);
        if (intro?['start'] != null && intro?['end'] != null) {
          skipTimes.add(
            SkipTime(
              type: 'op',
              startTime: Duration(seconds: (intro!['start'] as num).toInt()),
              endTime: Duration(seconds: (intro['end'] as num).toInt()),
            ),
          );
        }
        if (outro?['start'] != null && outro?['end'] != null) {
          skipTimes.add(
            SkipTime(
              type: 'ed',
              startTime: Duration(seconds: (outro!['start'] as num).toInt()),
              endTime: Duration(seconds: (outro['end'] as num).toInt()),
            ),
          );
        }

        final primary = sources.firstWhere(
          (source) =>
              source.quality.toLowerCase() == 'auto' ||
              source.quality == '1080p',
          orElse: () => sources.first,
        );
        return StreamResult(
          url: primary.url,
          quality: primary.quality,
          provider: 'Animetsu ($currentServer)',
          sources: sources,
          subtitles: subtitles,
          skipTimes: skipTimes,
          availableQualities: sources
              .map((source) => source.quality)
              .toSet()
              .toList(),
          availableAudios: const ['Default', 'English'],
          selectedAudio: isDub ? 'English' : 'Default',
          isM3U8: primary.isM3U8,
          headers: const {
            'Referer': 'https://animetsu.live/',
            'User-Agent': _animetsuUserAgent,
          },
        );
      }
    } on DioException {
      return null;
    } on FormatException {
      return null;
    }
    return null;
  }
}

class MiruroStreamProvider implements AnimeStreamProvider {
  MiruroStreamProvider({http.Client? client})
    : _client = client ?? http.Client();

  final http.Client _client;
  final _hlsSanitizer = _AnimeHlsSanitizer('Miruro');
  final List<int> _obfuscationKey = utf8.encode(
    '71951034f8fbcf53d89db52ceb3dc22c',
  );

  @override
  String get name => 'Miruro';

  @override
  Future<List<String>> availableServers(PlaybackRequest request) async {
    final id = request.numericMediaId;
    if (id == null) return const [];
    try {
      final data = await _pipe('episodes', {
        'anilistId': id,
        'version': '0.1.0',
      });
      final providers = _map(data)?['providers'];
      if (providers is! Map) return const [];
      final servers = providers.keys.map((key) => key.toString()).toList();
      _prioritizeBonk(servers);
      return servers;
    } catch (_) {
      return const [];
    }
  }

  @override
  Future<StreamResult?> resolve(
    PlaybackRequest request, {
    required String server,
  }) async {
    final id = request.numericMediaId;
    if (id == null) return null;
    try {
      final episodeData = await _pipe('episodes', {
        'anilistId': id,
        'version': '0.1.0',
      });
      final providers = _map(_map(episodeData)?['providers']);
      final provider = _map(providers?[server]);
      final episodesMap = _map(provider?['episodes']);
      final category = _prefersDub(request.preferredAudioTrack) ? 'dub' : 'sub';
      final episodes = episodesMap?[category];
      if (episodes is! List) return null;

      Map<String, dynamic>? selectedEpisode;
      for (final raw in episodes) {
        final episode = _map(raw);
        if ((episode?['number'] as num?)?.toInt() == (request.episode ?? 1)) {
          selectedEpisode = episode;
          break;
        }
      }
      if (selectedEpisode == null) return null;

      final rawId = selectedEpisode['id']?.toString() ?? '';
      if (rawId.isEmpty) return null;
      var decodedId = rawId;
      try {
        final padded = rawId.padRight((rawId.length + 3) ~/ 4 * 4, '=');
        final decoded = utf8.decode(base64Url.decode(padded));
        if (decoded.contains(':')) decodedId = decoded;
      } catch (_) {}

      final encodedId = base64UrlEncode(
        utf8.encode(decodedId),
      ).replaceAll('=', '');
      final sourceData = await _pipe('sources', {
        'episodeId': encodedId,
        'provider': server,
        'category': category,
        'anilistId': id,
        'version': '0.1.0',
      });
      final data = _map(sourceData);
      final streams = data?['streams'];
      if (streams is! List) return null;

      final sources = <StreamSource>[];
      var referer = 'https://www.miruro.bz/';
      for (final raw in streams) {
        final stream = _map(raw);
        final url = stream?['url']?.toString() ?? '';
        if (url.isEmpty) continue;
        final streamReferer = stream?['referer']?.toString() ?? referer;
        final streamOrigin = streamReferer.endsWith('/')
            ? streamReferer.substring(0, streamReferer.length - 1)
            : streamReferer;
        referer = streamReferer;
        var quality = stream?['quality']?.toString() ?? 'Auto';
        final fansub = stream?['fansub']?.toString();
        final serverName = stream?['server']?.toString();
        if (fansub != null && fansub.isNotEmpty) {
          quality += ' ($fansub)';
        } else if (serverName != null && serverName.isNotEmpty) {
          quality += ' ($serverName)';
        }
        final isHls =
            url.contains('.m3u8') ||
            stream?['type']?.toString().toLowerCase() == 'hls';
        final sourceHeaders = {
          'Referer': streamReferer,
          'Origin': streamOrigin,
          'User-Agent': _miruroUserAgent,
        };
        final resolvedUrl = isHls
            ? await _hlsSanitizer.proxyPlaylist(url, sourceHeaders)
            : url;
        sources.add(
          StreamSource(
            url: resolvedUrl,
            quality: quality,
            isDub: category == 'dub',
            isM3U8: isHls,
          ),
        );
      }
      if (sources.isEmpty) return null;

      final subtitles = <SubtitleTrack>[];
      final rawSubtitles = data?['subtitles'];
      if (rawSubtitles is List) {
        for (final raw in rawSubtitles) {
          final subtitle = _map(raw);
          final url =
              subtitle?['url']?.toString() ??
              subtitle?['file']?.toString() ??
              '';
          if (url.startsWith('http')) {
            subtitles.add(
              SubtitleTrack(
                url: url,
                lang:
                    subtitle?['language']?.toString() ??
                    subtitle?['label']?.toString() ??
                    'Unknown',
              ),
            );
          }
        }
      }

      final selected = sources.firstWhere(
        (source) => source.isM3U8,
        orElse: () => sources.first,
      );
      final origin = referer.endsWith('/')
          ? referer.substring(0, referer.length - 1)
          : referer;
      return StreamResult(
        url: selected.url,
        quality: selected.quality,
        provider: 'Miruro ($server)',
        sources: sources,
        subtitles: subtitles,
        isM3U8: selected.isM3U8,
        headers: {
          'Referer': referer,
          'Origin': origin,
          'User-Agent': _miruroUserAgent,
        },
        availableAudios: _availableAudioLabels(episodesMap),
        selectedAudio: category == 'dub' ? 'English (Dub)' : 'Japanese (Sub)',
      );
    } catch (_) {
      return null;
    }
  }

  Future<Object?> _pipe(String path, Map<String, dynamic> query) async {
    final payload = base64UrlEncode(
      utf8.encode(
        jsonEncode({
          'path': path,
          'method': 'GET',
          'query': query,
          'body': null,
        }),
      ),
    ).replaceAll('=', '');
    final response = await _client.get(
      Uri.parse('https://www.miruro.bz/api/secure/pipe?e=$payload'),
      headers: const {
        'User-Agent': _miruroUserAgent,
        'Referer': 'https://www.miruro.bz/',
        'Origin': 'https://www.miruro.bz',
        'Accept': 'application/json, text/plain, */*',
        'Accept-Language': 'en-US,en;q=0.9',
        'sec-fetch-site': 'same-origin',
        'sec-fetch-mode': 'cors',
        'sec-fetch-dest': 'empty',
        'sec-ch-ua':
            '"Not.A/Brand";v="8", "Chromium";v="114", "Google Chrome";v="114"',
        'sec-ch-ua-mobile': '?1',
        'sec-ch-ua-platform': '"Android"',
      },
    );
    _animeLog(
      'Miruro',
      'Request URL: ${response.request?.url} HTTP ${response.statusCode} '
          'headers=${_mapHeaderSummary(response.headers)}',
    );
    if (response.statusCode != 200) {
      throw FormatException('Miruro HTTP ${response.statusCode}');
    }

    final padded = response.body.padRight(
      (response.body.length + 3) ~/ 4 * 4,
      '=',
    );
    var bytes = base64Url.decode(padded);
    if (response.headers['x-obfuscated'] == '2') {
      final decoded = Uint8List(bytes.length);
      for (var i = 0; i < bytes.length; i++) {
        decoded[i] = bytes[i] ^ _obfuscationKey[i % _obfuscationKey.length];
      }
      bytes = decoded;
    }
    return jsonDecode(utf8.decode(gzip.decode(bytes)));
  }
}

class AnimexStreamProvider implements AnimeStreamProvider {
  AnimexStreamProvider({http.Client? client})
    : _client = client ?? http.Client();

  final http.Client _client;
  final _hlsSanitizer = _AnimeHlsSanitizer('Animex');
  final _slugCache = <int, _AnimeCacheEntry<String>>{};
  final _serverCache = <String, _AnimeCacheEntry<Map<String, dynamic>>>{};
  static const _baseUrl = 'https://animex.one';
  static const _apiUrl = 'https://pp.animex.one/rest/api';
  static const _cacheTtl = Duration(minutes: 30);

  @override
  String get name => 'Animex';

  Future<String?> _slug(PlaybackRequest request) async {
    final id = request.numericMediaId;
    if (id == null) return null;
    final cached = _slugCache[id];
    if (cached != null && cached.isFresh(_cacheTtl)) return cached.value;
    final response = await _client.get(
      Uri.parse('$_baseUrl/anime/$id'),
      headers: const {
        'User-Agent': _animexUserAgent,
        'Accept':
            'text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,image/apng,*/*;q=0.8',
        'Accept-Language': 'en-US,en;q=0.9',
      },
    );
    _animeLog(
      name,
      'Request URL: ${response.request?.url} HTTP ${response.statusCode} '
      'headers=${_mapHeaderSummary(response.headers)}',
    );
    if (response.statusCode != 200) return null;
    final slug = RegExp(r'slug:"([^"]+)"').firstMatch(response.body)?.group(1);
    if (slug != null && slug.isNotEmpty) {
      _slugCache[id] = _AnimeCacheEntry(slug);
    }
    return slug;
  }

  @override
  Future<List<String>> availableServers(PlaybackRequest request) async {
    try {
      final slug = await _slug(request);
      if (slug == null) return const [];
      final data = await _servers(slug, request.episode ?? 1);
      final providers = _animexProviderListFor(data, request);
      if (providers is! List) return const [];
      final result = <String>[];
      for (final raw in providers) {
        final provider = _map(raw);
        final name =
            provider?['serverName']?.toString() ?? provider?['id']?.toString();
        if (name == null || name.isEmpty) continue;
        final tip = provider?['tip']?.toString().toLowerCase() ?? '';
        if (tip.contains('soft sub')) {
          result.add('$name (Soft Sub)');
        } else if (tip.contains('hard sub')) {
          result.add('$name (Hard Sub)');
        } else {
          result.add(name);
        }
      }
      _prioritizeBonk(result);
      return result;
    } catch (_) {
      return const [];
    }
  }

  @override
  Future<StreamResult?> resolve(
    PlaybackRequest request, {
    required String server,
  }) async {
    try {
      final slug = await _slug(request);
      if (slug == null) return null;
      final episode = request.episode ?? 1;
      final serverData = await _servers(slug, episode);
      final type = _prefersDub(request.preferredAudioTrack) ? 'dub' : 'sub';
      final providers = serverData == null
          ? null
          : type == 'dub'
          ? serverData['dubProviders']
          : serverData['subProviders'];
      if (providers is! List || providers.isEmpty) return null;
      final availableAudios = _animexAvailableAudioLabels(serverData);

      String? providerId;
      final cleanServer = server
          .replaceAll(' (Soft Sub)', '')
          .replaceAll(' (Hard Sub)', '')
          .toLowerCase();
      for (final raw in providers) {
        final provider = _map(raw);
        final id = provider?['id']?.toString();
        final name = provider?['serverName']?.toString();
        if (id?.toLowerCase() == cleanServer ||
            name?.toLowerCase() == cleanServer) {
          providerId = id;
          break;
        }
      }
      providerId ??= _defaultAnimexProviderId(providers);
      if (providerId == null) return null;

      final response = await _client.get(
        Uri.parse(
          '$_apiUrl/sources?id=$slug&epNum=$episode&type=$type&providerId=$providerId',
        ),
        headers: const {
          'User-Agent': _animexUserAgent,
          'Origin': _baseUrl,
          'Referer': '$_baseUrl/',
          'Accept': '*/*',
        },
      );
      _animeLog(
        name,
        'Request URL: ${response.request?.url} HTTP ${response.statusCode} '
        'headers=${_mapHeaderSummary(response.headers)}',
      );
      if (response.statusCode != 200) return null;
      final data = _map(jsonDecode(response.body));
      final rawSources = data?['sources'];
      if (rawSources is! List) return null;

      final sources = <StreamSource>[];
      for (final raw in rawSources) {
        final source = _map(raw);
        final url = source?['url']?.toString() ?? '';
        if (url.isEmpty) continue;
        sources.add(
          StreamSource(
            url: url,
            quality: source?['quality']?.toString() ?? 'Auto',
            isM3U8:
                url.contains('.m3u8') ||
                source?['type']?.toString().toLowerCase() == 'video/mpegurl',
          ),
        );
      }
      if (sources.isEmpty) return null;
      final selected = sources.firstWhere(
        (source) => source.isM3U8,
        orElse: () => sources.first,
      );

      final headers = <String, String>{};
      final rawHeaders = _map(data?['headers']);
      rawHeaders?.forEach((key, value) => headers[key] = value.toString());
      headers.putIfAbsent('User-Agent', () => _animexUserAgent);
      headers.putIfAbsent('Referer', () => '$_baseUrl/');
      headers.putIfAbsent('Origin', () => _baseUrl);

      final subtitles = <SubtitleTrack>[];
      final tracks = data?['tracks'];
      if (tracks is List) {
        for (final raw in tracks) {
          final track = _map(raw);
          final url = track?['url']?.toString() ?? '';
          final kind = track?['kind']?.toString().toLowerCase() ?? '';
          final lowerUrl = url.toLowerCase();
          if (url.isEmpty || !url.startsWith('http')) continue;
          if (kind == 'thumbnails' ||
              lowerUrl.contains('.m3u8') ||
              lowerUrl.contains('.m3u') ||
              lowerUrl.contains('.ass') ||
              lowerUrl.contains('.ssa')) {
            continue;
          }
          subtitles.add(
            SubtitleTrack(
              url: url,
              lang:
                  track?['lang']?.toString() ??
                  track?['label']?.toString() ??
                  'Unknown',
            ),
          );
        }
      }

      final skipTimes = <SkipTime>[];
      final intro = _map(data?['intro']);
      final outro = _map(data?['outro']);
      if (intro?['start'] != null && intro?['end'] != null) {
        skipTimes.add(
          SkipTime(
            startTime: Duration(
              milliseconds: ((intro!['start'] as num).toInt() * 1000),
            ),
            endTime: Duration(
              milliseconds: ((intro['end'] as num).toInt() * 1000),
            ),
            type: 'intro',
          ),
        );
      }
      if (outro?['start'] != null && outro?['end'] != null) {
        skipTimes.add(
          SkipTime(
            startTime: Duration(
              milliseconds: ((outro!['start'] as num).toInt() * 1000),
            ),
            endTime: Duration(
              milliseconds: ((outro['end'] as num).toInt() * 1000),
            ),
            type: 'outro',
          ),
        );
      }

      final resolvedUrl = selected.isM3U8
          ? await _hlsSanitizer.proxyPlaylist(selected.url, headers)
          : selected.url;
      final resolvedSources = selected.isM3U8
          ? [
              StreamSource(
                url: resolvedUrl,
                quality: selected.quality,
                isM3U8: true,
                isDub: type == 'dub',
              ),
              ...sources.where((source) => source.url != selected.url),
            ]
          : sources;
      return StreamResult(
        url: resolvedUrl,
        quality: selected.quality,
        provider: 'Animex ($providerId)',
        headers: headers,
        sources: resolvedSources,
        subtitles: subtitles,
        skipTimes: skipTimes,
        isM3U8: selected.isM3U8,
        availableAudios: availableAudios,
        selectedAudio: type == 'dub' ? 'English (Dub)' : 'Japanese (Sub)',
      );
    } catch (_) {
      return null;
    }
  }

  Future<Map<String, dynamic>?> _servers(String slug, int episode) async {
    final cacheKey = '$slug|$episode';
    final cached = _serverCache[cacheKey];
    if (cached != null && cached.isFresh(_cacheTtl)) return cached.value;
    final response = await _client.get(
      Uri.parse('$_apiUrl/servers?id=$slug&epNum=$episode'),
      headers: const {
        'User-Agent': _animexUserAgent,
        'Origin': _baseUrl,
        'Referer': '$_baseUrl/',
        'Accept': '*/*',
      },
    );
    _animeLog(
      name,
      'Request URL: ${response.request?.url} HTTP ${response.statusCode} '
      'headers=${_mapHeaderSummary(response.headers)}',
    );
    if (response.statusCode != 200) return null;
    final data = _map(jsonDecode(response.body));
    if (data != null) {
      _serverCache[cacheKey] = _AnimeCacheEntry(data);
    }
    return data;
  }
}

class _AnimeCacheEntry<T> {
  _AnimeCacheEntry(this.value) : createdAt = DateTime.now();

  final T value;
  final DateTime createdAt;

  bool isFresh(Duration ttl) => DateTime.now().difference(createdAt) < ttl;
}

List<dynamic>? _animexProviderListFor(
  Map<String, dynamic>? data,
  PlaybackRequest request,
) {
  if (data == null) return null;
  final type = _prefersDub(request.preferredAudioTrack) ? 'dub' : 'sub';
  final providers = type == 'dub' ? data['dubProviders'] : data['subProviders'];
  return providers is List ? providers : null;
}

List<String> _animexAvailableAudioLabels(Map<String, dynamic>? data) {
  if (data == null) return const [];
  final labels = <String>[];
  if ((data['subProviders'] as List?)?.isNotEmpty == true) {
    labels.add('Japanese (Sub)');
  }
  if ((data['dubProviders'] as List?)?.isNotEmpty == true) {
    labels.add('English (Dub)');
  }
  return labels;
}

String? _defaultAnimexProviderId(List<dynamic> providers) {
  for (final raw in providers) {
    final provider = _map(raw);
    if (provider?['default'] == true) {
      return provider?['id']?.toString();
    }
  }
  return _map(providers.first)?['id']?.toString();
}

class _AnimeHlsSanitizer {
  _AnimeHlsSanitizer(this.providerName);

  final String providerName;
  HttpServer? _server;

  Future<String> proxyPlaylist(
    String playlistUrl,
    Map<String, String> headers,
  ) async {
    await _start();
    final uri = _proxyUri(playlistUrl, headers, _AnimexProxyKind.playlist);
    _animeLog(
      providerName,
      'Resolved URL: $playlistUrl backend=media_kit via anime HLS sanitizer',
    );
    return uri.toString();
  }

  Future<void> _start() async {
    if (_server != null) return;
    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _server!.listen(_handleRequest);
    _animeLog(providerName, 'HLS sanitizer started on port ${_server!.port}');
  }

  Uri _proxyUri(
    String targetUrl,
    Map<String, String> headers,
    _AnimexProxyKind kind,
  ) {
    String encode(String value) =>
        base64Url.encode(utf8.encode(value)).replaceAll('=', '');

    return Uri(
      scheme: 'http',
      host: InternetAddress.loopbackIPv4.address,
      port: _server!.port,
      path: '/animex-hls',
      queryParameters: {
        'url': encode(targetUrl),
        'kind': kind.name,
        if (headers['User-Agent'] case final userAgent?)
          'ua': encode(userAgent),
        if (headers['Referer'] case final referer?) 'ref': encode(referer),
        if (headers['Origin'] case final origin?) 'origin': encode(origin),
      },
    );
  }

  Future<void> _handleRequest(HttpRequest request) async {
    if (request.uri.path != '/animex-hls') {
      request.response.statusCode = HttpStatus.notFound;
      await request.response.close();
      return;
    }

    try {
      final targetUrl = _decodeParam(request.uri.queryParameters['url']);
      if (targetUrl == null) {
        request.response.statusCode = HttpStatus.badRequest;
        await request.response.close();
        return;
      }

      final kind = _AnimexProxyKind.values.firstWhere(
        (value) => value.name == request.uri.queryParameters['kind'],
        orElse: () => _AnimexProxyKind.segment,
      );
      final headers = _headersFrom(request.uri);
      final targetUri = Uri.parse(targetUrl);
      final upstream = await http.get(targetUri, headers: headers);
      request.response.statusCode = upstream.statusCode;

      if (kind == _AnimexProxyKind.playlist) {
        final body = utf8.decode(upstream.bodyBytes, allowMalformed: true);
        final rewritten = _rewritePlaylist(targetUri, body, headers);
        final bytes = utf8.encode(rewritten);
        request.response.headers.contentType = ContentType(
          'application',
          'vnd.apple.mpegurl',
          charset: 'utf-8',
        );
        request.response.headers.contentLength = bytes.length;
        request.response.add(bytes);
      } else if (kind == _AnimexProxyKind.segment) {
        final bytes = _stripFakePngPrelude(upstream.bodyBytes);
        request.response.headers.contentType = ContentType('video', 'mp2t');
        request.response.headers.contentLength = bytes.length;
        request.response.add(bytes);
      } else {
        request.response.add(upstream.bodyBytes);
      }
    } catch (error) {
      _animeLog(providerName, 'HLS sanitizer error: $error');
      request.response.statusCode = HttpStatus.internalServerError;
    } finally {
      await request.response.close();
    }
  }

  String _rewritePlaylist(
    Uri playlistUri,
    String body,
    Map<String, String> headers,
  ) {
    final lines = body.split('\n');
    final rewritten = <String>[];
    for (final rawLine in lines) {
      final line = rawLine.trim();
      if (line.isEmpty) continue;

      if (line.startsWith('#EXT-X-KEY:')) {
        rewritten.add(_rewriteKeyLine(playlistUri, line, headers));
      } else if (line.startsWith('#')) {
        rewritten.add(line);
      } else {
        final absolute = playlistUri.resolve(line).toString();
        final kind = line.toLowerCase().contains('.m3u8')
            ? _AnimexProxyKind.playlist
            : _AnimexProxyKind.segment;
        rewritten.add(_proxyUri(absolute, headers, kind).toString());
      }
    }
    return rewritten.join('\n');
  }

  String _rewriteKeyLine(
    Uri playlistUri,
    String line,
    Map<String, String> headers,
  ) {
    final match = RegExp(r'URI="([^"]+)"').firstMatch(line);
    if (match == null) return line;
    final original = match.group(1)!;
    final absolute = playlistUri.resolve(original).toString();
    final proxied = _proxyUri(
      absolute,
      headers,
      _AnimexProxyKind.raw,
    ).toString();
    return line.replaceFirst('URI="$original"', 'URI="$proxied"');
  }

  Uint8List _stripFakePngPrelude(Uint8List bytes) {
    if (!_hasPngMagic(bytes)) return bytes;
    final syncOffset = _mpegTsSyncOffset(bytes);
    if (syncOffset == null || syncOffset == 0) return bytes;
    _animeLog(
      providerName,
      'Stripped fake PNG prelude from HLS segment at byte $syncOffset',
    );
    return Uint8List.sublistView(bytes, syncOffset);
  }

  bool _hasPngMagic(Uint8List bytes) {
    return bytes.length >= 8 &&
        bytes[0] == 0x89 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x4E &&
        bytes[3] == 0x47 &&
        bytes[4] == 0x0D &&
        bytes[5] == 0x0A &&
        bytes[6] == 0x1A &&
        bytes[7] == 0x0A;
  }

  int? _mpegTsSyncOffset(Uint8List bytes) {
    final searchLimit = bytes.length < 4096 ? bytes.length : 4096;
    for (var offset = 0; offset < searchLimit; offset++) {
      var matches = 0;
      for (var packet = 0; packet < 5; packet++) {
        final index = offset + (188 * packet);
        if (index >= bytes.length || bytes[index] != 0x47) break;
        matches++;
      }
      if (matches >= 3) return offset;
    }
    return null;
  }

  Map<String, String> _headersFrom(Uri uri) {
    final headers = <String, String>{
      'Accept': '*/*',
      'Sec-Fetch-Site': 'cross-site',
      'Sec-Fetch-Mode': 'cors',
      'Sec-Fetch-Dest': 'empty',
    };
    final userAgent = _decodeParam(uri.queryParameters['ua']);
    final referer = _decodeParam(uri.queryParameters['ref']);
    final origin = _decodeParam(uri.queryParameters['origin']);
    headers['User-Agent'] = userAgent ?? _animexUserAgent;
    if (referer != null) headers['Referer'] = referer;
    if (origin != null) headers['Origin'] = origin;
    return headers;
  }

  String? _decodeParam(String? value) {
    if (value == null || value.isEmpty) return null;
    final padded = value.padRight(
      value.length + (4 - value.length % 4) % 4,
      '=',
    );
    return utf8.decode(base64Url.decode(padded));
  }
}

enum _AnimexProxyKind { playlist, segment, raw }

enum _XonCandidateKind { movie, episode }

class _XonCandidate {
  const _XonCandidate({
    required this.kind,
    required this.title,
    required this.showTitle,
    required this.seasonName,
    required this.seasonNumber,
    required this.languageLabel,
    required this.sources,
  });

  final _XonCandidateKind kind;
  final String title;
  final String showTitle;
  final String seasonName;
  final int? seasonNumber;
  final String languageLabel;
  final List<StreamSource> sources;

  String get titleNormalized => _normalizeTitle(title);

  factory _XonCandidate.fromJson(Map<String, dynamic> json) {
    final language = _cleanXonLanguage(
      json['language_name']?.toString() ?? json['languageName']?.toString(),
    );
    final seasonName =
        json['season_name']?.toString() ?? json['seasonName']?.toString() ?? '';
    return _XonCandidate(
      kind: json.containsKey('season_id')
          ? _XonCandidateKind.episode
          : _XonCandidateKind.movie,
      title: json['name']?.toString() ?? '',
      showTitle:
          json['show_name']?.toString() ?? json['showName']?.toString() ?? '',
      seasonName: seasonName,
      seasonNumber: _xonSeasonNumber(seasonName),
      languageLabel: language.isEmpty ? 'Default' : language,
      sources: _xonSources(json),
    );
  }
}

List<StreamSource> _xonSources(Map<String, dynamic> json) {
  final sources = <StreamSource>[];
  void add(String key, String quality) {
    final rawUrl = json[key]?.toString().trim() ?? '';
    if (rawUrl.isEmpty) return;
    final url = _formatXonUrl(rawUrl);
    if (url.isEmpty || sources.any((source) => source.url == url)) return;
    sources.add(
      StreamSource(url: url, quality: quality, isM3U8: _isXonM3u8(url)),
    );
  }

  add('basic', '360p');
  add('sd', '480p');
  add('hd', '720p');
  add('fhd', '1080p');
  return sources;
}

Map<String, dynamic>? _decodeXonBody(Object? data) {
  if (data is Map<String, dynamic>) return data;
  if (data is Map) return Map<String, dynamic>.from(data);
  if (data is String && data.trim().isNotEmpty) {
    final decoded = jsonDecode(data);
    return _map(decoded);
  }
  return null;
}

String _formatXonUrl(String url) {
  if (url.startsWith('http://') || url.startsWith('https://')) return url;
  return '${XonStreamProvider._archiveBaseUrl}$url';
}

String _cleanXonLanguage(String? value) {
  final raw = value?.trim() ?? '';
  if (raw.isEmpty) return '';
  for (final language in const [
    'Tamil',
    'Telugu',
    'Hindi',
    'Malayalam',
    'Kannada',
    'English',
    'Japanese',
    'Korean',
  ]) {
    if (raw.toLowerCase().contains(language.toLowerCase())) return language;
  }
  final parenthesized = RegExp(r'\(([^)]+)\)').firstMatch(raw)?.group(1);
  final candidate = (parenthesized ?? raw).trim();
  return candidate;
}

String _normalizedLanguage(String value) {
  final clean = _cleanXonLanguage(value);
  return clean.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '');
}

String _normalizeTitle(String value) {
  return value
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
      .trim()
      .replaceAll(RegExp(r'\s+'), ' ');
}

int? _intValue(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '');
}

int? _xonSeasonNumber(String value) {
  final match = RegExp(
    r'\bseason\s*0*(\d+)\b',
    caseSensitive: false,
  ).firstMatch(value);
  final raw = match?.group(1);
  return raw == null ? null : int.tryParse(raw);
}

bool _isXonM3u8(String url) => url.toLowerCase().contains('.m3u8');

Map<String, dynamic>? _map(Object? value) {
  if (value is Map<String, dynamic>) return value;
  if (value is Map) return Map<String, dynamic>.from(value);
  return null;
}

void _prioritizeBonk(List<String> servers) {
  servers.sort((a, b) {
    if (a.toLowerCase() == 'bonk') return -1;
    if (b.toLowerCase() == 'bonk') return 1;
    return 0;
  });
}

bool _prefersDub(String? preferredAudioTrack) {
  final value = preferredAudioTrack?.toLowerCase().trim() ?? '';
  return value == 'english' ||
      value == 'dub' ||
      value.contains('english') ||
      value.contains('dub');
}

List<String> _availableAudioLabels(Map<String, dynamic>? episodesMap) {
  if (episodesMap == null) return const [];
  final labels = <String>[];
  for (final entry in episodesMap.entries) {
    final value = entry.value;
    if (value is! List || value.isEmpty) continue;
    final key = entry.key.toLowerCase();
    if (key == 'sub') {
      labels.add('Japanese (Sub)');
    } else if (key == 'dub') {
      labels.add('English (Dub)');
    } else {
      labels.add(entry.key.toUpperCase());
    }
  }
  return labels;
}

const String _animetsuUserAgent =
    'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 '
    '(KHTML, like Gecko) Chrome/147.0.0.0 Safari/537.36';

const String _miruroUserAgent =
    'Mozilla/5.0 (Linux; Android 13; Pixel 7) AppleWebKit/537.36 '
    '(KHTML, like Gecko) Chrome/114.0.0.0 Mobile Safari/537.36';

const String _animexUserAgent =
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
    '(KHTML, like Gecko) Chrome/137.0.0.0 Safari/537.36';

void _animeLog(String provider, String message) {
  PlaybackRuntimeDiagnostics.providerLog(provider, message);
}

String _dioHeaderSummary(Headers headers) {
  final contentType = headers.value(Headers.contentTypeHeader) ?? 'unknown';
  final location = headers.value('location');
  return 'content-type=$contentType${location == null ? '' : ', location=$location'}';
}

String _mapHeaderSummary(Map<String, String> headers) {
  final contentType = headers['content-type'] ?? 'unknown';
  final location = headers['location'];
  return 'content-type=$contentType${location == null ? '' : ', location=$location'}';
}
