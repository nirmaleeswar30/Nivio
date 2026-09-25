import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:nivio/core/debug_log.dart';
import 'package:nivio/models/watchlist_item.dart';

/// Minimal profile for a connected Simkl account.
class SimklUser {
  final String id;
  final String username;
  final String? avatarUrl;
  final DateTime connectedAt;

  const SimklUser({
    required this.id,
    required this.username,
    this.avatarUrl,
    required this.connectedAt,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'username': username,
        'avatarUrl': avatarUrl,
        'connectedAt': connectedAt.toIso8601String(),
      };

  factory SimklUser.fromJson(Map<String, dynamic> json) => SimklUser(
        id: (json['id'] ?? '').toString(),
        username: json['username'] as String? ?? 'Simkl User',
        avatarUrl: json['avatarUrl'] as String?,
        connectedAt: DateTime.tryParse(json['connectedAt'] as String? ?? '') ??
            DateTime.now(),
      );
}

/// Handles Simkl AUTH V2 authentication (OAuth 2.0 authorization code + PKCE,
/// public client — no secret) and syncs watchlist status for movies, TV and
/// anime via Simkl's `sync/add-to-list` endpoint.
///
/// Simkl covers all three media types, so unlike [AniListAuthService] this is
/// wired into every watchlist change, not just anime.
class SimklAuthService {
  static final SimklAuthService instance = SimklAuthService._();
  SimklAuthService._();

  // AUTH V2 endpoints (see api.simkl.org).
  static const String _authorizeUrl = 'https://simkl.com/oauth2/authorize';
  static const String _tokenUrl = 'https://api.simkl.com/oauth2/token';
  static const String _apiBase = 'https://api.simkl.com';

  static const String _prefTokenKey = 'simkl_access_token';
  static const String _prefRefreshKey = 'simkl_refresh_token';
  static const String _prefUserKey = 'simkl_user_profile';
  static const String _prefVerifierKey = 'simkl_pkce_verifier';
  static const String _prefStateKey = 'simkl_oauth_state';
  static const String _prefLastSyncKey = 'simkl_last_synced_at';

  final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 15),
    ),
  );

  String? _accessToken;
  String? _refreshToken;
  SimklUser? _currentUser;
  DateTime? _lastSyncedAt;
  bool _initialized = false;

  final ValueNotifier<SimklUser?> userNotifier = ValueNotifier<SimklUser?>(null);

  bool get isAuthenticated => _accessToken != null && _currentUser != null;
  SimklUser? get currentUser => _currentUser;
  String? get accessToken => _accessToken;
  DateTime? get lastSyncedAt => _lastSyncedAt;

  // Credentials come only from .env. No hardcoded values.
  String get clientId => dotenv.env['SIMKL_CLIENT_ID']?.trim() ?? '';
  String get redirectUrl =>
      dotenv.env['SIMKL_REDIRECT_URL']?.trim() ?? 'nivio://auth/simkl';

  /// Headers required on every Simkl API request.
  Map<String, String> _headers({bool auth = true}) => {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
        'simkl-api-key': clientId,
        if (auth && _accessToken != null) 'Authorization': 'Bearer $_accessToken',
      };

  /// Load any saved session from local storage.
  Future<void> init() async {
    if (_initialized) return;
    // Auto-refresh the 7-day access token on 401, then retry the request once.
    _dio.interceptors.add(InterceptorsWrapper(onError: _onDioError));
    try {
      final prefs = await SharedPreferences.getInstance();
      _accessToken = prefs.getString(_prefTokenKey);
      _refreshToken = prefs.getString(_prefRefreshKey);
      final lastSyncStr = prefs.getString(_prefLastSyncKey);
      if (lastSyncStr != null) _lastSyncedAt = DateTime.tryParse(lastSyncStr);
      final userJson = prefs.getString(_prefUserKey);
      if (userJson != null && userJson.isNotEmpty) {
        _currentUser = SimklUser.fromJson(jsonDecode(userJson));
        userNotifier.value = _currentUser;
      }
      if (_accessToken != null && _currentUser == null) {
        await fetchUserProfile();
      }
    } catch (e) {
      appDebugLog('[SimklAuth] Error loading cached session: $e');
    } finally {
      _initialized = true;
    }
  }

  // ─── Token refresh ────────────────────────────────────────────

  /// Dio error hook: on a 401, refresh the access token with the stored
  /// refresh token and replay the failed request once.
  Future<void> _onDioError(
      DioException e, ErrorInterceptorHandler handler) async {
    final is401 = e.response?.statusCode == 401;
    final alreadyRetried = e.requestOptions.extra['simkl_retried'] == true;
    if (is401 && _refreshToken != null && !alreadyRetried) {
      final refreshed = await _refreshAccessToken();
      if (refreshed) {
        final opts = e.requestOptions;
        opts.headers['Authorization'] = 'Bearer $_accessToken';
        opts.extra['simkl_retried'] = true;
        try {
          final clone = await _dio.fetch<dynamic>(opts);
          return handler.resolve(clone);
        } catch (err) {
          return handler.next(err is DioException ? err : e);
        }
      }
    }
    return handler.next(e);
  }

  /// Exchange the stored refresh token for a fresh access token (public PKCE
  /// client — no secret). Uses a bare Dio so it can't recurse the interceptor.
  Future<bool> _refreshAccessToken() async {
    if (_refreshToken == null) return false;
    try {
      final resp = await Dio().post(
        _tokenUrl,
        options: Options(
          contentType: Headers.formUrlEncodedContentType,
          headers: {'simkl-api-key': clientId},
        ),
        data: {
          'grant_type': 'refresh_token',
          'client_id': clientId,
          'refresh_token': _refreshToken,
        },
      );
      final token = resp.data['access_token'] as String?;
      if (token == null || token.isEmpty) return false;
      _accessToken = token;
      _refreshToken = resp.data['refresh_token'] as String? ?? _refreshToken;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefTokenKey, token);
      if (_refreshToken != null) {
        await prefs.setString(_prefRefreshKey, _refreshToken!);
      }
      appDebugLog('[SimklAuth] Access token refreshed');
      return true;
    } catch (e) {
      appDebugLog('[SimklAuth] Token refresh failed: $e');
      return false;
    }
  }

  // ─── PKCE helpers ─────────────────────────────────────────────

  String _randomString(int length) {
    const chars =
        'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~';
    final rand = Random.secure();
    return List.generate(length, (_) => chars[rand.nextInt(chars.length)]).join();
  }

  String _codeChallengeS256(String verifier) {
    final digest = sha256.convert(utf8.encode(verifier));
    return base64Url.encode(digest.bytes).replaceAll('=', '');
  }

  /// Build the authorization URL, generating and persisting a fresh PKCE
  /// verifier + CSRF state for the pending exchange.
  Future<String> _buildAuthorizationUrl() async {
    final verifier = _randomString(64);
    final challenge = _codeChallengeS256(verifier);
    final state = _randomString(24);

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefVerifierKey, verifier);
    await prefs.setString(_prefStateKey, state);

    final params = {
      'response_type': 'code',
      'client_id': clientId,
      'redirect_uri': redirectUrl,
      'scope': 'media:read media:write',
      'state': state,
      'code_challenge': challenge,
      'code_challenge_method': 'S256',
    };
    return Uri.parse(_authorizeUrl).replace(queryParameters: params).toString();
  }

  /// Open the Simkl authorization page in the browser. The redirect back to
  /// `nivio://auth/simkl?code=...` is handled by the deep-link handler, which
  /// calls [exchangeCodeForToken].
  Future<bool> launchAuthorization() async {
    if (clientId.isEmpty) {
      appDebugLog('[SimklAuth] Missing SIMKL_CLIENT_ID');
      return false;
    }
    try {
      final url = await _buildAuthorizationUrl();
      return await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    } catch (e) {
      appDebugLog('[SimklAuth] Failed to launch authorization url: $e');
      return false;
    }
  }

  String _cleanCode(String input) {
    final str = input.trim();
    final uri = Uri.tryParse(str);
    if (uri != null && uri.queryParameters.containsKey('code')) {
      return uri.queryParameters['code']!;
    }
    final match = RegExp(r'[?&]code=([^&#]+)').firstMatch(str);
    if (match != null) return Uri.decodeComponent(match.group(1)!);
    return str;
  }

  /// Exchange an authorization code (or a full redirect URL) for tokens.
  Future<bool> authenticateWithInput(String input) => exchangeCodeForToken(input);

  /// Exchange the authorization code for access/refresh tokens using the stored
  /// PKCE verifier, then load the user profile.
  Future<bool> exchangeCodeForToken(String code) async {
    final cleanCode = _cleanCode(code);
    if (cleanCode.isEmpty) return false;
    try {
      final prefs = await SharedPreferences.getInstance();
      final verifier = prefs.getString(_prefVerifierKey) ?? '';

      final response = await _dio.post(
        _tokenUrl,
        options: Options(
          contentType: Headers.formUrlEncodedContentType,
          headers: {'simkl-api-key': clientId},
        ),
        data: {
          'grant_type': 'authorization_code',
          'client_id': clientId,
          'redirect_uri': redirectUrl,
          'code': cleanCode,
          'code_verifier': verifier,
        },
      );

      final token = response.data['access_token'] as String?;
      if (token == null || token.isEmpty) return false;

      _accessToken = token;
      _refreshToken = response.data['refresh_token'] as String? ?? _refreshToken;

      await prefs.setString(_prefTokenKey, token);
      if (_refreshToken != null) {
        await prefs.setString(_prefRefreshKey, _refreshToken!);
      }
      await prefs.remove(_prefVerifierKey);

      final ok = await fetchUserProfile();
      if (ok) appDebugLog('[SimklAuth] Authenticated as ${_currentUser?.username}');
      return ok;
    } catch (e) {
      appDebugLog('[SimklAuth] Code exchange error: $e');
      return false;
    }
  }

  /// Load the authenticated user's Simkl profile.
  Future<bool> fetchUserProfile() async {
    if (_accessToken == null) return false;
    try {
      final response = await _dio.get(
        '$_apiBase/users/settings',
        options: Options(headers: _headers()),
      );
      final data = response.data as Map<String, dynamic>?;
      final user = data?['user'] as Map<String, dynamic>?;
      final account = data?['account'] as Map<String, dynamic>?;
      if (user == null) return false;

      _currentUser = SimklUser(
        id: (account?['id'] ?? user['name'] ?? '').toString(),
        username: user['name'] as String? ?? 'Simkl User',
        avatarUrl: user['avatar'] as String?,
        connectedAt: DateTime.now(),
      );
      userNotifier.value = _currentUser;

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefUserKey, jsonEncode(_currentUser!.toJson()));
      return true;
    } catch (e) {
      appDebugLog('[SimklAuth] Error fetching profile: $e');
      return false;
    }
  }

  // ─── Sync ─────────────────────────────────────────────────────

  /// Map a Simkl list status string to an app [WatchStatus].
  static WatchStatus statusFromSimkl(String? s) {
    switch (s) {
      case 'watching':
        return WatchStatus.watching;
      case 'plantowatch':
        return WatchStatus.planning;
      case 'hold':
        return WatchStatus.paused;
      case 'completed':
        return WatchStatus.completed;
      case 'dropped':
      case 'notinteresting':
        return WatchStatus.dropped;
      default:
        return WatchStatus.planning;
    }
  }

  static const String _posterBase = 'https://simkl.in/posters';
  String? _posterUrl(String? path) =>
      (path == null || path.isEmpty) ? null : '$_posterBase/${path}_m.webp';

  /// Fetch the user's entire Simkl library (movies, TV & anime) with statuses.
  /// Returns a flat, media-typed list for the reconcile in WatchlistService.
  Future<List<SimklSyncedItem>> fetchAllItems() async {
    if (!isAuthenticated) return [];
    try {
      final response = await _dio.get(
        '$_apiBase/sync/all-items',
        options: Options(headers: _headers()),
      );
      final data = response.data as Map<String, dynamic>?;
      if (data == null) return [];

      final items = <SimklSyncedItem>[];

      SimklSyncedItem? parse(dynamic e, String mediaType, String objKey) {
        if (e is! Map) return null;
        final obj = e[objKey] as Map<String, dynamic>?;
        if (obj == null) return null;
        final ids = obj['ids'] as Map<String, dynamic>? ?? const {};
        int? asInt(dynamic v) => v == null ? null : int.tryParse(v.toString());
        // Simkl reports 0 for episode counts it doesn't track (e.g. movies, or
        // shows/anime where we only pushed status). Treat 0 as "unknown" (null)
        // so it never clobbers a real value the anime tracker already set.
        final total = asInt(e['total_episodes_count']);
        return SimklSyncedItem(
          mediaType: mediaType,
          tmdbId: asInt(ids['tmdb']),
          malId: asInt(ids['mal']),
          anilistId: asInt(ids['anilist']),
          simklId: asInt(ids['simkl']),
          title: obj['title'] as String? ?? 'Unknown',
          year: asInt(obj['year']),
          posterUrl: _posterUrl(obj['poster'] as String?),
          status: statusFromSimkl(e['status'] as String?),
          watchedEpisodes: asInt(e['watched_episodes_count']) ?? 0,
          totalEpisodes: (total != null && total > 0) ? total : null,
        );
      }

      for (final e in (data['movies'] as List<dynamic>? ?? const [])) {
        final item = parse(e, 'movie', 'movie');
        if (item != null) items.add(item);
      }
      for (final e in (data['shows'] as List<dynamic>? ?? const [])) {
        final item = parse(e, 'tv', 'show');
        if (item != null) items.add(item);
      }
      for (final e in (data['anime'] as List<dynamic>? ?? const [])) {
        // Anime entries carry their object under `show` too.
        final item = parse(e, 'anime', 'show');
        if (item != null) items.add(item);
      }

      appDebugLog('[SimklAuth] Fetched ${items.length} remote items');
      return items;
    } catch (e) {
      appDebugLog('[SimklAuth] Error fetching all items: $e');
      return [];
    }
  }

  /// Persist the last successful two-way sync time.
  Future<void> updateLastSyncedAt(DateTime dt) async {
    _lastSyncedAt = dt;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefLastSyncKey, dt.toIso8601String());
    } catch (_) {}
  }

  /// Map an app [WatchStatus] to Simkl's `to` list value.
  static String simklStatus(WatchStatus status) {
    switch (status) {
      case WatchStatus.planning:
        return 'plantowatch';
      case WatchStatus.watching:
        return 'watching';
      case WatchStatus.completed:
        return 'completed';
      case WatchStatus.paused:
        return 'hold';
      case WatchStatus.dropped:
        return 'dropped';
    }
  }

  /// Build the Simkl `ids` object for a watchlist item, per media type.
  Map<String, dynamic>? _idsFor(WatchlistItem item) {
    if (item.mediaType == 'anime') {
      final ids = <String, dynamic>{};
      if (item.malId != null) ids['mal'] = item.malId;
      if (item.anilistId != null) ids['anilist'] = item.anilistId;
      // Fall back to the TMDB id only when no anime-native id is available.
      if (ids.isEmpty && item.id > 0) ids['tmdb'] = item.id.toString();
      return ids.isEmpty ? null : ids;
    }
    // Movies and TV are keyed by their TMDB id.
    if (item.id <= 0) return null;
    return {'tmdb': item.id.toString()};
  }

  String _bucketFor(String mediaType) {
    switch (mediaType) {
      case 'movie':
        return 'movies';
      case 'anime':
        return 'anime';
      default:
        return 'shows'; // 'tv'
    }
  }

  /// Push a single watchlist item's status to Simkl (movies/TV/anime).
  Future<bool> syncItem(WatchlistItem item) async {
    if (!isAuthenticated) return false;
    final ids = _idsFor(item);
    if (ids == null) return false;

    final bucket = _bucketFor(item.mediaType);
    final entry = {'to': simklStatus(item.watchStatus), 'ids': ids};

    try {
      await _dio.post(
        '$_apiBase/sync/add-to-list',
        options: Options(headers: _headers()),
        data: {
          bucket: [entry],
        },
      );
      appDebugLog(
          '[SimklAuth] Synced ${item.title} → ${entry['to']} ($bucket)');
      return true;
    } catch (e) {
      appDebugLog('[SimklAuth] Sync error for ${item.title}: $e');
      return false;
    }
  }

  /// Push many items in one request, grouped into movies/shows/anime buckets.
  Future<int> syncItems(List<WatchlistItem> items) async {
    if (!isAuthenticated || items.isEmpty) return 0;
    final body = <String, List<Map<String, dynamic>>>{
      'movies': [],
      'shows': [],
      'anime': [],
    };
    var count = 0;
    for (final item in items) {
      final ids = _idsFor(item);
      if (ids == null) continue;
      body[_bucketFor(item.mediaType)]!
          .add({'to': simklStatus(item.watchStatus), 'ids': ids});
      count++;
    }
    body.removeWhere((_, v) => v.isEmpty);
    if (body.isEmpty) return 0;

    try {
      await _dio.post(
        '$_apiBase/sync/add-to-list',
        options: Options(headers: _headers()),
        data: body,
      );
      appDebugLog('[SimklAuth] Batch synced $count items to Simkl');
      return count;
    } catch (e) {
      appDebugLog('[SimklAuth] Batch sync error: $e');
      return 0;
    }
  }

  /// Mark a movie watched, or an episode of a show/anime watched, in Simkl's
  /// watch history. This is what drives Simkl's watched-episode count — the
  /// equivalent of AniList/MAL episode progress. Status (watching/completed)
  /// is handled separately by [syncItem]; this adds the actual progress.
  Future<bool> markWatched({
    required String mediaType, // 'movie' | 'tv' | 'anime'
    int? tmdbId,
    int? malId,
    int? anilistId,
    int season = 1,
    int? episode,
  }) async {
    if (!isAuthenticated) return false;
    final ids = <String, dynamic>{};
    if (mediaType == 'anime') {
      if (malId != null) ids['mal'] = malId;
      if (anilistId != null) ids['anilist'] = anilistId;
      if (ids.isEmpty && tmdbId != null) ids['tmdb'] = tmdbId.toString();
    } else if (tmdbId != null) {
      ids['tmdb'] = tmdbId.toString();
    }
    if (ids.isEmpty) return false;

    try {
      final Map<String, dynamic> body = mediaType == 'movie'
          ? {
              'movies': [
                {'ids': ids}
              ],
            }
          : {
              'shows': [
                {
                  'ids': ids,
                  'seasons': [
                    {
                      'number': season,
                      'episodes': [
                        {'number': episode ?? 1}
                      ],
                    }
                  ],
                }
              ],
            };
      await _dio.post(
        '$_apiBase/sync/history',
        options: Options(headers: _headers()),
        data: body,
      );
      appDebugLog(
          '[SimklAuth] Marked watched: $mediaType ${mediaType == 'movie' ? '' : 'S${season}E$episode'}');
      return true;
    } catch (e) {
      appDebugLog('[SimklAuth] markWatched error: $e');
      return false;
    }
  }

  /// Remove an item from the user's Simkl library entirely (both watch history
  /// and any list status). Without this, a locally-deleted title would be
  /// re-created on the next pull because it still exists on Simkl.
  Future<bool> removeItem(WatchlistItem item) async {
    if (!isAuthenticated) return false;
    final ids = _idsFor(item);
    if (ids == null) return false;
    // The remove endpoint groups anime under `shows`, unlike add-to-list.
    final bucket = item.mediaType == 'movie' ? 'movies' : 'shows';
    try {
      await _dio.post(
        '$_apiBase/sync/history/remove',
        options: Options(headers: _headers()),
        data: {
          bucket: [
            {'ids': ids}
          ],
        },
      );
      appDebugLog('[SimklAuth] Removed ${item.title} from Simkl');
      return true;
    } catch (e) {
      appDebugLog('[SimklAuth] Remove error for ${item.title}: $e');
      return false;
    }
  }

  /// Disconnect and wipe the Simkl session.
  Future<void> disconnect() async {
    _accessToken = null;
    _refreshToken = null;
    _currentUser = null;
    _lastSyncedAt = null;
    userNotifier.value = null;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_prefTokenKey);
      await prefs.remove(_prefRefreshKey);
      await prefs.remove(_prefUserKey);
      await prefs.remove(_prefLastSyncKey);
      appDebugLog('[SimklAuth] Disconnected Simkl session');
    } catch (e) {
      appDebugLog('[SimklAuth] Error clearing preferences: $e');
    }
  }
}

/// A single remote item pulled from the user's Simkl library, normalized to the
/// app's media types for reconciliation in WatchlistService.
class SimklSyncedItem {
  final String mediaType; // 'movie' | 'tv' | 'anime'
  final int? tmdbId;
  final int? malId;
  final int? anilistId;
  final int? simklId;
  final String title;
  final int? year;
  final String? posterUrl;
  final WatchStatus status;
  final int watchedEpisodes;
  final int? totalEpisodes;

  const SimklSyncedItem({
    required this.mediaType,
    this.tmdbId,
    this.malId,
    this.anilistId,
    this.simklId,
    required this.title,
    this.year,
    this.posterUrl,
    required this.status,
    this.watchedEpisodes = 0,
    this.totalEpisodes,
  });
}
