import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';

import '../../../shared/models/stream_result.dart';
import '../models/playback_request.dart';

class MovieBoxStreamProvider {
  MovieBoxStreamProvider({Dio? dio, String? deviceId})
    : _deviceId = deviceId ?? _generateDeviceId(),
      _dio =
          dio ??
          Dio(
            BaseOptions(
              baseUrl: _mainUrl,
              connectTimeout: const Duration(seconds: 15),
              receiveTimeout: const Duration(seconds: 20),
              validateStatus: (status) => status != null && status < 600,
              headers: const {'Accept': 'application/json'},
            ),
          );

  static const String providerName = 'MovieBox';
  static const String _mainUrl = 'https://api3.aoneroom.com';
  static const String _packageName = 'com.community.oneroom';
  static const int _versionCode = 50020042;
  static const String _versionName = '3.0.13.0325.03';
  static const String _brand = 'Samsung';
  static const String _model = 'SM-S918B';
  static const String _userAgent =
      'com.community.oneroom/$_versionCode (Linux; U; Android 13; en_US; '
      '$_brand; Build/TQ3A.230901.001; Cronet/145.0.7582.0)';
  static const String _defaultSecretEncoded =
      'NzZpUmwwN3MweFNOOWpxbUVXQXQ3OUVCSlp1bElRSXNWNjRGWnIyTw==';

  final Dio _dio;
  final String _deviceId;
  String? _token;

  Future<StreamResult?> resolve(PlaybackRequest request) async {
    if (!_supports(request)) return null;

    try {
      final token = await _anonymousToken();
      if (token == null || token.isEmpty) return null;

      final results = await _search(request.title, token);
      final candidates = _rankCandidates(results, request).take(6);
      for (final candidate in candidates) {
        final details = await _details(candidate.subjectId, token);
        if (details == null) continue;

        final sources = _sourcesFrom(details);
        if (sources.isEmpty) continue;

        final selected = _selectSource(sources, request.preferredQuality);
        final subtitles = _subtitlesFrom(details);
        final languages = _streamLanguagesFor(
          results: results,
          selected: candidate,
          details: details,
        );
        final selectedAudio = _selectAudioLabel(
          languages,
          request.preferredAudioTrack,
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
          headers: const {},
          sources: sources,
        );
      }
      return null;
    } on DioException {
      return null;
    } on FormatException {
      return null;
    } on ArgumentError {
      return null;
    }
  }

  bool _supports(PlaybackRequest request) =>
      request.mediaType == PlaybackMediaType.movie ||
      request.mediaType == PlaybackMediaType.unknown;

  Future<String?> _anonymousToken() async {
    final cached = _token;
    if (cached != null && cached.isNotEmpty) return cached;

    final path =
        '/wefeed-mobile-bff/tab/ranking-list?tabId=0&categoryType=4516404531735022304&page=1&perPage=1';
    final response = await _dio.get<String>(
      path,
      options: Options(
        responseType: ResponseType.plain,
        headers: _headers(
          method: 'GET',
          url: '$_mainUrl$path',
          accept: 'application/json',
          contentType: 'application/json',
        ),
      ),
    );
    if (response.statusCode != 200) return null;
    final xUser = response.headers.value('x-user');
    if (xUser == null || xUser.trim().isEmpty) return null;
    final token = _asMap(jsonDecode(xUser))?['token']?.toString();
    if (token == null || token.isEmpty) return null;
    _token = token;
    return token;
  }

  Future<List<_MovieBoxSearchResult>> _search(
    String title,
    String token,
  ) async {
    const path = '/wefeed-mobile-bff/subject-api/search/v2';
    final body = jsonEncode({'page': 1, 'perPage': 20, 'keyword': title});
    final response = await _dio.post<String>(
      path,
      data: body,
      options: Options(
        responseType: ResponseType.plain,
        contentType: 'application/json; charset=utf-8',
        headers: _headers(
          method: 'POST',
          url: '$_mainUrl$path',
          accept: 'application/json',
          contentType: 'application/json; charset=utf-8',
          body: body,
          token: token,
        ),
      ),
    );
    if (response.statusCode != 200 || response.data == null) return const [];
    final root = _asMap(jsonDecode(response.data!));
    final data = _asMap(root?['data']);
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
    final path = '/wefeed-mobile-bff/subject-api/get?subjectId=$subjectId';
    final response = await _dio.get<String>(
      path,
      options: Options(
        responseType: ResponseType.plain,
        headers: _headers(
          method: 'GET',
          url: '$_mainUrl$path',
          accept: 'application/json',
          contentType: 'application/json',
          token: token,
        ),
      ),
    );
    if (response.statusCode != 200 || response.data == null) return null;
    final root = _asMap(jsonDecode(response.data!));
    return _asMap(root?['data']);
  }

  Map<String, String> _headers({
    required String method,
    required String url,
    required String accept,
    required String contentType,
    String? body,
    String? token,
  }) {
    return {
      'user-agent': _userAgent,
      'accept': accept,
      'content-type': contentType,
      'connection': 'keep-alive',
      'x-client-token': _xClientToken(),
      'x-tr-signature': _signature(
        method: method,
        accept: accept,
        contentType: contentType,
        url: url,
        body: body,
      ),
      'x-client-info': _clientInfo(),
      'x-client-status': '0',
      if (token != null && token.isNotEmpty) 'authorization': 'Bearer $token',
    };
  }

  String _clientInfo() {
    return jsonEncode({
      'package_name': _packageName,
      'version_name': _versionName,
      'version_code': _versionCode,
      'os': 'android',
      'os_version': '13',
      'install_ch': 'ps',
      'device_id': _deviceId,
      'install_store': 'ps',
      'gaid': '1b2212c1-dadf-43c3-a0c8-bd6ce48ae22d',
      'brand': _brand,
      'model': _model,
      'system_language': 'en',
      'net': 'NETWORK_WIFI',
      'region': 'US',
      'timezone': 'Asia/Calcutta',
      'sp_code': '',
      'X-Play-Mode': '1',
      'X-Idle-Data': '1',
      'X-Family-Mode': '0',
      'X-Content-Mode': '0',
    });
  }

  static String _xClientToken() {
    final timestamp = DateTime.now().millisecondsSinceEpoch.toString();
    final reversed = timestamp.split('').reversed.join();
    return '$timestamp,${md5.convert(utf8.encode(reversed))}';
  }

  static String _signature({
    required String method,
    required String accept,
    required String contentType,
    required String url,
    String? body,
  }) {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final canonical = _canonical(
      method: method,
      accept: accept,
      contentType: contentType,
      url: url,
      body: body,
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
    String? body,
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
    final bodyBytes = body == null ? null : utf8.encode(body);
    final bodyHash = bodyBytes == null
        ? ''
        : md5.convert(bodyBytes.take(102400).toList()).toString();
    final bodyLength = bodyBytes?.length.toString() ?? '';
    return [
      method.toUpperCase(),
      accept,
      contentType,
      bodyLength,
      timestamp,
      bodyHash,
      canonicalUrl,
    ].join('\n');
  }

  List<_MovieBoxSearchResult> _rankCandidates(
    List<_MovieBoxSearchResult> results,
    PlaybackRequest request,
  ) {
    final sorted = [...results]
      ..sort((a, b) {
        final language = _languageScore(
          b,
          request.preferredAudioTrack,
        ).compareTo(_languageScore(a, request.preferredAudioTrack));
        if (language != 0) return language;
        final title = _titleScore(
          b.title,
          request.title,
        ).compareTo(_titleScore(a.title, request.title));
        if (title != 0) return title;
        return _qualityHint(b).compareTo(_qualityHint(a));
      });
    return sorted;
  }

  List<StreamSource> _sourcesFrom(Map<String, dynamic> details) {
    final sources = <StreamSource>[];
    for (final detector in _asList(details['resourceDetectors'])) {
      final detectorMap = _asMap(detector);
      for (final raw in _asList(detectorMap?['resolutionList'])) {
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
    sources.sort(
      (a, b) => _resolution(b.quality).compareTo(_resolution(a.quality)),
    );
    return sources;
  }

  List<SubtitleTrack> _subtitlesFrom(Map<String, dynamic> details) {
    final subtitles = <SubtitleTrack>[];
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
          SubtitleTrack(url: url, lang: map['lang']?.toString() ?? 'Unknown'),
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

  static int _languageScore(
    _MovieBoxSearchResult result,
    String? preferredAudio,
  ) {
    final preferred = preferredAudio?.trim();
    if (preferred == null || preferred.isEmpty) return 0;
    return _candidateStreamLanguages(
          result,
        ).any((language) => _languageMatches(language, preferred))
        ? 10
        : 0;
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

  static int _qualityHint(_MovieBoxSearchResult result) =>
      _resolution(result.title);

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
    return source == target ||
        source.contains(target) ||
        target.contains(source);
  }

  static String? _firstUrl(Map<String, dynamic>? data) {
    if (data == null) return null;
    for (final key in const [
      'url',
      'resourceLink',
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
    final json = MovieBoxStreamProvider._asMap(raw);
    final subjectId =
        json?['subjectId']?.toString() ??
        json?['id']?.toString() ??
        json?['subject_id']?.toString();
    final title =
        json?['title']?.toString().trim() ??
        json?['name']?.toString().trim() ??
        json?['subjectTitle']?.toString().trim();
    if (subjectId == null ||
        subjectId.isEmpty ||
        title == null ||
        title.isEmpty) {
      return null;
    }
    return _MovieBoxSearchResult(
      subjectId: subjectId,
      title: title,
      language:
          json?['language']?.toString().trim() ??
          json?['lang']?.toString().trim() ??
          MovieBoxStreamProvider._titleLanguage(title) ??
          '',
      releaseDate: json?['releaseDate']?.toString().trim() ?? '',
      subjectType:
          int.tryParse(
            json?['subjectType']?.toString() ?? json?['type']?.toString() ?? '',
          ) ??
          0,
    );
  }
}
