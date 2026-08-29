import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nivio/core/debug_log.dart';
import 'package:nivio/models/stream_result.dart';

final movieBoxScraperProvider = Provider((ref) => MovieBoxScraperService());

class MovieBoxScraperService {
  final String providerName;
  final HttpClient _client;
  final String _deviceId;
  String? _token;

  MovieBoxScraperService({this.providerName = 'MovieBox'})
      : _client = HttpClient()..connectionTimeout = const Duration(seconds: 15),
        _deviceId = _generateDeviceId();

  static const String _packageName = 'com.community.mbox.in';
  static const int _versionCode = 50020042;
  static const String _versionName = '3.0.03.0529.03';
  static const String _brand = 'google';
  static const String _model = 'sdk_gphone64_x86_64';
  static const String _userAgent =
      'com.community.mbox.in/50020042 (Linux; U; Android 16; en_IN; '
      'sdk_gphone64_x86_64; Build/BP22.250325.006; Cronet/133.0.6876.3)';
  static const Map<String, String> _mediaHeaders = {
    'User-Agent': _userAgent,
  };
  static const String _defaultSecretEncoded =
      'NzZpUmwwN3MweFNOOWpxbUVXQXQ3OUVCSlp1bElRSXNWNjRGWnIyTw==';

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
      final token = await _anonymousToken();
      if (token == null || token.isEmpty) return null;

      final results = await _search(title, token);
      final candidates = _rankCandidates(results, title, preferredAudio).take(6);
      
      for (final candidate in candidates) {
        final details = await _details(candidate.subjectId, token);
        if (details == null) continue;

        var sources = _sourcesFrom(details);
        if (sources.isEmpty) {
          final playInfo = await _playInfo(candidate.subjectId, token);
          if (playInfo != null) sources = _sourcesFrom(playInfo);
        }
        if (sources.isEmpty) continue;

        final selected = _selectSource(sources, null);
        final subtitles = _subtitlesFrom(details);
        final languages = _streamLanguagesFor(
          results: results,
          selected: candidate,
          details: details,
        );
        final selectedAudio = _selectAudioLabel(
          languages,
          preferredAudio,
        );

        return StreamResult(
          url: selected.url,
          quality: selected.quality,
          provider: providerName,
          subtitles: subtitles,
          availableQualities: _dedupe(sources.map((source) => source.quality)),
          availableAudios: languages,
          selectedAudio: selectedAudio,
          isM3U8: _isHls(selected.url),
          headers: _mediaHeaders,
          sources: sources,
        );
      }
      return null;
    } catch (e, st) {
      appDebugLog('MovieBox error: $e\n$st');
      return null;
    }
  }

  Future<Map<String, dynamic>?> _get(String path, {String? token}) async {
    try {
      final fullUrl = 'https://api3.aoneroom.com$path';
      final ts = DateTime.now().millisecondsSinceEpoch;
      final req = await _client.getUrl(Uri.parse(fullUrl)).timeout(const Duration(seconds: 15));
      req.headers.set('user-agent', _userAgent);
      req.headers.set('accept', 'application/json');
      req.headers.set('content-type', 'application/json');
      if (token != null && token.isNotEmpty) req.headers.set('authorization', 'Bearer $token');
      req.headers.set('x-client-token', _xClientToken(ts));
      req.headers.set('x-tr-signature', _signature(method: 'GET', accept: 'application/json', contentType: 'application/json', url: fullUrl, timestamp: ts));
      req.headers.set('x-client-info', _clientInfo());
      req.headers.set('x-client-status', '0');
      req.headers.set('x-play-mode', '2');

      final resp = await req.close().timeout(const Duration(seconds: 15));
      final body = await utf8.decoder.bind(resp).join();
      if (resp.statusCode != 200) return null;
      return _asMap(jsonDecode(body));
    } catch (e) {
      appDebugLog('MovieBox _get error: $e');
      return null;
    }
  }

  Future<Map<String, dynamic>?> _post(String path, Map<String, dynamic> data, {String? token}) async {
    try {
      final fullUrl = 'https://api3.aoneroom.com$path';
      final body = jsonEncode(data);
      final ts = DateTime.now().millisecondsSinceEpoch;
      final req = await _client.postUrl(Uri.parse(fullUrl)).timeout(const Duration(seconds: 15));
      req.headers.set('user-agent', _userAgent);
      req.headers.set('accept', 'application/json');
      req.headers.set('content-type', 'application/json');
      if (token != null && token.isNotEmpty) req.headers.set('authorization', 'Bearer $token');
      req.headers.set('x-client-token', _xClientToken(ts));
      req.headers.set('x-tr-signature', _signature(method: 'POST', accept: 'application/json', contentType: 'application/json', url: fullUrl, timestamp: ts));
      req.headers.set('x-client-info', _clientInfo());
      req.headers.set('x-client-status', '0');
      req.headers.set('x-play-mode', '2');
      req.write(body);

      final resp = await req.close().timeout(const Duration(seconds: 15));
      final resBody = await utf8.decoder.bind(resp).join();
      if (resp.statusCode != 200) {
        appDebugLog('MovieBox _post ($path) returned status ${resp.statusCode}: $resBody');
        return null;
      }
      return _asMap(jsonDecode(resBody));
    } catch (e) {
      appDebugLog('MovieBox _post error: $e');
      return null;
    }
  }

  Future<String?> _anonymousToken() async {
    final cached = _token;
    if (cached != null && cached.isNotEmpty) return cached;

    try {
      const path = '/wefeed-mobile-bff/tab/ranking-list?tabId=0&categoryType=4516404531735022304&page=1&perPage=1';
      final fullUrl = 'https://api3.aoneroom.com$path';
      final ts = DateTime.now().millisecondsSinceEpoch;
      final req = await _client.getUrl(Uri.parse(fullUrl)).timeout(const Duration(seconds: 15));
      req.headers.set('user-agent', _userAgent);
      req.headers.set('accept', 'application/json');
      req.headers.set('content-type', 'application/json');
      req.headers.set('x-client-token', _xClientToken(ts));
      req.headers.set('x-tr-signature', _signature(method: 'GET', accept: 'application/json', contentType: 'application/json', url: fullUrl, timestamp: ts));
      req.headers.set('x-client-info', _clientInfo());
      req.headers.set('x-client-status', '0');
      req.headers.set('x-play-mode', '2');

      final resp = await req.close().timeout(const Duration(seconds: 15));
      if (resp.statusCode != 200) return null;
      final xUser = resp.headers.value('x-user');
      if (xUser == null || xUser.trim().isEmpty) return null;
      final token = _asMap(jsonDecode(xUser))?['token']?.toString();
      if (token == null || token.isEmpty) return null;
      _token = token;
      return token;
    } catch (e) {
      appDebugLog('MovieBox _anonymousToken error: $e');
      return null;
    }
  }

  Future<List<_MovieBoxSearchResult>> _search(String title, String token) async {
    const path = '/wefeed-mobile-bff/subject-api/search/v2';
    final root = await _post(path, {'page': 1, 'perPage': 20, 'keyword': title}, token: token);
    if (root == null) return const [];
    final data = _asMap(root['data']);
    final rawResults = <Object?>[
      ..._asList(data?['subjects']),
      ..._asList(data?['items']),
      ..._asList(data?['list']),
    ];
    for (final group in _asList(data?['results'])) {
      final map = _asMap(group);
      rawResults.addAll(_asList(map?['subjects']));
      rawResults.addAll(_asList(map?['items']));
      rawResults.addAll(_asList(map?['list']));
    }
    final results = <_MovieBoxSearchResult>[];
    for (final raw in rawResults) {
      final result = _MovieBoxSearchResult.fromJson(raw);
      if (result != null) results.add(result);
    }
    return results;
  }

  Future<Map<String, dynamic>?> _details(String subjectId, String token) async {
    final path = '/wefeed-mobile-bff/subject-api/get?subjectId=${Uri.encodeQueryComponent(subjectId)}';
    final root = await _get(path, token: token);
    return _asMap(root?['data']);
  }

  Future<Map<String, dynamic>?> _playInfo(String subjectId, String token) async {
    final path = '/wefeed-mobile-bff/subject-api/play-info?subjectId=${Uri.encodeQueryComponent(subjectId)}';
    final root = await _get(path, token: token);
    return _asMap(root?['data']);
  }

  String _clientInfo() {
    return jsonEncode({
      'package_name': _packageName,
      'version_name': _versionName,
      'version_code': _versionCode,
      'os': 'android',
      'os_version': '16',
      'install_ch': 'ps',
      'device_id': _deviceId,
      'install_store': 'ps',
      'gaid': 'd7578036d13336cc',
      'brand': _brand,
      'model': _model,
      'system_language': 'en',
      'net': 'NETWORK_WIFI',
      'region': 'IN',
      'timezone': 'Asia/Calcutta',
      'sp_code': '',
    });
  }

  static String _xClientToken(int timestamp) {
    final ts = timestamp.toString();
    final reversed = ts.split('').reversed.join();
    return '$ts,${md5.convert(utf8.encode(reversed))}';
  }

  static String _signature({
    required String method,
    required String accept,
    required String contentType,
    required String url,
    required int timestamp,
  }) {
    final canonical = _canonical(
      method: method,
      accept: accept,
      contentType: contentType,
      url: url,
      timestamp: timestamp,
    );
    final decodedSecret = utf8.decode(base64Decode(_defaultSecretEncoded));
    final secret = base64Decode(decodedSecret);
    final signature = Hmac(md5, secret).convert(utf8.encode(canonical));
    return '$timestamp|2|${base64Encode(signature.bytes)}';
  }

  static String _canonical({
    required String method,
    required String accept,
    required String contentType,
    required String url,
    required int timestamp,
  }) {
    final uri = Uri.parse(url);
    final keys = uri.queryParametersAll.keys.toList()..sort();
    final query = keys
        .map(
          (key) => uri.queryParametersAll[key]!
              .map((value) => '$key=$value')
              .join('&'),
        )
        .where((part) => part.isNotEmpty)
        .join('&');
    final canonicalUrl = query.isEmpty ? uri.path : '${uri.path}?$query';
    return [
      method.toUpperCase(),
      accept,
      contentType,
      '',
      timestamp,
      '',
      canonicalUrl,
    ].join('\n');
  }

  List<_MovieBoxSearchResult> _rankCandidates(
    List<_MovieBoxSearchResult> results,
    String requestTitle,
    String? preferredAudio,
  ) {
    final sorted = [...results]
      ..sort((a, b) {
        final language = _languageScore(b, preferredAudio).compareTo(_languageScore(a, preferredAudio));
        if (language != 0) return language;
        final title = _titleScore(b.title, requestTitle).compareTo(_titleScore(a.title, requestTitle));
        if (title != 0) return title;
        return _qualityHint(b).compareTo(_qualityHint(a));
      });
    return sorted;
  }

  List<StreamSource> _sourcesFrom(Map<String, dynamic> details) {
    final sources = <StreamSource>[];
    void collectResolutionList(List<Object?> values) {
      for (final raw in values) {
        final item = _asMap(raw);
        final url = _firstUrl(item);
        if (url == null || sources.any((source) => source.url == url)) {
          continue;
        }
        sources.add(
          StreamSource(
            url: url,
            quality: _qualityLabel(item) ?? 'Auto',
            isM3U8: _isHls(url),
          ),
        );
      }
    }

    for (final detector in _asList(details['resourceDetectors'])) {
      final detectorMap = _asMap(detector);
      collectResolutionList(_asList(detectorMap?['resolutionList']));
    }
    for (final stream in _asList(details['streams'])) {
      final streamMap = _asMap(stream);
      final streamUrl = _firstUrl(streamMap);
      if (streamUrl != null && !sources.any((source) => source.url == streamUrl)) {
        sources.add(
          StreamSource(
            url: streamUrl,
            quality: _qualityLabel(streamMap) ?? 'Auto',
            isM3U8: _isHls(streamUrl),
          ),
        );
      }
      collectResolutionList(_asList(streamMap?['resolutionList']));
    }
    sources.sort((a, b) => _resolution(b.quality).compareTo(_resolution(a.quality)));
    return sources;
  }

  List<StreamSubtitleTrack> _subtitlesFrom(Map<String, dynamic> details) {
    final subtitles = <StreamSubtitleTrack>[];
    void collect(Object? value) {
      if (value is List) {
        for (final item in value) {
          collect(item);
        }
        return;
      }
      final map = _asMap(value);
      if (map == null) return;
      final url = _firstUrl(map);
      final isCaption =
          map.containsKey('captionUrl') ||
          map.containsKey('subtitleUrl') ||
          map.containsKey('subtitlingUrl') ||
          map.containsKey('lang');
      if (isCaption && url != null) {
        subtitles.add(
          StreamSubtitleTrack(url: url, lang: map['lang']?.toString() ?? 'Unknown'),
        );
      }
      for (final item in map.values) {
        if (item is List || item is Map) collect(item);
      }
    }

    collect(details['extCaptions']);
    collect(details['captions']);
    collect(details['subtitles']);
    final seen = <String>{};
    return subtitles
        .where((subtitle) => seen.add('${subtitle.lang}|${subtitle.url}'))
        .toList(growable: false);
  }

  StreamSource _selectSource(List<StreamSource> sources, String? preferred) {
    final target = preferred?.trim().toLowerCase();
    if (target != null && target.isNotEmpty) {
      for (final source in sources) {
        if (source.quality.toLowerCase().contains(target)) return source;
      }
    }
    return sources.first;
  }

  static int _languageScore(_MovieBoxSearchResult result, String? preferredAudio) {
    final preferred = preferredAudio?.trim();
    if (preferred == null || preferred.isEmpty) return 0;
    return _candidateStreamLanguages(result).any((language) => _languageMatches(language, preferred)) ? 10 : 0;
  }

  static List<String> _languagesFrom(String value) {
    return _dedupe(
      value
          .split(RegExp(r'[,/|]'))
          .map((part) => part.trim())
          .where((part) => part.isNotEmpty),
    );
  }

  static List<String> _streamLanguagesFor({
    required List<_MovieBoxSearchResult> results,
    required _MovieBoxSearchResult selected,
    required Map<String, dynamic> details,
  }) {
    final variants = <String>[];
    final selectedBase = _normalizeTitle(selected.title);
    for (final result in results) {
      if (result.subjectType != selected.subjectType) continue;
      if (result.releaseDate != selected.releaseDate) continue;
      if (_normalizeTitle(result.title) != selectedBase) continue;
      variants.addAll(_candidateStreamLanguages(result));
    }
    if (variants.isNotEmpty) return _dedupe(variants);

    final detailTitle = details['title']?.toString() ?? '';
    final detailTitleLanguage = _titleLanguage(detailTitle);
    if (detailTitleLanguage != null && detailTitleLanguage.isNotEmpty) {
      return _languagesFrom(detailTitleLanguage);
    }

    final detailLanguages = _languagesFrom(_languageFrom(details) ?? '');
    return detailLanguages.length == 1 ? detailLanguages : const [];
  }

  static List<String> _candidateStreamLanguages(_MovieBoxSearchResult result) {
    final titleLanguage = _titleLanguage(result.title);
    if (titleLanguage != null && titleLanguage.isNotEmpty) {
      return _languagesFrom(titleLanguage);
    }

    final languages = _languagesFrom(result.language);
    return languages.length == 1 ? languages : const [];
  }

  static String _selectAudioLabel(List<String> languages, String? preferred) {
    if (languages.isEmpty) return '';
    final target = preferred?.trim();
    if (target != null && target.isNotEmpty) {
      for (final language in languages) {
        if (_languageMatches(language, target)) return language;
      }
    }
    return languages.first;
  }

  static int _titleScore(String candidate, String target) {
    final a = _normalizeTitle(candidate);
    final b = _normalizeTitle(target);
    if (a == b) return 20;
    if (a.contains(b) || b.contains(a)) return 10;
    return 0;
  }

  static int _qualityHint(_MovieBoxSearchResult result) => _resolution(result.title);

  static String? _languageFrom(Map<String, dynamic> details) {
    for (final key in const ['language', 'lang', 'subjectLanguage']) {
      final value = details[key]?.toString().trim();
      if (value != null && value.isNotEmpty) return value;
    }
    return _titleLanguage(details['title']?.toString() ?? '');
  }

  static String? _titleLanguage(String title) {
    final match = RegExp(r'\[([^\]]+)\]').firstMatch(title);
    return match?.group(1)?.trim();
  }

  static bool _languageMatches(String language, String preferred) {
    final source = language.toLowerCase();
    final target = preferred.toLowerCase();
    return source == target || source.contains(target) || target.contains(source);
  }

  static String? _firstUrl(Map<String, dynamic>? data) {
    if (data == null) return null;
    for (final key in const [
      'url',
      'resourceLink',
      'streamUrl',
      'link',
      'file',
      'videoUrl',
      'captionUrl',
      'subtitleUrl',
      'subtitlingUrl',
    ]) {
      final value = data[key]?.toString().trim();
      if (value != null && value.startsWith('http')) return value;
    }
    return null;
  }

  static String? _qualityLabel(Map<String, dynamic>? data) {
    if (data == null) return null;
    for (final key in const [
      'resolution',
      'quality',
      'qualityName',
      'description',
      'title',
    ]) {
      final value = data[key]?.toString().trim();
      if (value != null && value.isNotEmpty) return value;
    }
    return null;
  }

  static bool _isHls(String url) => Uri.parse(url).path.endsWith('.m3u8');

  static int _resolution(String quality) {
    final match = RegExp(r'(\d{3,4})').firstMatch(quality);
    return match == null ? 0 : int.tryParse(match.group(1)!) ?? 0;
  }

  static List<String> _dedupe(Iterable<String> values) {
    final seen = <String>{};
    final deduped = <String>[];
    for (final value in values) {
      final trimmed = value.trim();
      if (trimmed.isNotEmpty && seen.add(trimmed.toLowerCase())) {
        deduped.add(trimmed);
      }
    }
    return deduped;
  }

  static String _normalizeTitle(String value) => value
      .toLowerCase()
      .replaceAll(RegExp(r'\[[^\]]+\]'), '')
      .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
      .trim();

  static Map<String, dynamic>? _asMap(Object? value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) return Map<String, dynamic>.from(value);
    return null;
  }

  static List<Object?> _asList(Object? value) {
    if (value is List) return value;
    return const [];
  }

  static String _generateDeviceId() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    return bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
  }
}

class _MovieBoxSearchResult {
  const _MovieBoxSearchResult({
    required this.subjectId,
    required this.title,
    required this.language,
    required this.releaseDate,
    required this.subjectType,
  });

  final String subjectId;
  final String title;
  final String language;
  final String releaseDate;
  final int subjectType;

  static _MovieBoxSearchResult? fromJson(Object? raw) {
    final json = MovieBoxScraperService._asMap(raw);
    final subjectId = json?['subjectId']?.toString() ?? json?['id']?.toString() ?? json?['subject_id']?.toString();
    final title = json?['title']?.toString().trim() ?? json?['name']?.toString().trim() ?? json?['subjectTitle']?.toString().trim();
    if (subjectId == null || subjectId.isEmpty || title == null || title.isEmpty) {
      return null;
    }
    return _MovieBoxSearchResult(
      subjectId: subjectId,
      title: title,
      language: json?['language']?.toString().trim() ??
          json?['lang']?.toString().trim() ??
          MovieBoxScraperService._titleLanguage(title) ??
          '',
      releaseDate: json?['releaseDate']?.toString().trim() ?? '',
      subjectType: int.tryParse(json?['subjectType']?.toString() ?? json?['type']?.toString() ?? '') ?? 0,
    );
  }
}
