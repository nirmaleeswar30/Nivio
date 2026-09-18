import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:nivio/core/debug_log.dart';
import 'package:nivio/services/cache_service.dart';

/// Represents filler classifications for an anime
class AnimeFillerData {
  /// Set of episode numbers that are pure filler (no manga-canon content)
  final Set<int> fillerEpisodes;

  /// Set of episode numbers that are mixed canon and filler
  final Set<int> mixedEpisodes;

  const AnimeFillerData({
    this.fillerEpisodes = const {},
    this.mixedEpisodes = const {},
  });

  bool isFiller(int episode) => fillerEpisodes.contains(episode);
  bool isMixed(int episode) => mixedEpisodes.contains(episode);
  bool isAnyFiller(int episode) => isFiller(episode) || isMixed(episode);

  Map<String, dynamic> toJson() => {
        'filler': fillerEpisodes.toList(),
        'mixed': mixedEpisodes.toList(),
      };

  factory AnimeFillerData.fromJson(Map<String, dynamic> json) {
    return AnimeFillerData(
      fillerEpisodes: (json['filler'] as List<dynamic>?)
              ?.map((e) => (e as num).toInt())
              .toSet() ??
          {},
      mixedEpisodes: (json['mixed'] as List<dynamic>?)
              ?.map((e) => (e as num).toInt())
              .toSet() ??
          {},
    );
  }
}

/// Service that fetches and caches anime filler episode lists from AnimeFillerList,
/// mapping AniList entries to AFL slugs via title matching and AniZip episode offsets,
/// with Jikan (MyAnimeList) as fallback.
class AnimeFillerService {
  final CacheService _cache;
  final http.Client _client;

  final Map<int, AnimeFillerData> _memoryCache = {};
  Map<String, String>? _aflDirectory;

  static const String _aflBaseUrl = 'https://www.animefillerlist.com';
  static const Map<String, String> _headers = {
    'User-Agent':
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
    'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
  };

  AnimeFillerService(this._cache, {http.Client? client})
      : _client = client ?? http.Client();

  /// Normalizes titles for fuzzy matching
  String _normalize(String s) {
    return s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '').trim();
  }

  /// Fetches and caches the index of all shows on AnimeFillerList
  Future<Map<String, String>> _getAflDirectory() async {
    if (_aflDirectory != null) return _aflDirectory!;

    final cached = await _cache.get<Map<String, dynamic>>(
      'afl_directory_v1',
      (json) => json,
    );
    if (cached != null) {
      _aflDirectory = cached.map((k, v) => MapEntry(k, v.toString()));
      return _aflDirectory!;
    }

    try {
      appDebugLog('🌀 [AFL] Fetching AnimeFillerList shows directory...');
      final uri = Uri.parse('$_aflBaseUrl/shows');
      final res = await _client.get(uri, headers: _headers).timeout(
            const Duration(seconds: 10),
          );

      if (res.statusCode == 200) {
        final regex = RegExp(r'<a\s+href="/shows/([^"]+)">([^<]+)</a>');
        final matches = regex.allMatches(res.body);

        final dir = <String, String>{};
        for (final m in matches) {
          final slug = m.group(1)!;
          final rawTitle = m.group(2)!;

          dir[_normalize(rawTitle)] = slug;
          dir[_normalize(slug)] = slug;

          // Parse "English Title (Romaji Title)" format
          final parenMatch = RegExp(r'^(.*?)\s*\((.*?)\)$').firstMatch(rawTitle);
          if (parenMatch != null) {
            final en = parenMatch.group(1)!;
            final romaji = parenMatch.group(2)!;
            dir[_normalize(en)] = slug;
            dir[_normalize(romaji)] = slug;
          }
        }

        if (dir.isNotEmpty) {
          appDebugLog('✅ [AFL] Indexed ${dir.length} title keys for ${matches.length} shows');
          _aflDirectory = dir;
          await _cache.set(
            'afl_directory_v1',
            dir,
            ttl: CacheService.extraLongCache,
          );
          return dir;
        }
      }
    } catch (e) {
      appDebugLog('❌ [AFL] Failed to fetch shows directory: $e');
    }

    return _aflDirectory ?? {};
  }

  /// Finds an AFL slug from candidate titles
  String? _findSlug(Map<String, String> dir, List<String> candidates) {
    for (final c in candidates) {
      if (c.trim().isEmpty) continue;
      final norm = _normalize(c);
      if (dir.containsKey(norm)) return dir[norm];

      // Strip common season/sequel suffixes e.g. "Season 2", "2nd Season", "Part 2", "S2"
      final stripped = c
          .replaceAll(
            RegExp(
              r'\s*(?:season\s*\d+|\d+(?:st|nd|rd|th)\s*season|part\s*\d+|s\d+|cour\s*\d+)',
              caseSensitive: false,
            ),
            '',
          )
          .trim();
      final normStripped = _normalize(stripped);
      if (dir.containsKey(normStripped)) return dir[normStripped];

      // Try candidate as slug
      final slugCandidate = c
          .toLowerCase()
          .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
          .replaceAll(RegExp(r'^-+|-+$'), '');
      if (dir.containsKey(_normalize(slugCandidate))) {
        return dir[_normalize(slugCandidate)];
      }
    }
    return null;
  }

  /// Main method: returns filler episode data for an anime by AniList ID
  Future<AnimeFillerData> getFillerData({
    required int anilistId,
    required String title,
    String? romajiTitle,
    int? malId,
  }) async {
    // 1. In-memory cache check
    if (_memoryCache.containsKey(anilistId)) {
      return _memoryCache[anilistId]!;
    }

    // 2. Disk cache check
    final cacheKey = 'anime_filler_$anilistId';
    final cached = await _cache.get<AnimeFillerData>(
      cacheKey,
      (json) => AnimeFillerData.fromJson(json),
    );
    if (cached != null) {
      _memoryCache[anilistId] = cached;
      return cached;
    }

    // 3. AniZip mapping to get absolute episode offsets and MAL ID
    final relativeToAbsolute = <int, int>{};
    int? resolvedMalId = malId;

    try {
      final zipUri = Uri.parse('https://api.ani.zip/mappings?anilist_id=$anilistId');
      final zipRes = await _client.get(zipUri).timeout(const Duration(seconds: 5));
      if (zipRes.statusCode == 200) {
        final zipData = jsonDecode(zipRes.body);
        resolvedMalId ??= zipData['mappings']?['mal_id'] as int?;

        final episodes = zipData['episodes'] as Map<String, dynamic>?;
        if (episodes != null) {
          for (final entry in episodes.entries) {
            final relEp = int.tryParse(entry.key);
            final epData = entry.value;
            if (relEp != null && epData is Map) {
              final absEp = epData['absoluteEpisodeNumber'] as int? ?? relEp;
              relativeToAbsolute[relEp] = absEp;
            }
          }
        }
      }
    } catch (e) {
      appDebugLog('AniZip mapping error for anime $anilistId: $e');
    }

    // 4. Resolve slug and query AnimeFillerList
    final dir = await _getAflDirectory();
    final slug = _findSlug(dir, [title, if (romajiTitle != null) romajiTitle]);

    if (slug != null) {
      try {
        appDebugLog('🌀 [AFL] Fetching filler list for slug: $slug (anime $anilistId)');
        final showUri = Uri.parse('$_aflBaseUrl/shows/$slug');
        final showRes = await _client.get(showUri, headers: _headers).timeout(
              const Duration(seconds: 8),
            );

        if (showRes.statusCode == 200) {
          final html = showRes.body;
          final rowRegex = RegExp(r'<tr class="([^"]+)"[^>]*>\s*<td class="Number">(\d+)</td>');
          final matches = rowRegex.allMatches(html);

          final aflFillers = <int>{};
          final aflMixed = <int>{};

          for (final m in matches) {
            final cls = m.group(1)!;
            final num = int.tryParse(m.group(2)!);
            if (num == null) continue;

            if (cls.contains('mixed_canon/filler')) {
              aflMixed.add(num);
            } else if (cls.contains('filler')) {
              aflFillers.add(num);
            }
          }

          // Fallback to condensed span if table rows were not present
          if (aflFillers.isEmpty && aflMixed.isEmpty) {
            _parseCondensedEpisodes(html, 'filler', aflFillers);
            _parseCondensedEpisodes(html, 'mixed_canon/filler', aflMixed);
          }

          if (aflFillers.isNotEmpty || aflMixed.isNotEmpty) {
            final relativeFillers = <int>{};
            final relativeMixed = <int>{};

            if (relativeToAbsolute.isNotEmpty) {
              final absToRel = <int, int>{};
              for (final entry in relativeToAbsolute.entries) {
                absToRel[entry.value] = entry.key;
              }

              for (final f in aflFillers) {
                final rel = absToRel[f];
                if (rel != null) relativeFillers.add(rel);
              }
              for (final m in aflMixed) {
                final rel = absToRel[m];
                if (rel != null) relativeMixed.add(rel);
              }
            } else {
              relativeFillers.addAll(aflFillers);
              relativeMixed.addAll(aflMixed);
            }

            final result = AnimeFillerData(
              fillerEpisodes: relativeFillers,
              mixedEpisodes: relativeMixed,
            );

            appDebugLog(
              '✅ [AFL] Found ${result.fillerEpisodes.length} fillers and ${result.mixedEpisodes.length} mixed for "$title" (slug: $slug)',
            );

            await _cache.set(cacheKey, result.toJson(), ttl: CacheService.longCache);
            _memoryCache[anilistId] = result;
            return result;
          }
        }
      } catch (e) {
        appDebugLog('❌ [AFL] Error fetching show page for slug $slug: $e');
      }
    }

    // 5. Fallback: Jikan API
    if (resolvedMalId != null) {
      try {
        appDebugLog('🌀 [AFL Fallback] Querying Jikan for MAL ID $resolvedMalId');
        final jikanUri = Uri.parse('https://api.jikan.moe/v4/anime/$resolvedMalId/episodes');
        final jikanRes = await _client.get(jikanUri).timeout(const Duration(seconds: 6));

        if (jikanRes.statusCode == 200) {
          final jikanData = jsonDecode(jikanRes.body);
          final data = jikanData['data'] as List<dynamic>?;
          if (data != null && data.isNotEmpty) {
            final jikanFillers = <int>{};
            for (final ep in data) {
              final epNum = ep['mal_id'] as int?;
              final isFiller = ep['filler'] == true;
              if (epNum != null && isFiller) {
                jikanFillers.add(epNum);
              }
            }

            final result = AnimeFillerData(
              fillerEpisodes: jikanFillers,
              mixedEpisodes: {},
            );

            appDebugLog('✅ [AFL Fallback] Jikan found ${jikanFillers.length} filler episodes');
            await _cache.set(cacheKey, result.toJson(), ttl: CacheService.longCache);
            _memoryCache[anilistId] = result;
            return result;
          }
        }
      } catch (e) {
        appDebugLog('❌ [AFL Fallback] Jikan error: $e');
      }
    }

    // 6. No fillers found or not applicable
    const emptyResult = AnimeFillerData();
    await _cache.set(cacheKey, emptyResult.toJson(), ttl: CacheService.longCache);
    _memoryCache[anilistId] = emptyResult;
    return emptyResult;
  }

  /// Parses condensed section e.g. <div class="filler">...<span class="Episodes">...</span></div>
  void _parseCondensedEpisodes(String html, String className, Set<int> target) {
    final blockRegex = RegExp(
      '<div class="$className">.*?<span class="Episodes">(.*?)</span>',
      dotAll: true,
    );
    final match = blockRegex.firstMatch(html);
    if (match == null) return;

    final episodesContent = match.group(1)!;
    // Strip HTML tags (e.g. <a>...</a>)
    final cleanText = episodesContent.replaceAll(RegExp(r'<[^>]*>'), '');
    final parts = cleanText.split(',');

    for (var part in parts) {
      part = part.trim();
      if (part.contains('-')) {
        final range = part.split('-');
        final start = int.tryParse(range[0].trim());
        final end = int.tryParse(range[1].trim());
        if (start != null && end != null) {
          for (int i = start; i <= end; i++) {
            target.add(i);
          }
        }
      } else {
        final single = int.tryParse(part);
        if (single != null) target.add(single);
      }
    }
  }
}
