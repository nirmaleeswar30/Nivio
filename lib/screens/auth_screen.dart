import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:nivio/core/theme.dart';
import 'package:nivio/providers/auth_provider.dart';
import 'package:nivio/providers/watchlist_provider.dart';

class AuthScreen extends ConsumerStatefulWidget {
  const AuthScreen({super.key});

  @override
  ConsumerState<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends ConsumerState<AuthScreen> {
  bool _isLoading = false;

  /// Check if Google Sign-In is supported on this platform
  bool get _supportsGoogleSignIn {
    if (kIsWeb) return true; // Web supports Google Sign-In
    // Google Sign-In works on Android, iOS, macOS
    // Not supported on Windows and Linux
    return Platform.isAndroid || Platform.isIOS || Platform.isMacOS;
  }

  @override
  void initState() {
    super.initState();
    _checkAuthState();
  }

  Future<void> _checkAuthState() async {
    // Check if user is already signed in
    final user = FirebaseAuth.instance.currentUser;
    if (user != null && mounted) {
      context.go('/');
    }
  }

  Future<void> _signInWithGoogle() async {
    if (!_supportsGoogleSignIn) return;
    
    setState(() => _isLoading = true);
    
    try {
      final authService = ref.read(authServiceProvider);
      final result = await authService.signInWithGoogle();
      
      if (result != null && mounted) {
        // Sync watchlist to cloud after sign in
        final watchlistService = ref.read(watchlistServiceProvider);
        await watchlistService.syncAllToCloud();
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Signed in successfully!'),
              duration: Duration(seconds: 2),
            ),
          );
          context.go('/');
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Sign in failed: $e'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _signInAnonymously() async {
    setState(() => _isLoading = true);
    
    try {
      final authService = ref.read(authServiceProvider);
      await authService.signInAnonymously();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Continuing as guest'),
            duration: Duration(seconds: 2),
          ),
        );
        context.go('/');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to sign in: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              NivioTheme.netflixBlack,
              Color(0xFF000000),
            ],
          ),
        ),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Logo
              Image.asset(
                'assets/images/nivio-dark.png',
                height: 180,
                fit: BoxFit.contain,
              ),
              const SizedBox(height: 16),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32.0),
                child: Text(
                  'Unlimited movies, TV shows, and more',
                  style: Theme.of(context).textTheme.titleLarge,
                  textAlign: TextAlign.center,
                ),
              ),
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32.0),
                child: Text(
                  'Sign in to sync your watchlist across devices',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Colors.white70,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
              const SizedBox(height: 64),
              
              // Sign In Buttons
              if (_isLoading)
                const CircularProgressIndicator(
                  color: NivioTheme.netflixRed,
                )
              else ...[
                // Google Sign In Button (only show on supported platforms)
                if (_supportsGoogleSignIn) ...[
                  ElevatedButton.icon(
                    onPressed: _signInWithGoogle,
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 32,
                        vertical: 16,
                      ),
                      backgroundColor: Colors.white,
                      foregroundColor: Colors.black87,
                    ),
                    icon: const Icon(Icons.login, size: 24),
                    label: const Text(
                      'SIGN IN WITH GOOGLE',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.2,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
                
                // Guest/Anonymous Button (or main button on Windows/Linux)
                if (_supportsGoogleSignIn)
                  OutlinedButton(
                    onPressed: _signInAnonymously,
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 32,
                        vertical: 16,
                      ),
                      side: const BorderSide(color: Colors.white70, width: 2),
                      foregroundColor: Colors.white,
                    ),
                    child: const Text(
                      'CONTINUE AS GUEST',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.2,
                      ),
                    ),
                  )
                else
                  // On Windows/Linux, show a primary button for guest mode
                  ElevatedButton.icon(
                    onPressed: _signInAnonymously,
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 32,
                        vertical: 16,
                      ),
                      backgroundColor: NivioTheme.netflixRed,
                      foregroundColor: Colors.white,
                    ),
                    icon: const Icon(Icons.play_arrow, size: 24),
                    label: const Text(
                      'GET STARTED',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.2,
                      ),
                    ),
                  ),
                const SizedBox(height: 16),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 48.0),
                  child: Text(
                    _supportsGoogleSignIn
                        ? 'Guest mode: Your watchlist will only be saved locally'
                        : 'Your watchlist will be saved locally on this device',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Colors.white60,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
