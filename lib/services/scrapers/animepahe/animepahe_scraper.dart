import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nivio/core/debug_log.dart';
import 'package:nivio/models/stream_result.dart';
import 'package:nivio/services/scrapers/animepahe/cloudflare_bypass_service.dart';
final animepaheScraperProvider = Provider<AnimepaheScraperService>((ref) {
  return AnimepaheScraperService(ref.read(cloudflareBypassProvider));
});

class AnimepaheScraperService {
  final CloudflareBypassService _bypassService;
  
  AnimepaheScraperService(this._bypassService);



  /// Scrapes the direct native .m3u8 or Kwik link from Animepahe
  Future<StreamResult?> fetchStreamUrl(String title, int season, int episode, {String subDub = 'sub'}) async {
    try {
      // 1. Wait for Cloudflare bypass to complete if it hasn't
      await _bypassService.waitForBypass();
      
      // 2. Search for the anime
      appDebugLog('🎌 Animepahe: Searching for "$title"');
      final searchUrl = 'https://animepahe.pw/api?m=search&q=${Uri.encodeComponent(title)}';
      final searchBody = await _bypassService.fetchViaWebView(searchUrl);
      
      if (searchBody == null) {
        appDebugLog('🎌 Animepahe: Search failed to return data');
        return null;
      }
      
      final searchJson = jsonDecode(searchBody);
      final data = searchJson['data'] as List?;
      if (data == null || data.isEmpty) {
        appDebugLog('🎌 Animepahe: No search results found');
        return null;
      }
      
      // Get the first result's session ID
      final animeSession = data[0]['session'] as String;
      
      // 3. Find the requested episode
      appDebugLog('🎌 Animepahe: Fetching episode list for session $animeSession');
      String? episodeSession;
      int page = 1;
      
      while (episodeSession == null && page <= 10) {
        final releaseUrl = 'https://animepahe.pw/api?m=release&id=$animeSession&sort=episode_asc&page=$page';
        final releaseBody = await _bypassService.fetchViaWebView(releaseUrl);
        if (releaseBody == null) break;
        
        final releaseJson = jsonDecode(releaseBody);
        final releaseData = releaseJson['data'] as List?;
        if (releaseData == null || releaseData.isEmpty) break;
        
        for (var ep in releaseData) {
          if (ep['episode'] == episode) {
            episodeSession = ep['session'];
            break;
          }
        }
        
        if (releaseJson['last_page'] == page) break;
        page++;
      }
      
      if (episodeSession == null) {
        appDebugLog('🎌 Animepahe: Could not find episode $episode');
        return null;
      }
      
      // 4. Get Kwik embed links
      appDebugLog('🎌 Animepahe: Fetching links for episode session $episodeSession');
      
      final playUrl = 'https://animepahe.pw/play/$animeSession/$episodeSession';
      final playHtml = await _bypassService.fetchViaWebView(playUrl);
      
      String? kwikUrl;
      List<StreamSource> sources = [];
      List<String> qualities = [];
      List<String> audios = [];
      
      if (playHtml != null && playHtml.contains('kwik')) {
        appDebugLog('🎌 Animepahe: Extracting links from Play HTML...');
        // Match things like: data-src="https://kwik.cx/e/..." data-audio="jpn" data-resolution="720"
        final tagRegex = RegExp(r'<[^>]+data-src="(https://kwik\.cx/e/[^"]+)"[^>]*>');
        final matches = tagRegex.allMatches(playHtml);
        
        List<Map<String, String>> extractedLinks = [];
        for (var match in matches) {
          final tagHtml = match.group(0)!;
          final src = match.group(1)!;
          
          final audioMatch = RegExp(r'data-audio="([^"]+)"').firstMatch(tagHtml);
          final resMatch = RegExp(r'data-resolution="([^"]+)"').firstMatch(tagHtml);
          
          final audio = audioMatch?.group(1) ?? 'jpn';
          final resolution = resMatch?.group(1) ?? '720';
          
          extractedLinks.add({
            'src': src,
            'audio': audio,
            'resolution': resolution,
          });
          
          final isDub = audio != 'jpn';
          sources.add(StreamSource(
            url: src,
            quality: '${resolution}p',
            isM3U8: false,
            isDub: isDub,
          ));
          
          final q = '${resolution}p';
          if (!qualities.contains(q)) qualities.add(q);
          
          final a = isDub ? 'dub' : 'sub';
          if (!audios.contains(a)) audios.add(a);
        }
        
        if (extractedLinks.isNotEmpty) {
          // Sort by resolution descending (e.g. 1080 -> 720)
          extractedLinks.sort((a, b) => (int.tryParse(b['resolution']!) ?? 0).compareTo((int.tryParse(a['resolution']!) ?? 0)));
          
          // Try to find matching sub/dub
          for (var link in extractedLinks) {
            bool isSub = link['audio'] == 'jpn';
            if ((subDub == 'sub' && isSub) || (subDub == 'dub' && !isSub)) {
              kwikUrl = link['src'];
              break;
            }
          }
          
          // Fallback to highest res if sub/dub match not found
          kwikUrl ??= extractedLinks.first['src'];
          appDebugLog('🎌 Animepahe: Successfully extracted ${extractedLinks.length} Kwik URLs');
        }
      }

      if (kwikUrl == null) {
        appDebugLog('🎌 Animepahe: Failed to find Kwik links in HTML.');
        return null;
      }
      
      appDebugLog('🎌 Animepahe: Returning StreamResult with ${sources.length} sources. Default: $kwikUrl');
      
      return StreamResult(
        url: kwikUrl,
        quality: 'auto',
        provider: 'Animepahe (NATIVE)',
        subtitles: [],
        availableQualities: qualities,
        availableAudios: audios,
        selectedAudio: subDub,
        isM3U8: false,
        headers: {
          'Referer': 'https://kwik.cx/',
          'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
        },
        sources: sources,
      );
      
    } catch (e) {
      appDebugLog('🎌 Animepahe Error: $e');
      return null;
    }
  }
}
