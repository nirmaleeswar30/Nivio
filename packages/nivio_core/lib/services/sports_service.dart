import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nivio/core/debug_log.dart';
import 'package:nivio/models/sports_match.dart';

final sportsServiceProvider = Provider((ref) => SportsService());

/// Live sports provider. Sources the match catalog and resolves direct HLS
/// streams from the "solaris" (streamed/damitv) backend that Bingr exposes.
///
/// The match list and stream resolver are plain open GET endpoints (no auth),
/// and the resolved `embedUrl` for the "Direct CDN" option is a direct
/// `.m3u8` playlist. That CDN is Referer-gated, so playback must send
/// [playbackReferer] (handled by the player via directStreamReferer).
class SportsService {
  final Dio _dio;

  SportsService()
      : _dio = Dio(
          BaseOptions(
            baseUrl: _apiBase,
            connectTimeout: const Duration(seconds: 15),
            receiveTimeout: const Duration(seconds: 20),
            validateStatus: (status) => status != null && status < 600,
            headers: const {
              'Accept': 'application/json',
              'Referer': 'https://bingr.one/',
              'Origin': 'https://bingr.one',
              'User-Agent':
                  'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/127.0.0.0 Safari/537.36',
            },
          ),
        );

  // Single swappable backend origin.
  static const String _apiBase = 'https://api.bingr.one/api';

  /// Referer the live-sports CDN expects when fetching the HLS playlist.
  static const String playbackReferer = 'https://bingr.one/';

  /// Fetch all live/upcoming matches, popular first then by start time.
  Future<List<SportsMatch>> fetchMatches() async {
    try {
      final res = await _dio.get<Object?>('/sports/matches/all');
      if (res.statusCode != 200) {
        appDebugLog('Sports: matches failed ${res.statusCode}');
        return const [];
      }
      final data = res.data;
      if (data is! List) return const [];
      final matches = <SportsMatch>[];
      for (final raw in data) {
        if (raw is Map) {
          matches.add(SportsMatch.fromJson(Map<String, dynamic>.from(raw)));
        }
      }
      matches.sort((a, b) {
        if (a.popular != b.popular) return a.popular ? -1 : 1;
        return a.dateMs.compareTo(b.dateMs);
      });
      appDebugLog('Sports: ${matches.length} matches');
      return matches;
    } catch (e) {
      appDebugLog('Sports: fetchMatches error $e');
      return const [];
    }
  }

  /// Resolve playable direct-HLS streams for a match (embeds/iframes skipped).
  Future<List<SportsStream>> resolveStreams(SportsMatch match) async {
    final streams = <SportsStream>[];
    for (final ref in match.sources) {
      try {
        final res = await _dio.get<Object?>(
          '/sports/stream/${Uri.encodeComponent(ref.source)}/${Uri.encodeComponent(ref.id)}',
        );
        if (res.statusCode != 200 || res.data is! List) continue;
        for (final raw in (res.data as List)) {
          if (raw is! Map) continue;
          final m = Map<String, dynamic>.from(raw);
          final url = m['embedUrl']?.toString() ?? '';
          // Direct streams only — skip iframe embeds (embed.st/etc.).
          final isDirect = url.contains('.m3u8') || url.contains('/proxy/m3u8');
          if (url.isEmpty || !isDirect) continue;
          streams.add(SportsStream(
            id: m['id']?.toString() ?? '${ref.source}-${streams.length}',
            url: url,
            streamNo: int.tryParse(m['streamNo']?.toString() ?? '') ?? 1,
            language: m['language']?.toString() ?? '',
            hd: m['hd'] == true,
            label: m['source']?.toString() ?? ref.source,
          ));
        }
      } catch (e) {
        appDebugLog('Sports: resolve ${ref.source} error $e');
      }
    }
    return streams;
  }
}
