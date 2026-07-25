import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lucide_flutter/lucide_flutter.dart';

import '../../shared/theme/index.dart';
import 'desktop_cloud_sync_service.dart';
import 'firebase_auth_rest_service.dart';

class AuthView extends StatefulWidget {
  const AuthView({super.key});

  @override
  State<AuthView> createState() => _AuthViewState();
}

class _AuthViewState extends State<AuthView> {
  final FirebaseAuthRestService _auth = FirebaseAuthRestService.instance;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _auth.addListener(_onAuthChanged);
    unawaited(_auth.initialize());
  }

  @override
  void dispose() {
    _auth.removeListener(_onAuthChanged);
    super.dispose();
  }

  void _onAuthChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _signInWithGoogle() async {
    await _runAuthAction(() async {
      await _auth.signInWithGoogle();
      await DesktopCloudSyncService.instance.syncEverything();
      return 'Signed in successfully';
    });
  }

  Future<void> _continueAsGuest() async {
    await _runAuthAction(() async {
      await _auth.signInAnonymously();
      return 'Continuing as guest';
    });
  }

  Future<void> _runAuthAction(Future<String> Function() action) async {
    setState(() => _loading = true);
    try {
      final message = await action();
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Sign in failed: $error'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final accent = context.appAccent;
    return Scaffold(
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [AppColors.surface, Colors.black],
          ),
        ),
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpacing.xxl),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Image.asset(
                    'assets/images/nivio-dark.png',
                    height: 180,
                    fit: BoxFit.contain,
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  Text(
                    'Unlimited movies, TV shows, and more',
                    textAlign: TextAlign.center,
                    style: AppTypography.pageTitle,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    'Sign in to sync your watchlist and history across devices.',
                    textAlign: TextAlign.center,
                    style: AppTypography.body.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 56),
                  if (_loading || _auth.isBusy)
                    CircularProgressIndicator(color: accent)
                  else ...[
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: _auth.isGoogleConfigured
                            ? _signInWithGoogle
                            : null,
                        icon: const Icon(LucideIcons.logIn, size: 22),
                        label: const Text('SIGN IN WITH GOOGLE'),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: _auth.isConfigured ? _continueAsGuest : null,
                        icon: const Icon(LucideIcons.userRound, size: 22),
                        label: const Text('CONTINUE AS GUEST'),
                      ),
                    ),
                  ],
                  const SizedBox(height: AppSpacing.lg),
                  Text(
                    _auth.isConfigured
                        ? 'Guest mode saves data locally on this desktop.'
                        : 'Firebase auth is not configured.',
                    textAlign: TextAlign.center,
                    style: AppTypography.caption,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
