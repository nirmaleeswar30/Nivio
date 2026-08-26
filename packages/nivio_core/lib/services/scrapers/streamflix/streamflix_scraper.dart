import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nivio/core/debug_log.dart';
import 'package:nivio/models/stream_result.dart';

final streamFlixScraperProvider = Provider((ref) => StreamFlixScraperService());

class StreamFlixScraperService {
  final String providerName;
  final Dio _dio;

  StreamFlixScraperService({this.providerName = 'StreamFlix'})
      : _dio = Dio(
          BaseOptions(
            baseUrl: 'https://api.streamflix.app',
            connectTimeout: const Duration(seconds: 15),
            receiveTimeout: const Duration(seconds: 20),
            validateStatus: (status) => status != null && status < 600,
            headers: const {
              'Accept': 'application/json',
              'User-Agent': 'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36',
            },
          ),
        );

  static const String _firebaseUrl = 'https://chilflix-410be-default-rtdb.asia-southeast1.firebasedatabase.app';
  static const String _firebaseNamespace = 'chilflix-410be-default-rtdb';
  static const String _fallbackDownloadBase = 'https://cf.streamflixserver.site/';

  String? _downloadBase;
  List<_StreamFlixEntry>? _catalog;

  Future<StreamResult?> fetchStreamUrl({
    required String tmdbId,
    required String title,
    required String mediaType,
    String? year,
    String? preferredAudio,
    int season = 1,
    int episode = 1,
  }) async {
    try {
      final isTv = mediaType != 'movie';
      final catalog = await _loadCatalog();
      final entry = _selectEntry(catalog, title, isTv, tmdbId);
      if (entry == null) return null;

      final link = entry.isTv ? await _episodeLink(entry, season, episode) : entry.movieLink;
      if (link == null || link.trim().isEmpty) return null;

      final base = await _loadDownloadBase();
      final url = _joinUrl(base, link);
      final quality = _qualityFrom(link);
      
      final isHls = _isHls(url);

      return StreamResult(
        url: url,
        quality: quality,
        provider: providerName,
        availableQualities: [quality],
        isM3U8: isHls,
        headers: const {
          'Referer': 'https://api.streamflix.app/',
          'User-Agent': 'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36',
        },
        sources: [
          StreamSource(url: url, quality: quality, isM3U8: isHls),
        ],
      );
    } catch (e) {
      appDebugLog('StreamFlix error: $e');
      return null;
    }
  }

  Future<String> _loadDownloadBase() async {
    if (_downloadBase != null && _downloadBase!.isNotEmpty) return _downloadBase!;
    try {
      final response = await _dio.get('/config/config-streamflixapp.json');
      if (response.statusCode == 200) {
        final config = _asMap(response.data);
        final download = _asList(config?['download']);
        final base = download.isNotEmpty ? download.first?.toString() : null;
        if (base != null && base.trim().isNotEmpty) {
          _downloadBase = _normalizeBase(base);
          return _downloadBase!;
        }
      }
    } catch (_) {}
    _downloadBase = _fallbackDownloadBase;
    return _downloadBase!;
  }

  Future<List<_StreamFlixEntry>> _loadCatalog() async {
    if (_catalog != null) return _catalog!;
    try {
      final response = await _dio.get('/data.json');
      if (response.statusCode != 200) return const [];
      final root = _asMap(response.data);
      final entries = <_StreamFlixEntry>[];
      for (final raw in _asList(root?['data'])) {
        final entry = _StreamFlixEntry.fromJson(raw);
        if (entry != null) entries.add(entry);
      }
      _catalog = entries;
      return entries;
    } catch (_) {
      return const [];
    }
  }

  Future<String?> _episodeLink(_StreamFlixEntry entry, int season, int episode) async {
    final path = '/Data/${entry.movieKey}/seasons/$season/episodes.json';
    try {
      final response = await _dio.get(
        '$_firebaseUrl$path',
        queryParameters: const {'ns': _firebaseNamespace},
      );
      if (response.statusCode != 200) return null;

      final episodes = _episodesFrom(response.data);
      if (episodes.isEmpty) return null;
      final targetIndex = episode - 1;
      for (final item in episodes) {
        if (item.key == targetIndex) return item.link;
      }
      if (targetIndex >= 0 && targetIndex < episodes.length) {
        return episodes[targetIndex].link;
      }
    } catch (_) {}
    return null;
  }

  _StreamFlixEntry? _selectEntry(List<_StreamFlixEntry> entries, String requestTitle, bool isTv, String tmdbId) {
    final filtered = entries.where((entry) => entry.isTv == isTv).toList();
    if (filtered.isEmpty) return null;

    final titleMatches = filtered.where((entry) => _titleScore(entry.movieName, requestTitle) > 0).toList(growable: false);
    final candidates = titleMatches.isNotEmpty ? titleMatches : filtered;
    
    final sorted = [...candidates]
      ..sort((a, b) {
        final title = _titleScore(b.movieName, requestTitle).compareTo(_titleScore(a.movieName, requestTitle));
        if (title != 0) return title;
        final tmdb = _tmdbScore(b, tmdbId).compareTo(_tmdbScore(a, tmdbId));
        if (tmdb != 0) return tmdb;
        return b.year.compareTo(a.year);
      });
    final best = sorted.first;
    return _titleScore(best.movieName, requestTitle) > 0 || _tmdbScore(best, tmdbId) > 0 ? best : null;
  }

  static List<_StreamFlixEpisode> _episodesFrom(Object? raw) {
    final values = raw is List
        ? raw
        : raw is Map
            ? raw.entries.map((entry) => entry.value)
            : const Iterable<Object?>.empty();
    final episodes = <_StreamFlixEpisode>[];
    for (final value in values) {
      final episode = _StreamFlixEpisode.fromJson(value);
      if (episode != null) episodes.add(episode);
    }
    episodes.sort((a, b) => a.key.compareTo(b.key));
    return episodes;
  }

  static int _tmdbScore(_StreamFlixEntry entry, String? tmdbId) =>
      tmdbId != null && tmdbId.isNotEmpty && entry.tmdb == tmdbId ? 100 : 0;

  static int _titleScore(String candidate, String target) {
    final a = _normalizeTitle(candidate);
    final b = _normalizeTitle(target);
    if (a == b) return 20;
    if (a.contains(b) || b.contains(a)) return 10;
    return 0;
  }

  static String _qualityFrom(String link) {
    final match = RegExp(r'(2160p|1080p|720p|480p|360p)', caseSensitive: false).firstMatch(link);
    return match?.group(1)?.toUpperCase().replaceAll('P', 'p') ?? 'Auto';
  }

  static String _joinUrl(String base, String path) {
    final normalizedBase = _normalizeBase(base);
    final normalizedPath = path.startsWith('/') ? path.substring(1) : path;
    return '$normalizedBase$normalizedPath';
  }

  static String _normalizeBase(String base) => base.endsWith('/') ? base : '$base/';

  static bool _isHls(String url) => Uri.parse(url).path.endsWith('.m3u8');

  static String _normalizeTitle(String value) =>
      value.toLowerCase().replaceAll(RegExp(r'\[[^\]]+\]'), '').replaceAll(RegExp(r'[^a-z0-9]+'), ' ').trim();

  static Map<String, dynamic>? _asMap(Object? value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) return Map<String, dynamic>.from(value);
    if (value is String && value.trim().isNotEmpty) {
      try {
        return _asMap(jsonDecode(value));
      } catch (_) {}
    }
    return null;
  }

  static List<Object?> _asList(Object? value) {
    if (value is List) return value;
    return const [];
  }
}

class _StreamFlixEntry {
  const _StreamFlixEntry({
    required this.isTv,
    required this.movieName,
    required this.year,
    required this.movieType,
    required this.movieInfo,
    required this.movieKey,
    required this.movieLink,
    required this.tmdb,
  });

  final bool isTv;
  final String movieName;
  final String year;
  final String movieType;
  final String movieInfo;
  final String movieKey;
  final String? movieLink;
  final String tmdb;

  static _StreamFlixEntry? fromJson(Object? raw) {
    final json = StreamFlixScraperService._asMap(raw);
    final name = json?['moviename']?.toString().trim();
    final key = json?['moviekey']?.toString().trim();
    if (name == null || name.isEmpty || key == null || key.isEmpty) {
      return null;
    }
    return _StreamFlixEntry(
      isTv: json?['isTV'] == true || json?['isTV']?.toString() == 'true',
      movieName: name,
      year: json?['movieyear']?.toString().trim() ?? '',
      movieType: json?['movietype']?.toString().trim() ?? '',
      movieInfo: json?['movieinfo']?.toString().trim() ?? '',
      movieKey: key,
      movieLink: json?['movielink']?.toString().trim(),
      tmdb: json?['tmdb']?.toString().trim() ?? '',
    );
  }
}

class _StreamFlixEpisode {
  const _StreamFlixEpisode({required this.key, required this.link});

  final int key;
  final String link;

  static _StreamFlixEpisode? fromJson(Object? raw) {
    final json = StreamFlixScraperService._asMap(raw);
    final link = json?['link']?.toString().trim();
    if (link == null || link.isEmpty) return null;
    return _StreamFlixEpisode(
      key: int.tryParse(json?['key']?.toString() ?? '') ?? 0,
      link: link,
    );
  }
}
