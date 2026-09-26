import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:nivio/core/debug_log.dart';
import 'package:nivio/models/stream_result.dart';
import 'package:nivio/services/skip_times_models.dart';

class AnimexScraperService {
  final http.Client client = http.Client();
  final String _baseUrl = 'https://animex.one';
  final String _apiUrl = 'https://pp.animex.one/rest/api';

  Future<String?> _getSlug(String anilistId) async {
    try {
      final res = await client.get(Uri.parse('$_baseUrl/anime/$anilistId'), headers: {
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/137.0.0.0 Safari/537.36',
        'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,image/apng,*/*;q=0.8',
        'Accept-Language': 'en-US,en;q=0.9',
      });

      if (res.statusCode != 200) return null;

      final match = RegExp(r'slug:"([^"]+)"').firstMatch(res.body);
      if (match != null) {
        return match.group(1);
      }
      return null;
    } catch (e) {
      appDebugLog('Animex _getSlug error: $e');
      return null;
    }
  }
  Future<List<String>> fetchAvailableServers({
    required String tmdbId, 
    required int episode, 
    required String preferredAudio,
  }) async {
    try {
      final anilistId = int.tryParse(tmdbId);
      if (anilistId == null) return [];

      final slug = await _getSlug(anilistId.toString());
      if (slug == null) return [];

      final type = preferredAudio.toLowerCase().contains('english') || preferredAudio.toLowerCase() == 'dub' ? 'dub' : 'sub';

      final serversRes = await client.get(Uri.parse('$_apiUrl/servers?id=$slug&epNum=$episode'), headers: {
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/137.0.0.0 Safari/537.36',
        'Origin': _baseUrl,
        'Referer': '$_baseUrl/',
        'Accept': '*/*',
      });

      if (serversRes.statusCode != 200) return [];

      final serversData = jsonDecode(serversRes.body);
      final providersList = (type == 'dub' ? serversData['dubProviders'] : serversData['subProviders']) as List<dynamic>?;

      if (providersList == null || providersList.isEmpty) return [];

      return providersList.map((p) {
        String name = p['serverName']?.toString() ?? p['id'].toString();
        
        final tip = p['tip']?.toString().toLowerCase() ?? '';
        if (tip.contains('soft sub')) {
          name += ' (Soft Sub)';
        } else if (tip.contains('hard sub')) {
          name += ' (Hard Sub)';
        }
        
        return name;
      }).toList();
    } catch (e) {
      appDebugLog('Animex fetchAvailableServers error: $e');
      return [];
    }
  }

  final Map<String, Future<String?>> _slugCache = {};
  final Map<String, Future<http.Response>> _serversCache = {};

  Future<StreamResult?> fetchStreamUrl({
    required String tmdbId, // Actually Anilist ID is passed as tmdbId in anime
    required int season,
    required int episode,
    required String preferredAudio, // 'english' or 'japanese'
    required String providerName, // Currently 'Auto'
  }) async {
    try {
      final anilistId = int.tryParse(tmdbId);
      if (anilistId == null) return null;

      // 1. Get the slug (deduplicated)
      final slugKey = '$anilistId';
      if (!_slugCache.containsKey(slugKey)) {
        _slugCache[slugKey] = _getSlug(anilistId.toString());
        Future.delayed(const Duration(minutes: 5), () { _slugCache.remove(slugKey); });
      }
      final slug = await _slugCache[slugKey];
      
      if (slug == null) {
        appDebugLog('Animex: Could not find slug for Anilist ID $anilistId');
        return null;
      }

      final type = preferredAudio.toLowerCase().contains('english') || preferredAudio.toLowerCase() == 'dub' ? 'dub' : 'sub';

      // 2. Get the servers (deduplicated)
      final serversKey = '$slug:$episode';
      if (!_serversCache.containsKey(serversKey)) {
        _serversCache[serversKey] = client.get(Uri.parse('$_apiUrl/servers?id=$slug&epNum=$episode'), headers: {
          'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/137.0.0.0 Safari/537.36',
          'Origin': _baseUrl,
          'Referer': '$_baseUrl/',
          'Accept': '*/*',
        });
        Future.delayed(const Duration(seconds: 15), () { _serversCache.remove(serversKey); });
      }
      
      final serversRes = await _serversCache[serversKey];

      if (serversRes == null || serversRes.statusCode != 200) {
        appDebugLog('Animex: /servers returned ${serversRes?.statusCode} for $slug ep $episode (server "$providerName")');
        return null;
      }

      final serversData = jsonDecode(serversRes.body);
      final providersList = (type == 'dub' ? serversData['dubProviders'] : serversData['subProviders']) as List<dynamic>?;

      final List<String> availableAudios = [];
      if ((serversData['subProviders'] as List<dynamic>?)?.isNotEmpty == true) {
        availableAudios.add('Japanese (Sub)');
      }
      if ((serversData['dubProviders'] as List<dynamic>?)?.isNotEmpty == true) {
        availableAudios.add('English (Dub)');
      }

      if (providersList == null || providersList.isEmpty) {
        appDebugLog('Animex: No $type servers found for $slug ep $episode');
        return null;
      }

      // Try to use requested provider, fallback to default or first
      String? targetProviderId;
      if (providerName != 'Auto') {
        final cleanProviderName = providerName.replaceAll(' (Soft Sub)', '').replaceAll(' (Hard Sub)', '').toLowerCase();
        for (final p in providersList) {
          if (p['id'].toString().toLowerCase() == cleanProviderName || 
              p['serverName']?.toString().toLowerCase() == cleanProviderName) {
            targetProviderId = p['id'];
            break;
          }
        }
      }
      
      if (targetProviderId == null) {
        for (final p in providersList) {
          if (p['default'] == true) {
            targetProviderId = p['id'];
            break;
          }
        }
      }
      targetProviderId ??= providersList[0]['id'];
      
      appDebugLog('Animex: Requested server "$providerName", resolved targetProviderId: "$targetProviderId"');

      // 3. Get the sources
      final sourcesRes = await client.get(
        Uri.parse('$_apiUrl/sources?id=$slug&epNum=$episode&type=$type&providerId=$targetProviderId'),
        headers: {
          'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/137.0.0.0 Safari/537.36',
          'Origin': _baseUrl,
          'Referer': '$_baseUrl/',
          'Accept': '*/*',
        }
      );

      if (sourcesRes.statusCode != 200) {
        appDebugLog('Animex: /sources returned status ${sourcesRes.statusCode} for $targetProviderId');
        return null;
      }

      final sourcesData = jsonDecode(sourcesRes.body);
      final sourcesList = sourcesData['sources'] as List<dynamic>?;
      if (sourcesList == null || sourcesList.isEmpty) {
        appDebugLog('Animex: /sources returned empty list for $targetProviderId. Body: ${sourcesRes.body}');
        return null;
      }

      // Prefer m3u8 if available, but keep DASH since player now supports it
      final List<StreamSource> mappedSources = [];
      dynamic bestStream;
      for (final s in sourcesList) {
        final url = s['url']?.toString() ?? '';
        if (url.isNotEmpty) {
          mappedSources.add(StreamSource(
            url: url,
            quality: s['quality']?.toString() ?? 'Auto',
            isDub: type == 'dub',
          ));
          if (bestStream == null && (url.contains('.m3u8') || s['type'] == 'video/mpegurl')) {
            bestStream = s;
          }
        }
      }
      bestStream ??= sourcesList.firstWhere((s) {
        return s['url'] != null;
      }, orElse: () => null);
      
      if (bestStream == null) {
        appDebugLog('Animex: No playable streams found for provider $targetProviderId');
        return null;
      }

      final List<StreamSubtitleTrack> subtitles = [];
      final tracks = sourcesData['tracks'] as List<dynamic>?;
      if (tracks != null) {
        for (final t in tracks) {
          final url = t['url']?.toString() ?? '';
          final kind = t['kind']?.toString().toLowerCase() ?? '';
          if (url.isNotEmpty && url.startsWith('http')) {
            if (kind == 'thumbnails' || url.contains('.m3u8') || url.contains('.m3u') || url.contains('.ass') || url.contains('.ssa')) {
              continue; // Skip unsupported subtitle formats and playlists
            }
            final rawLang = (t['lang'] ?? t['language'] ?? t['label'] ?? t['name'] ?? '').toString().trim();
            final lang = (rawLang.isEmpty || rawLang.toLowerCase() == 'auto' || rawLang.toLowerCase() == 'und' || rawLang.toLowerCase() == 'unknown')
                ? 'Default Subtitle'
                : rawLang;
            subtitles.add(StreamSubtitleTrack(
              url: url,
              lang: lang,
            ));
          }
        }
      }

      final Map<String, String> headers = {};
      final h = sourcesData['headers'] as Map<String, dynamic>?;
      if (h != null) {
        h.forEach((key, value) {
          headers[key] = value.toString();
        });
      }

      // Fill basic skip times if chapters available or intro/outro available
      final List<SkipTime> skipTimes = [];
      final intro = sourcesData['intro'];
      final outro = sourcesData['outro'];
      if (intro != null && intro['start'] != null && intro['end'] != null) {
        skipTimes.add(SkipTime(
          startTime: Duration(milliseconds: (intro['start'] as num).toInt() * 1000),
          endTime: Duration(milliseconds: (intro['end'] as num).toInt() * 1000),
          type: 'intro'
        ));
      }
      if (outro != null && outro['start'] != null && outro['end'] != null) {
        skipTimes.add(SkipTime(
          startTime: Duration(milliseconds: (outro['start'] as num).toInt() * 1000),
          endTime: Duration(milliseconds: (outro['end'] as num).toInt() * 1000),
          type: 'outro'
        ));
      }

      return StreamResult(
        url: bestStream['url'],
        quality: bestStream['quality'] ?? 'Auto',
        provider: 'Animex ($targetProviderId)',
        headers: headers,
        subtitles: subtitles,
        skipTimes: skipTimes,
        availableAudios: availableAudios,
        selectedAudio: type == 'dub' ? 'English (Dub)' : 'Japanese (Sub)',
        sources: mappedSources,
      );
    } catch (e) {
      appDebugLog('Animex fetchStreamUrl error: $e');
      return null;
    }
  }
}
