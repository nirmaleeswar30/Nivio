import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../models/iptv_channel.dart';
import '../models/iptv_playlist.dart';
import '../models/iptv_vod.dart';
import 'xtream_client.dart';
import 'package:flutter/foundation.dart';

final iptvServiceProvider = Provider<IptvService>((ref) => IptvService());

class IptvService {
  static const String _playlistsKey = 'iptv_playlists';
  static const String _favoritesKey = 'iptv_favorites';

  Future<List<IptvPlaylist>> getPlaylists() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonString = prefs.getString(_playlistsKey);
    if (jsonString != null && jsonString.isNotEmpty) {
      final List<dynamic> decoded = jsonDecode(jsonString);
      return decoded.map((e) => IptvPlaylist.fromJson(e as Map<String, dynamic>)).toList();
    }
    return [];
  }

  Future<void> _savePlaylists(List<IptvPlaylist> playlists) async {
    final prefs = await SharedPreferences.getInstance();
    final jsonString = jsonEncode(playlists.map((e) => e.toJson()).toList());
    await prefs.setString(_playlistsKey, jsonString);
  }

  Future<List<String>> getFavorites() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList(_favoritesKey) ?? [];
  }

  Future<void> toggleFavorite(String url) async {
    final prefs = await SharedPreferences.getInstance();
    final favs = prefs.getStringList(_favoritesKey) ?? [];
    if (favs.contains(url)) {
      favs.remove(url);
    } else {
      favs.add(url);
    }
    await prefs.setStringList(_favoritesKey, favs);
  }

  Future<File> _getPlaylistFile(String id) async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/playlist_$id.m3u');
  }

  // ── Xtream Codes ──
  // Channels are cached as JSON (like the saved .m3u file) and refreshed in
  // the background once a day; the password lives in secure storage.

  static const _secureStorage = FlutterSecureStorage();
  static const _xtreamRefreshAfter = Duration(hours: 24);
  static String _xtreamPasswordKey(String id) => 'iptv_xtream_password_$id';

  Future<File> _getXtreamCacheFile(String id) async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/playlist_$id.xtream.json');
  }

  Future<void> _writeXtreamCache(String id, List<IptvChannel> channels) async {
    final file = await _getXtreamCacheFile(id);
    await file.writeAsString(await compute(_encodeChannelCache, channels));
  }

  /// Logs in to an Xtream Codes account, downloads its live channels and saves
  /// it as a playlist. Throws [XtreamException] with a user-facing message.
  Future<void> addXtreamPlaylist({
    required String server,
    required String username,
    required String password,
    String? name,
  }) async {
    final creds = XtreamCredentials(
      server: XtreamCredentials.normalizeServer(server),
      username: username.trim(),
      password: password,
    );
    final client = XtreamClient(creds);
    final userInfo = await client.login();
    final channels = await client.liveChannels(userInfo);
    if (channels.isEmpty) {
      throw const XtreamException('Logged in, but this account has no live channels.');
    }

    final id = DateTime.now().millisecondsSinceEpoch.toString();
    await _writeXtreamCache(id, channels);
    await _secureStorage.write(key: _xtreamPasswordKey(id), value: creds.password);
    final playlists = await getPlaylists();
    playlists.add(IptvPlaylist(
      id: id,
      name: (name == null || name.trim().isEmpty) ? Uri.parse(creds.server).host : name.trim(),
      url: creds.server,
      type: 'xtream',
      username: creds.username,
    ));
    await _savePlaylists(playlists);
  }

  /// Cached channels of an Xtream playlist. A cache over a day old is still
  /// shown straight away and refreshed in the background for the next load;
  /// only a missing cache waits for the server.
  Future<List<IptvChannel>> _loadXtreamChannels(IptvPlaylist playlist) async {
    final file = await _getXtreamCacheFile(playlist.id);
    if (!await file.exists()) return await _refreshXtream(playlist) ?? [];
    if (DateTime.now().difference(await file.lastModified()) > _xtreamRefreshAfter) {
      unawaited(_refreshXtream(playlist));
    }
    return compute(_decodeChannelCache, await file.readAsString());
  }

  /// Re-downloads an Xtream playlist's channels into its cache.
  Future<List<IptvChannel>?> _refreshXtream(IptvPlaylist playlist) async {
    try {
      final password = await _secureStorage.read(key: _xtreamPasswordKey(playlist.id));
      if (password == null || playlist.username == null) return null;
      final client = XtreamClient(XtreamCredentials(
        server: playlist.url,
        username: playlist.username!,
        password: password,
      ));
      final fresh = await client.liveChannels(await client.login());
      if (fresh.isEmpty) return null;
      await _writeXtreamCache(playlist.id, fresh);
      return fresh;
    } catch (e) {
      debugPrint('Xtream refresh failed for ${playlist.name}: $e');
      return null;
    }
  }

  Future<void> deletePlaylist(String id) async {
    final playlists = await getPlaylists();
    playlists.removeWhere((p) => p.id == id);
    await _savePlaylists(playlists);

    try {
      final file = await _getPlaylistFile(id);
      if (await file.exists()) {
        await file.delete();
      }
      final xtreamCache = await _getXtreamCacheFile(id);
      if (await xtreamCache.exists()) {
        await xtreamCache.delete();
      }
      final vodCache = await _getXtreamVodCacheFile(id);
      if (await vodCache.exists()) {
        await vodCache.delete();
      }
      _parsedM3u.remove(id);
      await _secureStorage.delete(key: _xtreamPasswordKey(id));
    } catch (e) {
      debugPrint('Error deleting playlist file: $e');
    }
  }

  Future<List<IptvChannel>> loadAllChannels() async {
    await migrateLegacyPlaylist();
    
    final playlists = await getPlaylists();
    final favorites = await getFavorites();
    final List<IptvChannel> allChannels = [];
    
    for (var playlist in playlists) {
      try {
        if (playlist.isXtream) {
          final channels = await _loadXtreamChannels(playlist);
          allChannels.addAll(channels.map((c) => IptvChannel(
                name: c.name,
                url: c.url,
                group: c.group,
                logo: c.logo,
                tvgId: c.tvgId,
                isFavorite: favorites.contains(c.url),
              )));
          continue;
        }
        final file = await _getPlaylistFile(playlist.id);
        if (await file.exists()) {
          final rawM3u = await file.readAsString();
          // Big playlists take a while to parse; keep it off the UI thread.
          final channels = await compute(_parseM3uJob, (rawM3u, favorites));
          _parsedM3u[playlist.id] = channels;
          // Movie/series entries (Xtream-style M3U exports) go to Movies/Series.
          allChannels.addAll(channels.where((c) => !isVodUrl(c.url)));
        }
      } catch (e) {
        debugPrint('Error loading playlist ${playlist.id}: $e');
      }
    }

    // Sort so favorites are at the top
    allChannels.sort((a, b) {
      if (a.isFavorite && !b.isFavorite) return -1;
      if (!a.isFavorite && b.isFavorite) return 1;
      return 0; // Maintain natural parsing order for others
    });
    
    return allChannels;
  }

  // ── Movies & series (VOD) ──

  // M3U parses from the last loadAllChannels, so loadVod needn't re-read big files.
  final Map<String, List<IptvChannel>> _parsedM3u = {};

  /// Xtream-style on-demand links, also used in M3U exports of such accounts.
  static bool isVodUrl(String url) {
    final path = Uri.tryParse(url)?.path ?? url;
    return path.contains('/movie/') || path.contains('/series/');
  }

  Future<File> _getXtreamVodCacheFile(String id) async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/playlist_$id.xtream_vod.json');
  }

  /// Movies and series from every playlist: the Xtream VOD API for Xtream
  /// accounts, `/movie/` and `/series/` entries for M3U playlists.
  Future<IptvVodLibrary> loadVod() async {
    final movies = <IptvMovie>[];
    final series = <IptvSeries>[];
    for (final playlist in await getPlaylists()) {
      try {
        if (playlist.isXtream) {
          final lib = await _loadXtreamVod(playlist);
          movies.addAll(lib.movies);
          series.addAll(lib.series);
        } else {
          var channels = _parsedM3u[playlist.id];
          if (channels == null) {
            final file = await _getPlaylistFile(playlist.id);
            if (!await file.exists()) continue;
            final parsed = await compute(_parseM3uJob, (await file.readAsString(), const <String>[]));
            _parsedM3u[playlist.id] = parsed;
            channels = parsed;
          }
          final lib = m3uVod(channels);
          movies.addAll(lib.movies);
          series.addAll(lib.series);
        }
      } catch (e) {
        debugPrint('Error loading VOD for ${playlist.name}: $e');
      }
    }
    return IptvVodLibrary(movies: movies, series: series);
  }

  static final _episodePattern = RegExp(r'^(.*?)[\s._\-|]*S(\d{1,2})[\s._]*E(\d{1,4})\b', caseSensitive: false);

  /// Splits an M3U's `/movie/` and `/series/` entries into movies and series.
  /// Series episodes are grouped by show name using the usual "S01 E02" naming.
  static IptvVodLibrary m3uVod(List<IptvChannel> channels) {
    final movies = <IptvMovie>[];
    final shows = <String, List<(IptvChannel, int, int)>>{};
    for (final c in channels) {
      final path = Uri.tryParse(c.url)?.path ?? c.url;
      if (path.contains('/movie/')) {
        movies.add(IptvMovie(name: c.name, url: c.url, poster: c.logo, group: c.group));
      } else if (path.contains('/series/')) {
        final m = _episodePattern.firstMatch(c.name);
        final show = (m?.group(1) ?? c.name).trim();
        shows.putIfAbsent(show.isEmpty ? c.name : show, () => []).add((
          c,
          int.tryParse(m?.group(2) ?? '') ?? 1,
          int.tryParse(m?.group(3) ?? '') ?? 0,
        ));
      }
    }
    final series = shows.entries.map((e) {
      final eps = e.value.map((x) => IptvEpisode(season: x.$2, episode: x.$3, title: x.$1.name, url: x.$1.url)).toList()
        ..sort((a, b) => a.season != b.season ? a.season.compareTo(b.season) : a.episode.compareTo(b.episode));
      final first = e.value.first.$1;
      return IptvSeries(name: e.key, poster: first.logo, group: first.group, episodes: eps);
    }).toList();
    return IptvVodLibrary(movies: movies, series: series);
  }

  /// Cached Xtream movies/series, refreshed like live channels (see
  /// _loadXtreamChannels). Only a missing cache waits for the server.
  Future<IptvVodLibrary> _loadXtreamVod(IptvPlaylist playlist) async {
    final file = await _getXtreamVodCacheFile(playlist.id);
    if (!await file.exists()) return await _refreshXtreamVod(playlist) ?? const IptvVodLibrary();
    if (DateTime.now().difference(await file.lastModified()) > _xtreamRefreshAfter) {
      unawaited(_refreshXtreamVod(playlist));
    }
    return compute(_decodeVodCache, await file.readAsString());
  }

  Future<XtreamClient?> _xtreamClientFor(IptvPlaylist playlist) async {
    final password = await _secureStorage.read(key: _xtreamPasswordKey(playlist.id));
    if (password == null || playlist.username == null) return null;
    return XtreamClient(XtreamCredentials(server: playlist.url, username: playlist.username!, password: password));
  }

  Future<IptvVodLibrary?> _refreshXtreamVod(IptvPlaylist playlist) async {
    try {
      final client = await _xtreamClientFor(playlist);
      if (client == null) return null;
      // An account without VOD answers these with empty lists; that's fine.
      final results = await Future.wait([
        client.movies().catchError((_) => <IptvMovie>[]),
        client.series(playlist.id).catchError((_) => <IptvSeries>[]),
      ]);
      final lib = IptvVodLibrary(movies: results[0] as List<IptvMovie>, series: results[1] as List<IptvSeries>);
      final file = await _getXtreamVodCacheFile(playlist.id);
      await file.writeAsString(await compute(_encodeVodCache, lib));
      return lib;
    } catch (e) {
      debugPrint('Xtream VOD refresh failed for ${playlist.name}: $e');
      return null;
    }
  }

  /// Episodes of a series: from the playlist for M3U, from the server for Xtream.
  Future<List<IptvEpisode>> seriesEpisodes(IptvSeries series) async {
    if (series.episodes.isNotEmpty || series.seriesId == null || series.playlistId == null) {
      return series.episodes;
    }
    final playlist = (await getPlaylists()).where((p) => p.id == series.playlistId).firstOrNull;
    if (playlist == null) throw const XtreamException('This playlist was removed.');
    final client = await _xtreamClientFor(playlist);
    if (client == null) throw const XtreamException('Log in to this Xtream account again.');
    return client.seriesEpisodes(series.seriesId!);
  }

  Future<void> fetchAndSavePlaylist(String url, String name) async {
    // An Xtream account's M3U link: use the Xtream API instead (proper
    // categories, daily refresh, and much faster than a huge M3U download).
    final xtream = XtreamCredentials.fromUrl(url);
    if (xtream != null) {
      return addXtreamPlaylist(
        server: xtream.server,
        username: xtream.username,
        password: xtream.password,
        name: name == 'New Playlist' ? null : name,
      );
    }
    try {
      final response = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 30));
      if (response.statusCode == 200) {
        final rawM3u = response.body;
        final id = DateTime.now().millisecondsSinceEpoch.toString();
        
        // Save file
        final file = await _getPlaylistFile(id);
        await file.writeAsString(rawM3u);
        
        // Save metadata
        final playlists = await getPlaylists();
        playlists.add(IptvPlaylist(id: id, name: name, url: url));
        await _savePlaylists(playlists);
      } else {
        throw Exception('Failed to load playlist: HTTP ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('IPTV fetch error: $e');
      rethrow;
    }
  }

  Future<void> migrateLegacyPlaylist() async {
    final prefs = await SharedPreferences.getInstance();
    final oldUrl = prefs.getString('iptv_playlist_url');
    final oldRaw = prefs.getString('iptv_playlist_raw');
    
    if (oldUrl != null && oldRaw != null && oldUrl.isNotEmpty) {
      final id = DateTime.now().millisecondsSinceEpoch.toString();
      final file = await _getPlaylistFile(id);
      await file.writeAsString(oldRaw);
      
      final playlists = await getPlaylists();
      playlists.add(IptvPlaylist(id: id, name: 'Legacy Playlist', url: oldUrl));
      await _savePlaylists(playlists);
      
      await prefs.remove('iptv_playlist_url');
      await prefs.remove('iptv_playlist_raw');
    }
  }

  static List<IptvChannel> parseM3u(String rawM3u, List<String> favorites) {
    final lines = const LineSplitter().convert(rawM3u);
    final List<IptvChannel> channels = [];
    
    String? currentName;
    String currentGroup = 'Uncategorized';
    String currentLogo = '';
    String currentTvgId = '';
    
    for (int i = 0; i < lines.length; i++) {
      final line = lines[i].trim();
      if (line.isEmpty) continue;
      
      if (line.startsWith('#EXTINF:')) {
        currentGroup = _extractAttribute(line, 'group-title') ?? 'Uncategorized';
        currentLogo = _extractAttribute(line, 'tvg-logo') ?? '';
        currentTvgId = _extractAttribute(line, 'tvg-id') ?? '';
        
        final commaIndex = line.lastIndexOf(',');
        if (commaIndex != -1 && commaIndex < line.length - 1) {
          currentName = line.substring(commaIndex + 1).trim();
        } else {
          currentName = 'Unknown Channel';
        }
      } else if (!line.startsWith('#')) {
        if (currentName != null) {
          channels.add(IptvChannel(
            name: currentName,
            url: line,
            group: currentGroup,
            logo: currentLogo,
            tvgId: currentTvgId,
            isFavorite: favorites.contains(line),
          ));
          currentName = null;
          currentGroup = 'Uncategorized';
          currentLogo = '';
          currentTvgId = '';
        }
      }
    }
    
    return channels;
  }
  
  static String? _extractAttribute(String line, String attributeName) {
    final regex = RegExp('$attributeName="([^"]*)"');
    final match = regex.firstMatch(line);
    return match?.group(1);
  }
}

// Isolate entry points (top-level so compute can run them).

List<IptvChannel> _parseM3uJob((String, List<String>) args) => IptvService.parseM3u(args.$1, args.$2);

List<IptvChannel> _decodeChannelCache(String json) => (jsonDecode(json) as List<dynamic>)
    .map((e) => IptvChannel.fromJson(e as Map<String, dynamic>))
    .toList();

String _encodeChannelCache(List<IptvChannel> channels) => jsonEncode(channels.map((c) => c.toJson()).toList());

IptvVodLibrary _decodeVodCache(String json) {
  final j = jsonDecode(json) as Map<String, dynamic>;
  return IptvVodLibrary(
    movies: ((j['movies'] as List?) ?? const []).map((e) => IptvMovie.fromJson(e as Map<String, dynamic>)).toList(),
    series: ((j['series'] as List?) ?? const []).map((e) => IptvSeries.fromJson(e as Map<String, dynamic>)).toList(),
  );
}

String _encodeVodCache(IptvVodLibrary lib) => jsonEncode({
      'movies': lib.movies.map((m) => m.toJson()).toList(),
      'series': lib.series.map((s) => s.toJson()).toList(),
    });
