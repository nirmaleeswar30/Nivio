import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:nivio/services/discord_oauth.dart';

enum DiscordGatewayStatus { disconnected, connecting, connected, error }

class DiscordGatewayState {
  final DiscordGatewayStatus status;
  final String? username;
  final String? globalName;
  final String? avatarUrl;
  final String? errorMessage;

  const DiscordGatewayState({
    required this.status,
    this.username,
    this.globalName,
    this.avatarUrl,
    this.errorMessage,
  });

  String get displayName {
    if (globalName != null && globalName!.trim().isNotEmpty) return globalName!.trim();
    if (username != null && username!.isNotEmpty) return username!;
    return 'Discord User';
  }

  DiscordGatewayState copyWith({
    DiscordGatewayStatus? status,
    String? username,
    String? globalName,
    String? avatarUrl,
    String? errorMessage,
  }) {
    return DiscordGatewayState(
      status: status ?? this.status,
      username: username ?? this.username,
      globalName: globalName ?? this.globalName,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      errorMessage: errorMessage,
    );
  }
}

/// Mobile Discord Rich Presence via **OAuth2** (Metrolist-style) over the
/// Gateway. The user authorizes in the system browser and the app receives an
/// access token with the `sdk.social_layer_presence` scope, which drives
/// presence over the Gateway just like a first-party client — no user-token
/// scraping, and external cover art resolves to real `mp:` asset refs so it
/// renders. Ported from the Inzx implementation.
class DiscordGatewayService {
  DiscordGatewayService._();
  static final DiscordGatewayService instance = DiscordGatewayService._();

  static const String _gatewayUrl = 'wss://gateway.discord.gg/?v=10&encoding=json';
  static const String _apiBase = 'https://discord.com/api/v10';

  // Secure storage (OAuth tokens)
  static const String _secureAccessTokenKey = 'nivio_discord_access_token';
  static const String _secureRefreshTokenKey = 'nivio_discord_refresh_token';
  static const String _secureExpiresAtKey = 'nivio_discord_expires_at';
  // Cached identity for the UI
  static const String _prefCachedName = 'nivio_discord_cached_name';
  static const String _prefCachedGlobal = 'nivio_discord_cached_global';
  static const String _prefCachedAvatar = 'nivio_discord_cached_avatar';

  static const String _logoUrl =
      'https://raw.githubusercontent.com/nirmaleeswar30/Nivio/main/assets/icon/icon.png';

  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();

  final ValueNotifier<DiscordGatewayState> stateNotifier =
      ValueNotifier<DiscordGatewayState>(
    const DiscordGatewayState(status: DiscordGatewayStatus.disconnected),
  );
  DiscordGatewayState get state => stateNotifier.value;

  String? _clientId;

  // OAuth token state
  String? _accessToken;
  String? _refreshToken;
  int _expiresAtEpochSec = 0;
  bool get isAuthorized => _accessToken != null && _accessToken!.isNotEmpty;
  bool _authorizeInProgress = false;

  // Gateway state
  WebSocket? _webSocket;
  StreamSubscription? _wsSubscription;
  Timer? _heartbeatTimer;
  Timer? _reconnectTimer;
  Timer? _presenceDebounceTimer;
  int? _lastSequence;
  int _reconnectAttempts = 0;
  bool _intentionalDisconnect = false;
  bool _refreshedThisCycle = false;

  // Current activity. kind: 'watching' | 'paused' | 'browsing' | null
  String? _kind;
  String? _title;
  String? _details;
  String? _posterUrl;
  DateTime? _startedAt;

  // Resolved external asset cache (source url -> "mp:..." ref)
  final Map<String, String> _assetCache = {};

  void _debug(String m) => debugPrint('[DiscordGateway] $m');

  // ─────────────────────────── Lifecycle ───────────────────────────

  /// Loads the client id + stored tokens and connects if already authorized.
  Future<void> load(String clientId) async {
    _clientId = clientId.trim();
    try {
      final prefs = await SharedPreferences.getInstance();
      final name = prefs.getString(_prefCachedName);
      if (name != null) {
        stateNotifier.value = DiscordGatewayState(
          status: DiscordGatewayStatus.disconnected,
          username: name,
          globalName: prefs.getString(_prefCachedGlobal),
          avatarUrl: prefs.getString(_prefCachedAvatar),
        );
      }
    } catch (_) {}
    try {
      _accessToken = await _secureStorage.read(key: _secureAccessTokenKey);
      _refreshToken = await _secureStorage.read(key: _secureRefreshTokenKey);
      _expiresAtEpochSec =
          int.tryParse(await _secureStorage.read(key: _secureExpiresAtKey) ?? '') ?? 0;
    } catch (e) {
      _debug('token read failed: $e');
    }

    if (isAuthorized &&
        state.status != DiscordGatewayStatus.connected &&
        state.status != DiscordGatewayStatus.connecting) {
      await _connectWithFreshToken();
    }
  }

  /// Runs the browser OAuth flow and stores the tokens. Returns true on success.
  /// Does not connect — the caller enables RPC, which triggers [load]/connect.
  Future<bool> authorize() async {
    final id = _clientId;
    if (id == null || id.isEmpty) {
      stateNotifier.value = state.copyWith(
        status: DiscordGatewayStatus.error,
        errorMessage: 'DISCORD_CLIENT_ID is not set in .env',
      );
      return false;
    }
    if (_authorizeInProgress) return false;
    _authorizeInProgress = true;
    stateNotifier.value =
        state.copyWith(status: DiscordGatewayStatus.connecting, errorMessage: null);
    try {
      final tokens = await DiscordOAuth.authorize(id);
      await _storeTokens(tokens);
      await connect();
      return true;
    } on DiscordAuthException catch (e) {
      stateNotifier.value = state.copyWith(
        status: DiscordGatewayStatus.disconnected,
        errorMessage: e.message,
      );
      return false;
    } catch (e) {
      stateNotifier.value = state.copyWith(
        status: DiscordGatewayStatus.disconnected,
        errorMessage: 'Sign-in failed: $e',
      );
      return false;
    } finally {
      _authorizeInProgress = false;
    }
  }

  /// Sign out: disconnect and forget all tokens + cached identity.
  Future<void> logout() async {
    _accessToken = null;
    _refreshToken = null;
    _expiresAtEpochSec = 0;
    try {
      await _secureStorage.delete(key: _secureAccessTokenKey);
      await _secureStorage.delete(key: _secureRefreshTokenKey);
      await _secureStorage.delete(key: _secureExpiresAtKey);
    } catch (_) {}
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_prefCachedName);
      await prefs.remove(_prefCachedGlobal);
      await prefs.remove(_prefCachedAvatar);
    } catch (_) {}
    disconnect();
    _assetCache.clear();
    stateNotifier.value =
        const DiscordGatewayState(status: DiscordGatewayStatus.disconnected);
  }

  Future<void> _storeTokens(DiscordTokens tokens) async {
    _accessToken = tokens.accessToken;
    if (tokens.refreshToken.isNotEmpty) _refreshToken = tokens.refreshToken;
    _expiresAtEpochSec = tokens.expiresInSec > 0
        ? (DateTime.now().millisecondsSinceEpoch ~/ 1000) + tokens.expiresInSec
        : 0;
    try {
      await _secureStorage.write(key: _secureAccessTokenKey, value: _accessToken);
      if (_refreshToken != null) {
        await _secureStorage.write(key: _secureRefreshTokenKey, value: _refreshToken);
      }
      await _secureStorage.write(
          key: _secureExpiresAtKey, value: _expiresAtEpochSec.toString());
    } catch (e) {
      _debug('persist tokens failed: $e');
    }
  }

  // ─────────────────────────── Token freshness ───────────────────────────

  Future<void> _connectWithFreshToken() async {
    await _refreshIfNeeded();
    await connect();
  }

  Future<bool> _refreshIfNeeded() async {
    final nowSec = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final needs = _refreshToken != null &&
        _refreshToken!.isNotEmpty &&
        _expiresAtEpochSec > 0 &&
        (_expiresAtEpochSec - nowSec) < 3600;
    if (!needs) return true;
    return _doRefresh();
  }

  Future<bool> _doRefresh() async {
    final id = _clientId;
    if (_refreshToken == null || _refreshToken!.isEmpty || id == null) return false;
    try {
      final tokens = await DiscordOAuth.refresh(id, _refreshToken!);
      await _storeTokens(tokens);
      _debug('token refreshed');
      return true;
    } catch (e) {
      _debug('token refresh failed: $e');
      return false;
    }
  }

  // ─────────────────────────── Gateway ───────────────────────────

  Future<void> connect() async {
    if (!isAuthorized) {
      stateNotifier.value = state.copyWith(
        status: DiscordGatewayStatus.disconnected,
        errorMessage: 'Not signed in',
      );
      return;
    }
    _intentionalDisconnect = false;
    _reconnectTimer?.cancel();
    _tearDownSocket();
    stateNotifier.value =
        state.copyWith(status: DiscordGatewayStatus.connecting, errorMessage: null);
    try {
      _webSocket = await WebSocket.connect(_gatewayUrl)
          .timeout(const Duration(seconds: 15));
      _reconnectAttempts = 0;
      _wsSubscription = _webSocket!.listen(
        _onMessage,
        onError: (e) => _handleDisconnect(error: 'Socket error: $e'),
        onDone: _onSocketDone,
        cancelOnError: false,
      );
    } catch (e) {
      _handleDisconnect(error: 'Connection failed: $e');
    }
  }

  void disconnect() {
    _intentionalDisconnect = true;
    _reconnectTimer?.cancel();
    _tearDownSocket();
    stateNotifier.value =
        state.copyWith(status: DiscordGatewayStatus.disconnected, errorMessage: null);
  }

  void _tearDownSocket() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    _wsSubscription?.cancel();
    _wsSubscription = null;
    try {
      _webSocket?.close(1000, 'Client closed');
    } catch (_) {}
    _webSocket = null;
  }

  void _onSocketDone() {
    final code = _webSocket?.closeCode;
    // 4004 = auth failed (expired/invalid token) → try one refresh.
    if (code == 4004 && !_refreshedThisCycle) {
      _refreshedThisCycle = true;
      _tearDownSocket();
      _doRefresh().then((ok) {
        if (ok && !_intentionalDisconnect) {
          connect();
        } else {
          stateNotifier.value = state.copyWith(
            status: DiscordGatewayStatus.error,
            errorMessage: 'Session expired. Please reconnect Discord.',
          );
        }
      });
      return;
    }
    if (!_intentionalDisconnect) _handleDisconnect(error: 'Connection lost');
  }

  void _handleDisconnect({String? error}) {
    _tearDownSocket();
    if (_intentionalDisconnect || !isAuthorized) {
      stateNotifier.value = state.copyWith(
        status: DiscordGatewayStatus.disconnected,
        errorMessage: error,
      );
      return;
    }
    stateNotifier.value = state.copyWith(
      status: DiscordGatewayStatus.connecting,
      errorMessage: error != null ? '$error (reconnecting…)' : 'Reconnecting…',
    );
    _reconnectAttempts++;
    final backoff = min(60, 3 * pow(2, min(_reconnectAttempts, 4)).toInt());
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(Duration(seconds: backoff), () {
      if (isAuthorized && !_intentionalDisconnect) connect();
    });
  }

  void _onMessage(dynamic message) {
    try {
      final data = jsonDecode(message as String);
      final int op = data['op'] as int? ?? -1;
      final dynamic d = data['d'];
      final int? s = data['s'] as int?;
      if (s != null) _lastSequence = s;

      switch (op) {
        case 10: // HELLO
          _startHeartbeat(d['heartbeat_interval'] as int? ?? 41250);
          _sendIdentify();
          break;
        case 0: // DISPATCH
          if (data['t'] == 'READY') _handleReady(d);
          break;
        case 1:
          _sendHeartbeat();
          break;
        case 7:
        case 9:
          _handleDisconnect(error: 'Gateway asked to reconnect');
          break;
      }
    } catch (e) {
      _debug('parse error: $e');
    }
  }

  void _startHeartbeat(int intervalMs) {
    _heartbeatTimer?.cancel();
    final jitter = (intervalMs * (0.1 + 0.8 * Random().nextDouble())).floor();
    _heartbeatTimer = Timer(Duration(milliseconds: jitter), () {
      _sendHeartbeat();
      _heartbeatTimer =
          Timer.periodic(Duration(milliseconds: intervalMs), (_) => _sendHeartbeat());
    });
  }

  void _sendHeartbeat() {
    if (_webSocket?.readyState == WebSocket.open) {
      _webSocket!.add(jsonEncode({'op': 1, 'd': _lastSequence}));
    }
  }

  void _sendIdentify() {
    if (_webSocket?.readyState != WebSocket.open || _accessToken == null) return;
    _webSocket!.add(jsonEncode({
      'op': 2,
      'd': {
        'token': 'Bearer $_accessToken',
        'intents': 0,
        'properties': {
          'os': 'android',
          'browser': 'Discord Android',
          'device': _clientId ?? 'nivio',
        },
        'compress': false,
      },
    }));
  }

  void _handleReady(dynamic d) {
    _refreshedThisCycle = false;
    stateNotifier.value =
        state.copyWith(status: DiscordGatewayStatus.connected, errorMessage: null);
    _fetchCurrentUser();
    _sendPresence();
  }

  Future<void> _fetchCurrentUser() async {
    final token = _accessToken;
    if (token == null) return;
    try {
      final resp = await http.get(
        Uri.parse('$_apiBase/users/@me'),
        headers: {'Authorization': 'Bearer $token', 'Accept': 'application/json'},
      ).timeout(const Duration(seconds: 10));
      if (resp.statusCode < 200 || resp.statusCode >= 300) return;
      final user = jsonDecode(resp.body) as Map<String, dynamic>;
      final id = user['id'] as String?;
      final username = user['username'] as String?;
      final globalName = user['global_name'] as String?;
      final avatarHash = user['avatar'] as String?;
      String? avatarUrl;
      if (id != null && avatarHash != null && avatarHash.isNotEmpty) {
        avatarUrl = 'https://cdn.discordapp.com/avatars/$id/$avatarHash.png?size=128';
      }
      try {
        final prefs = await SharedPreferences.getInstance();
        if (username != null) await prefs.setString(_prefCachedName, username);
        if (globalName != null) await prefs.setString(_prefCachedGlobal, globalName);
        if (avatarUrl != null) await prefs.setString(_prefCachedAvatar, avatarUrl);
      } catch (_) {}
      stateNotifier.value = state.copyWith(
        status: DiscordGatewayStatus.connected,
        username: username,
        globalName: globalName,
        avatarUrl: avatarUrl,
      );
    } catch (e) {
      _debug('fetchCurrentUser failed: $e');
    }
  }

  // ─────────────────────────── Presence API ───────────────────────────

  void setWatching({
    required String title,
    String? details,
    String? posterUrl,
    DateTime? startedAt,
  }) {
    _kind = 'watching';
    _title = title;
    _details = details;
    _posterUrl = posterUrl;
    _startedAt = startedAt ?? DateTime.now();
    _triggerPresence();
  }

  void setPaused({String? title}) {
    _kind = 'paused';
    _title = title;
    _details = 'Paused';
    _startedAt = null;
    _triggerPresence();
  }

  void setBrowsing() {
    _kind = 'browsing';
    _title = 'Browsing';
    _details = 'Exploring movies & shows';
    _posterUrl = null;
    _startedAt = null;
    _triggerPresence();
  }

  void clearActivity() {
    _kind = null;
    _triggerPresence();
  }

  void _triggerPresence() {
    _presenceDebounceTimer?.cancel();
    _presenceDebounceTimer =
        Timer(const Duration(milliseconds: 400), _sendPresence);
  }

  Future<void> _sendPresence() async {
    if (_webSocket?.readyState != WebSocket.open) return;
    final activities = await _buildActivities();
    _webSocket!.add(jsonEncode({
      'op': 3,
      'd': {
        'since': null,
        'activities': activities,
        'status': 'online',
        'afk': false,
      },
    }));
  }

  Future<List<Map<String, dynamic>>> _buildActivities() async {
    final id = _clientId;
    if (id == null || id.isEmpty || _kind == null) return [];

    final activity = <String, dynamic>{
      'name': 'Nivio',
      'type': 3, // Watching
      'application_id': id,
      'details': _title ?? 'Nivio',
      if (_details != null && _details!.isNotEmpty) 'state': _details,
    };

    if (_kind == 'watching' && _startedAt != null) {
      activity['timestamps'] = {'start': _startedAt!.millisecondsSinceEpoch};
    }

    final assets = <String, dynamic>{};
    if (_kind == 'watching' && _posterUrl != null && _posterUrl!.isNotEmpty) {
      final large = await _resolveAsset(_posterUrl!);
      if (large != null) {
        assets['large_image'] = large;
        assets['large_text'] = _title ?? 'Nivio';
      }
      final small = await _resolveAsset(_logoUrl);
      if (small != null) {
        assets['small_image'] = small;
        assets['small_text'] = 'Nivio';
      }
    } else {
      final large = await _resolveAsset(_logoUrl);
      if (large != null) {
        assets['large_image'] = large;
        assets['large_text'] = 'Nivio';
      }
    }
    if (assets.isNotEmpty) activity['assets'] = assets;

    return [activity];
  }

  /// Converts an external https image URL into an `mp:` asset ref that Rich
  /// Presence accepts for an OAuth application. Cached per URL.
  Future<String?> _resolveAsset(String url) async {
    if (_assetCache.containsKey(url)) return _assetCache[url];
    final id = _clientId;
    final token = _accessToken;
    if (id == null || token == null) return null;
    try {
      final resp = await http
          .post(
            Uri.parse('$_apiBase/applications/$id/external-assets'),
            headers: {
              'Authorization': 'Bearer $token',
              'Content-Type': 'application/json',
            },
            body: jsonEncode({
              'urls': [url]
            }),
          )
          .timeout(const Duration(seconds: 10));
      if (resp.statusCode < 200 || resp.statusCode >= 300) return null;
      final list = jsonDecode(resp.body) as List<dynamic>;
      if (list.isEmpty) return null;
      final path =
          (list.first as Map<String, dynamic>)['external_asset_path'] as String?;
      if (path == null) return null;
      final ref = 'mp:$path';
      _assetCache[url] = ref;
      return ref;
    } catch (e) {
      _debug('external-assets resolve failed: $e');
      return null;
    }
  }
}
