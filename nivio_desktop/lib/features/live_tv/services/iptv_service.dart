import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/config/app_environment.dart';
import '../../../shared/models/iptv_channel.dart';
import '../../../shared/models/iptv_playlist.dart';
import 'builtin_live_tv_providers.dart';

enum LiveTvSourceFilter { all, iptv, tamilUltra, sportzx }

class DesktopIptvService {
  DesktopIptvService({BuiltInLiveTvProviders? builtInProviders})
    : _builtInProviders = builtInProviders ?? BuiltInLiveTvProviders();

  static const String playlistsKey = 'iptv_playlists';
  static const String defaultPlaylistUrlKey = 'iptv_playlist_url';
  static const String favoritesKey = 'iptv_favorites';
  static const Duration operationTimeout = Duration(seconds: 35);
  static final Map<String, List<IptvChannel>> _playlistChannelCache = {};

  final BuiltInLiveTvProviders _builtInProviders;

  Future<String> defaultPlaylistUrl() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(defaultPlaylistUrlKey)?.trim();
    if (saved != null && saved.isNotEmpty) return saved;
    return AppEnvironment.iptvPlaylistUrl;
  }

  Future<List<IptvPlaylist>> getPlaylists() async {
    _log('getPlaylists start');
    final prefs = await SharedPreferences.getInstance();
    final jsonString = prefs.getString(playlistsKey);
    if (jsonString == null || jsonString.isEmpty) {
      _log('getPlaylists end count=0');
      return [];
    }
    final decoded = jsonDecode(jsonString) as List<dynamic>;
    final playlists = decoded
        .map((item) => IptvPlaylist.fromJson(item as Map<String, dynamic>))
        .toList();
    final seenUrls = <String>{};
    final duplicateIds = <String>[];
    final unique = <IptvPlaylist>[];
    for (final playlist in playlists) {
      final normalizedUrl = playlist.url.trim();
      if (normalizedUrl.isEmpty || !seenUrls.add(normalizedUrl)) {
        duplicateIds.add(playlist.id);
        continue;
      }
      unique.add(playlist);
    }
    if (duplicateIds.isNotEmpty) {
      _log('getPlaylists dedupe removed=${duplicateIds.length}');
      await _savePlaylists(unique);
      for (final id in duplicateIds) {
        _playlistChannelCache.removeWhere((key, _) => key.startsWith('$id:'));
        try {
          final file = await _getPlaylistFile(id);
          if (await file.exists()) await file.delete();
        } catch (error) {
          _log('getPlaylists dedupe delete failed id=$id error=$error');
        }
      }
    }
    _log('getPlaylists end count=${unique.length}');
    return unique;
  }

  Future<void> fetchAndSavePlaylist(String url, String name) async {
    _log('env playlistUrl=${AppEnvironment.iptvPlaylistUrl}');
    _log('request start url=$url');
    try {
      final response = await http
          .get(Uri.parse(url))
          .timeout(const Duration(seconds: 30));
      _log(
        'request end status=${response.statusCode} bytes=${response.bodyBytes.length}',
      );
      if (response.statusCode != 200) {
        throw IptvServiceException(
          'Failed to load playlist: HTTP ${response.statusCode}',
        );
      }
      if (response.body.trim().isEmpty) {
        throw const IptvServiceException('Playlist response was empty.');
      }

      final parsedChannels = await parseM3u(response.body, const []);
      if (parsedChannels.isEmpty) {
        throw const IptvServiceException(
          'Playlist loaded but no playable channels were found.',
        );
      }

      final id = DateTime.now().millisecondsSinceEpoch.toString();
      final file = await _getPlaylistFile(id);
      await file.writeAsString(response.body).timeout(operationTimeout);

      final playlists = await getPlaylists();
      final normalizedUrl = url.trim();
      final existing = playlists
          .where((playlist) => playlist.url.trim() == normalizedUrl)
          .toList();
      for (final playlist in existing) {
        playlists.remove(playlist);
        _playlistChannelCache.removeWhere(
          (key, _) => key.startsWith('${playlist.id}:'),
        );
        try {
          final oldFile = await _getPlaylistFile(playlist.id);
          if (await oldFile.exists()) await oldFile.delete();
        } catch (_) {}
      }
      playlists.add(IptvPlaylist(id: id, name: name, url: url));
      await _savePlaylists(playlists);
      _log(
        'fetchAndSavePlaylist saved id=$id channels=${parsedChannels.length}',
      );
    } catch (error, stackTrace) {
      _log('request exception type=${error.runtimeType} error=$error');
      debugPrintStack(stackTrace: stackTrace, label: '[iptv] request stack');
      if (error is IptvServiceException) rethrow;
      throw IptvServiceException('Failed to load playlist: $error');
    }
  }

  Future<List<IptvChannel>> loadAllChannels({
    LiveTvSourceFilter sourceFilter = LiveTvSourceFilter.all,
  }) async {
    _log('loadAllChannels start source=$sourceFilter');
    await migrateLegacyPlaylist().timeout(operationTimeout);

    final playlists = await getPlaylists();
    final favorites = await getFavorites();
    _log('favorites loaded count=${favorites.length}');
    final channels = <IptvChannel>[];
    final failures = <String>[];

    if (sourceFilter == LiveTvSourceFilter.all ||
        sourceFilter == LiveTvSourceFilter.tamilUltra ||
        sourceFilter == LiveTvSourceFilter.sportzx) {
      _log('built-in providers load start');
      final builtIns = switch (sourceFilter) {
        LiveTvSourceFilter.tamilUltra =>
          await _builtInProviders
              .loadProviderChannels('tamilultra', favorites)
              .timeout(operationTimeout),
        LiveTvSourceFilter.sportzx =>
          await _builtInProviders
              .loadProviderChannels('sportzx', favorites)
              .timeout(operationTimeout),
        _ =>
          await _builtInProviders
              .loadChannels(favorites)
              .timeout(operationTimeout),
      };
      channels.addAll(builtIns);
      _log('built-in providers load end channels=${builtIns.length}');
    }

    final playlistFallback = _playlistFallbackPredicate(sourceFilter);
    final shouldLoadPlaylists =
        sourceFilter == LiveTvSourceFilter.all ||
        sourceFilter == LiveTvSourceFilter.iptv ||
        (playlistFallback != null && channels.isEmpty);
    if (shouldLoadPlaylists) {
      if (playlistFallback != null && channels.isEmpty) {
        _log('provider empty; falling back to filtered IPTV channels');
      }
      for (final playlist in playlists) {
        try {
          _log('playlist read start id=${playlist.id} name=${playlist.name}');
          final file = await _getPlaylistFile(playlist.id);
          if (await file.exists()) {
            final parsed = await _loadPlaylistChannels(
              playlist,
              file,
              favorites,
            );
            if (parsed.isEmpty) {
              throw const IptvServiceException(
                'Playlist parsed successfully but contained no channels.',
              );
            }
            channels.addAll(
              playlistFallback == null
                  ? parsed
                  : parsed.where(playlistFallback),
            );
          } else {
            _log('playlist file missing id=${playlist.id}');
          }
        } catch (error, stackTrace) {
          failures.add('${playlist.name}: $error');
          _log(
            'playlist exception id=${playlist.id} type=${error.runtimeType} error=$error',
          );
          debugPrintStack(
            stackTrace: stackTrace,
            label: '[iptv] playlist stack',
          );
        }
      }
    }

    if (failures.isNotEmpty && channels.isEmpty && playlists.isNotEmpty) {
      throw IptvServiceException(
        'Failed to load saved playlist${failures.length == 1 ? '' : 's'}: ${failures.join('; ')}',
      );
    }

    channels.sort((a, b) {
      if (a.isFavorite && !b.isFavorite) return -1;
      if (!a.isFavorite && b.isFavorite) return 1;
      return 0;
    });
    _log('loadAllChannels end channels=${channels.length}');
    return channels;
  }

  Future<List<IptvChannel>> _loadPlaylistChannels(
    IptvPlaylist playlist,
    File file,
    List<String> favorites,
  ) async {
    final stat = await file.stat().timeout(operationTimeout);
    final cacheKey =
        '${playlist.id}:${stat.modified.millisecondsSinceEpoch}:${stat.size}';
    final cached = _playlistChannelCache[cacheKey];
    if (cached != null) {
      _log('playlist cache hit id=${playlist.id} channels=${cached.length}');
      return _applyFavorites(cached, favorites);
    }

    final rawM3u = await file.readAsString().timeout(operationTimeout);
    _log('playlist read end id=${playlist.id} bytes=${rawM3u.length}');
    final parsed = await parseM3u(rawM3u, const []);
    _playlistChannelCache
      ..removeWhere((key, _) => key.startsWith('${playlist.id}:'))
      ..[cacheKey] = parsed;
    return _applyFavorites(parsed, favorites);
  }

  List<IptvChannel> _applyFavorites(
    List<IptvChannel> channels,
    List<String> favorites,
  ) {
    final favoriteSet = favorites.toSet();
    return channels
        .map(
          (channel) => IptvChannel(
            name: channel.name,
            url: channel.url,
            group: channel.group,
            logo: channel.logo,
            tvgId: channel.tvgId,
            isFavorite: favoriteSet.contains(channel.url),
          ),
        )
        .toList(growable: false);
  }

  bool Function(IptvChannel)? _playlistFallbackPredicate(
    LiveTvSourceFilter sourceFilter,
  ) {
    return switch (sourceFilter) {
      LiveTvSourceFilter.tamilUltra => (channel) {
        final text = '${channel.name} ${channel.group}'.toLowerCase();
        return text.contains('tamil') ||
            text.contains('india') ||
            text.contains('sun tv') ||
            text.contains('vijay') ||
            text.contains('zee tamil') ||
            text.contains('ktv');
      },
      LiveTvSourceFilter.sportzx => (channel) {
        final text = '${channel.name} ${channel.group}'.toLowerCase();
        return text.contains('sport') ||
            text.contains('cricket') ||
            text.contains('football') ||
            text.contains('soccer') ||
            text.contains('tennis') ||
            text.contains('f1') ||
            text.contains('espn') ||
            text.contains('sky sports') ||
            text.contains('star sports') ||
            text.contains('sony ten');
      },
      _ => null,
    };
  }

  Future<List<String>> getFavorites() async {
    _log('getFavorites start');
    final prefs = await SharedPreferences.getInstance();
    final favorites = prefs.getStringList(favoritesKey) ?? [];
    _log('getFavorites end count=${favorites.length}');
    return favorites;
  }

  Future<void> toggleFavorite(String url) async {
    _log('toggleFavorite start url=$url');
    final prefs = await SharedPreferences.getInstance();
    final favorites = prefs.getStringList(favoritesKey) ?? [];
    if (favorites.contains(url)) {
      favorites.remove(url);
    } else {
      favorites.add(url);
    }
    await prefs.setStringList(favoritesKey, favorites);
    _log('toggleFavorite end favorites=${favorites.length}');
  }

  Future<void> deletePlaylist(String id) async {
    _log('deletePlaylist start id=$id');
    final playlists = await getPlaylists();
    playlists.removeWhere((playlist) => playlist.id == id);
    await _savePlaylists(playlists);
    _playlistChannelCache.removeWhere((key, _) => key.startsWith('$id:'));

    try {
      final file = await _getPlaylistFile(id);
      if (await file.exists()) await file.delete();
    } catch (error, stackTrace) {
      _log(
        'deletePlaylist file exception type=${error.runtimeType} error=$error',
      );
      debugPrintStack(stackTrace: stackTrace, label: '[iptv] delete stack');
    }
    _log('deletePlaylist end id=$id');
  }

  Future<void> migrateLegacyPlaylist() async {
    _log('migrateLegacyPlaylist start');
    final prefs = await SharedPreferences.getInstance();
    final oldUrl = prefs.getString(defaultPlaylistUrlKey);
    final oldRaw = prefs.getString('iptv_playlist_raw');
    if (oldUrl == null || oldRaw == null || oldUrl.isEmpty || oldRaw.isEmpty) {
      _log('migrateLegacyPlaylist end migrated=false');
      return;
    }

    final id = DateTime.now().millisecondsSinceEpoch.toString();
    final file = await _getPlaylistFile(id);
    await file.writeAsString(oldRaw);

    final playlists = await getPlaylists();
    playlists.add(IptvPlaylist(id: id, name: 'Legacy Playlist', url: oldUrl));
    await _savePlaylists(playlists);

    await prefs.remove(defaultPlaylistUrlKey);
    await prefs.remove('iptv_playlist_raw');
    _log('migrateLegacyPlaylist end migrated=true');
  }

  Future<List<IptvChannel>> parseM3u(
    String rawM3u,
    List<String> favorites,
  ) async {
    _log('parser start bytes=${rawM3u.length}');
    try {
      final parsed = await compute(_parseM3uPayload, {
        'rawM3u': rawM3u,
        'favorites': favorites,
      }).timeout(operationTimeout);
      final channels = parsed
          .map((item) => IptvChannel.fromJson(item))
          .toList(growable: false);
      _log('parser end channels=${channels.length}');
      return channels;
    } catch (error, stackTrace) {
      _log('parser exception type=${error.runtimeType} error=$error');
      debugPrintStack(stackTrace: stackTrace, label: '[iptv] parser stack');
      if (error is IptvServiceException) rethrow;
      throw IptvServiceException('Playlist parsing failed: $error');
    }
  }

  Future<File> _getPlaylistFile(String id) async {
    final directory = await getApplicationDocumentsDirectory();
    return File('${directory.path}/playlist_$id.m3u');
  }

  Future<void> _savePlaylists(List<IptvPlaylist> playlists) async {
    _log('savePlaylists start count=${playlists.length}');
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      playlistsKey,
      jsonEncode(playlists.map((playlist) => playlist.toJson()).toList()),
    );
    _log('savePlaylists end count=${playlists.length}');
  }

  void _log(String message) {
    debugPrint('[iptv] $message');
  }
}

class IptvServiceException implements Exception {
  const IptvServiceException(this.message);

  final String message;

  @override
  String toString() => message;
}

List<Map<String, dynamic>> _parseM3uPayload(Map<String, Object?> payload) {
  final rawM3u = payload['rawM3u'] as String? ?? '';
  final favorites = (payload['favorites'] as List<dynamic>? ?? const [])
      .map((item) => item.toString())
      .toSet();

  final trimmed = rawM3u.trim();
  if (trimmed.isEmpty) {
    throw const IptvServiceException('Playlist response was empty.');
  }
  if (!trimmed.contains('#EXTINF:')) {
    throw const IptvServiceException(
      'Malformed playlist: no #EXTINF channel entries found.',
    );
  }

  final lines = const LineSplitter().convert(rawM3u);
  final channels = <Map<String, dynamic>>[];

  String? currentName;
  var currentGroup = 'Uncategorized';
  var currentLogo = '';
  var currentTvgId = '';

  for (final rawLine in lines) {
    final line = rawLine.trim();
    if (line.isEmpty) continue;

    if (line.startsWith('#EXTINF:')) {
      currentGroup =
          _extractM3uAttribute(line, 'group-title') ?? 'Uncategorized';
      currentLogo = _extractM3uAttribute(line, 'tvg-logo') ?? '';
      currentTvgId = _extractM3uAttribute(line, 'tvg-id') ?? '';

      final commaIndex = line.lastIndexOf(',');
      currentName = commaIndex != -1 && commaIndex < line.length - 1
          ? line.substring(commaIndex + 1).trim()
          : 'Unknown Channel';
    } else if (!line.startsWith('#') && currentName != null) {
      channels.add({
        'name': currentName,
        'url': line,
        'group': currentGroup,
        'logo': currentLogo,
        'tvgId': currentTvgId,
        'isFavorite': favorites.contains(line),
      });
      currentName = null;
      currentGroup = 'Uncategorized';
      currentLogo = '';
      currentTvgId = '';
    }
  }

  if (channels.isEmpty) {
    throw const IptvServiceException(
      'Playlist parsed successfully but contained no channels.',
    );
  }

  return channels;
}

String? _extractM3uAttribute(String line, String attributeName) {
  final regex = RegExp('$attributeName="([^"]*)"');
  return regex.firstMatch(line)?.group(1);
}
