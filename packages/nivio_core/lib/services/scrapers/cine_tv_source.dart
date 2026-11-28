import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:nivio/models/search_result.dart';
import 'package:nivio/services/public_web_client.dart';
import 'package:pointycastle/export.dart' hide Digest;

/// Dart client for CineTv's guest catalog and playback API.
class CineTvSource {
  CineTvSource({Dio? client})
    : _client =
          client ??
          Dio(
            BaseOptions(
              connectTimeout: const Duration(seconds: 8),
              receiveTimeout: const Duration(seconds: 9),
            ),
          ),
      _ownsClient = client == null;

  static const _origin = 'https://filmin.ajfysu.com';
  static const _userAgent = 'okhttp/4.11.0';
  static final _nonWords = RegExp(r'[^\p{L}\p{N}]+', unicode: true);
  static final _year = RegExp(r'^\d{4}');
  static final _season = RegExp(r'\d+');
  static final _random = Random.secure();
  // The published CineTv client uses these protocol constants for its
  // device handshake and encrypted API responses.
  static final _requestSalt = utf8.decode(
    _decrypt(
      DESedeEngine(),
      'MxASAkl/yHTGg+/Tw1R7u96nGqkWsOZ2',
      'dsawdf634eebGFHITR5UT9kS',
      '32456738',
    ),
  );

  final Dio _client;
  final bool _ownsClient;
  final String _device = List.generate(
    8,
    (_) => _random.nextInt(256).toRadixString(16).padLeft(2, '0'),
  ).join();

  void close() {
    if (_ownsClient) _client.close(force: true);
  }

  Future<List<Map<String, dynamic>>> resolve(
    SearchResult media, {
    required int season,
    required int episode,
  }) async {
    final movie = media.mediaType == 'movie';
    final title = (media.title ?? media.name ?? '').trim();
    if (title.isEmpty ||
        (!movie && (media.mediaType != 'tv' || season < 1 || episode < 1))) {
      return [];
    }
    final init = await _post('/api/public/init', {
      'invited_by': '',
      'is_install': '1',
    });
    final token = _map(_map(init['result'])['user_info'])['token'];
    if (token is! String || token.isEmpty) return [];
    final search = await _post('/api/search/result', {
      'kw': title,
      'pn': '1',
    }, token: token);
    final year = _year.stringMatch(
      media.releaseDate ?? media.firstAirDate ?? '',
    );
    final matches = _rows(search['result']).where((row) {
      final candidateYear = _year.stringMatch('${row['vod_year']}');
      return row['type_pid'].toString() == (movie ? '1' : '2') &&
          [row['vod_name'], row['vod_en']].whereType<String>().any(
            (name) => _normalize(name) == _normalize(title),
          ) &&
          (year == null || candidateYear == null || candidateYear == year);
    }).toList();
    final dated = matches.where(
      (row) => _year.stringMatch('${row['vod_year']}') == year,
    );
    final id = _id((dated.firstOrNull ?? matches.firstOrNull)?['id']);
    if (id == null) return [];

    var details = await _details(id, token);
    var playbackId = id;
    if (!movie) {
      final seasons = _rows(details['series_info']);
      if (seasons.isNotEmpty) {
        final target = seasons
            .where(
              (row) => _season.stringMatch('${row['series']}') == '$season',
            )
            .firstOrNull;
        final targetId = _id(target?['vod_id']);
        if (targetId == null) return [];
        if (targetId != id) {
          playbackId = targetId;
          details = await _details(playbackId, token);
        }
      } else if (season != 1) {
        return [];
      }
    }

    final audioOptions = _rows(details['audio_type_option']);
    final alternates = await Future.wait([
      for (final option in audioOptions.take(6))
        if (int.tryParse('${option['type']}') case final type? when type > 0)
          _details(playbackId, token, audio: type).then(
            (data) => (data, option['type_name']?.toString()),
            onError: (Object _) => (const <String, dynamic>{}, null),
          ),
    ]);
    final seen = <String>{};
    return [
      for (final (data, language) in [(details, null), ...alternates])
        if (_episode(data, movie ? null : episode) case final row?)
          if ((_playbackUrl(row['vod_url']) ?? _playbackUrl(row['down_url']))
              case final url?)
            if (seen.add(url))
              {
                'url': url,
                'title': ['CineTv', ?language].join(' · '),
                if (language != null) 'language': language,
                'headers': const {
                  'Referer': '$_origin/',
                  'User-Agent': _userAgent,
                },
              },
    ];
  }

  Future<Map<String, dynamic>> _details(
    String id,
    String token, {
    int audio = 0,
  }) async {
    final time = DateTime.now().millisecondsSinceEpoch.toString();
    final response = await _post(
      '/api/vod/info_new',
      {
        'sign': _md5('Zox882LYjEn4Rqpa$_device$id$time').toUpperCase(),
        'vod_id': id,
        'cur_time': time,
        'audio_type': '$audio',
      },
      token: token,
      timestamp: time,
    );
    return _map(response['result']);
  }

  Future<Map<String, dynamic>> _post(
    String path,
    Map<String, String> data, {
    String token = '',
    String? timestamp,
  }) async {
    final time = timestamp ?? DateTime.now().millisecondsSinceEpoch.toString();
    final response = await _client.post<String>(
      '$_origin$path',
      data: data,
      options: Options(
        responseType: ResponseType.plain,
        contentType: Headers.formUrlEncodedContentType,
        followRedirects: false,
        headers: {
          'androidid': _device,
          'app_id': 'filmin',
          'app_language': 'en',
          'channel_code': 'filmin_sh_1000',
          'cur_time': time,
          'device_id': _device,
          'en_al': '0',
          'gaid': '',
          'is_display': 'GMT+05:30',
          'is_language': 'en',
          'is_vvv': '0',
          'mob_mfr': 'Google',
          'mobmodel': 'Pixel 7',
          'package_name': 'com.dramarush.shortin',
          'sign': _md5('$_requestSalt$_device$time').toUpperCase(),
          'sys_platform': '2',
          'sysrelease': '13',
          'token': token,
          'User-Agent': _userAgent,
          'version': '30000',
        },
      ),
    );
    final body = response.data?.trim() ?? '';
    if (body.startsWith('{')) return _map(jsonDecode(body));
    if (body.isEmpty) return {};
    final bytes = _decrypt(
      AESEngine(),
      body,
      '0123456789123456',
      '2015030120123456',
    );
    final clear = bytes.length > 2 && bytes[0] == 31 && bytes[1] == 139
        ? gzip.decode(bytes)
        : bytes;
    return _map(jsonDecode(utf8.decode(clear)));
  }

  static Map<String, dynamic>? _episode(
    Map<String, dynamic> data,
    int? number,
  ) {
    final episodes = _rows(data['vod_collection']);
    return number == null
        ? episodes.firstOrNull
        : episodes
              .where((row) => '${row['collection']}' == '$number')
              .firstOrNull;
  }

  static String? _playbackUrl(Object? value) {
    final uri = value is String ? Uri.tryParse(value.trim()) : null;
    return uri == null || !isPublicWebUrl(uri) ? null : uri.toString();
  }

  static const _downloadPrefix = 'cinetv|||';

  /// A download URL that [freshDownloadUrl] signs again for every request,
  /// since a signature only lasts a minute.
  static String downloadUrl(Uri uri) => '$_downloadPrefix$uri';

  /// The URL to request now for [url]; other URLs pass through.
  static String freshDownloadUrl(String url) {
    if (!url.startsWith(_downloadPrefix)) return url;
    final uri = Uri.tryParse(url.substring(_downloadPrefix.length));
    return uri == null ? url : signPlaybackUrl(uri).toString();
  }

  static Uri signPlaybackUrl(Uri uri) {
    final expires = (DateTime.now().millisecondsSinceEpoch ~/ 1000 + 60)
        .toRadixString(16);
    return uri.replace(
      queryParameters: {
        ...uri.queryParameters,
        'wsTime': expires,
        'wsSecret': _md5('00b5f05c40b4f1d91dbc9b3fd8a059ef${uri.path}$expires'),
      },
    );
  }

  static Uint8List _decrypt(
    BlockCipher engine,
    String data,
    String key,
    String iv,
  ) {
    final cipher = PaddedBlockCipherImpl(PKCS7Padding(), CBCBlockCipher(engine))
      ..init(
        false,
        PaddedBlockCipherParameters<ParametersWithIV<KeyParameter>, Null>(
          ParametersWithIV(KeyParameter(utf8.encode(key)), utf8.encode(iv)),
          null,
        ),
      );
    return cipher.process(base64Decode(data));
  }

  static String _md5(String value) =>
      md5.convert(utf8.encode(value)).toString();
  static String _normalize(String name) =>
      name.toLowerCase().replaceAll(_nonWords, '');
  static Map<String, dynamic> _map(Object? value) =>
      value is Map<String, dynamic> ? value : const {};
  static Iterable<Map<String, dynamic>> _rows(Object? value) =>
      value is List ? value.whereType<Map<String, dynamic>>() : const [];
  static String? _id(Object? value) {
    final id = int.tryParse('$value');
    return id == null || id <= 0 ? null : '$id';
  }
}
