import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:nivio/core/theme.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  bool _isLoading = false;

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

  Future<void> _signInAnonymously() async {
    setState(() => _isLoading = true);
    
    try {
      await FirebaseAuth.instance.signInAnonymously();
      if (mounted) {
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
              Text(
                'Unlimited movies, TV shows, and more',
                style: Theme.of(context).textTheme.titleLarge,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 64),
              
              // Sign In Button
              if (_isLoading)
                const CircularProgressIndicator(
                  color: NivioTheme.netflixRed,
                )
              else
                ElevatedButton(
                  onPressed: _signInAnonymously,
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 48,
                      vertical: 16,
                    ),
                    backgroundColor: NivioTheme.netflixRed,
                  ),
                  child: const Text(
                    'GET STARTED',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.5,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
