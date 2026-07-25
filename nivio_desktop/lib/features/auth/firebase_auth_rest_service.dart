import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/config/app_environment.dart';

class DesktopAuthUser {
  const DesktopAuthUser({
    required this.uid,
    required this.isAnonymous,
    this.email,
    this.displayName,
    this.photoUrl,
  });

  final String uid;
  final bool isAnonymous;
  final String? email;
  final String? displayName;
  final String? photoUrl;

  String get title {
    final name = displayName?.trim();
    if (name != null && name.isNotEmpty) return name;
    final mail = email?.trim();
    if (mail != null && mail.isNotEmpty) return mail;
    return isAnonymous ? 'Nivio Guest' : 'Nivio User';
  }

  String get subtitle {
    if (isAnonymous) return 'Guest account';
    final mail = email?.trim();
    if (mail != null && mail.isNotEmpty) return mail;
    return 'Signed in';
  }
}

class FirebaseAuthRestService extends ChangeNotifier {
  FirebaseAuthRestService._();

  static final FirebaseAuthRestService instance = FirebaseAuthRestService._();

  static const _uidKey = 'firebase_auth_uid';
  static const _idTokenKey = 'firebase_auth_id_token';
  static const _refreshTokenKey = 'firebase_auth_refresh_token';
  static const _expiresAtKey = 'firebase_auth_expires_at_ms';
  static const _emailKey = 'firebase_auth_email';
  static const _displayNameKey = 'firebase_auth_display_name';
  static const _photoUrlKey = 'firebase_auth_photo_url';
  static const _anonymousKey = 'firebase_auth_is_anonymous';

  final http.Client _client = http.Client();
  bool _initialized = false;
  bool _busy = false;
  String? _idToken;
  String? _refreshToken;
  int _expiresAtMs = 0;
  DesktopAuthUser? _currentUser;

  bool get isBusy => _busy;
  bool get isInitialized => _initialized;
  DesktopAuthUser? get currentUser => _currentUser;
  bool get isSignedIn => _currentUser != null;
  bool get canSyncCloud =>
      _currentUser != null && _currentUser?.isAnonymous != true;
  bool get isConfigured =>
      AppEnvironment.firebaseWebApiKey.isNotEmpty &&
      AppEnvironment.firebaseProjectId.isNotEmpty;
  bool get isGoogleConfigured =>
      isConfigured &&
      AppEnvironment.firebaseGoogleClientId.isNotEmpty &&
      AppEnvironment.authExchangeUrl.isNotEmpty;

  Future<void> initialize() async {
    if (_initialized) return;
    final prefs = await SharedPreferences.getInstance();
    _idToken = prefs.getString(_idTokenKey);
    _refreshToken = prefs.getString(_refreshTokenKey);
    _expiresAtMs = prefs.getInt(_expiresAtKey) ?? 0;
    final uid = prefs.getString(_uidKey);
    if (uid != null && uid.isNotEmpty) {
      _currentUser = DesktopAuthUser(
        uid: uid,
        isAnonymous: prefs.getBool(_anonymousKey) ?? false,
        email: prefs.getString(_emailKey),
        displayName: prefs.getString(_displayNameKey),
        photoUrl: prefs.getString(_photoUrlKey),
      );
    }
    _initialized = true;
    notifyListeners();
    if (_currentUser != null && _refreshToken != null) {
      unawaited(idToken(forceRefresh: true).catchError((_) => null));
    }
  }

  Future<DesktopAuthUser> signInAnonymously() async {
    _requireFirebaseConfig();
    return _runBusy(() async {
      final uri = _identityUri('accounts:signUp');
      final response = await _postJson(uri, {'returnSecureToken': true});
      final user = await _persistAuthResponse(response, isAnonymous: true);
      notifyListeners();
      return user;
    });
  }

  Future<DesktopAuthUser> signInWithGoogle() async {
    _requireGoogleConfig();
    return _runBusy(() async {
      final response = await _requestGoogleFirebaseSession();
      final user = await _persistAuthResponse(response, isAnonymous: false);
      notifyListeners();
      return user;
    });
  }

  Future<void> signOut() async {
    final prefs = await SharedPreferences.getInstance();
    await Future.wait([
      prefs.remove(_uidKey),
      prefs.remove(_idTokenKey),
      prefs.remove(_refreshTokenKey),
      prefs.remove(_expiresAtKey),
      prefs.remove(_emailKey),
      prefs.remove(_displayNameKey),
      prefs.remove(_photoUrlKey),
      prefs.remove(_anonymousKey),
    ]);
    _idToken = null;
    _refreshToken = null;
    _expiresAtMs = 0;
    _currentUser = null;
    notifyListeners();
  }

  Future<String?> idToken({bool forceRefresh = false}) async {
    await initialize();
    if (_currentUser == null) return null;
    final now = DateTime.now().millisecondsSinceEpoch;
    if (!forceRefresh && _idToken != null && now < _expiresAtMs - 60000) {
      return _idToken;
    }
    final refreshToken = _refreshToken;
    if (refreshToken == null || refreshToken.isEmpty) return _idToken;
    final response = await _client.post(
      Uri.https('securetoken.googleapis.com', '/v1/token', {
        'key': AppEnvironment.firebaseWebApiKey,
      }),
      headers: {'Content-Type': 'application/x-www-form-urlencoded'},
      body: {'grant_type': 'refresh_token', 'refresh_token': refreshToken},
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw AuthFailure(_firebaseErrorMessage(response.body));
    }
    final json = jsonDecode(response.body) as Map<String, dynamic>;
    _idToken = json['id_token']?.toString();
    _refreshToken = json['refresh_token']?.toString() ?? refreshToken;
    final expiresIn =
        int.tryParse(json['expires_in']?.toString() ?? '') ?? 3600;
    _expiresAtMs = DateTime.now()
        .add(Duration(seconds: expiresIn))
        .millisecondsSinceEpoch;
    final uid = json['user_id']?.toString() ?? _currentUser!.uid;
    _currentUser = DesktopAuthUser(
      uid: uid,
      isAnonymous: _currentUser!.isAnonymous,
      email: _currentUser!.email,
      displayName: _currentUser!.displayName,
      photoUrl: _currentUser!.photoUrl,
    );
    await _saveSession();
    notifyListeners();
    return _idToken;
  }

  Future<Map<String, dynamic>> _requestGoogleFirebaseSession() async {
    final verifier = _randomVerifier();
    final challenge = _base64UrlNoPadding(
      sha256.convert(utf8.encode(verifier)).bytes,
    );
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final redirectUri = 'http://127.0.0.1:${server.port}/';
    try {
      final authUri = Uri.https('accounts.google.com', '/o/oauth2/v2/auth', {
        'client_id': AppEnvironment.firebaseGoogleClientId,
        'redirect_uri': redirectUri,
        'response_type': 'code',
        'scope': 'openid email profile',
        'code_challenge': challenge,
        'code_challenge_method': 'S256',
        'access_type': 'offline',
        'prompt': 'select_account',
      });
      final launched = await launchUrl(
        authUri,
        mode: LaunchMode.externalApplication,
      );
      if (!launched) {
        throw const AuthFailure('Could not open Google sign-in in browser.');
      }
      final request = await server.first.timeout(const Duration(minutes: 3));
      final params = request.uri.queryParameters;
      final error = params['error'];
      if (error != null) {
        final description = params['error_description'];
        await _writeBrowserResponse(
          request,
          'Nivio sign-in cancelled',
          'You can close this tab and return to Nivio.',
        );
        throw AuthFailure(
          'Google sign-in failed: $error'
          '${description == null ? '' : ' - $description'}',
        );
      }
      final code = params['code'];
      if (code == null || code.isEmpty) {
        await _writeBrowserResponse(
          request,
          'Nivio sign-in failed',
          'No authorization code was returned.',
        );
        throw const AuthFailure('Google did not return an authorization code.');
      }
      await _writeBrowserResponse(
        request,
        'Nivio sign-in complete',
        'You can close this tab and return to Nivio.',
      );
      return _exchangeGoogleCodeForFirebaseSession(
        code: code,
        codeVerifier: verifier,
        redirectUri: redirectUri,
      );
    } finally {
      await server.close(force: true);
    }
  }

  Future<Map<String, dynamic>> _exchangeGoogleCodeForFirebaseSession({
    required String code,
    required String codeVerifier,
    required String redirectUri,
  }) async {
    final exchangeUrl = AppEnvironment.authExchangeUrl;
    if (exchangeUrl.isEmpty) {
      throw const AuthFailure(
        'Google sign-in needs AUTH_EXCHANGE_URL or API_BASE_URL for backend token exchange.',
      );
    }

    final response = await _client.post(
      Uri.parse(exchangeUrl),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'code': code,
        'codeVerifier': codeVerifier,
        'redirectUri': redirectUri,
        'clientId': AppEnvironment.firebaseGoogleClientId,
      }),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw AuthFailure(_firebaseErrorMessage(response.body));
    }
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  Future<DesktopAuthUser> _persistAuthResponse(
    Map<String, dynamic> json, {
    required bool isAnonymous,
  }) async {
    final uid = json['localId']?.toString();
    final idToken = json['idToken']?.toString();
    final refreshToken = json['refreshToken']?.toString();
    if (uid == null || uid.isEmpty || idToken == null || idToken.isEmpty) {
      throw const AuthFailure('Firebase returned an incomplete auth session.');
    }
    final expiresIn = int.tryParse(json['expiresIn']?.toString() ?? '') ?? 3600;
    _idToken = idToken;
    _refreshToken = refreshToken;
    _expiresAtMs = DateTime.now()
        .add(Duration(seconds: expiresIn))
        .millisecondsSinceEpoch;
    _currentUser = DesktopAuthUser(
      uid: uid,
      isAnonymous: isAnonymous,
      email: _stringOrNull(json['email']),
      displayName: _stringOrNull(json['displayName']),
      photoUrl: _stringOrNull(json['photoUrl']),
    );
    await _saveSession();
    return _currentUser!;
  }

  Future<void> _saveSession() async {
    final user = _currentUser;
    if (user == null) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_uidKey, user.uid);
    if (_idToken != null) await prefs.setString(_idTokenKey, _idToken!);
    if (_refreshToken != null) {
      await prefs.setString(_refreshTokenKey, _refreshToken!);
    }
    await prefs.setInt(_expiresAtKey, _expiresAtMs);
    await prefs.setBool(_anonymousKey, user.isAnonymous);
    await _setOptionalString(prefs, _emailKey, user.email);
    await _setOptionalString(prefs, _displayNameKey, user.displayName);
    await _setOptionalString(prefs, _photoUrlKey, user.photoUrl);
  }

  Future<Map<String, dynamic>> _postJson(
    Uri uri,
    Map<String, dynamic> body,
  ) async {
    final response = await _client.post(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(body),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw AuthFailure(_firebaseErrorMessage(response.body));
    }
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  Uri _identityUri(String method) => Uri.https(
    'identitytoolkit.googleapis.com',
    '/v1/$method',
    {'key': AppEnvironment.firebaseWebApiKey},
  );

  Future<T> _runBusy<T>(Future<T> Function() action) async {
    _busy = true;
    notifyListeners();
    try {
      return await action();
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  void _requireFirebaseConfig() {
    if (isConfigured) return;
    throw const AuthFailure(
      'Firebase auth is not configured. Add FIREBASE_WEB_API_KEY and FIREBASE_PROJECT_ID.',
    );
  }

  void _requireGoogleConfig() {
    _requireFirebaseConfig();
    if (AppEnvironment.firebaseGoogleClientId.isNotEmpty &&
        AppEnvironment.authExchangeUrl.isNotEmpty) {
      return;
    }
    throw const AuthFailure(
      'Google sign-in is not configured. Add FIREBASE_GOOGLE_CLIENT_ID and AUTH_EXCHANGE_URL.',
    );
  }

  static String _randomVerifier() {
    final random = Random.secure();
    final bytes = List<int>.generate(64, (_) => random.nextInt(256));
    return _base64UrlNoPadding(bytes);
  }

  static String _base64UrlNoPadding(List<int> bytes) =>
      base64UrlEncode(bytes).replaceAll('=', '');

  static Future<void> _writeBrowserResponse(
    HttpRequest request,
    String title,
    String body,
  ) async {
    request.response
      ..statusCode = HttpStatus.ok
      ..headers.contentType = ContentType.html
      ..write(
        '<!doctype html><html><head><meta charset="utf-8"><title>$title</title></head>'
        '<body style="font-family:sans-serif;background:#111;color:#eee;padding:32px">'
        '<h1>$title</h1><p>$body</p></body></html>',
      );
    await request.response.close();
  }

  static String _firebaseErrorMessage(String body) {
    try {
      final json = jsonDecode(body);
      final message = json['error']?['message'];
      if (message != null) return message.toString();
    } catch (_) {}
    return body;
  }

  static String? _stringOrNull(Object? value) {
    final text = value?.toString().trim();
    return text == null || text.isEmpty ? null : text;
  }

  static Future<void> _setOptionalString(
    SharedPreferences prefs,
    String key,
    String? value,
  ) {
    if (value == null || value.isEmpty) return prefs.remove(key);
    return prefs.setString(key, value);
  }
}

class AuthFailure implements Exception {
  const AuthFailure(this.message);

  final String message;

  @override
  String toString() => message;
}
