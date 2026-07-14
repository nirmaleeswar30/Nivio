library firebase_auth;

import 'dart:async';
import 'dart:convert';
import 'package:firebase_core/firebase_core.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class FirebaseAuth {
  static final FirebaseAuth instance = FirebaseAuth._();
  FirebaseAuth._() {
    _loadUser();
  }

  final _authController = StreamController<User?>.broadcast();
  User? _currentUser;
  String? _idToken;
  String? _refreshToken;

  User? get currentUser => _currentUser;

  Stream<User?> authStateChanges() {
    // Emit current user initially if available
    Future.microtask(() => _authController.add(_currentUser));
    return _authController.stream;
  }

  Future<void> _loadUser() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final userJson = prefs.getString('stub_firebase_user');
      _idToken = prefs.getString('stub_firebase_token');
      _refreshToken = prefs.getString('stub_firebase_refresh_token');
      if (userJson != null) {
        final data = jsonDecode(userJson) as Map<String, dynamic>;
        _currentUser = User(
          uid: data['uid'],
          email: data['email'],
          displayName: data['displayName'],
          isAnonymous: data['isAnonymous'] ?? true,
          photoURL: data['photoURL'],
        );
        _authController.add(_currentUser);
      }
    } catch (_) {}
  }

  Future<void> _saveUser(User? user, {String? token, String? refreshToken}) async {
    _currentUser = user;
    if (token != null) _idToken = token;
    if (refreshToken != null) _refreshToken = refreshToken;
    _authController.add(user);
    try {
      final prefs = await SharedPreferences.getInstance();
      if (user == null) {
        _idToken = null;
        _refreshToken = null;
        await prefs.remove('stub_firebase_user');
        await prefs.remove('stub_firebase_token');
        await prefs.remove('stub_firebase_refresh_token');
      } else {
        await prefs.setString(
          'stub_firebase_user',
          jsonEncode({
            'uid': user.uid,
            'email': user.email,
            'displayName': user.displayName,
            'isAnonymous': user.isAnonymous,
            'photoURL': user.photoURL,
          }),
        );
        if (token != null) {
          await prefs.setString('stub_firebase_token', token);
        }
        if (refreshToken != null) {
          await prefs.setString('stub_firebase_refresh_token', refreshToken);
        }
      }
    } catch (_) {}
  }

  Future<String?> getIdToken({bool forceRefresh = false}) async {
    if (_idToken == null) return null;

    bool isExpired = forceRefresh;
    if (!isExpired) {
      final payload = _decodeJwt(_idToken!);
      final exp = payload['exp'] as int?;
      if (exp != null) {
        final nowSeconds = DateTime.now().millisecondsSinceEpoch ~/ 1000;
        // Expired if current time is within 5 minutes (300 seconds) of expiration
        if (nowSeconds >= (exp - 300)) {
          isExpired = true;
        }
      } else {
        isExpired = true;
      }
    }

    if (isExpired && _refreshToken != null) {
      final apiKey = Firebase.options?.apiKey;
      if (apiKey != null) {
        try {
          final url = Uri.parse('https://securetoken.googleapis.com/v1/token?key=$apiKey');
          final response = await http.post(
            url,
            headers: {'content-type': 'application/x-www-form-urlencoded'},
            body: {
              'grant_type': 'refresh_token',
              'refresh_token': _refreshToken!,
            },
          );

          if (response.statusCode == 200) {
            final data = jsonDecode(response.body);
            final newToken = data['id_token'] as String;
            final newRefreshToken = data['refresh_token'] as String;
            await _saveUser(_currentUser, token: newToken, refreshToken: newRefreshToken);
            return newToken;
          } else {
            // Clear user session if refresh fails
            await signOut();
            return null;
          }
        } catch (_) {
          return _idToken; // Fallback to current token if network fails
        }
      }
    }

    return _idToken;
  }

  Future<UserCredential> signInAnonymously() async {
    final apiKey = Firebase.options?.apiKey;
    if (apiKey == null) {
      throw FirebaseAuthException(
        code: 'api-key-missing',
        message: 'Firebase Options API Key is missing.',
      );
    }

    final url = Uri.parse('https://identitytoolkit.googleapis.com/v1/accounts:signUp?key=$apiKey');
    final response = await http.post(
      url,
      headers: {'content-type': 'application/json'},
      body: jsonEncode({'returnSecureToken': true}),
    );

    if (response.statusCode != 200) {
      throw FirebaseAuthException(
        code: 'auth-error',
        message: 'Failed to sign in anonymously: ${response.body}',
      );
    }

    final resData = jsonDecode(response.body);
    final uid = resData['localId'];
    final token = resData['idToken'];
    final refreshToken = resData['refreshToken'];
    final user = User(
      uid: uid,
      isAnonymous: true,
    );

    await _saveUser(user, token: token, refreshToken: refreshToken);
    return UserCredential(user: user);
  }

  Future<void> signOut() async {
    await _saveUser(null);
  }

  Future<UserCredential> signInWithCredential(AuthCredential credential) async {
    final idToken = credential.idToken;
    if (idToken == null) {
      throw FirebaseAuthException(
        code: 'missing-id-token',
        message: 'Google Sign-In did not return an ID token.',
      );
    }

    final apiKey = Firebase.options?.apiKey;
    if (apiKey == null) {
      throw FirebaseAuthException(
        code: 'api-key-missing',
        message: 'Firebase Options API Key is missing.',
      );
    }

    final url = Uri.parse('https://identitytoolkit.googleapis.com/v1/accounts:signInWithIdp?key=$apiKey');
    final response = await http.post(
      url,
      headers: {'content-type': 'application/json'},
      body: jsonEncode({
        'postBody': 'id_token=$idToken&providerId=google.com',
        'requestUri': 'http://localhost',
        'returnSecureToken': true,
      }),
    );

    if (response.statusCode != 200) {
      throw FirebaseAuthException(
        code: 'auth-error',
        message: 'Failed to sign in with ID token: ${response.body}',
      );
    }

    final resData = jsonDecode(response.body);
    final uid = resData['localId'];
    final token = resData['idToken'];
    final refreshToken = resData['refreshToken'];
    final email = resData['email'];
    final displayName = resData['displayName'];
    final photoURL = resData['photoUrl'];

    final user = User(
      uid: uid,
      email: email,
      displayName: displayName,
      photoURL: photoURL,
      isAnonymous: false,
    );

    await _saveUser(user, token: token, refreshToken: refreshToken);
    return UserCredential(user: user);
  }
}

class User {
  final String uid;
  final String? email;
  final String? displayName;
  final bool isAnonymous;
  final String? photoURL;

  User({
    required this.uid,
    this.email,
    this.displayName,
    this.isAnonymous = false,
    this.photoURL,
  });

  Future<String?> getIdToken([bool forceRefresh = false]) async {
    return FirebaseAuth.instance.getIdToken(forceRefresh: forceRefresh);
  }
}

class UserCredential {
  final User? user;

  UserCredential({this.user});
}

class AuthCredential {
  final String? idToken;
  AuthCredential({this.idToken});
}

class GoogleAuthProvider {
  static AuthCredential credential({String? idToken, String? accessToken}) {
    return AuthCredential(idToken: idToken);
  }
}

class FirebaseAuthException implements Exception {
  final String code;
  final String message;

  FirebaseAuthException({required this.code, required this.message});

  @override
  String toString() => 'FirebaseAuthException: [$code] $message';
}

Map<String, dynamic> _decodeJwt(String token) {
  try {
    final parts = token.split('.');
    if (parts.length != 3) return {};
    final payload = parts[1];
    final normalized = base64Url.normalize(payload);
    final decoded = utf8.decode(base64Url.decode(normalized));
    return jsonDecode(decoded) as Map<String, dynamic>;
  } catch (_) {
    return {};
  }
}
