import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:nivio/core/debug_log.dart';
import 'package:nivio/models/anime_tracking_models.dart';

/// Service handling AniList OAuth authentication, user profile management,
/// and watch status synchronization via AniList GraphQL API.
class AniListAuthService {
  static final AniListAuthService instance = AniListAuthService._();
  AniListAuthService._();

  static const String _graphqlUrl = 'https://graphql.anilist.co';
  static const String _tokenUrl = 'https://anilist.co/api/v2/oauth/token';

  static const String _prefTokenKey = 'anilist_access_token';
  static const String _prefUserKey = 'anilist_user_profile';

  final Dio _dio = Dio(
    BaseOptions(
      baseUrl: _graphqlUrl,
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 15),
      headers: {'Content-Type': 'application/json', 'Accept': 'application/json'},
    ),
  );

  String? _accessToken;
  TrackingUser? _currentUser;
  bool _initialized = false;

  final ValueNotifier<TrackingUser?> userNotifier =
      ValueNotifier<TrackingUser?>(null);

  bool get isAuthenticated => _accessToken != null && _currentUser != null;
  TrackingUser? get currentUser => _currentUser;
  String? get accessToken => _accessToken;

  String get clientId =>
      dotenv.env['ANILIST_CLIENT_ID']?.trim() ?? '51426';

  String get clientSecret =>
      dotenv.env['ANILIST_CLIENT_SECRET']?.trim() ??
      'jIlRqzaZIXM1HruaKPaAKr9DiBoVf4h0b6xZ7BLo';

  String get redirectUrl =>
      dotenv.env['ANILIST_REDIRECT_URL']?.trim() ?? 'nivio://auth/anilist';

  /// Initialize and load saved session from local storage.
  Future<void> init() async {
    if (_initialized) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      _accessToken = prefs.getString(_prefTokenKey);
      final userJson = prefs.getString(_prefUserKey);
      if (userJson != null && userJson.isNotEmpty) {
        _currentUser = TrackingUser.fromJson(jsonDecode(userJson));
        userNotifier.value = _currentUser;
      }

      if (_accessToken != null && _currentUser == null) {
        // Token exists but user profile missing — fetch viewer profile
        await fetchViewerProfile();
      }
    } catch (e) {
      appDebugLog('[AniListAuth] Error loading cached session: $e');
    } finally {
      _initialized = true;
    }
  }

  /// URL for starting OAuth authorization.
  String get authorizationUrl {
    return 'https://anilist.co/api/v2/oauth/authorize'
        '?client_id=$clientId'
        '&redirect_uri=${Uri.encodeComponent(redirectUrl)}'
        '&response_type=code';
  }

  /// Launch the authorization page in the default browser.
  Future<bool> launchAuthorization() async {
    final uri = Uri.parse(authorizationUrl);
    try {
      return await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (e) {
      appDebugLog('[AniListAuth] Failed to launch authorization url: $e');
      return false;
    }
  }

  String _cleanCode(String input) {
    var str = input.trim();
    if (str.contains('code=')) {
      final uri = Uri.tryParse(str);
      if (uri != null && uri.queryParameters.containsKey('code')) {
        return uri.queryParameters['code']!;
      }
      final match = RegExp(r'[?&]code=([^&#]+)').firstMatch(str);
      if (match != null) {
        return Uri.decodeComponent(match.group(1)!);
      }
    }
    return str;
  }

  String _cleanToken(String input) {
    var str = input.trim();
    if (str.contains('access_token=')) {
      final match = RegExp(r'access_token=([^&#]+)').firstMatch(str);
      if (match != null) {
        return Uri.decodeComponent(match.group(1)!);
      }
    }
    return str;
  }

  /// Authenticate with either an authorization code, redirect URL, or raw token.
  Future<bool> authenticateWithInput(String input) async {
    final clean = input.trim();
    if (clean.isEmpty) return false;

    if (clean.contains('code=')) {
      return await exchangeCodeForToken(_cleanCode(clean));
    }
    if (clean.contains('access_token=')) {
      return await authenticateWithToken(_cleanToken(clean));
    }

    // Try exchanging as code first
    final codeSuccess = await exchangeCodeForToken(clean);
    if (codeSuccess) return true;

    // Fallback to direct token
    return await authenticateWithToken(clean);
  }

  /// Complete authentication using an access token (from deep link or token paste).
  Future<bool> authenticateWithToken(String token) async {
    final cleanToken = _cleanToken(token);
    if (cleanToken.isEmpty) return false;

    _accessToken = cleanToken;
    final success = await fetchViewerProfile();
    if (success) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefTokenKey, cleanToken);
      if (_currentUser != null) {
        await prefs.setString(_prefUserKey, jsonEncode(_currentUser!.toJson()));
      }
      appDebugLog('[AniListAuth] Authenticated as ${_currentUser?.username}');
      return true;
    } else {
      _accessToken = null;
      return false;
    }
  }

  /// Exchange an authorization code for an access token.
  Future<bool> exchangeCodeForToken(String code) async {
    final cleanCode = _cleanCode(code);
    try {
      final response = await _dio.post(
        _tokenUrl,
        data: {
          'grant_type': 'authorization_code',
          'client_id': clientId,
          'client_secret': clientSecret,
          'redirect_uri': redirectUrl,
          'code': cleanCode,
        },
      );

      final token = response.data['access_token'] as String?;
      if (token != null && token.isNotEmpty) {
        return await authenticateWithToken(token);
      }
      return false;
    } catch (e) {
      appDebugLog('[AniListAuth] Code exchange error: $e');
      return false;
    }
  }

  /// Fetch authenticated user profile from AniList.
  Future<bool> fetchViewerProfile() async {
    if (_accessToken == null) return false;

    const query = '''
      query {
        Viewer {
          id
          name
          avatar {
            large
            medium
          }
        }
      }
    ''';

    try {
      final response = await _dio.post(
        _graphqlUrl,
        options: Options(
          headers: {'Authorization': 'Bearer $_accessToken'},
        ),
        data: {'query': query},
      );

      final data = response.data['data']?['Viewer'];
      if (data != null) {
        _currentUser = TrackingUser(
          id: data['id'].toString(),
          username: data['name'] as String,
          avatarUrl: data['avatar']?['large'] as String? ??
              data['avatar']?['medium'] as String?,
          provider: TrackingProvider.anilist,
          connectedAt: DateTime.now(),
        );
        userNotifier.value = _currentUser;

        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_prefUserKey, jsonEncode(_currentUser!.toJson()));
        return true;
      }
      return false;
    } catch (e) {
      appDebugLog('[AniListAuth] Error fetching Viewer profile: $e');
      return false;
    }
  }

  /// Save or update episode watch progress and list status on AniList.
  Future<bool> updateWatchProgress({
    required int anilistId,
    required int episode,
    AnimeWatchStatus status = AnimeWatchStatus.watching,
  }) async {
    if (!isAuthenticated) return false;

    const query = '''
      mutation (\$mediaId: Int, \$progress: Int, \$status: MediaListStatus) {
        SaveMediaListEntry (mediaId: \$mediaId, progress: \$progress, status: \$status) {
          id
          mediaId
          status
          progress
        }
      }
    ''';

    try {
      final response = await _dio.post(
        _graphqlUrl,
        options: Options(
          headers: {'Authorization': 'Bearer $_accessToken'},
        ),
        data: {
          'query': query,
          'variables': {
            'mediaId': anilistId,
            'progress': episode,
            'status': status.toAniListStatus(),
          },
        },
      );

      final entry = response.data['data']?['SaveMediaListEntry'];
      if (entry != null) {
        appDebugLog(
          '[AniListAuth] Synced progress: Anime $anilistId → Ep $episode (${status.toAniListStatus()})',
        );
        return true;
      }
      return false;
    } catch (e) {
      appDebugLog('[AniListAuth] Error updating watch progress: $e');
      return false;
    }
  }

  /// Batch-saves multiple list entries in a single GraphQL request using
  /// aliased mutations, so N updates cost ~1 request instead of N. Large inputs
  /// are chunked to stay under AniList's query-complexity cap, with a small
  /// pause between chunks to respect the rate limit. Returns the number saved.
  Future<int> updateWatchProgressBatch(
      List<AniListProgressUpdate> updates) async {
    if (!isAuthenticated || updates.isEmpty) return 0;

    const chunkSize = 40;
    int saved = 0;

    for (var start = 0; start < updates.length; start += chunkSize) {
      final end =
          (start + chunkSize < updates.length) ? start + chunkSize : updates.length;
      final chunk = updates.sublist(start, end);

      final sb = StringBuffer('mutation {\n');
      for (var i = 0; i < chunk.length; i++) {
        final u = chunk[i];
        // mediaId/progress are ints and status is a fixed enum token, so inlining
        // is safe here and avoids declaring dozens of GraphQL variables.
        sb.writeln(
          '  m$i: SaveMediaListEntry(mediaId: ${u.anilistId}, progress: ${u.episode}, status: ${u.status.toAniListStatus()}) { id }',
        );
      }
      sb.writeln('}');

      try {
        final response = await _dio.post(
          _graphqlUrl,
          options: Options(
            headers: {'Authorization': 'Bearer $_accessToken'},
          ),
          data: {'query': sb.toString()},
        );
        final data = response.data['data'] as Map<String, dynamic>?;
        if (data != null) {
          for (var i = 0; i < chunk.length; i++) {
            if (data['m$i'] != null) saved++;
          }
        }
        appDebugLog(
            '[AniListAuth] Batch synced ${chunk.length} entries (saved so far: $saved)');
      } catch (e) {
        appDebugLog('[AniListAuth] Batch update error: $e');
      }

      if (end < updates.length) {
        await Future.delayed(const Duration(milliseconds: 1200));
      }
    }

    return saved;
  }

  /// Add anime to user's AniList Planning list (Watchlist).
  Future<bool> addToWatchlist(int anilistId) async {
    if (!isAuthenticated) return false;

    const query = '''
      mutation (\$mediaId: Int, \$status: MediaListStatus) {
        SaveMediaListEntry (mediaId: \$mediaId, status: \$status) {
          id
          mediaId
          status
        }
      }
    ''';

    try {
      final response = await _dio.post(
        _graphqlUrl,
        options: Options(
          headers: {'Authorization': 'Bearer $_accessToken'},
        ),
        data: {
          'query': query,
          'variables': {
            'mediaId': anilistId,
            'status': AnimeWatchStatus.planning.toAniListStatus(),
          },
        },
      );

      return response.data['data']?['SaveMediaListEntry'] != null;
    } catch (e) {
      appDebugLog('[AniListAuth] Error adding to watchlist: $e');
      return false;
    }
  }

  /// Remove entry from user's AniList list.
  Future<bool> removeFromList(int anilistId) async {
    if (!isAuthenticated) return false;

    // First query list entry ID for media
    const getEntryQuery = '''
      query (\$mediaId: Int) {
        Media (id: \$mediaId) {
          mediaListEntry {
            id
          }
        }
      }
    ''';

    try {
      final getRes = await _dio.post(
        _graphqlUrl,
        options: Options(
          headers: {'Authorization': 'Bearer $_accessToken'},
        ),
        data: {
          'query': getEntryQuery,
          'variables': {'mediaId': anilistId},
        },
      );

      final entryId = getRes.data['data']?['Media']?['mediaListEntry']?['id'];
      if (entryId == null) return true; // Not in list, consider removed

      const deleteQuery = '''
        mutation (\$id: Int) {
          DeleteMediaListEntry (id: \$id) {
            deleted
          }
        }
      ''';

      await _dio.post(
        _graphqlUrl,
        options: Options(
          headers: {'Authorization': 'Bearer $_accessToken'},
        ),
        data: {
          'query': deleteQuery,
          'variables': {'id': entryId},
        },
      );
      return true;
    } catch (e) {
      appDebugLog('[AniListAuth] Error deleting list entry: $e');
      return false;
    }
  }

  /// Fetch user's entire anime list from AniList.
  Future<List<SyncedAnimeItem>> fetchUserAnimeList() async {
    if (!isAuthenticated || _currentUser == null) return [];

    const query = '''
      query (\$userId: Int) {
        MediaListCollection (userId: \$userId, type: ANIME) {
          lists {
            name
            status
            entries {
              id
              mediaId
              status
              progress
              score
              media {
                id
                idMal
                title {
                  romaji
                  english
                  native
                }
                coverImage {
                  large
                }
                episodes
                averageScore
              }
            }
          }
        }
      }
    ''';

    try {
      final response = await _dio.post(
        _graphqlUrl,
        options: Options(
          headers: {'Authorization': 'Bearer $_accessToken'},
        ),
        data: {
          'query': query,
          'variables': {'userId': int.tryParse(_currentUser!.id)},
        },
      );

      final rawLists =
          response.data['data']?['MediaListCollection']?['lists'] as List<dynamic>?;
      if (rawLists == null) return [];

      final items = <SyncedAnimeItem>[];
      for (final list in rawLists) {
        final entries = list['entries'] as List<dynamic>? ?? [];
        for (final entry in entries) {
          final media = entry['media'] as Map<String, dynamic>?;
          if (media == null) continue;

          final titleObj = media['title'] as Map<String, dynamic>? ?? {};
          final title = (titleObj['english'] as String?)?.trim().isNotEmpty == true
              ? titleObj['english'] as String
              : (titleObj['romaji'] as String?)?.trim().isNotEmpty == true
                  ? titleObj['romaji'] as String
                  : titleObj['native'] as String? ?? 'Anime';

          items.add(
            SyncedAnimeItem(
              anilistId: media['id'] as int?,
              malId: media['idMal'] as int?,
              title: title,
              posterUrl: media['coverImage']?['large'] as String?,
              episodesWatched: entry['progress'] as int? ?? 0,
              totalEpisodes: media['episodes'] as int?,
              status: AnimeWatchStatus.fromAniList(
                entry['status'] as String? ?? 'PLANNING',
              ),
              // Use the community average rating (0–100) converted to the
              // 0–10 scale used everywhere else, NOT the user's personal list
              // score (which is 0 when they haven't rated the entry).
              score: () {
                final avg = (media['averageScore'] as num?)?.toDouble();
                return (avg != null && avg > 0) ? avg / 10.0 : null;
              }(),
            ),
          );
        }
      }

      return items;
    } catch (e) {
      appDebugLog('[AniListAuth] Error fetching anime collection: $e');
      return [];
    }
  }

  /// Disconnect and wipe AniList credentials.
  Future<void> disconnect() async {
    _accessToken = null;
    _currentUser = null;
    userNotifier.value = null;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_prefTokenKey);
      await prefs.remove(_prefUserKey);
      appDebugLog('[AniListAuth] Disconnected AniList session');
    } catch (e) {
      appDebugLog('[AniListAuth] Error clearing preferences: $e');
    }
  }
}

/// A single list-entry update for [AniListAuthService.updateWatchProgressBatch].
class AniListProgressUpdate {
  final int anilistId;
  final int episode;
  final AnimeWatchStatus status;

  const AniListProgressUpdate({
    required this.anilistId,
    required this.episode,
    this.status = AnimeWatchStatus.watching,
  });
}
