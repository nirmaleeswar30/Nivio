import 'dart:convert';
import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path_provider/path_provider.dart';
import '../models/iptv_channel.dart';
import '../models/iptv_playlist.dart';
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

  Future<void> deletePlaylist(String id) async {
    final playlists = await getPlaylists();
    playlists.removeWhere((p) => p.id == id);
    await _savePlaylists(playlists);
    
    try {
      final file = await _getPlaylistFile(id);
      if (await file.exists()) {
        await file.delete();
      }
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
        final file = await _getPlaylistFile(playlist.id);
        if (await file.exists()) {
          final rawM3u = await file.readAsString();
          final channels = parseM3u(rawM3u, favorites);
          allChannels.addAll(channels);
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

  Future<void> fetchAndSavePlaylist(String url, String name) async {
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

  List<IptvChannel> parseM3u(String rawM3u, List<String> favorites) {
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
  
  String? _extractAttribute(String line, String attributeName) {
    final regex = RegExp('$attributeName="([^"]*)"');
    final match = regex.firstMatch(line);
    return match?.group(1);
  }
}
