import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:nivio/core/debug_log.dart';
import 'package:nivio/models/search_result.dart';
import 'package:nivio/services/public_web_client.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Shared catalog for the CNC Verse movie and TV sources.
class NetMirrorSource {
  NetMirrorSource({Dio? client, Future<String?> Function()? verifiedCookie})
    : _verifiedCookie = verifiedCookie ?? _sharedVerifiedCookie,
      _client =
          client ??
          (Dio(
              BaseOptions(
                connectTimeout: const Duration(seconds: 5),
                receiveTimeout: const Duration(seconds: 7),
                followRedirects: false,
              ),
            )
            ..httpClientAdapter = IOHttpClientAdapter(
              createHttpClient: publicWebHttpClient,
            )),
      _ownsClient = client == null;

  static const _catalogs = {
    'Netflix': (section: '', ott: 'nf', studio: null),
    'Prime Video': (section: 'pv/', ott: 'pv', studio: null),
    'Hotstar': (section: 'hs/', ott: 'hs', studio: null),
    'Disney': (section: 'hs/', ott: 'dp', studio: 'disney'),
    'Marvel': (section: 'hs/', ott: 'dp', studio: 'marvel'),
    'Star Wars': (section: 'hs/', ott: 'dp', studio: 'starwars'),
    'Pixar': (section: 'hs/', ott: 'dp', studio: 'pixar'),
  };
  static final names = List<String>.unmodifiable([
    for (final name in _catalogs.keys) ...[
      name,
      name == 'Prime Video' ? 'PrimeVideoM' : '${name}M',
    ],
  ]);

  static final _catalog = Uri.https('net52.cc');
  static const _referer = 'https://net52.cc/mobile/home?app=1';
  static const _userAgent =
      'Mozilla/5.0 (Linux; Android 13; Pixel 5 Build/TQ3A.230901.001; wv) '
      'AppleWebKit/537.36 (KHTML, like Gecko) Version/4.0 '
      'Chrome/149.0.0.0 Mobile Safari/537.36 /OS.Gatu v3.0';
  static const _tvHeaders = {
    'Accept': 'application/json',
    'X-Requested-With': 'NetmirrorNewTV v1.0',
    'User-Agent':
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:136.0) '
        'Gecko/20100101 Firefox/136.0 /OS.GatuNewTV v1.0',
  };
  static final _nonWords = RegExp(r'[^\p{L}\p{N}]+', unicode: true);
  static final _digits = RegExp(r'\d+');
  static final _year = RegExp(r'^\d{4}');
  static final _titleYear = RegExp(r'\s*\((\d{4})\)$');
  static final _height = RegExp(r'\b\d{3,4}p\b', caseSensitive: false);

  final Dio _client;
  final bool _ownsClient;
  final Future<String?> Function() _verifiedCookie;

  // Searches only return results for a client that passed NetMirror's
  // check, which it proves with a `t_hash_t` cookie. The check takes about
  // 40 seconds, so one cookie is shared and kept (also across launches) for
  // as long as the CNC Verse plugin keeps it, and renewed in the background
  // before it runs out (see [warmUp]).
  static const _cookieKey = 'netmirror_t_hash_t';
  static const _cookieLifetime = Duration(hours: 11);
  // Renew this long before the cookie expires, so a search never waits.
  static const _refreshAhead = Duration(hours: 1);
  // After a failed background renewal, try again this much later.
  static const _retryAfter = Duration(minutes: 10);
  // The whole check gives up after this long, like the plugin's.
  static const _verifyBudget = Duration(seconds: 60);
  static const _verifyUserAgent =
      'Mozilla/5.0 (Linux; Android 12; RMX2117 Build/SP1A.210812.016; wv) '
      'AppleWebKit/537.36 (KHTML, like Gecko) Version/4.0 '
      'Chrome/147.0.7727.55 Mobile Safari/537.36 /OS.Gatu v3.0';
  static final _addhash = RegExp(
    r'''data-addhash\s*=\s*["']([^"']+)["']''',
    caseSensitive: false,
  );
  static String? _cookie;
  static DateTime? _cookieTime;
  static Future<String?>? _verifying;
  static Timer? _refreshTimer;

  static Duration get _cookieAge => DateTime.now().difference(_cookieTime!);

  static bool get _cookieFresh =>
      _cookie != null && _cookieAge < _cookieLifetime;

  /// Missing, expired, or inside the renewal window.
  static bool get _cookieDue =>
      !_cookieFresh || _cookieAge >= _cookieLifetime - _refreshAhead;

  /// Checks how old the saved cookie is and, when it is missing or close to
  /// expiring, gets a new one in the background; otherwise schedules that
  /// renewal. Called when the app opens and returns to the foreground.
  static Future<void> warmUp() async {
    await _loadSavedCookie();
    if (_cookieDue) {
      unawaited(_renew());
    } else {
      _scheduleRenewal();
    }
  }

  static Future<String?> _sharedVerifiedCookie() async {
    await _loadSavedCookie();
    if (_cookieFresh) {
      // Still valid: use it now, renew it behind the scenes if it's due.
      if (_cookieDue) unawaited(_renew());
      return _cookie;
    }
    return _renew();
  }

  static Future<void> _loadSavedCookie() async {
    if (_cookie != null) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString(_cookieKey)?.split('|');
      if (saved == null || saved.length != 2 || saved[1].isEmpty) return;
      _cookie = saved[1];
      _cookieTime = DateTime.fromMillisecondsSinceEpoch(
        int.tryParse(saved[0]) ?? 0,
      );
    } catch (_) {}
  }

  /// One verification at a time; the current cookie stays in use until a
  /// new one replaces it.
  static Future<String?> _renew() {
    return _verifying ??= () async {
      String? cookie;
      try {
        cookie = await _verify();
      } finally {
        _verifying = null;
      }
      _scheduleRenewal(failed: cookie == null);
      return cookie;
    }();
  }

  static void _scheduleRenewal({bool failed = false}) {
    _refreshTimer?.cancel();
    _refreshTimer = null;
    // Nothing to keep alive; the next search or app open will verify.
    if (_cookie == null || _cookieTime == null) return;
    final due = _cookieTime!
        .add(_cookieLifetime - _refreshAhead)
        .difference(DateTime.now());
    final wait = failed ? _retryAfter : (due.isNegative ? Duration.zero : due);
    _refreshTimer = Timer(wait, () => unawaited(_renew()));
  }

  /// Forgets a cookie the catalog no longer accepts.
  static Future<void> _dropCookie() async {
    _refreshTimer?.cancel();
    _refreshTimer = null;
    _cookie = null;
    _cookieTime = null;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_cookieKey);
    } catch (_) {}
  }

  static Future<String?> _verify() async {
    final client =
        Dio(
            BaseOptions(
              connectTimeout: const Duration(seconds: 10),
              receiveTimeout: const Duration(seconds: 15),
              followRedirects: false,
              validateStatus: (_) => true,
            ),
          )
          ..httpClientAdapter = IOHttpClientAdapter(
            createHttpClient: publicWebHttpClient,
          );
    final cookies = <String, String>{};
    Future<Response<String>> request(
      Uri uri,
      Map<String, String> headers, {
      String? body,
    }) async {
      final response = await client.requestUri<String>(
        uri,
        data: body,
        options: Options(
          method: body == null ? 'GET' : 'POST',
          responseType: ResponseType.plain,
          headers: {
            ...headers,
            if (cookies.isNotEmpty)
              'Cookie': [
                for (final entry in cookies.entries)
                  '${entry.key}=${entry.value}',
              ].join('; '),
          },
        ),
      );
      for (final raw in response.headers['set-cookie'] ?? const <String>[]) {
        final pair = raw.split(';').first;
        final equals = pair.indexOf('=');
        if (equals <= 0) continue;
        final value = pair.substring(equals + 1).trim();
        final name = pair.substring(0, equals).trim();
        if (value.isEmpty) {
          cookies.remove(name);
        } else {
          cookies[name] = value;
        }
      }
      return response;
    }

    final elapsed = Stopwatch()..start();
    try {
      const app = {
        'User-Agent': _verifyUserAgent,
        'X-Requested-With': 'app.netmirror.netmirrornew',
      };
      final home = await request(_catalog.resolve(_referer), app);
      final addhash = _addhash.firstMatch(home.data ?? '')?.group(1);
      if (addhash == null) return null;
      await request(
        Uri.https('userver.${_catalog.host}', '/', {
          'hee5': addhash,
          'a': 'y',
          't': '${DateTime.now().microsecondsSinceEpoch}',
        }),
        app,
      );
      // The check completes after a delay (about 40 seconds).
      while (elapsed.elapsed < _verifyBudget) {
        await Future<void>.delayed(const Duration(seconds: 5));
        final response =
            await request(_catalog.replace(path: '/mobile/verify2.php'), const {
              'User-Agent': _verifyUserAgent,
              'X-Requested-With': 'XMLHttpRequest',
              'Content-Type': 'application/x-www-form-urlencoded',
            }, body: 'verify=${Uri.encodeQueryComponent(addhash)}');
        if (!(response.data ?? '').contains('All Done')) continue;
        final cookie = cookies['t_hash_t'];
        if (cookie == null) return null;
        _cookie = cookie;
        _cookieTime = DateTime.now();
        try {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString(
            _cookieKey,
            '${_cookieTime!.millisecondsSinceEpoch}|$cookie',
          );
        } catch (_) {}
        return cookie;
      }
      appDebugLog('NetMirror: verification did not complete');
      return null;
    } catch (e) {
      appDebugLog('NetMirror: verification failed: $e');
      return null;
    } finally {
      client.close(force: true);
    }
  }

  void close() {
    if (_ownsClient) _client.close(force: true);
  }

  Future<List<Map<String, dynamic>>> resolve(
    String name,
    SearchResult media, {
    required int season,
    required int episode,
  }) async {
    final mobile = name.endsWith('M');
    final catalogName = name == 'PrimeVideoM'
        ? 'Prime Video'
        : mobile
        ? name.substring(0, name.length - 1)
        : name;
    final catalog = _catalogs[catalogName];
    if (catalog == null) return [];
    final movie = media.mediaType == 'movie';
    final title = (media.title ?? media.name ?? '').trim();
    if (title.isEmpty ||
        (!movie && (media.mediaType != 'tv' || season < 1 || episode < 1))) {
      return [];
    }
    final year = _year.stringMatch(
      media.releaseDate ?? media.firstAirDate ?? '',
    );
    final studio = catalog.studio;
    final verified = await _verifiedCookie();
    final headers = {
      'Accept': 'application/json',
      'User-Agent': _userAgent,
      'Referer': _referer,
      'X-Requested-With': 'app.netmirror.netmirrornew',
      'Cookie':
          '${verified == null ? '' : 't_hash_t=$verified; '}'
          'ott=${catalog.ott}; hd=on'
          '${studio == null ? '' : '; studio=$studio'}',
    };
    final section = '/mobile/${catalog.section}';
    final titleKey = _normalize(title);
    Map<String, dynamic>? match;
    for (final path in [
      section,
      if (catalog.section != 'hs/') '/${catalog.section}',
    ]) {
      try {
        final search = _map(await _get(path, 'search', headers, {'s': title}));
        // Without a valid cookie the catalog ignores the query.
        if (verified != null &&
            search['status'] == 'n' &&
            (search['head'] == 'Top Searches' ||
                '${search['error']}'.contains('Enter Some Words')) &&
            identical(_verifiedCookie, _sharedVerifiedCookie)) {
          await _dropCookie();
        }
        final matches = _rows(search['searchResult']).where((row) {
          final name = _text(row['t']) ?? '';
          final suffix = _titleYear.firstMatch(name);
          final candidateYear =
              _year.stringMatch('${row['y']}') ?? suffix?.group(1);
          return _text(row['id']) != null &&
              (_normalize(name) == titleKey ||
                  _normalize(name.replaceFirst(_titleYear, '')) == titleKey) &&
              (year == null || candidateYear == null || candidateYear == year);
        });
        final dated = year == null
            ? const <Map<String, dynamic>>[]
            : matches.where((row) => _year.stringMatch('${row['y']}') == year);
        match = dated.firstOrNull ?? matches.singleOrNull;
        if (match != null) break;
      } on DioException {
        continue;
      }
    }
    final id = _text(match?['id']);
    if (id == null) return [];

    var details = _map(await _get(section, 'post', headers, {'id': id}));
    if (details['error'] != null && catalog.section != 'hs/') {
      try {
        final webDetails = _map(
          await _get('/${catalog.section}', 'post', headers, {'id': id}),
        );
        if (webDetails['title'] != null) details = webDetails;
      } on DioException {
        // The mobile catalog still supplies IDs for movie playlists.
      }
    }
    final detailsYear = _year.stringMatch('${details['year']}');
    if (year != null && detailsYear != null && year != detailsYear) return [];
    final series =
        _rows(details['season']).isNotEmpty ||
        _rows(details['episodes']).isNotEmpty;
    if (movie && series) return [];
    final playId = movie
        ? id
        : await _episodeId(section, id, details, headers, season, episode);
    if (playId == null) return [];

    if (!mobile) {
      final streams = await _resolveTv(
        name,
        playId,
        studio == null ? catalog.ott : 'hs',
      );
      if (streams.isNotEmpty) return streams;
    }
    final playlist = await _get(section, 'playlist', headers, {
      'id': playId,
      't': title,
      'tm': _timestamp,
    });
    final seen = <String>{};
    return [
      for (final row in _rows(playlist))
        for (final source in _rows(row['sources']))
          if (_publicUrl(source['file'], relativeTo: _catalog) case final url?)
            if (seen.add(url))
              if (_mediaHeaders(url, headers) case final choiceHeaders
                  when await _isPlaylist(url, choiceHeaders))
                {
                  'url': url,
                  'title': name,
                  'quality': _quality(source['label']),
                  'type': 'hls',
                  'headers': choiceHeaders,
                  'subtitles': [
                    for (final track in _rows(row['tracks']))
                      if (track['kind'] == 'captions' ||
                          track['kind'] == 'subtitles')
                        if (_publicUrl(track['file'], relativeTo: _catalog)
                            case final caption?)
                          {
                            'url': caption,
                            'lang': _text(track['label']) ?? 'Unknown',
                          },
                  ],
                },
    ];
  }

  Future<String?> _episodeId(
    String section,
    String id,
    Map<String, dynamic> details,
    Map<String, String> headers,
    int season,
    int episode,
  ) async {
    String? find(Object? data) => _rows(data)
        .where((row) {
          return _digits.stringMatch('${row['s']}') == '$season' &&
              _digits.stringMatch('${row['ep']}') == '$episode';
        })
        .map((row) => _text(row['id']))
        .nonNulls
        .firstOrNull;
    final initial = find(details['episodes']);
    if (initial != null) return initial;
    final sectionId = _rows(details['season'])
        .where((row) => _digits.stringMatch('${row['s']}') == '$season')
        .map((row) => _text(row['id']))
        .nonNulls
        .firstOrNull;
    if (sectionId == null) return null;
    for (var page = 1; page <= 10; page++) {
      final data = _map(
        await _get(section, 'episodes', headers, {
          's': sectionId,
          'series': id,
          'page': '$page',
        }),
      );
      final match = find(data['episodes']);
      if (match != null) return match;
      if (data['nextPageShow'].toString() != '1') break;
    }
    return null;
  }

  Future<List<Map<String, dynamic>>> _resolveTv(
    String provider,
    String id,
    String ott,
  ) async {
    for (final host in [
      'mobiledetects.com',
      'mobiledetect.app',
      'mobidetect.art',
    ]) {
      try {
        final discovery = await _client.getUri<Object?>(
          Uri.https(host, '/checknewtv.php'),
          options: Options(headers: _tvHeaders),
        );
        final encoded = _text(_map(discovery.data)['token_hash']);
        if (encoded == null) continue;
        final url = Uri.tryParse(utf8.decode(base64Decode(encoded)));
        if (url == null || url.scheme != 'https' || !isPublicWebUrl(url))
          continue;
        final api = Uri.https(url.host, '/newtv/otp.php');
        final headers = {..._tvHeaders, 'Ott': ott};
        final guest = await _client.getUri<Object?>(
          api,
          options: Options(headers: headers),
        );
        final token = _text(_map(guest.data)['usertoken']);
        if (token == null) continue;
        final response = await _client.getUri<Object?>(
          api.replace(path: '/newtv/player.php', queryParameters: {'id': id}),
          options: Options(headers: {...headers, 'Usertoken': token}),
        );
        final data = _map(response.data);
        final stream = _publicUrl(data['video_link']);
        if (stream == null) continue;
        final referer = _publicUrl(data['referer']);
        return [
          {
            'url': stream,
            'title': provider,
            'quality': 'Auto',
            'headers': {
              'User-Agent': _userAgent,
              if (referer != null) 'Referer': referer,
            },
          },
        ];
      } on DioException {
        continue;
      } on FormatException {
        continue;
      }
    }
    return [];
  }

  Future<bool> _isPlaylist(String url, Map<String, String> headers) async {
    final uri = Uri.parse(url);
    if (uri.host != _catalog.host) return true;
    try {
      final response = await _client.getUri<ResponseBody>(
        uri,
        options: Options(headers: headers, responseType: ResponseType.stream),
      );
      final bytes = await response.data!.stream.first;
      return utf8
          .decode(bytes, allowMalformed: true)
          .trimLeft()
          .startsWith('#EXTM3U');
    } on DioException {
      return false;
    } on StateError {
      return false;
    }
  }

  Map<String, String> _mediaHeaders(
    String url,
    Map<String, String> catalogHeaders,
  ) => Uri.parse(url).host == _catalog.host
      ? catalogHeaders
      : {'Referer': _referer, 'User-Agent': _userAgent};

  Future<Object?> _get(
    String section,
    String operation,
    Map<String, String> headers,
    Map<String, String> query,
  ) async {
    final response = await _client.getUri<Object?>(
      _catalog.replace(
        path: '$section$operation.php',
        queryParameters: {'t': _timestamp, ...query},
      ),
      options: Options(headers: headers),
    );
    return response.data;
  }

  static String get _timestamp =>
      '${DateTime.now().millisecondsSinceEpoch ~/ 1000}';
  static String _normalize(String text) =>
      text.toLowerCase().replaceAll(_nonWords, '');
  static String _quality(Object? label) =>
      switch (_text(label)?.toLowerCase()) {
        'full hd' => '1080p',
        'mid hd' => '720p',
        'low hd' => '480p',
        final String value => _height.stringMatch(value) ?? 'Auto',
        _ => 'Auto',
      };
  static Map<String, dynamic> _map(Object? value) =>
      value is Map<String, dynamic> ? value : const {};
  static Iterable<Map<String, dynamic>> _rows(Object? value) =>
      value is List ? value.whereType<Map<String, dynamic>>() : const [];
  static String? _text(Object? value) =>
      value is String && value.trim().isNotEmpty ? value.trim() : null;
  static String? _publicUrl(Object? value, {Uri? relativeTo}) {
    final text = _text(value);
    if (text == null) return null;
    final uri = relativeTo?.resolve(text) ?? Uri.tryParse(text);
    return uri != null && isPublicWebUrl(uri) ? uri.toString() : null;
  }
}
