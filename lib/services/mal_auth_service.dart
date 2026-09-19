import 'dart:convert';
import 'dart:math';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:nivio/core/debug_log.dart';
import 'package:nivio/models/anime_tracking_models.dart';

/// Service handling MyAnimeList (MAL) PKCE OAuth 2.0 authentication,
/// user profile management, and watch status synchronization via MAL REST v2 API.
class MalAuthService {
  static final MalAuthService instance = MalAuthService._();
  MalAuthService._();

  static const String _apiBaseUrl = 'https://api.myanimelist.net/v2';
  static const String _oauthTokenUrl = 'https://myanimelist.net/v1/oauth2/token';
  static const String _oauthAuthorizeUrl =
      'https://myanimelist.net/v1/oauth2/authorize';

  static const String _prefTokensKey = 'mal_auth_tokens';
  static const String _prefUserKey = 'mal_user_profile';
  static const String _prefVerifierKey = 'mal_code_verifier';

  final Dio _dio = Dio(
    BaseOptions(
      baseUrl: _apiBaseUrl,
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 15),
    ),
  );

  TrackingTokens? _tokens;
  TrackingUser? _currentUser;
  bool _initialized = false;

  bool get isAuthenticated => _tokens != null && _currentUser != null;
  TrackingUser? get currentUser => _currentUser;
  TrackingTokens? get tokens => _tokens;

  final ValueNotifier<TrackingUser?> userNotifier =
      ValueNotifier<TrackingUser?>(null);

  String get clientId =>
      dotenv.env['MAL_CLIENT_ID']?.trim() ??
      '36f080169b17784558ab37d5f2ad03cd';

  String get redirectUrl =>
      dotenv.env['MAL_REDIRECT_URL']?.trim() ?? 'nivio://auth/mal';

  /// Initialize and load saved session from local storage.
  Future<void> init() async {
    if (_initialized) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final tokensJson = prefs.getString(_prefTokensKey);
      if (tokensJson != null && tokensJson.isNotEmpty) {
        _tokens = TrackingTokens.fromJson(jsonDecode(tokensJson));
      }

      final userJson = prefs.getString(_prefUserKey);
      if (userJson != null && userJson.isNotEmpty) {
        _currentUser = TrackingUser.fromJson(jsonDecode(userJson));
        userNotifier.value = _currentUser;
      }

      if (_tokens != null && _tokens!.isExpired && _tokens!.refreshToken != null) {
        await refreshToken();
      } else if (_tokens != null && _currentUser == null) {
        await fetchViewerProfile();
      }
    } catch (e) {
      appDebugLog('[MalAuth] Error loading cached session: $e');
    } finally {
      _initialized = true;
    }
  }

  /// Generate a random 128-character alphanumeric string for PKCE code_verifier.
  String _generateCodeVerifier() {
    const chars =
        'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~';
    final random = Random.secure();
    return List.generate(128, (_) => chars[random.nextInt(chars.length)]).join();
  }

  /// Generate authorization URL and store verifier locally for token exchange.
  Future<String> createAuthorizationUrl() async {
    final verifier = _generateCodeVerifier();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefVerifierKey, verifier);

    return '$_oauthAuthorizeUrl'
        '?response_type=code'
        '&client_id=$clientId'
        '&code_challenge=$verifier'
        '&code_challenge_method=plain'
        '&redirect_uri=${Uri.encodeComponent(redirectUrl)}';
  }

  /// Launch MAL authorization page in the default browser.
  Future<bool> launchAuthorization() async {
    try {
      final url = await createAuthorizationUrl();
      final uri = Uri.parse(url);
      return await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (e) {
      appDebugLog('[MalAuth] Failed to launch authorization: $e');
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

  /// Exchange authorization code from deep link redirect for tokens.
  Future<bool> exchangeCodeForToken(String code) async {
    final prefs = await SharedPreferences.getInstance();
    final verifier = prefs.getString(_prefVerifierKey) ?? '';
    if (verifier.isEmpty) {
      appDebugLog('[MalAuth] Code verifier missing from storage');
      return false;
    }

    try {
      final response = await _dio.post(
        _oauthTokenUrl,
        options: Options(
          contentType: Headers.formUrlEncodedContentType,
        ),
        data: {
          'client_id': clientId,
          'grant_type': 'authorization_code',
          'code': _cleanCode(code),
          'code_verifier': verifier,
          'redirect_uri': redirectUrl,
        },
      );

      final accessToken = response.data['access_token'] as String?;
      final refreshToken = response.data['refresh_token'] as String?;
      final expiresIn = response.data['expires_in'] as int? ?? 2678400; // 31 days

      if (accessToken != null && accessToken.isNotEmpty) {
        _tokens = TrackingTokens(
          accessToken: accessToken,
          refreshToken: refreshToken,
          expiresAt: DateTime.now().add(Duration(seconds: expiresIn)),
          provider: TrackingProvider.mal,
        );

        await prefs.setString(_prefTokensKey, jsonEncode(_tokens!.toJson()));
        await prefs.remove(_prefVerifierKey);

        await fetchViewerProfile();
        appDebugLog('[MalAuth] Authenticated as ${_currentUser?.username}');
        return true;
      }
      return false;
    } catch (e) {
      appDebugLog('[MalAuth] Token exchange error: $e');
      return false;
    }
  }

  /// Refresh expired access token using refresh_token.
  Future<bool> refreshToken() async {
    final rToken = _tokens?.refreshToken;
    if (rToken == null || rToken.isEmpty) return false;

    try {
      final response = await _dio.post(
        _oauthTokenUrl,
        options: Options(
          contentType: Headers.formUrlEncodedContentType,
        ),
        data: {
          'client_id': clientId,
          'grant_type': 'refresh_token',
          'refresh_token': rToken,
        },
      );

      final newAccess = response.data['access_token'] as String?;
      final newRefresh = response.data['refresh_token'] as String?;
      final expiresIn = response.data['expires_in'] as int? ?? 2678400;

      if (newAccess != null && newAccess.isNotEmpty) {
        _tokens = TrackingTokens(
          accessToken: newAccess,
          refreshToken: newRefresh ?? rToken,
          expiresAt: DateTime.now().add(Duration(seconds: expiresIn)),
          provider: TrackingProvider.mal,
        );

        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_prefTokensKey, jsonEncode(_tokens!.toJson()));
        return true;
      }
      return false;
    } catch (e) {
      appDebugLog('[MalAuth] Token refresh error: $e');
      return false;
    }
  }

  /// Fetch authenticated user profile from MAL.
  Future<bool> fetchViewerProfile() async {
    if (_tokens == null) return false;

    try {
      final response = await _dio.get(
        '$_apiBaseUrl/users/@me',
        options: Options(
          headers: {'Authorization': 'Bearer ${_tokens!.accessToken}'},
        ),
      );

      final data = response.data;
      if (data != null) {
        _currentUser = TrackingUser(
          id: (data['id'] as int).toString(),
          username: data['name'] as String,
          avatarUrl: data['picture'] as String?,
          provider: TrackingProvider.mal,
          connectedAt: DateTime.now(),
        );
        userNotifier.value = _currentUser;

        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_prefUserKey, jsonEncode(_currentUser!.toJson()));
        return true;
      }
      return false;
    } catch (e) {
      appDebugLog('[MalAuth] Error fetching user profile: $e');
      return false;
    }
  }

  /// Save or update episode watch progress and status on MyAnimeList.
  Future<bool> updateWatchProgress({
    required int malId,
    required int episode,
    AnimeWatchStatus status = AnimeWatchStatus.watching,
  }) async {
    if (!isAuthenticated) return false;
    if (_tokens!.isExpired) {
      await refreshToken();
    }

    try {
      final response = await _dio.put(
        '$_apiBaseUrl/anime/$malId/my_list_status',
        options: Options(
          headers: {'Authorization': 'Bearer ${_tokens!.accessToken}'},
          contentType: Headers.formUrlEncodedContentType,
        ),
        data: {
          'status': status.toMalStatus(),
          'num_watched_episodes': episode,
        },
      );

      appDebugLog(
        '[MalAuth] Synced progress: MAL $malId → Ep $episode (${status.toMalStatus()})',
      );
      return response.statusCode == 200;
    } catch (e) {
      appDebugLog('[MalAuth] Error updating watch progress: $e');
      return false;
    }
  }

  /// Add anime to user's Plan to Watch list on MAL.
  Future<bool> addToWatchlist(int malId) async {
    if (!isAuthenticated) return false;
    if (_tokens!.isExpired) {
      await refreshToken();
    }

    try {
      final response = await _dio.put(
        '$_apiBaseUrl/anime/$malId/my_list_status',
        options: Options(
          headers: {'Authorization': 'Bearer ${_tokens!.accessToken}'},
          contentType: Headers.formUrlEncodedContentType,
        ),
        data: {
          'status': AnimeWatchStatus.planning.toMalStatus(),
        },
      );
      return response.statusCode == 200;
    } catch (e) {
      appDebugLog('[MalAuth] Error adding to MAL watchlist: $e');
      return false;
    }
  }

  /// Remove anime from user's MAL list.
  Future<bool> removeFromList(int malId) async {
    if (!isAuthenticated) return false;
    if (_tokens!.isExpired) {
      await refreshToken();
    }

    try {
      final response = await _dio.delete(
        '$_apiBaseUrl/anime/$malId/my_list_status',
        options: Options(
          headers: {'Authorization': 'Bearer ${_tokens!.accessToken}'},
        ),
      );
      return response.statusCode == 200;
    } catch (e) {
      appDebugLog('[MalAuth] Error deleting MAL list entry: $e');
      return false;
    }
  }

  /// Fetch user's anime list from MAL.
  Future<List<SyncedAnimeItem>> fetchUserAnimeList() async {
    if (!isAuthenticated) return [];
    if (_tokens!.isExpired) {
      await refreshToken();
    }

    try {
      final response = await _dio.get(
        '$_apiBaseUrl/users/@me/animelist',
        queryParameters: {
          'fields': 'list_status,num_episodes,main_picture',
          'limit': 500,
        },
        options: Options(
          headers: {'Authorization': 'Bearer ${_tokens!.accessToken}'},
        ),
      );

      final data = response.data['data'] as List<dynamic>?;
      if (data == null) return [];

      final items = <SyncedAnimeItem>[];
      for (final raw in data) {
        final node = raw['node'] as Map<String, dynamic>?;
        final listStatus = raw['list_status'] as Map<String, dynamic>?;
        if (node == null || listStatus == null) continue;

        items.add(
          SyncedAnimeItem(
            malId: node['id'] as int?,
            title: node['title'] as String? ?? 'Anime',
            posterUrl: node['main_picture']?['large'] as String? ??
                node['main_picture']?['medium'] as String?,
            episodesWatched: listStatus['num_episodes_watched'] as int? ?? 0,
            totalEpisodes: node['num_episodes'] as int?,
            status: AnimeWatchStatus.fromMal(
              listStatus['status'] as String? ?? 'plan_to_watch',
            ),
            score: (listStatus['score'] as num?)?.toDouble(),
          ),
        );
      }
      return items;
    } catch (e) {
      appDebugLog('[MalAuth] Error fetching MAL user list: $e');
      return [];
    }
  }

  /// Disconnect and wipe MAL credentials.
  Future<void> disconnect() async {
    _tokens = null;
    _currentUser = null;
    userNotifier.value = null;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_prefTokensKey);
      await prefs.remove(_prefUserKey);
      await prefs.remove(_prefVerifierKey);
      appDebugLog('[MalAuth] Disconnected MAL session');
    } catch (e) {
      appDebugLog('[MalAuth] Error clearing MAL preferences: $e');
    }
  }
}
