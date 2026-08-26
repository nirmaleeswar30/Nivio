import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';

import 'package:nivio/core/debug_log.dart';

/// Service for handling Firebase Authentication
class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final GoogleSignIn _googleSignIn = GoogleSignIn.instance;
  Future<void>? _googleSignInInit;

  /// Get current user
  User? get currentUser => _auth.currentUser;

  /// Stream of auth state changes
  Stream<User?> get authStateChanges => _auth.authStateChanges();

  /// Check if user is signed in
  bool get isSignedIn => currentUser != null;

  Future<void> _ensureGoogleSignInInitialized() {
    return _googleSignInInit ??= _googleSignIn.initialize();
  }

  /// Sign in with Google
  Future<UserCredential?> signInWithGoogle() async {
    try {
      appDebugLog('🔐 Starting Google Sign-In...');
      await _ensureGoogleSignInInitialized();

      // Trigger the authentication flow
      final GoogleSignInAccount googleUser = await _googleSignIn.authenticate();

      appDebugLog('✅ Google account selected: ${googleUser.email}');

      // Obtain the auth details from the request
      final GoogleSignInAuthentication googleAuth = googleUser.authentication;

      if (googleAuth.idToken == null) {
        throw FirebaseAuthException(
          code: 'missing-google-id-token',
          message: 'Google Sign-In did not return an ID token.',
        );
      }

      // Create a new credential
      final credential = GoogleAuthProvider.credential(
        idToken: googleAuth.idToken,
      );

      appDebugLog('🔑 Signing in to Firebase...');

      // Sign in to Firebase with the Google credential
      final userCredential = await _auth.signInWithCredential(credential);

      appDebugLog(
        '✅ Firebase sign-in successful: ${userCredential.user?.email}',
      );

      return userCredential;
    } on GoogleSignInException catch (e) {
      if (e.code == GoogleSignInExceptionCode.canceled) {
        appDebugLog('❌ Google Sign-In cancelled by user');
        return null;
      }
      appDebugLog('❌ Error signing in with Google: $e');
      rethrow;
    } catch (e) {
      appDebugLog('❌ Error signing in with Google: $e');
      rethrow;
    }
  }

  /// Sign in anonymously
  Future<UserCredential> signInAnonymously() async {
    try {
      appDebugLog('🔐 Signing in anonymously...');
      final userCredential = await _auth.signInAnonymously();
      appDebugLog('✅ Anonymous sign-in successful');
      return userCredential;
    } catch (e) {
      appDebugLog('❌ Error signing in anonymously: $e');
      rethrow;
    }
  }

  /// Sign out
  Future<void> signOut() async {
    try {
      appDebugLog('🚪 Signing out...');
      await _ensureGoogleSignInInitialized();
      await Future.wait([_auth.signOut(), _googleSignIn.signOut()]);
      appDebugLog('✅ Sign-out successful');
    } catch (e) {
      appDebugLog('❌ Error signing out: $e');
      rethrow;
    }
  }

  /// Get user display name
  String? get displayName => currentUser?.displayName;

  /// Get user email
  String? get email => currentUser?.email;

  /// Get user photo URL
  String? get photoURL => currentUser?.photoURL;

  /// Get user ID
  String? get uid => currentUser?.uid;
}
