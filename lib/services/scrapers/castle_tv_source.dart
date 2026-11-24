import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:nivio/models/search_result.dart';
import 'package:pointycastle/export.dart';

/// CastleTV movie and episode lookup with one result per audio/quality variant.
class CastleTvSource {
  CastleTvSource({Dio? client})
    : _client =
          client ??
          Dio(
            BaseOptions(
              baseUrl: _origin,
              connectTimeout: const Duration(seconds: 8),
              receiveTimeout: const Duration(seconds: 10),
              validateStatus: (status) => status == 200,
            ),
          ),
      _ownsClient = client == null;

  static const _origin = 'https://api.hlowb.com';
  static const _appName = 'com.external.castle';
  static const _clientIdentity = {
    'channel': 'IndiaA',
    'clientType': 1,
    'lang': 'en-US',
  };
  static const _clientFingerprint = 'ED0955EB04E67A1D9F3305B95454FED485261475';
  static const _responseKeySuffix = 'T!BgJB';
  static const _mediaHeaders = {'Referer': '$_origin/', 'Origin': _origin};
  static final _nonWords = RegExp(r'[^\p{L}\p{N}]+', unicode: true);
  static final _knownHeight = RegExp(r'\d{3,4}p', caseSensitive: false);

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
    final title = (media.title ?? media.name ?? '').trim();
    if (title.isEmpty || (!movie && (season < 0 || episode < 1))) return [];
    final key = await _fetchResponseKey();
    if (key == null) return [];

    final search = await _get('/film-api/v1.1.0/movie/searchByKeyword', key, {
      'keyword': title,
      'mode': 1,
      'page': 1,
      'size': 30,
    });
    final rows = _rows(search['rows']);
    final candidates = rows.isEmpty ? _rows(search['list']) : rows;
    final normalizedTitle = _normalize(title);
    final matching = candidates.where((candidate) {
      final kind = _int(candidate['movieType']);
      return (movie ? kind == 2 : kind == 1 || kind == 3 || kind == 5) &&
          [candidate['title'], candidate['originalTitle']]
              .whereType<String>()
              .any((name) => _normalize(name) == normalizedTitle);
    });
    final wantedYear = _int(
      (media.releaseDate ?? media.firstAirDate)?.split('-').first,
    );
    final dated = matching.where(
      (candidate) => _year(candidate['publishTime']) == wantedYear,
    );
    final undated = matching.where(
      (candidate) => _year(candidate['publishTime']) == null,
    );
    final candidate = wantedYear == null
        ? matching.singleOrNull
        : dated.singleOrNull ?? (dated.isEmpty ? undated.singleOrNull : null);
    final id = _int(candidate?['id']);
    if (id == null) return [];

    var details = await _details(id, key);
    var movieId = id;
    if (!movie) {
      final seasons = _rows(details['seasons']);
      final current = _int(details['seasonNumber']);
      if (current != season &&
          (current != null || seasons.isNotEmpty || season != 1)) {
        final target = seasons
            .where((row) => _int(row['number']) == season)
            .singleOrNull;
        final targetId = _int(target?['movieId']);
        if (targetId == null) return [];
        movieId = targetId;
        if (targetId != id) details = await _details(targetId, key);
      }
    }
    final episodes = _rows(details['episodes']);
    final item = movie
        ? episodes.firstOrNull
        : episodes.where((row) => _int(row['number']) == episode).singleOrNull;
    final episodeId = _int(item?['id']);
    if (item == null || episodeId == null) return [];

    final audio = _rows(item['tracks']);
    final individual = audio.where(
      (track) => track['existIndividualVideo'] == true,
    );
    final sharedAudio = <String>{
      for (final track in audio)
        if (_text(track['languageName'] ?? track['abbreviate'])
            case final lang?)
          lang,
    };
    final tracks = individual.isNotEmpty
        ? individual.toList()
        : [
            audio.where((row) => row['isDefault'] == true).firstOrNull ??
                audio.firstOrNull,
          ];
    final advertised = _rows(item['videos']);
    final resolutions = {
      for (final quality in advertised)
        if (quality['premiumProPermission'] != true)
          if (_int(quality['resolution']) case final id?)
            id: _quality(quality['resolutionDescription']),
      if (advertised.isEmpty)
        _int(item['playResolution']) ?? 2: 'Unknown quality',
    };
    final results = await Future.wait([
      for (final track in tracks)
        for (final option in resolutions.entries)
          _resolveTrack(
            key,
            movieId,
            episodeId,
            track,
            languages: individual.isNotEmpty
                ? _text(track?['languageName'] ?? track?['abbreviate'])
                : (sharedAudio.isEmpty ? null : sharedAudio.join(' / ')),
            quality: option.value,
            resolution: option.key,
          ),
    ]);
    final seen = <(String?, String?, String?)>{};
    return [
      for (final trackResults in results)
        for (final choice in trackResults)
          if (seen.add((
            choice['url'] as String?,
            choice['quality'] as String?,
            choice['language'] as String?,
          )))
            choice,
    ];
  }

  Future<List<Map<String, dynamic>>> _resolveTrack(
    Uint8List key,
    int movie,
    int episode,
    Map<String, dynamic>? track, {
    required String? languages,
    required String quality,
    required int resolution,
  }) async {
    final languageId = _int(track?['languageId']);
    Map<String, dynamic> video;
    try {
      final response = await _client.post<String>(
        '/film-api/v2.0.1/movie/getVideo2',
        queryParameters: {..._clientIdentity, 'packageName': _appName},
        options: Options(
          responseType: ResponseType.plain,
          contentType: Headers.jsonContentType,
        ),
        data: {
          'mode': '1',
          'appMarket': 'GuanWang',
          'clientType': '1',
          'woolUser': 'false',
          'apkSignKey': _clientFingerprint,
          'androidVersion': '13',
          if (languageId != null) 'languageId': '$languageId',
          'movieId': '$movie',
          'episodeId': '$episode',
          'isNewUser': 'true',
          'resolution': '$resolution',
          'packageName': _appName,
        },
      );
      video = _decodeData(response.data, key);
    } on DioException {
      return [];
    } on FormatException {
      return [];
    } on ArgumentError {
      return [];
    }
    final subtitles = [
      for (final caption in [
        ..._rows(video['subtitles']),
        ..._rows(track?['subtitles']),
      ])
        if (_playableUrl(caption['url']) case final url?)
          {
            'url': url,
            'lang':
                _text(caption['title'] ?? caption['abbreviate']) ?? 'Unknown',
          },
    ];
    return [
      for (final entry in [video, ..._rows(video['videos'])])
        if (entry['premiumProPermission'] != true)
          if (_playableUrl(
                entry['videoUrl'] ?? entry['url'] ?? entry['playUrl'],
              )
              case final url?)
            {
              'url': url,
              'title':
                  'Castle TV${languages == null ? '' : ' - $languages'} ${_quality(entry['resolutionDescription'], fallback: quality)}',
              'quality': _quality(
                entry['resolutionDescription'],
                fallback: quality,
              ),
              if (languages != null) 'language': languages,
              'headers': _mediaHeaders,
              'subtitles': subtitles,
            },
    ];
  }

  Future<Uint8List?> _fetchResponseKey() async {
    final response = await _client.get<Object?>(
      '/v0.1/system/getSecurityKey/1',
      queryParameters: _clientIdentity,
    );
    final data = _text(_map(response.data)['data']);
    if (data == null) return null;
    final key = Uint8List.fromList([
      ...base64Decode(data),
      ...utf8.encode(_responseKeySuffix),
    ]);
    return key.length == 16 ? key : null;
  }

  Future<Map<String, dynamic>> _details(int id, Uint8List key) =>
      _get('/film-api/v1.9.9/movie', key, {'movieId': id});

  Future<Map<String, dynamic>> _get(
    String path,
    Uint8List key,
    Map<String, Object> query,
  ) async {
    final response = await _client.get<String>(
      path,
      queryParameters: {..._clientIdentity, 'packageName': _appName, ...query},
      options: Options(responseType: ResponseType.plain),
    );
    return _decodeData(response.data, key);
  }

  static Map<String, dynamic> _decodeData(String? body, Uint8List key) {
    if (body == null || body.isEmpty) return {};
    final value = body.trim();
    // Service errors can be plain JSON even when success responses are encrypted.
    if (value.startsWith('{')) return _map(_map(jsonDecode(value))['data']);
    final cipher =
        PaddedBlockCipherImpl(PKCS7Padding(), CBCBlockCipher(AESEngine()))
          ..init(
            false,
            PaddedBlockCipherParameters<ParametersWithIV<KeyParameter>, Null>(
              ParametersWithIV<KeyParameter>(KeyParameter(key), key),
              null,
            ),
          );
    final clear = cipher.process(base64Decode(value));
    return _map(_map(jsonDecode(utf8.decode(clear)))['data']);
  }

  static Map<String, dynamic> _map(Object? value) =>
      value is Map<String, dynamic> ? value : const {};
  static List<Map<String, dynamic>> _rows(Object? value) => value is List
      ? value.whereType<Map<String, dynamic>>().toList()
      : const [];
  static String? _text(Object? value) =>
      value is String && value.trim().isNotEmpty ? value.trim() : null;
  static int? _int(Object? value) =>
      value is num ? value.toInt() : int.tryParse(value?.toString() ?? '');
  static String _normalize(String value) =>
      value.trim().toLowerCase().replaceAll(_nonWords, '');
  static int? _year(Object? value) {
    final ms = _int(value);
    if (ms == null || ms <= 0 || ms > 253402300799999) return null;
    return DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true).year;
  }

  static String _quality(
    Object? value, {
    String fallback = 'Unknown quality',
  }) =>
      _knownHeight.stringMatch(value?.toString() ?? '')?.toLowerCase() ??
      fallback;

  static String? _playableUrl(Object? raw) {
    final link = _text(raw);
    final url = link == null ? null : Uri.tryParse(link);
    if (url == null ||
        (url.scheme != 'http' && url.scheme != 'https') ||
        url.host.isEmpty ||
        url.userInfo.isNotEmpty)
      return null;
    return url.toString();
  }
}
