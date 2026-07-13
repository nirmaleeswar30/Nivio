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

  User? get currentUser => _currentUser;
  String? get idToken => _idToken;

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

  Future<void> _saveUser(User? user, {String? token}) async {
    _currentUser = user;
    _idToken = token;
    _authController.add(user);
    try {
      final prefs = await SharedPreferences.getInstance();
      if (user == null) {
        await prefs.remove('stub_firebase_user');
        await prefs.remove('stub_firebase_token');
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
      }
    } catch (_) {}
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
    final user = User(
      uid: uid,
      isAnonymous: true,
    );

    await _saveUser(user, token: token);
    return UserCredential(user: user);
  }

  Future<void> signOut() async {
    await _saveUser(null);
  }

  Future<UserCredential> signInWithCredential(AuthCredential credential) async {
    throw UnimplementedError('Google Sign-In is not supported on desktop.');
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
}

class UserCredential {
  final User? user;

  UserCredential({this.user});
}

class AuthCredential {}

class GoogleAuthProvider {
  static AuthCredential credential({String? idToken, String? accessToken}) {
    return AuthCredential();
  }
}

class FirebaseAuthException implements Exception {
  final String code;
  final String message;

  FirebaseAuthException({required this.code, required this.message});

  @override
  String toString() => 'FirebaseAuthException: [$code] $message';
}
