import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:cronet_http/cronet_http.dart';
import 'package:nivio/core/debug_log.dart';
import 'package:nivio/models/stream_result.dart';

import 'package:nivio/services/hls_proxy_service.dart';

class MiruroScraperService {
  late final http.Client client;
  final List<int> _obfKey = utf8.encode('71951034f8fbcf53d89db52ceb3dc22c');

  MiruroScraperService() {
    if (Platform.isAndroid) {
      final engine = CronetEngine.build(
        cacheMode: CacheMode.disabled,
        userAgent: 'Mozilla/5.0 (Linux; Android 13; Pixel 7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/114.0.0.0 Mobile Safari/537.36',
      );
      client = CronetClient.fromCronetEngine(engine);
    } else {
      client = http.Client();
    }
  }

  String _encodePipeRequest(Map<String, dynamic> payload) {
    final jsonString = jsonEncode(payload);
    return base64UrlEncode(utf8.encode(jsonString)).replaceAll('=', '');
  }

  dynamic _decodePipeResponse(String encodedStr, String? obfHeader) {
    final padded = encodedStr.padRight((encodedStr.length + 3) ~/ 4 * 4, '=');
    var rawBytes = base64Url.decode(padded);

    if (obfHeader == '2') {
      final xored = Uint8List(rawBytes.length);
      for (int i = 0; i < rawBytes.length; i++) {
        xored[i] = rawBytes[i] ^ _obfKey[i % _obfKey.length];
      }
      rawBytes = xored;
    }

    final decompressed = gzip.decode(rawBytes);
    final jsonStr = utf8.decode(decompressed);
    return jsonDecode(jsonStr);
  }

  Future<dynamic> _pipeRequest(String path, Map<String, dynamic> query) async {
    final payload = {
      'path': path,
      'method': 'GET',
      'query': query,
      'body': null,
    };

    final encodedReq = _encodePipeRequest(payload);
    final uri = Uri.parse('https://www.miruro.bz/api/secure/pipe?e=$encodedReq');

    final res = await client.get(uri, headers: {
      "User-Agent": "Mozilla/5.0 (Linux; Android 13; Pixel 7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/114.0.0.0 Mobile Safari/537.36",
      "Referer": "https://www.miruro.bz/",
      "Origin": "https://www.miruro.bz",
      "Accept": "application/json, text/plain, */*",
      "Accept-Language": "en-US,en;q=0.9",
      "sec-fetch-site": "same-origin",
      "sec-fetch-mode": "cors",
      "sec-fetch-dest": "empty",
      "sec-ch-ua": "\"Not.A/Brand\";v=\"8\", \"Chromium\";v=\"114\", \"Google Chrome\";v=\"114\"",
      "sec-ch-ua-mobile": "?1",
      "sec-ch-ua-platform": "\"Android\"",
    });

    if (res.statusCode != 200) {
      throw Exception('Pipe request failed with status: ${res.statusCode}');
    }

    return _decodePipeResponse(res.body, res.headers['x-obfuscated']);
  }

  Future<List<String>> fetchAvailableServers({required String tmdbId}) async {
    try {
      final anilistId = int.tryParse(tmdbId);
      if (anilistId == null) return [];

      final episodesData = await _pipeRequest('episodes', {'anilistId': anilistId, 'version': '0.1.0'});
      final providers = episodesData['providers'] as Map<String, dynamic>?;
      if (providers == null) return [];

      return providers.keys.toList();
    } catch (e) {
      appDebugLog('Error in Miruro fetchAvailableServers: $e');
      return [];
    }
  }

  Future<StreamResult?> fetchStreamUrl({
    required String tmdbId, // Actually Anilist ID is passed as tmdbId in anime
    required int season,
    required int episode,
    required String preferredAudio, // 'english' or 'japanese'
    required String providerName, // e.g., 'zoro' or 'gogo'
  }) async {
    try {
      final anilistId = int.tryParse(tmdbId);
      if (anilistId == null) return null;

      // 1. Fetch episodes
      final episodesData = await _pipeRequest('episodes', {'anilistId': anilistId, 'version': '0.1.0'});
      final providers = episodesData['providers'] as Map<String, dynamic>?;
      if (providers == null) return null;

      final provData = providers[providerName] as Map<String, dynamic>?;
      if (provData == null) return null;

      String category = 'sub';
      final prefLower = preferredAudio.toLowerCase();
      if (prefLower == 'english' || prefLower == 'dub' || prefLower.contains('english (dub)')) {
          category = 'dub';
      } else if (prefLower == 'japanese' || prefLower == 'sub' || prefLower.contains('japanese (sub)')) {
          category = 'sub';
      } else {
          category = prefLower;
      }

      final episodes = provData['episodes']?[category] as List<dynamic>?;
      if (episodes == null || episodes.isEmpty) return null;

      final availableAudios = <String>[];
      final epsMap = provData['episodes'] as Map<String, dynamic>?;
      if (epsMap != null) {
        for (final key in epsMap.keys) {
          if ((epsMap[key] as List<dynamic>?)?.isNotEmpty == true) {
             if (key.toLowerCase() == 'sub') availableAudios.add('Japanese (Sub)');
             else if (key.toLowerCase() == 'dub') availableAudios.add('English (Dub)');
             else availableAudios.add(key.toUpperCase());
          }
        }
      }

      // Find episode by number
      dynamic targetEp;
      for (final ep in episodes) {
        if (ep['number'] == episode) {
          targetEp = ep;
          break;
        }
      }

      if (targetEp == null) return null;

      // Get the rawPipeId or id
      String rawId = targetEp['id'] ?? '';
      
      // Let's decode if necessary
      String targetId = rawId;
      try {
        final padded = rawId.padRight((rawId.length + 3) ~/ 4 * 4, '=');
        final decoded = utf8.decode(base64Url.decode(padded));
        if (decoded.contains(':')) targetId = decoded;
      } catch (_) {}

      // 2. Fetch sources
      final encId = base64UrlEncode(utf8.encode(targetId)).replaceAll('=', '');
      final sourcesData = await _pipeRequest('sources', {
        'episodeId': encId,
        'provider': providerName,
        'category': category,
        'anilistId': anilistId,
        'version': '0.1.0',
      });

      final streams = sourcesData['streams'] as List<dynamic>?;
      if (streams == null || streams.isEmpty) return null;

      final String userAgent = 'Mozilla/5.0 (Linux; Android 13; Pixel 7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/114.0.0.0 Mobile Safari/537.36';

      final List<StreamSource> sources = [];
      dynamic bestStream;

      for (final s in streams) {
        final url = s['url'] as String?;
        if (url != null) {
          final isHlsStream = url.contains('.m3u8') || s['type'] == 'hls';
          if (isHlsStream && bestStream == null) bestStream = s;
          
          String streamReferer = s['referer'] as String? ?? 'https://www.miruro.bz/';
          String streamOrigin = streamReferer.endsWith('/') ? streamReferer.substring(0, streamReferer.length - 1) : streamReferer;
          String streamExtension = isHlsStream ? '.m3u8' : (url.contains('.mp4') ? '.mp4' : '');
          
          final proxiedUrl = HlsProxyService.instance.getProxyUrl(
            url,
            userAgent,
            {},
            referer: streamReferer,
            origin: streamOrigin,
            extension: streamExtension,
          );

          String qualityLabel = s['quality']?.toString() ?? 'Auto';
          if (s['fansub'] != null) qualityLabel += ' (${s['fansub']})';
          else if (s['server'] != null) qualityLabel += ' (${s['server']})';

          sources.add(StreamSource(
            url: proxiedUrl,
            quality: qualityLabel,
            isDub: category == 'dub',
          ));
        }
      }
      
      bestStream ??= streams.firstWhere((s) => s['url'] != null, orElse: () => null);
      if (bestStream == null || sources.isEmpty) return null;

      // Subtitles
      final subtitles = <SubtitleTrack>[];
      final rawSubs = sourcesData['subtitles'] as List<dynamic>?;
      if (rawSubs != null) {
        for (final sub in rawSubs) {
          final url = sub['url'] ?? sub['file'];
          if (url != null && url.startsWith('http')) {
            subtitles.add(SubtitleTrack(
              url: url,
              lang: sub['language'] ?? sub['label'] ?? 'Unknown',
            ));
          }
        }
      }

      // Best stream proxy info for main stream
      String referer = bestStream['referer'] as String? ?? 'https://www.miruro.bz/';
      String origin = referer.endsWith('/') ? referer.substring(0, referer.length - 1) : referer;
      final String streamUrl = bestStream['url'];
      final bool isHls = streamUrl.contains('.m3u8') || bestStream['type'] == 'hls';
      final String streamExtension = isHls ? '.m3u8' : (streamUrl.contains('.mp4') ? '.mp4' : '');

      final proxiedUrl = HlsProxyService.instance.getProxyUrl(
        streamUrl,
        userAgent,
        {}, // No cookies needed yet
        referer: referer.toString(),
        origin: origin.toString(),
        extension: streamExtension,
      );

      final Map<String, String> finalHeaders = {
        'Referer': referer.toString(),
        'Origin': origin.toString(),
        'User-Agent': userAgent,
      };
      
      return StreamResult(
        url: proxiedUrl,
        quality: sources.first.quality,
        provider: 'Miruro ($providerName)',
        headers: finalHeaders,
        subtitles: subtitles,
        isM3U8: isHls,
        sources: sources,
        availableAudios: availableAudios,
        selectedAudio: preferredAudio,
      );

    } catch (e) {
      appDebugLog('Error in MiruroScraperService: $e');
      return null;
    }
  }
}
