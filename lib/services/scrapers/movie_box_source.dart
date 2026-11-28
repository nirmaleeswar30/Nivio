import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:nivio/models/search_result.dart';

/// MovieBox's web catalog and playback API, using a provider-issued guest session.
class MovieBoxSource {
  MovieBoxSource({Dio? client, this.india = false})
    : _client =
          client ??
          Dio(BaseOptions(connectTimeout: const Duration(seconds: 8))),
      _ownsClient = client == null;

  static const _api = 'https://h5-api.aoneroom.com/wefeed-h5api-bff';
  static const _userAgent = 'Mozilla/5.0';
  static final _nonWords = RegExp(r'[^\p{L}\p{N}]+', unicode: true);
  static final _year = RegExp(r'^\d{4}');
  static final _languageSuffix = RegExp(r'\s*\[([^\[\]]+)\]\s*$');
  static final _detailSlug = RegExp(
    r'^[a-z0-9][a-z0-9_-]+$',
    caseSensitive: false,
  );
  static final _mediaTokenHeader = RegExp(r'^x-[\w-]+$', caseSensitive: false);

  final bool india;
  final Dio _client;
  final bool _ownsClient;

  static const _host = 'movie-box.co';
  String get _origin => 'https://$_host';
  String get _name => india ? 'MovieBox IN' : 'MovieBox';

  void close() {
    if (_ownsClient) _client.close(force: true);
  }

  Future<List<Map<String, dynamic>>> resolve(
    SearchResult media, {
    required int season,
    required int episode,
  }) async {
    final movie = media.mediaType == 'movie';
    if (!movie && media.mediaType != 'tv') return [];
    final title = _text(media.title ?? media.name);
    if (title == null || (!movie && (season < 0 || episode < 1))) return [];

    final indiaApi = india ? _MovieBoxIndiaApi(_client) : null;
    final session = indiaApi == null
        ? await _guestSession()
        : await indiaApi.guestSession();
    if (session == null) return [];
    final searchBody = {'keyword': title, 'page': 1, 'perPage': 20};
    final search = indiaApi == null
        ? _map(
            (await _request(
              '/subject/search',
              session: session,
              body: searchBody,
            )).data,
          )
        : _map(
            (await indiaApi.catalog(
              '/subject-api/search/v2',
              session: session,
              body: searchBody,
            )).data,
          );
    final name = _normalize(title);
    final date = _year.stringMatch(
      media.releaseDate ?? media.firstAirDate ?? '',
    );
    final rows = [
      ..._rows(search['items']),
      ..._rows(search['subjects']),
      for (final group in _rows(search['results'])) ...[
        ..._rows(group['subjects']),
        ..._rows(group['items']),
      ],
    ];
    final matches = rows.where((row) {
      final candidate = _text(row['title']);
      final year = _releaseYear(row);
      return candidate != null &&
          row['subjectType']?.toString() == (movie ? '1' : '2') &&
          row['hasResource'] != false &&
          _identifier(row['subjectId']) != null &&
          (date == null || year == null || year == date) &&
          (_normalize(candidate) == name ||
              _normalize(candidate.replaceFirst(_languageSuffix, '')) == name);
    }).toList();
    final dated = matches.where((row) => _releaseYear(row) == date).toList();
    final candidates = date != null && dated.isNotEmpty ? dated : matches;
    if (candidates.isEmpty) return [];
    final playSession = indiaApi == null ? session : await _guestSession();
    if (playSession == null) return [];
    final variants = <String, ({String path, String? language})>{};
    final subjects = await Future.wait([
      for (final row in candidates.take(6)) _subject(row, indiaApi, session),
    ]);
    final missingPaths =
        indiaApi != null && subjects.any((row) => _path(row) == null);
    final webRows = missingPaths
        ? await _webSubjects(searchBody, playSession)
        : const <String, Map<String, dynamic>>{};
    for (final row in subjects) {
      final id = _identifier(row['subjectId'])!;
      final webRow = webRows[id];
      final detailPath = _path(row) ?? (webRow == null ? null : _path(webRow));
      if (detailPath == null) continue;
      final language = _languageSuffix.firstMatch(row['title'] as String);
      final dubs = [..._rows(row['dubs']), ..._rows(webRow?['dubs'])];
      variants.putIfAbsent(
        id,
        () => (
          path: detailPath,
          language:
              _text(
                dubs
                    .where((dub) => _identifier(dub['subjectId']) == id)
                    .firstOrNull?['lanName'],
              ) ??
              language?.group(1),
        ),
      );
      for (final dub in dubs) {
        final dubId = _identifier(dub['subjectId']);
        final path = _text(dub['detailPath']);
        if (dubId != null && path != null) {
          variants.putIfAbsent(
            dubId,
            () => (path: path, language: _text(dub['lanName'])),
          );
        }
      }
    }
    final batches = await Future.wait([
      for (final variant in variants.entries.take(10))
        _streams(
          variant.key,
          variant.value.path,
          variant.value.language,
          movie ? 0 : season,
          movie ? 0 : episode,
          playSession,
        ),
    ]);
    final seen = <(String, String?)>{};
    return [
      for (final batch in batches)
        for (final stream in batch)
          if (seen.add((
            stream['url'] as String,
            stream['language'] as String?,
          )))
            stream,
    ];
  }

  Future<String?> _guestSession() async {
    for (var attempt = 0; attempt < 2; attempt++) {
      try {
        final home = await _request('/home');
        return _guestToken(home.headers.value('x-user'));
      } on DioException catch (error) {
        final status = error.response?.statusCode;
        if (attempt == 1 || (status != null && status < 500)) rethrow;
      }
    }
    return null;
  }

  Future<Map<String, Map<String, dynamic>>> _webSubjects(
    Map<String, dynamic> body,
    String session,
  ) async {
    try {
      final search = await _request(
        '/subject/search',
        session: session,
        body: body,
      );
      return {
        for (final row in _rows(_map(search.data)['items']))
          if (_identifier(row['subjectId']) case final id?) id: row,
      };
    } on DioException {
      return const {};
    }
  }

  Future<Map<String, dynamic>> _subject(
    Map<String, dynamic> row,
    _MovieBoxIndiaApi? api,
    String session,
  ) async {
    if (api == null || _path(row) != null) return row;
    try {
      final reply = await api.catalog(
        '/subject-api/get',
        query: {'subjectId': _identifier(row['subjectId'])!},
        session: session,
      );
      final data = _map(reply.data);
      return {
        ...row,
        ...data,
        ..._map(data['subject']),
        'subjectId': row['subjectId'],
        'title': row['title'],
      };
    } on DioException {
      return row;
    }
  }

  static String? _path(Map<String, dynamic> row) {
    final explicit = _text(row['detailPath']);
    if (explicit != null) return explicit;
    for (final path in [row['detailUrl'], row['playUrl']].whereType<String>()) {
      final uri = Uri.tryParse(path);
      if (uri == null) continue;
      final slug =
          uri.queryParameters['detailPath'] ?? uri.pathSegments.lastOrNull;
      if (slug != null &&
          _detailSlug.hasMatch(slug) &&
          (uri.queryParameters.containsKey('detailPath') ||
              uri.pathSegments.contains('movies') ||
              uri.pathSegments.contains('tv-shows'))) {
        return slug;
      }
    }
    return null;
  }

  Future<List<Map<String, dynamic>>> _streams(
    String id,
    String path,
    String? audio,
    int season,
    int episode,
    String session,
  ) async {
    try {
      final referer = Uri(
        scheme: 'https',
        host: _host,
        pathSegments: ['spa', 'videoPlayPage', 'movies', path],
        queryParameters: {
          'id': id,
          'type': '/movie/detail',
          'detailSe': '$season',
          'detailEp': '$episode',
          'lang': 'en',
        },
      ).toString();
      final response = await _request(
        '/subject/play',
        session: session,
        referer: referer,
        query: {
          'subjectId': id,
          'detailPath': path,
          'se': season,
          'ep': episode,
          if (india) ...{
            'streamSignType': 1,
            'supportCodecs[hevc]': 1,
            'supportCodecs[h264]': 1,
          },
        },
      );
      final data = _map(response.data);
      final sources = [
        ..._rows(data['streams']),
        ..._rows(data['hls']),
      ].where((row) => row['vipLocked'] != true && _url(row['url']) != null);
      if (sources.isEmpty) return [];
      final captionEntry = sources
          .where((row) => _identifier(row['id']) != null)
          .firstOrNull;
      final subtitles = await _captions(
        captionEntry,
        id: id,
        path: path,
        referer: referer,
        session: session,
      );
      return [
        for (final source in sources)
          _choice(source, audio, referer, subtitles),
      ];
    } on DioException {
      return [];
    }
  }

  Future<List<Map<String, String>>> _captions(
    Map<String, dynamic>? stream, {
    required String id,
    required String path,
    required String referer,
    required String session,
  }) async {
    final streamId = _identifier(stream?['id']);
    if (streamId == null) return [];
    try {
      final result = await _request(
        '/subject/caption',
        query: {
          'id': streamId,
          'format': stream?['format'] ?? 'MP4',
          'subjectId': id,
          'detailPath': path,
        },
        referer: referer,
        session: session,
        receiveTimeout: const Duration(seconds: 3),
      );
      return [
        for (final row in _rows(_map(result.data)['captions'] ?? result.data))
          if (_url(row['url']) case final url?)
            {
              'url': url,
              'lang': _text(row['lanName'] ?? row['lan']) ?? 'Unknown',
            },
      ];
    } on DioException {
      return [];
    }
  }

  Map<String, dynamic> _choice(
    Map<String, dynamic> row,
    String? audio,
    String referer,
    List<Map<String, String>> subtitles,
  ) {
    final resolution = int.tryParse(row['resolutions']?.toString() ?? '');
    final quality = resolution == null || resolution <= 0
        ? 'Unknown quality'
        : '${resolution}p';
    final language = _text(row['lanName']) ?? audio;
    final codec = _text(row['codecName']);
    final format = _text(row['format'])?.toUpperCase();
    final url = _url(row['url'])!;
    final token = _text(row['signCookie']);
    final header = _text(row['signHeaderKey']) ?? 'X-MB-Token';
    return {
      'url': url,
      'title': [_name, quality, ?language, ?codec].join(' · '),
      'quality': quality,
      if (language != null) 'language': language,
      if (format == 'HLS' || format == 'M3U8') 'type': 'hls',
      'sizeBytes': row['size'],
      'subtitles': subtitles,
      'headers': {
        'Referer': referer,
        'Origin': _origin,
        'User-Agent': _userAgent,
        if (token != null &&
            Uri.parse(url).scheme == 'https' &&
            _mediaTokenHeader.hasMatch(header))
          header: token,
      },
    };
  }

  Future<({Object? data, Headers headers})> _request(
    String path, {
    Map<String, Object?> query = const {},
    Map<String, dynamic>? body,
    String? referer,
    String? session,
    Duration receiveTimeout = const Duration(seconds: 8),
  }) async {
    final options = Options(
      method: body == null ? 'GET' : 'POST',
      sendTimeout: const Duration(seconds: 8),
      receiveTimeout: receiveTimeout,
      followRedirects: false,
      headers: {
        'Accept': 'application/json',
        'User-Agent': _userAgent,
        'Origin': _origin,
        'Referer': referer ?? '$_origin/',
        if (session != null) 'Authorization': 'Bearer $session',
      },
    );
    final result = await _client.request<Object?>(
      '$_api$path',
      queryParameters: {'host': _host, ...query},
      options: options,
      data: body,
    );
    final envelope = _map(result.data);
    return (data: envelope['data'], headers: result.headers);
  }

  static String? _guestToken(String? header) {
    if (header == null || header.isEmpty) return null;
    try {
      return _text(_map(jsonDecode(header))['token']);
    } on FormatException {
      return null;
    }
  }

  static String? _releaseYear(Map<String, dynamic> row) =>
      _year.stringMatch(row['releaseDate']?.toString() ?? '');

  static String _normalize(String value) =>
      value.toLowerCase().replaceAll(_nonWords, '');

  static Map<String, dynamic> _map(Object? value) =>
      value is Map<String, dynamic> ? value : const {};

  static Iterable<Map<String, dynamic>> _rows(Object? value) =>
      value is List ? value.whereType<Map<String, dynamic>>() : const [];

  static String? _text(Object? value) =>
      value is String && value.trim().isNotEmpty ? value.trim() : null;

  static String? _identifier(Object? value) =>
      value is int ? value.toString() : _text(value);

  static String? _url(Object? value) {
    final raw = _text(value);
    final uri = raw == null ? null : Uri.tryParse(raw);
    return uri != null &&
            (uri.scheme == 'https' || uri.scheme == 'http') &&
            uri.host.isNotEmpty &&
            uri.userInfo.isEmpty
        ? raw
        : null;
  }
}

/// MovieBox IN's regional catalog issues a separate guest session from the
/// shared web player.
class _MovieBoxIndiaApi {
  _MovieBoxIndiaApi(this._client);

  static const _userAgent =
      'com.community.mbox.in/50020042 (Linux; U; Android 16; en_IN; '
      'sdk_gphone64_x86_64; Build/BP22.250325.006; Cronet/133.0.6876.3)';
  static final _signer = Hmac(
    md5,
    base64Decode(
      ascii.decode(
        base64Decode(
          'NzZpUmwwN3MweFNOOWpxbUVXQXQ3OUVCSlp1bElRSXNWNjRGWnIyTw==',
        ),
      ),
    ),
  );
  static final _random = Random.secure();
  final Dio _client;
  final String _deviceId = List.generate(
    16,
    (_) => _random.nextInt(256).toRadixString(16).padLeft(2, '0'),
  ).join();

  Future<String?> guestSession() async {
    for (final host in ['apig.inmoviebox.com', 'api3.aoneroom.com']) {
      try {
        final response = await request(
          host,
          '/tab/ranking-list',
          query: {
            'tabId': '0',
            'categoryType': '4516404531735022304',
            'page': '1',
            'perPage': '1',
          },
        );
        final token = MovieBoxSource._guestToken(
          response.headers.value('x-user'),
        );
        if (token != null) return token;
      } on DioException {
        continue;
      }
    }
    return null;
  }

  Future<({Object? data, Headers headers})> catalog(
    String path, {
    Map<String, String> query = const {},
    Map<String, Object>? body,
    required String session,
  }) async {
    try {
      return await request(
        'api3.aoneroom.com',
        path,
        query: query,
        body: body,
        session: session,
      );
    } on DioException catch (error) {
      final status = error.response?.statusCode;
      if (status != null && status < 500) rethrow;
    }
    return request(
      'apig.inmoviebox.com',
      path,
      query: query,
      body: body,
      session: session,
    );
  }

  Future<({Object? data, Headers headers})> request(
    String host,
    String path, {
    Map<String, String> query = const {},
    Map<String, Object>? body,
    String? session,
  }) async {
    final uri = Uri.https(host, '/wefeed-mobile-bff$path', query);
    final method = body == null ? 'GET' : 'POST';
    final type = body == null
        ? Headers.jsonContentType
        : 'application/json; charset=utf-8';
    final payload = body == null ? null : jsonEncode(body);
    final bytes = payload == null ? null : utf8.encode(payload);
    final time = DateTime.now().millisecondsSinceEpoch.toString();
    final keys = query.keys.toList()..sort();
    final canonical = [
      method,
      Headers.jsonContentType,
      type,
      bytes?.length ?? '',
      time,
      bytes == null ? '' : md5.convert(bytes),
      '${uri.path}${keys.isEmpty ? '' : '?${keys.map((key) => '$key=${query[key]}').join('&')}'}',
    ].join('\n');
    final signature = base64Encode(
      _signer.convert(utf8.encode(canonical)).bytes,
    );
    final clockHash = md5.convert(time.codeUnits.reversed.toList());
    final response = await _client.requestUri<Object?>(
      uri,
      data: payload,
      options: Options(
        method: method,
        contentType: type,
        followRedirects: false,
        sendTimeout: const Duration(seconds: 8),
        receiveTimeout: const Duration(seconds: 8),
        headers: {
          'Accept': Headers.jsonContentType,
          'User-Agent': _userAgent,
          'X-Client-Token': '$time,$clockHash',
          'X-Tr-Signature': '$time|2|$signature',
          'X-Client-Status': '0',
          'X-Client-Info': jsonEncode({
            'package_name': 'com.community.mbox.in',
            'version_name': '3.0.03.0529.03',
            'version_code': 50020042,
            'device_id': _deviceId,
            'os': 'android',
            'os_version': '16',
            'region': 'IN',
            'system_language': 'en',
          }),
          if (session != null) 'Authorization': 'Bearer $session',
        },
      ),
    );
    return (
      data: MovieBoxSource._map(response.data)['data'],
      headers: response.headers,
    );
  }
}
