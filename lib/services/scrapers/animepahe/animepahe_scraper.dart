import 'dart:convert';
import 'package:http/http.dart' as http;
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
  Future<StreamResult?> fetchStreamUrl(String title, int season, int episode, {String subDub = 'sub', void Function(String)? onStatusUpdate}) async {
    try {
      // 1. Wait for Cloudflare bypass to complete if it hasn't
      onStatusUpdate?.call('Warming up Animepahe bypass...');
      await _bypassService.waitForBypass();
      
      String? animeSession;
      int? absoluteEpisodeNumber;

      // --- 1. SEARCH PHASE (Prioritized for Exact Matches) ---
      onStatusUpdate?.call('Searching Animepahe for exact title match...');
      appDebugLog('🎌 Animepahe: Searching for "$title"');
      final searchUrl = 'https://animepahe.pw/api?m=search&q=${Uri.encodeComponent(title)}';
      final searchBody = await _bypassService.fetchViaWebView(searchUrl);
      
      if (searchBody != null) {
        try {
          final searchJson = jsonDecode(searchBody);
          final data = searchJson['data'] as List?;
          if (data != null && data.isNotEmpty) {
            Map<String, dynamic>? bestMatch;
            final expectedTitle = season > 1 ? '$title Season $season' : title;
            
            // 1st Pass: Exact title match AND type == TV
            for (var item in data) {
              final itemTitle = (item['title'] as String).toLowerCase();
              final itemType = (item['type'] as String?)?.toUpperCase() ?? '';
              if ((itemTitle == title.toLowerCase() || itemTitle == expectedTitle.toLowerCase()) && itemType == 'TV') {
                bestMatch = item as Map<String, dynamic>;
                break;
              }
            }
            
            // 2nd Pass: Just exact title match (if TV wasn't found)
            if (bestMatch == null) {
              for (var item in data) {
                final itemTitle = (item['title'] as String).toLowerCase();
                if (itemTitle == title.toLowerCase() || itemTitle == expectedTitle.toLowerCase()) {
                  bestMatch = item as Map<String, dynamic>;
                  break;
                }
              }
            }
            
            if (bestMatch != null) {
              animeSession = bestMatch['session'] as String;
              appDebugLog('🎌 Animepahe: Found exact title match in Search Phase: $animeSession');
            }
          }
        } catch (e) {
          appDebugLog('🎌 Animepahe: Search Phase failed: $e');
        }
      }

      // --- 2. MAPPING PHASE (Fallback if Search yields no exact match) ---
      if (animeSession == null) {
        try {
          final queryTitle = season > 1 ? '$title Season $season' : title;
          onStatusUpdate?.call('Mapping: Querying AniList for "$queryTitle"...');
          
          final aniListReq = await http.post(
            Uri.parse('https://graphql.anilist.co'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'query': 'query { Media(search: "$queryTitle", type: ANIME) { id idMal title { romaji english } } }'
            }),
          ).timeout(const Duration(seconds: 5));

          if (aniListReq.statusCode == 200) {
            final aniData = jsonDecode(aniListReq.body);
            final media = aniData['data']?['Media'];
            if (media != null) {
              final int? idMal = media['idMal'];
              final int? idAni = media['id'];
              
              if (idMal != null) {
                onStatusUpdate?.call('Mapping: Resolving Session via MAL-Sync...');
                final malReq = await http.get(
                  Uri.parse('https://api.malsync.moe/mal/anime/$idMal')
                ).timeout(const Duration(seconds: 5));

                if (malReq.statusCode == 200) {
                  final malData = jsonDecode(malReq.body);
                  final paheData = malData['Sites']?['animepahe'];
                  if (paheData != null && paheData.isNotEmpty) {
                    animeSession = paheData.values.first['identifier'] as String?;
                    
                    if (animeSession != null && int.tryParse(animeSession) != null) {
                      onStatusUpdate?.call('Mapping: Resolving legacy Animepahe ID...');
                      final finalUrl = await _bypassService.getFinalUrlViaWebView('https://animepahe.pw/a/$animeSession');
                      if (finalUrl != null && finalUrl.contains('/anime/')) {
                        animeSession = finalUrl.split('/anime/').last;
                        appDebugLog('🎌 Animepahe: Resolved legacy ID to UUID session: $animeSession');
                      } else {
                        animeSession = null;
                      }
                    } else {
                      appDebugLog('🎌 Animepahe: Successfully mapped to session $animeSession via MAL-Sync.');
                    }
                  }
                }
              }

              if (animeSession != null && idAni != null) {
                onStatusUpdate?.call('Mapping: Resolving Episode via AniZip...');
                final zipReq = await http.get(
                  Uri.parse('https://api.ani.zip/mappings?anilist_id=$idAni')
                ).timeout(const Duration(seconds: 5));

                if (zipReq.statusCode == 200) {
                  final zipData = jsonDecode(zipReq.body);
                  final epData = zipData['episodes']?['$episode'];
                  if (epData != null) {
                    absoluteEpisodeNumber = epData['absoluteEpisodeNumber'] as int?;
                    appDebugLog('🎌 Animepahe: Resolved absolute episode number $absoluteEpisodeNumber via AniZip.');
                  }
                }
              }
            }
          }
        } catch (e) {
          appDebugLog('🎌 Animepahe: Mapping failed. Error: $e');
        }
      }
      
      // --- 3. FINAL SEARCH FALLBACK (If everything else failed, just take the first search result) ---
      if (animeSession == null && searchBody != null) {
        try {
          final searchJson = jsonDecode(searchBody);
          final data = searchJson['data'] as List?;
          if (data != null && data.isNotEmpty) {
            animeSession = data[0]['session'] as String;
            appDebugLog('🎌 Animepahe: Fallback to first search result: $animeSession');
          }
        } catch (_) {}
      }
      
      // --- 3. FETCH EPISODES PHASE ---
      onStatusUpdate?.call('Fetching episodes list from Animepahe...');
      appDebugLog('🎌 Animepahe: Fetching episode list for session $animeSession');
      String? episodeSession;
      
      Future<String?> findEpisodeInSession(String session) async {
        int page = 1;
        while (page <= 10) {
          final releaseUrl = 'https://animepahe.pw/api?m=release&id=$session&sort=episode_asc&page=$page';
          final releaseBody = await _bypassService.fetchViaWebView(releaseUrl);
          if (releaseBody == null) return null;
          
          try {
            final releaseJson = jsonDecode(releaseBody);
            final releaseData = releaseJson['data'] as List?;
            if (releaseData == null || releaseData.isEmpty) return null;
            
            for (var ep in releaseData) {
              final epNum = ep['episode'];
              if (epNum == episode || epNum == absoluteEpisodeNumber || epNum == '$episode' || epNum == '$absoluteEpisodeNumber') {
                return ep['session'] as String;
              }
            }
            if (releaseJson['last_page'] == page) return null;
          } catch(e) {
            return null;
          }
          page++;
        }
        return null;
      }

      if (animeSession != null) {
         episodeSession = await findEpisodeInSession(animeSession);
      }
      
      // AGGRESSIVE FALLBACK: IF EPISODE NOT IN PRIMARY SESSION
      if (episodeSession == null) {
        onStatusUpdate?.call('Episode not found in primary session. Hunting across all seasons...');
        
        // Clean the title for Animepahe's search engine (remove -, :, ~)
        final cleanTitle = title.replaceAll(RegExp(r'[^a-zA-Z0-9\s]'), ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
        appDebugLog('🎌 Animepahe: Episode not found in $animeSession. Hunting across all related seasons using cleaned title: "$cleanTitle"');
        
        final searchUrl = 'https://animepahe.pw/api?m=search&q=${Uri.encodeComponent(cleanTitle)}';
        final searchBody = await _bypassService.fetchViaWebView(searchUrl);
        
        if (searchBody != null) {
          try {
            final searchJson = jsonDecode(searchBody);
            final data = searchJson['data'] as List?;
            if (data != null && data.isNotEmpty) {
              
              // Filter candidates by title relevance to avoid generic word matches (e.g. "World", "Life")
              final firstWord = title.split(' ').firstWhere((w) => w.length > 2, orElse: () => title).toLowerCase();
              final relevantCandidates = data.where((item) {
                final itemTitle = (item['title'] as String).toLowerCase();
                return itemTitle.contains(firstWord);
              }).toList();
              
              // Check up to top 15 related sessions
              for (int i = 0; i < relevantCandidates.length && i < 15; i++) {
                final candidateSession = relevantCandidates[i]['session'] as String;
                if (candidateSession == animeSession) continue; // Already checked
                
                onStatusUpdate?.call('Hunting in related season ${i+1}...');
                appDebugLog('🎌 Animepahe: Checking candidate session $candidateSession (${relevantCandidates[i]['title']})');
                final foundEpSession = await findEpisodeInSession(candidateSession);
                if (foundEpSession != null) {
                  animeSession = candidateSession; // Update the session for the play URL
                  episodeSession = foundEpSession;
                  appDebugLog('🎌 Animepahe: FOUND episode in candidate session $candidateSession');
                  break;
                }
              }
            }
          } catch(e) {
            appDebugLog('🎌 Animepahe: Aggressive hunt search parse failed: $e');
          }
        }
      }
      
      if (episodeSession == null) {
        appDebugLog('🎌 Animepahe: Could not find episode $episode (or abs: $absoluteEpisodeNumber) anywhere.');
        return null;
      }
      
      // --- 4. EXTRACT KWIK LINKS ---
      onStatusUpdate?.call('Extracting stream links from Animepahe...');
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
        provider: 'Kwik',
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
