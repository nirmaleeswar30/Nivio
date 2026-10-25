import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:nivio/core/debug_log.dart';
import 'package:nivio/models/stream_result.dart';
import 'package:nivio/services/network_client_factory.dart';
import 'package:nivio/services/hls_proxy_service.dart';

class MiruroScraperService {
  late final http.Client client;
  final List<int> _xorKey = utf8.encode('miruro/catalog');
  static const String _baseUrl = 'https://www.miruro.bz';
  static const String _userAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36';

  // Headers for miruro.bz API calls: what Chrome on Android sends for a
  // same-origin fetch. Cloudflare in front of the API now answers 403 to
  // Cronet requests that lack the sec-ch-ua / sec-fetch-* set (tested on a
  // phone: with these headers 200, without them 403, User-Agent aside).
  // The UA and sec-ch-ua versions must agree. No Origin: Chrome doesn't send
  // one on a same-origin GET.
  static const Map<String, String> _apiHeaders = {
    'User-Agent':
        'Mozilla/5.0 (Linux; Android 10; K) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/155.0.0.0 Mobile Safari/537.36',
    'Accept': 'application/octet-stream, application/json, */*',
    'Accept-Language': 'en-US,en;q=0.9',
    'Referer': '$_baseUrl/',
    'sec-ch-ua': '"Chromium";v="155", "Google Chrome";v="155", "Not_A Brand";v="99"',
    'sec-ch-ua-mobile': '?1',
    'sec-ch-ua-platform': '"Android"',
    'sec-fetch-site': 'same-origin',
    'sec-fetch-mode': 'cors',
    'sec-fetch-dest': 'empty',
  };

  final Map<String, String> _animeIdCache = {};
  final Map<String, Future<dynamic>> _playCache = {};

  MiruroScraperService() {
    client = NetworkClientFactory.createClient();
  }

  // Start of an error body, whitespace collapsed, for the log (an HTML error
  // page's <title> says whether it is a Cloudflare block or the API refusing).
  static String _bodySnippet(http.Response res) {
    final text = utf8.decode(res.bodyBytes, allowMalformed: true);
    final title = RegExp(r'<title>([^<]*)</title>', caseSensitive: false).firstMatch(text)?.group(1);
    final snippet = text.replaceAll(RegExp(r'\s+'), ' ');
    return title != null
        ? 'title="$title"'
        : snippet.substring(0, snippet.length < 200 ? snippet.length : 200);
  }

  static String? _thumbnailsVtt(Object? thumbnails) {
    final vtt = thumbnails is Map ? thumbnails['vtt']?.toString() : null;
    return (vtt != null && vtt.startsWith('http')) ? vtt : null;
  }

  dynamic _decodeCatalogResponse(List<int> bytes) {
    final xorBytes = List<int>.generate(
      bytes.length,
      (i) => bytes[i] ^ _xorKey[i % _xorKey.length],
    );
    final decompressed = gzip.decode(xorBytes);
    return jsonDecode(utf8.decode(decompressed));
  }

  Future<String?> _resolveTitleFromAniList(int anilistId) async {
    try {
      final res = await client.post(
        Uri.parse('https://graphql.anilist.co'),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
          'User-Agent': _userAgent,
        },
        body: jsonEncode({
          'query': 'query (\$id: Int) { Media(id: \$id, type: ANIME) { title { romaji english } } }',
          'variables': {'id': anilistId},
        }),
      );
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final titleObj = data['data']?['Media']?['title'];
        return titleObj?['romaji'] ?? titleObj?['english'];
      }
    } catch (e) {
      appDebugLog('AniList GraphQL lookup error in Miruro: $e');
    }
    return null;
  }

  Future<String?> _resolveMiruroAnimeId({
    required String anilistId,
    String? title,
  }) async {
    if (_animeIdCache.containsKey(anilistId)) {
      return _animeIdCache[anilistId];
    }

    String? searchTitle = title;
    if (searchTitle == null || searchTitle.trim().isEmpty) {
      final idNum = int.tryParse(anilistId);
      if (idNum != null) {
        searchTitle = await _resolveTitleFromAniList(idNum);
      }
    }

    if (searchTitle == null || searchTitle.trim().isEmpty) {
      return null;
    }

    final searchTitles = [
      searchTitle,
      searchTitle.replaceAll(RegExp(r'\([^)]*\)'), '').trim(),
      searchTitle.replaceAll(RegExp(r'Season \d+', caseSensitive: false), '').trim(),
    ].toSet().toList();

    for (final q in searchTitles) {
      if (q.isEmpty) continue;
      try {
        final uri = Uri.parse('$_baseUrl/api/v1/anime?q=${Uri.encodeComponent(q)}&limit=15&sort=-popularity');
        final res = await client.get(uri, headers: _apiHeaders);

        if (res.statusCode != 200) {
          appDebugLog(
            'Miruro: search "$q" returned ${res.statusCode} '
            '(${res.headers['content-type']}): ${_bodySnippet(res)}',
          );
          continue;
        }

        dynamic data;
        final ct = res.headers['content-type'] ?? '';
        if (ct.contains('octet-stream')) {
          data = _decodeCatalogResponse(res.bodyBytes);
        } else {
          data = jsonDecode(res.body);
        }

        final items = (data['data'] as List?) ?? [];
        for (final item in items) {
          final anilistIds = (item['external_ids']?['anilist'] as List?)
                  ?.map((e) => e.toString())
                  .toSet() ??
              {};
          if (anilistIds.contains(anilistId)) {
            final id = item['id'] as String;
            _animeIdCache[anilistId] = id;
            return id;
          }
        }

        if (items.isNotEmpty && q == searchTitle) {
          final id = items.first['id'] as String;
          _animeIdCache[anilistId] = id;
          return id;
        }
      } catch (e) {
        appDebugLog('Error searching Miruro for "$q": $e');
      }
    }

    return null;
  }

  Future<dynamic> _fetchPlayData(String miruroId, int episode) async {
    final cacheKey = '$miruroId:$episode';
    if (_playCache.containsKey(cacheKey)) {
      return await _playCache[cacheKey];
    }

    final future = () async {
      final uri = Uri.parse('$_baseUrl/api/v1/anime/$miruroId/episodes/$episode/play');
      final res = await client.get(uri, headers: _apiHeaders);

      if (res.statusCode != 200) {
        appDebugLog(
          'Miruro: play $miruroId ep $episode returned ${res.statusCode} '
          '(${res.headers['content-type']}): ${_bodySnippet(res)}',
        );
        throw Exception('Play request failed with status: ${res.statusCode}');
      }

      final ct = res.headers['content-type'] ?? '';
      if (ct.contains('octet-stream')) {
        return _decodeCatalogResponse(res.bodyBytes);
      } else {
        return jsonDecode(res.body);
      }
    }();

    _playCache[cacheKey] = future;
    Future.delayed(const Duration(seconds: 30), () {
      _playCache.remove(cacheKey);
    });

    return await future;
  }

  Future<List<String>> fetchAvailableServers({
    required String tmdbId,
    String? title,
    int episode = 1,
    String? preferredAudio,
  }) async {
    try {
      final miruroId = await _resolveMiruroAnimeId(anilistId: tmdbId, title: title);
      if (miruroId == null) return [];

      final playData = await _fetchPlayData(miruroId, episode);
      final tracks = (playData['tracks'] as List?) ?? [];
      if (tracks.isEmpty) return [];

      final isDub = preferredAudio?.toLowerCase().contains('dub') == true ||
          preferredAudio?.toLowerCase().contains('english') == true;

      Map<String, dynamic>? matchingTrack;
      for (final t in tracks) {
        final tName = (t['track'] as String? ?? '').toLowerCase();
        if (isDub && tName == 'dub') {
          matchingTrack = t as Map<String, dynamic>;
          break;
        } else if (!isDub && (tName == 'sub' || tName == 'ssub')) {
          matchingTrack = t as Map<String, dynamic>;
          break;
        }
      }

      matchingTrack ??= tracks.first as Map<String, dynamic>;

      final providers = (matchingTrack['providers'] as List?) ?? [];
      final serverNames = <String>[];
      for (final p in providers) {
        final name = p['provider']?.toString();
        final servers = (p['servers'] as List?) ?? [];
        final hasStreams = servers.any((s) => ((s['streams'] as List?)?.isNotEmpty ?? false));
        if (name != null && name.isNotEmpty && hasStreams) {
          serverNames.add(name);
        }
      }

      if (serverNames.isEmpty) {
        for (final t in tracks) {
          final provs = (t['providers'] as List?) ?? [];
          for (final p in provs) {
            final name = p['provider']?.toString();
            final servers = (p['servers'] as List?) ?? [];
            final hasStreams = servers.any((s) => ((s['streams'] as List?)?.isNotEmpty ?? false));
            if (name != null && name.isNotEmpty && hasStreams && !serverNames.contains(name)) {
              serverNames.add(name);
            }
          }
        }
      }

      return serverNames;
    } catch (e) {
      appDebugLog('Error in Miruro fetchAvailableServers: $e');
      return [];
    }
  }

  Future<StreamResult?> fetchStreamUrl({
    required String tmdbId,
    required int season,
    required int episode,
    required String preferredAudio,
    required String providerName,
    String? title,
  }) async {
    try {
      final miruroId = await _resolveMiruroAnimeId(anilistId: tmdbId, title: title);
      if (miruroId == null) return null;

      final playData = await _fetchPlayData(miruroId, episode);
      final tracks = (playData['tracks'] as List?) ?? [];
      if (tracks.isEmpty) return null;

      final isDub = preferredAudio.toLowerCase().contains('dub') ||
          preferredAudio.toLowerCase().contains('english');

      Map<String, dynamic>? targetTrack;
      for (final t in tracks) {
        final tName = (t['track'] as String? ?? '').toLowerCase();
        if (isDub && tName == 'dub') {
          targetTrack = t as Map<String, dynamic>;
          break;
        } else if (!isDub && (tName == 'sub' || tName == 'ssub')) {
          targetTrack = t as Map<String, dynamic>;
          break;
        }
      }
      targetTrack ??= tracks.first as Map<String, dynamic>;

      final providers = (targetTrack['providers'] as List?) ?? [];
      if (providers.isEmpty) return null;

      Map<String, dynamic>? selectedProv;
      final targetPName = providerName.toLowerCase();
      if (targetPName != 'auto') {
        for (final p in providers) {
          if ((p['provider']?.toString() ?? '').toLowerCase() == targetPName) {
            selectedProv = p as Map<String, dynamic>;
            break;
          }
        }
      }

      selectedProv ??= providers.firstWhere(
        (p) {
          final servers = (p['servers'] as List?) ?? [];
          return servers.any((s) => ((s['streams'] as List?)?.isNotEmpty ?? false));
        },
        orElse: () => null,
      ) as Map<String, dynamic>?;

      if (selectedProv == null) return null;

      final pName = selectedProv['provider']?.toString() ?? providerName;
      final servers = (selectedProv['servers'] as List?) ?? [];
      final subtitlesRaw = (selectedProv['subtitles'] as List?) ?? [];

      final List<StreamSource> sources = [];
      dynamic bestStream;
      Map<String, dynamic>? bestServer;

      for (final s in servers) {
        final sServersStreams = (s['streams'] as List?) ?? [];
        final sHeaders = (s['headers'] as Map<String, dynamic>?) ?? {};
        final serverName = s['server']?.toString() ?? '';

        String streamReferer = sHeaders['Referer']?.toString() ?? '$_baseUrl/';
        String streamOrigin = sHeaders['Origin']?.toString() ?? _baseUrl;

        for (final stream in sServersStreams) {
          final url = stream['url'] as String?;
          if (url == null || url.isEmpty) continue;

          final refLower = streamReferer.toLowerCase();
          if (url.contains('ibyteimg.com') || refLower.contains('vivibebe.site')) {
            appDebugLog('⚠️ Skipping dead bonk/ibyteimg stream: $url');
            continue;
          }

          final isHlsStream = url.contains('.m3u8') || stream['format'] == 'hls';
          if (bestStream == null) {
            bestStream = stream;
            bestServer = s as Map<String, dynamic>?;
          }

          final streamExtension = isHlsStream ? '.m3u8' : (url.contains('.mp4') ? '.mp4' : '');

          final proxiedUrl = HlsProxyService.instance.getProxyUrl(
            url,
            _userAgent,
            {},
            referer: streamReferer,
            origin: streamOrigin,
            extension: streamExtension,
          );

          String qualityLabel = stream['quality']?.toString().trim() ?? '';
          if (qualityLabel.isEmpty) {
            qualityLabel = stream['resolution']?.toString().trim() ?? '';
          }
          if (qualityLabel.isEmpty && serverName.isNotEmpty) {
            qualityLabel = serverName;
          }
          if (qualityLabel.isEmpty) {
            qualityLabel = 'Auto';
          }

          sources.add(StreamSource(
            url: proxiedUrl,
            quality: qualityLabel,
            isDub: isDub,
          ));
        }
      }

      if (sources.isEmpty || bestStream == null) return null;

      final subtitles = <StreamSubtitleTrack>[];
      for (final sub in subtitlesRaw) {
        final fileUrl = (sub['file'] ?? sub['url'])?.toString();
        if (fileUrl != null && fileUrl.startsWith('http')) {
          final label = (sub['label'] ?? sub['language'] ?? 'Default Subtitle').toString();
          subtitles.add(StreamSubtitleTrack(
            url: fileUrl,
            lang: label,
          ));
        }
      }

      final availableAudios = <String>[];
      for (final t in tracks) {
        final tName = (t['track'] as String? ?? '').toLowerCase();
        final provs = (t['providers'] as List?) ?? [];
        if (provs.isNotEmpty) {
          if (tName == 'dub' && !availableAudios.contains('English (Dub)')) {
            availableAudios.add('English (Dub)');
          } else if ((tName == 'sub' || tName == 'ssub') && !availableAudios.contains('Japanese (Sub)')) {
            availableAudios.add('Japanese (Sub)');
          }
        }
      }

      final bestServerHeaders = (bestServer?['headers'] as Map<String, dynamic>?) ?? {};
      final String finalReferer = bestServerHeaders['Referer']?.toString() ?? '$_baseUrl/';
      final String finalOrigin = bestServerHeaders['Origin']?.toString() ?? _baseUrl;
      final String mainStreamUrl = bestStream['url'] as String;
      final bool isHls = mainStreamUrl.contains('.m3u8') || bestStream['format'] == 'hls';

      final proxiedMainUrl = HlsProxyService.instance.getProxyUrl(
        mainStreamUrl,
        _userAgent,
        {},
        referer: finalReferer,
        origin: finalOrigin,
        extension: isHls ? '.m3u8' : (mainStreamUrl.contains('.mp4') ? '.mp4' : ''),
      );

      final Map<String, String> finalHeaders = {
        'Referer': finalReferer,
        'Origin': finalOrigin,
        'User-Agent': _userAgent,
      };

      return StreamResult(
        url: proxiedMainUrl,
        quality: sources.first.quality,
        provider: 'Miruro ($pName)',
        headers: finalHeaders,
        subtitles: subtitles,
        isM3U8: isHls,
        sources: sources,
        availableAudios: availableAudios,
        selectedAudio: preferredAudio,
        // Seek-bar previews: anikoto, kickassanime and icarus provide a
        // `thumbnails.vtt`; its CDN checks the same Referer as the stream.
        thumbnailsVtt: _thumbnailsVtt(selectedProv['thumbnails']),
        thumbnailsHeaders: finalHeaders,
      );
    } catch (e) {
      appDebugLog('Error in MiruroScraperService: $e');
      return null;
    }
  }
}
