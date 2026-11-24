import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:nivio/models/search_result.dart';

/// MovieBox's web catalog and playback API, using a provider-issued guest session.
class MovieBoxSource {
  MovieBoxSource({Dio? client})
    : _client =
          client ??
          Dio(BaseOptions(connectTimeout: const Duration(seconds: 8))),
      _ownsClient = client == null;

  static const _host = 'movie-box.co';
  static const _origin = 'https://$_host';
  static const _api = 'https://h5-api.aoneroom.com/wefeed-h5api-bff';
  static const _userAgent = 'Mozilla/5.0';
  static final _nonWords = RegExp(r'[^\p{L}\p{N}]+', unicode: true);
  static final _year = RegExp(r'^\d{4}');
  static final _mediaTokenHeader = RegExp(r'^x-[\w-]+$', caseSensitive: false);

  final Dio _client;
  final bool _ownsClient;

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

    final home = await _request('/home');
    final session = _guestToken(home.headers.value('x-user'));
    if (session == null) return [];
    final search = await _request(
      '/subject/search',
      session: session,
      body: {'keyword': title, 'page': 1, 'perPage': 20},
    );
    final name = _normalize(title);
    final matches = _rows(_map(search.data)['items']).where((row) {
      return row['subjectType']?.toString() == (movie ? '1' : '2') &&
          [
            row['title'],
            row['postTitle'],
          ].whereType<String>().any((value) => _normalize(value) == name);
    }).toList();
    final date = _year.stringMatch(
      media.releaseDate ?? media.firstAirDate ?? '',
    );
    final dated = matches.where((row) => _releaseYear(row) == date);
    final undated = matches.where((row) => _releaseYear(row) == null);
    final match = date == null
        ? matches.singleOrNull
        : dated.singleOrNull ?? (dated.isEmpty ? undated.singleOrNull : null);
    final id = _identifier(match?['subjectId']);
    final path = _text(match?['detailPath']);
    if (id == null || path == null) return [];

    final dubs = _rows(match?['dubs']);
    final variants = <String, ({String path, String? language})>{
      id: (
        path: path,
        language: _text(
          dubs
              .where((row) => _identifier(row['subjectId']) == id)
              .firstOrNull?['lanName'],
        ),
      ),
      for (final dub in dubs)
        if (_identifier(dub['subjectId']) case final dubId?)
          if (dubId != id && _text(dub['detailPath']) != null)
            dubId: (
              path: _text(dub['detailPath'])!,
              language: _text(dub['lanName']),
            ),
    };
    final batches = await Future.wait([
      for (final variant in variants.entries)
        _streams(
          variant.key,
          variant.value.path,
          variant.value.language,
          movie ? 0 : season,
          movie ? 0 : episode,
          session,
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

  static Map<String, dynamic> _choice(
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
      'title': ['MovieBox', quality, ?language, ?codec].join(' · '),
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
