import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../models/iptv_channel.dart';
import '../models/iptv_vod.dart';

/// Server + login for an Xtream Codes IPTV account.
class XtreamCredentials {
  final String server; // scheme://host[:port][/prefix], no trailing slash
  final String username;
  final String password;

  const XtreamCredentials({
    required this.server,
    required this.username,
    required this.password,
  });

  /// Cleans up what users paste as the server: adds http:// when missing and
  /// drops a trailing slash or a pasted `player_api.php` / `get.php` path.
  static String normalizeServer(String input) {
    var s = input.trim();
    if (!s.contains('://')) s = 'http://$s';
    final uri = Uri.parse(s);
    var path = uri.path;
    for (final file in const ['/player_api.php', '/get.php', '/xmltv.php', '/panel_api.php']) {
      if (path.endsWith(file)) path = path.substring(0, path.length - file.length);
    }
    while (path.endsWith('/')) {
      path = path.substring(0, path.length - 1);
    }
    return Uri(scheme: uri.scheme, host: uri.host, port: uri.hasPort ? uri.port : null, path: path).toString();
  }

  /// Recognises an Xtream link pasted as an M3U URL, e.g.
  /// `http://host:8080/get.php?username=u&password=p&type=m3u_plus`.
  static XtreamCredentials? fromUrl(String url) {
    final uri = Uri.tryParse(url.trim());
    if (uri == null || !uri.hasScheme) return null;
    final user = uri.queryParameters['username'];
    final pass = uri.queryParameters['password'];
    final file = uri.pathSegments.isEmpty ? '' : uri.pathSegments.last;
    if (user == null || pass == null || user.isEmpty) return null;
    if (file != 'get.php' && file != 'player_api.php') return null;
    return XtreamCredentials(server: normalizeServer(url.split('?').first), username: user, password: pass);
  }
}

class XtreamException implements Exception {
  final String message;
  const XtreamException(this.message);
  @override
  String toString() => message;
}

/// Minimal Xtream Codes API client: login check, live channels, movies and series.
///
/// API: `{server}/player_api.php?username=..&password=..[&action=..]`.
/// Live streams play from `{server}/live/{user}/{pass}/{stream_id}.{ext}`.
class XtreamClient {
  // Many panels reject unknown clients; a common player UA is accepted widely.
  static const _headers = {'User-Agent': 'VLC/3.0.20 LibVLC/3.0.20', 'Accept': '*/*'};

  final XtreamCredentials creds;
  XtreamClient(this.creds);

  Uri _api([String? action]) => Uri.parse('${creds.server}/player_api.php').replace(queryParameters: {
        'username': creds.username,
        'password': creds.password,
        if (action != null) 'action': action,
      });

  Future<dynamic> _get(String? action, {Duration timeout = const Duration(seconds: 20)}) async {
    final http.Response res;
    try {
      res = await http.get(_api(action), headers: _headers).timeout(timeout);
    } catch (e) {
      throw XtreamException('Could not reach the server: $e');
    }
    if (res.statusCode == 401 || res.statusCode == 403) {
      throw const XtreamException('The server refused the login (wrong username or password).');
    }
    if (res.statusCode != 200) {
      throw XtreamException('Server returned HTTP ${res.statusCode}.');
    }
    try {
      // Channel lists can be several MB; decode off the UI thread.
      return await compute(_decodeJson, res.body);
    } catch (_) {
      throw const XtreamException('The server did not answer like an Xtream Codes panel.');
    }
  }

  /// Checks the login. Returns the account's `user_info` map.
  Future<Map<String, dynamic>> login() async {
    final data = await _get(null);
    final info = data is Map ? data['user_info'] : null;
    if (info is! Map || '${info['auth']}' != '1') {
      throw const XtreamException('Wrong username or password.');
    }
    final status = '${info['status'] ?? ''}'.toLowerCase();
    if (status.isNotEmpty && status != 'active') {
      throw XtreamException('This account is ${info['status']}.');
    }
    return Map<String, dynamic>.from(info);
  }

  /// All live channels, grouped by their category name.
  Future<List<IptvChannel>> liveChannels(Map<String, dynamic> userInfo) async {
    final results = await Future.wait([
      _get('get_live_categories'),
      _get('get_live_streams', timeout: const Duration(seconds: 60)),
    ]);
    final categories = <String, String>{};
    if (results[0] is List) {
      for (final c in results[0] as List) {
        if (c is Map) categories['${c['category_id']}'] = '${c['category_name'] ?? ''}'.trim();
      }
    }
    final streams = results[1] is List ? results[1] as List : const [];

    // Prefer HLS when the account allows it; otherwise MPEG-TS.
    final formats = (userInfo['allowed_output_formats'] as List?)?.map((e) => '$e').toList() ?? const [];
    final ext = formats.isEmpty || formats.contains('m3u8') ? 'm3u8' : 'ts';
    final user = Uri.encodeComponent(creds.username);
    final pass = Uri.encodeComponent(creds.password);

    final channels = <IptvChannel>[];
    for (final s in streams) {
      if (s is! Map) continue;
      final id = s['stream_id'];
      if (id == null) continue;
      final group = categories['${s['category_id']}'];
      channels.add(IptvChannel(
        name: '${s['name'] ?? 'Channel $id'}'.trim(),
        url: '${creds.server}/live/$user/$pass/$id.$ext',
        group: (group == null || group.isEmpty) ? 'Uncategorized' : group,
        logo: '${s['stream_icon'] ?? ''}',
        tvgId: '${s['epg_channel_id'] ?? ''}',
      ));
    }
    return channels;
  }

  Future<Map<String, String>> _categories(String action) async {
    final data = await _get(action);
    final map = <String, String>{};
    if (data is List) {
      for (final c in data) {
        if (c is Map) map['${c['category_id']}'] = '${c['category_name'] ?? ''}'.trim();
      }
    }
    return map;
  }

  String get _user => Uri.encodeComponent(creds.username);
  String get _pass => Uri.encodeComponent(creds.password);

  static String _group(Map<String, String> cats, Object? id) {
    final name = cats['$id'];
    return (name == null || name.isEmpty) ? 'Uncategorized' : name;
  }

  static String _ext(Object? container, String fallback) {
    final e = '${container ?? ''}'.trim();
    return e.isEmpty ? fallback : e;
  }

  /// Movies (VOD). Play from `{server}/movie/{user}/{pass}/{id}.{ext}`.
  Future<List<IptvMovie>> movies() async {
    final results = await Future.wait([
      _categories('get_vod_categories'),
      _get('get_vod_streams', timeout: const Duration(seconds: 90)),
    ]);
    final cats = results[0] as Map<String, String>;
    final list = results[1] is List ? results[1] as List : const [];
    final movies = <IptvMovie>[];
    for (final m in list) {
      if (m is! Map || m['stream_id'] == null) continue;
      movies.add(IptvMovie(
        name: '${m['name'] ?? ''}'.trim(),
        url: '${creds.server}/movie/$_user/$_pass/${m['stream_id']}.${_ext(m['container_extension'], 'mp4')}',
        poster: '${m['stream_icon'] ?? ''}',
        group: _group(cats, m['category_id']),
        rating: '${m['rating'] ?? ''}',
      ));
    }
    return movies;
  }

  /// Series list; episodes are fetched per series with [seriesEpisodes].
  Future<List<IptvSeries>> series(String playlistId) async {
    final results = await Future.wait([
      _categories('get_series_categories'),
      _get('get_series', timeout: const Duration(seconds: 90)),
    ]);
    final cats = results[0] as Map<String, String>;
    final list = results[1] is List ? results[1] as List : const [];
    final series = <IptvSeries>[];
    for (final s in list) {
      if (s is! Map || s['series_id'] == null) continue;
      series.add(IptvSeries(
        name: '${s['name'] ?? ''}'.trim(),
        poster: '${s['cover'] ?? ''}',
        group: _group(cats, s['category_id']),
        rating: '${s['rating'] ?? ''}',
        plot: '${s['plot'] ?? ''}',
        playlistId: playlistId,
        seriesId: '${s['series_id']}',
      ));
    }
    return series;
  }

  /// Episodes of one series. Play from `{server}/series/{user}/{pass}/{id}.{ext}`.
  Future<List<IptvEpisode>> seriesEpisodes(String seriesId) async {
    final uri = _api('get_series_info').replace(queryParameters: {
      ..._api('get_series_info').queryParameters,
      'series_id': seriesId,
    });
    final http.Response res;
    try {
      res = await http.get(uri, headers: _headers).timeout(const Duration(seconds: 20));
    } catch (e) {
      throw XtreamException('Could not reach the server: $e');
    }
    if (res.statusCode != 200) throw XtreamException('Server returned HTTP ${res.statusCode}.');
    final data = await compute(_decodeJson, res.body);
    // `episodes` is a map of season number -> episode list (some panels send a list of lists).
    final raw = data is Map ? data['episodes'] : null;
    final seasons = <MapEntry<String, dynamic>>[];
    if (raw is Map) {
      seasons.addAll(raw.entries.map((e) => MapEntry('${e.key}', e.value)));
    } else if (raw is List) {
      for (var i = 0; i < raw.length; i++) {
        seasons.add(MapEntry('${i + 1}', raw[i]));
      }
    }
    final episodes = <IptvEpisode>[];
    for (final season in seasons) {
      if (season.value is! List) continue;
      for (final e in season.value as List) {
        if (e is! Map || e['id'] == null) continue;
        final info = e['info'] is Map ? e['info'] as Map : const {};
        episodes.add(IptvEpisode(
          season: int.tryParse('${e['season'] ?? season.key}') ?? 1,
          episode: int.tryParse('${e['episode_num'] ?? ''}') ?? 0,
          title: '${e['title'] ?? ''}'.trim(),
          url: '${creds.server}/series/$_user/$_pass/${e['id']}.${_ext(e['container_extension'], 'mp4')}',
          image: '${info['movie_image'] ?? ''}',
          plot: '${info['plot'] ?? ''}',
        ));
      }
    }
    episodes.sort((a, b) => a.season != b.season ? a.season.compareTo(b.season) : a.episode.compareTo(b.episode));
    return episodes;
  }
}

dynamic _decodeJson(String body) => jsonDecode(body);
