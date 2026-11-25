import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:html/parser.dart' as html;
import 'package:nivio/models/search_result.dart';
import 'package:nivio/models/stream_result.dart';
import 'package:nivio/services/public_web_client.dart';
import 'package:nivio/services/skip_times_models.dart';
import 'package:pointycastle/export.dart';

class AnikotoSource {
  AnikotoSource({Dio? client})
    : _client =
          client ??
          Dio(
            BaseOptions(
              connectTimeout: const Duration(seconds: 5),
              receiveTimeout: const Duration(seconds: 6),
              followRedirects: false,
            ),
          ),
      _ownsClient = client == null;

  static final _catalog = Uri.https('anikototv.bz');
  static final _embedOrigin = Uri.https('megaplay.buzz', '/');
  static const _agent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/149.0.0.0 Safari/537.36';
  static final _nonWords = RegExp(r'[^\p{L}\p{N}]+', unicode: true);
  static final _numbers = RegExp(r'^\d+$');
  static final _clientKeys = RegExp(
    r'''trustAesKey[^)]*"([^"]{16})"\)\),\w+=String\([^)]*"([^"]{16})"''',
  );

  final Dio _client;
  final bool _ownsClient;

  void close() {
    if (_ownsClient) _client.close(force: true);
  }

  Future<StreamResult?> resolve(
    SearchResult media, {
    required int episode,
    required bool dub,
  }) async {
    final title = (media.title ?? media.name ?? '').trim();
    if (media.mediaType != 'anime' || title.isEmpty || episode < 1) return null;
    final search = await _get(
      _catalog.replace(path: '/filter', queryParameters: {'keyword': title}),
    );
    final names = [media.title, media.name]
        .whereType<String>()
        .map(_normalize)
        .where((name) => name.isNotEmpty)
        .toSet();
    final links = html
        .parse(search)
        .querySelectorAll('a.name.d-title, a.d-title');
    final match = links
        .where((link) => names.contains(_normalize(link.text)))
        .map((link) => _uri(link.attributes['href'], _catalog))
        .nonNulls
        .where(
          (uri) => uri.host == _catalog.host && uri.path.startsWith('/watch/'),
        )
        .firstOrNull;
    if (match == null) return null;
    final page = html.parse(await _get(match));
    final id = page.querySelector('#watch-main')?.attributes['data-id'];
    if (id == null || !_numbers.hasMatch(id)) return null;
    final listing = await _ajax('/ajax/episode/list/$id', {}, match);
    final episodes = html.parse(_html(listing['result']));
    final serverIds = episodes
        .querySelector('a[data-num="$episode"][data-ids]')
        ?.attributes['data-ids'];
    if (serverIds == null || serverIds.isEmpty) return null;
    final servers = await _ajax('/ajax/server/list', {
      'servers': serverIds,
    }, match);
    final category = dub ? 'dub' : 'sub';
    final options = html
        .parse(_html(servers['result']))
        .querySelectorAll('[data-type="$category"] li[data-link-id]');
    for (final item in options.take(4)) {
      final linkId = item.attributes['data-link-id'];
      if (linkId == null || linkId.isEmpty) continue;
      try {
        final server = await _ajax('/ajax/server', {'get': linkId}, match);
        final result = _map(server['result']);
        final embed = _uri(result['url'], _embedOrigin);
        if (embed == null || embed.origin != _embedOrigin.origin) continue;
        final stream = await _resolveEmbed(embed, match, category, dub, result);
        if (stream != null) return stream;
      } on DioException {
        continue;
      } on FormatException {
        continue;
      }
    }
    return null;
  }

  Future<StreamResult?> _resolveEmbed(
    Uri embed,
    Uri watch,
    String category,
    bool dub,
    Map<String, dynamic> server,
  ) async {
    final document = html.parse(await _get(embed, referer: watch));
    final id = document.querySelector('[data-id]')?.attributes['data-id'];
    if (id == null || !_numbers.hasMatch(id)) return null;
    final source = _map(
      jsonDecode(
        await _get(
          _embedOrigin.replace(
            path: '/stream/getSourcesNew',
            queryParameters: {'id': id, 'type': category},
          ),
          referer: embed,
          ajax: true,
        ),
      ),
    );
    var playable = _sourceUrl(source['sources']);
    final encoded = source['enc'];
    if (playable == null && encoded is String && encoded.isNotEmpty) {
      playable = _decodeSource(encoded, "i?LMTAx0Q6,:}50U", "W0;27ToaUpl_P%'c");
      if (playable == null) {
        final script = document.querySelector(
          'script[src*="/lib/newclient.min.js"]',
        );
        final scriptUrl = _uri(script?.attributes['src'], _embedOrigin);
        if (scriptUrl != null && scriptUrl.origin == _embedOrigin.origin) {
          final keys = _clientKeys.firstMatch(
            await _get(scriptUrl, referer: embed),
          );
          if (keys != null)
            playable = _decodeSource(encoded, keys[1]!, keys[2]!);
        }
      }
    }
    if (playable == null || !playable.path.endsWith('.m3u8')) return null;
    const headers = {'Referer': 'https://megaplay.buzz/', 'User-Agent': _agent};
    final captions = <StreamSubtitleTrack>[];
    String? previews;
    for (final track in _rows(source['tracks'])) {
      final url = _uri(track['file'], _embedOrigin)?.toString();
      if (url == null) continue;
      switch (track['kind']) {
        case 'captions':
        case 'subtitles':
          captions.add(
            StreamSubtitleTrack(
              url: url,
              lang: track['label']?.toString() ?? 'English',
            ),
          );
        case 'thumbnails':
          previews ??= url;
      }
    }
    final skips = _map(server['skip_data']);
    return StreamResult(
      url: playable.toString(),
      quality: 'Auto',
      provider: 'AniKoto',
      subtitles: captions,
      selectedAudio: dub ? 'Dub' : 'Sub',
      availableQualities: const ['Auto'],
      isM3U8: true,
      headers: headers,
      thumbnailsVtt: previews,
      thumbnailsHeaders: headers,
      skipTimes: [
        if (_skip('op', skips['intro'] ?? source['intro']) case final intro?)
          intro,
        if (_skip('ed', skips['outro'] ?? source['outro']) case final outro?)
          outro,
      ],
    );
  }

  Future<Map<String, dynamic>> _ajax(
    String path,
    Map<String, String> query,
    Uri referer,
  ) async => _map(
    jsonDecode(
      await _get(
        _catalog.replace(path: path, queryParameters: query),
        referer: referer,
        ajax: true,
      ),
    ),
  );

  Future<String> _get(Uri uri, {Uri? referer, bool ajax = false}) async {
    final response = await _client.getUri<String>(
      uri,
      options: Options(
        responseType: ResponseType.plain,
        headers: {
          'User-Agent': _agent,
          if (referer != null) 'Referer': referer.toString(),
          if (ajax) ...{
            'X-Requested-With': 'XMLHttpRequest',
            'Origin': uri.origin,
            'Accept': 'application/json',
          },
        },
      ),
    );
    return response.data ?? '';
  }

  static Uri? _decodeSource(String encoded, String seed, String iv) {
    try {
      final cipher =
          PaddedBlockCipherImpl(PKCS7Padding(), CBCBlockCipher(AESEngine()))
            ..init(
              false,
              PaddedBlockCipherParameters<ParametersWithIV<KeyParameter>, Null>(
                ParametersWithIV(
                  KeyParameter(utf8.encode(seed.padRight(32, '\x00'))),
                  utf8.encode(iv),
                ),
                null,
              ),
            );
      return _sourceUrl(
        jsonDecode(
          utf8.decode(cipher.process(base64.decode(base64.normalize(encoded)))),
        ),
      );
    } on FormatException {
      return null;
    } on ArgumentError {
      return null;
    }
  }

  static Uri? _sourceUrl(Object? data) {
    if (data is! List) return _uri(_map(data)['file'], _embedOrigin);
    return _rows(
      data,
    ).map((row) => _uri(row['file'], _embedOrigin)).nonNulls.firstOrNull;
  }

  static SkipTime? _skip(String type, Object? value) {
    final start = value is List && value.length >= 2
        ? value[0]
        : _map(value)['start'];
    final end = value is List && value.length >= 2
        ? value[1]
        : _map(value)['end'];
    if (start is! num || end is! num || start < 0 || end <= start) return null;
    return SkipTime(
      type: type,
      startTime: Duration(milliseconds: (start * 1000).round()),
      endTime: Duration(milliseconds: (end * 1000).round()),
    );
  }

  static Uri? _uri(Object? value, Uri base) {
    if (value is! String || value.trim().isEmpty) return null;
    final reference = Uri.tryParse(value.trim());
    if (reference == null) return null;
    final url = base.resolveUri(reference);
    return url.scheme == 'https' && isPublicWebUrl(url) ? url : null;
  }

  static String _normalize(String name) =>
      name.toLowerCase().replaceAll(_nonWords, '');
  static Map<String, dynamic> _map(Object? value) =>
      value is Map<String, dynamic> ? value : const {};
  static String _html(Object? value) => value is String ? value : '';
  static Iterable<Map<String, dynamic>> _rows(Object? value) =>
      value is List ? value.whereType<Map<String, dynamic>>() : const [];
}
