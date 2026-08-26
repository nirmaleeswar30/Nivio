import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:nivio/core/debug_log.dart';
import 'package:nivio/models/stream_result.dart';

class XonScraperService {
  final http.Client client = http.Client();
  final String _baseUrl = 'https://xon-avens.xyz/apis';
  final String _archiveBaseUrl = 'https://archive.org/download/';
  final Map<String, String> _headers = {
    'Accept-Encoding': 'gzip',
    'API': '553y845hfhdlfhjkl438943943839443943fdhdkfjfj9834lnfd98',
    'CALLER': 'vion-official-app',
    'Connection': 'Keep-Alive',
    'Host': 'xon-avens.xyz',
    'User-Agent': 'okhttp/5.3.2',
  };

  List<Map<String, dynamic>> _shows = [];
  List<Map<String, dynamic>> _episodes = [];
  DateTime? _showsFetchedAt;
  DateTime? _episodesFetchedAt;
  static const _cacheTtl = Duration(minutes: 30);

  Future<void> _refreshShows() async {
    if (_showsFetchedAt != null && DateTime.now().difference(_showsFetchedAt!) < _cacheTtl) {
      return;
    }
    try {
      final res = await client.get(Uri.parse('$_baseUrl/nzgetshows.php'), headers: _headers);
      if (res.statusCode == 200) {
        final body = jsonDecode(res.body);
        if (body['movies'] is List) {
          _shows = List<Map<String, dynamic>>.from(body['movies']);
          _showsFetchedAt = DateTime.now();
        }
      }
    } catch (e) {
      appDebugLog('Xon _refreshShows error: $e');
    }
  }

  Future<void> _refreshEpisodes() async {
    if (_episodesFetchedAt != null && DateTime.now().difference(_episodesFetchedAt!) < _cacheTtl) {
      return;
    }
    try {
      final res = await client.get(Uri.parse('$_baseUrl/nzgetepisodes_v2.php'), headers: _headers);
      if (res.statusCode == 200) {
        final body = jsonDecode(res.body);
        if (body['episodes'] is List) {
          _episodes = List<Map<String, dynamic>>.from(body['episodes']);
          _episodesFetchedAt = DateTime.now();
        }
      }
    } catch (e) {
      appDebugLog('Xon _refreshEpisodes error: $e');
    }
  }

  String _normalizeTitle(String value) {
    return value.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), ' ').trim().replaceAll(RegExp(r'\s+'), ' ');
  }

  bool _matchesTitle(Map<String, dynamic> item, String title) {
    final name = _normalizeTitle(item['name']?.toString() ?? '');
    final showName = _normalizeTitle(item['show_name']?.toString() ?? item['showName']?.toString() ?? '');
    if (name.isNotEmpty && (name.contains(title) || title.contains(name))) return true;
    if (showName.isNotEmpty && (showName.contains(title) || title.contains(showName))) return true;
    return false;
  }

  int? _seasonNumber(String value) {
    final match = RegExp(r'\bseason\s*0*(\d+)\b', caseSensitive: false).firstMatch(value);
    final raw = match?.group(1);
    return raw == null ? null : int.tryParse(raw);
  }

  bool _matchesSeason(Map<String, dynamic> item, int season) {
    final seasonName = item['season_name']?.toString() ?? item['seasonName']?.toString() ?? '';
    final s = _seasonNumber(seasonName);
    return s == null || s == season;
  }

  String _cleanLanguage(String? value) {
    final raw = value?.trim() ?? '';
    if (raw.isEmpty) return 'Default';
    for (final lang in ['Tamil', 'Telugu', 'Hindi', 'Malayalam', 'Kannada', 'English', 'Japanese', 'Korean']) {
      if (raw.toLowerCase().contains(lang.toLowerCase())) return lang;
    }
    final parenthesized = RegExp(r'\(([^)]+)\)').firstMatch(raw)?.group(1);
    return (parenthesized ?? raw).trim();
  }

  List<StreamSource> _getSources(Map<String, dynamic> item) {
    final sources = <StreamSource>[];
    void add(String key, String quality) {
      final rawUrl = item[key]?.toString().trim() ?? '';
      if (rawUrl.isEmpty) return;
      final url = rawUrl.startsWith('http') ? rawUrl : '$_archiveBaseUrl$rawUrl';
      if (sources.any((s) => s.url == url)) return;
      sources.add(StreamSource(url: url, quality: quality, isM3U8: url.toLowerCase().contains('.m3u8')));
    }
    add('basic', '360p');
    add('sd', '480p');
    add('hd', '720p');
    add('fhd', '1080p');
    return sources;
  }

  Future<List<Map<String, dynamic>>> _matchingCandidates(String rawTitle, int season, int episode, bool isTv) async {
    final title = _normalizeTitle(rawTitle);
    final candidates = <Map<String, dynamic>>[];

    if (isTv) {
      await _refreshEpisodes();
      for (final ep in _episodes) {
        final epNoStr = ep['no']?.toString();
        final epNo = epNoStr != null ? int.tryParse(epNoStr) : null;
        if (epNo != null && epNo != episode) continue;
        if (!_matchesTitle(ep, title)) continue;
        if (!_matchesSeason(ep, season)) continue;
        if (_getSources(ep).isNotEmpty) candidates.add(ep);
      }
    } else {
      await _refreshShows();
      for (final show in _shows) {
        if (!_matchesTitle(show, title)) continue;
        if (_getSources(show).isNotEmpty) candidates.add(show);
      }
    }

    // Sort by language match? We will return all languages as servers
    return candidates;
  }

  Future<List<String>> fetchAvailableServers({
    required String tmdbId,
    required String title,
    required int season,
    required int episode,
    required bool isTv,
  }) async {
    final candidates = await _matchingCandidates(title, season, episode, isTv);
    if (candidates.isEmpty) return [];
    return ['Auto'];
  }

  Future<StreamResult?> fetchStreamUrl({
    required String tmdbId,
    required String title,
    required int season,
    required int episode,
    required String server,
    required bool isTv,
    String? preferredAudio,
  }) async {
    final candidates = await _matchingCandidates(title, season, episode, isTv);
    if (candidates.isEmpty) return null;

    final allLanguages = <String>[];
    Map<String, dynamic>? selected;

    for (final candidate in candidates) {
      final lang = _cleanLanguage(candidate['language_name']?.toString() ?? candidate['languageName']?.toString());
      if (!allLanguages.contains(lang)) allLanguages.add(lang);
    }
    
    String targetAudio = preferredAudio ?? 'English';
    if (!allLanguages.any((l) => l.toLowerCase() == targetAudio.toLowerCase())) {
      targetAudio = allLanguages.first; // Fallback to first available language
    }

    for (final candidate in candidates) {
      final lang = _cleanLanguage(candidate['language_name']?.toString() ?? candidate['languageName']?.toString());
      if (lang.toLowerCase() == targetAudio.toLowerCase()) {
        selected = candidate;
        break;
      }
    }

    if (selected == null) return null;
    final sources = _getSources(selected);
    if (sources.isEmpty) return null;

    // Pick highest quality by default, StreamResult allows user to change it
    final source = sources.last; 
    
    return StreamResult(
      url: source.url,
      quality: source.quality,
      provider: 'Xon ($server)',
      headers: const {'User-Agent': 'okhttp/5.3.2', 'Referer': 'https://xon-avens.xyz/apis'},
      sources: sources,
      availableQualities: sources.map((s) => s.quality).toSet().toList(),
      availableAudios: allLanguages,
      selectedAudio: targetAudio,
      isM3U8: source.isM3U8,
    );
  }
}
