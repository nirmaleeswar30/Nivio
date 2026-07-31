import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../core/services/desktop_update_service.dart';
import '../features/auth/auth_view.dart';
import '../features/auth/firebase_auth_rest_service.dart';
import '../shared/layout/desktop_scaffold.dart';
import '../shared/theme/index.dart';
import '../shared/widgets/dialogs/update_dialog.dart';
import '../core/interfaces/search_repository.dart';
import '../core/interfaces/home_repository.dart';
import '../core/interfaces/details_repository.dart';
import '../features/player/services/stream_resolver.dart';
import '../features/player/playback_engine.dart';
import '../core/interfaces/watch_history_repository.dart';

class NivioStartupSplashApp extends StatelessWidget {
  const NivioStartupSplashApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Nivio Desktop',
      debugShowCheckedModeBanner: false,
      theme: buildNivioDesktopTheme(),
      home: const _StartupSplashView(),
    );
  }
}

class NivioStartupErrorApp extends StatelessWidget {
  const NivioStartupErrorApp({super.key, required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Nivio Desktop',
      debugShowCheckedModeBanner: false,
      theme: buildNivioDesktopTheme(),
      home: _StartupErrorView(message: message),
    );
  }
}

/// Root widget for the Nivio Linux desktop application.
class NivioDesktopApp extends StatefulWidget {
  final SearchRepository? searchRepository;
  final HomeRepository? homeRepository;
  final DetailsRepository? detailsRepository;
  final StreamResolver? streamResolver;
  final PlaybackEngineFactory? playbackEngineFactory;
  final WatchHistoryRepository? watchHistoryRepository;
  final bool requireAuthentication;

  const NivioDesktopApp({
    super.key,
    this.searchRepository,
    this.homeRepository,
    this.detailsRepository,
    this.streamResolver,
    this.playbackEngineFactory,
    this.watchHistoryRepository,
    this.requireAuthentication = true,
  });

  @override
  State<NivioDesktopApp> createState() => _NivioDesktopAppState();
}

class _NivioDesktopAppState extends State<NivioDesktopApp> {
  final AppAccentController _accentController = AppAccentController.instance;
  final FirebaseAuthRestService _auth = FirebaseAuthRestService.instance;

  @override
  void initState() {
    super.initState();
    _accentController.addListener(_onAccentChanged);
    _auth.addListener(_onAuthChanged);
    unawaited(_accentController.load());
    unawaited(_auth.initialize());
  }

  @override
  void dispose() {
    _accentController.removeListener(_onAccentChanged);
    _auth.removeListener(_onAuthChanged);
    super.dispose();
  }

  void _onAccentChanged() {
    if (mounted) setState(() {});
  }

  void _onAuthChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final home = _StartupUpdateGate(
      child: DesktopScaffold(
        searchRepository: widget.searchRepository,
        homeRepository: widget.homeRepository,
        detailsRepository: widget.detailsRepository,
        streamResolver: widget.streamResolver,
        playbackEngineFactory: widget.playbackEngineFactory,
        watchHistoryRepository: widget.watchHistoryRepository,
      ),
    );
    final Widget startScreen;
    if (widget.requireAuthentication && !_auth.isInitialized) {
      startScreen = const _StartupSplashView();
    } else if (widget.requireAuthentication && !_auth.isSignedIn) {
      startScreen = const AuthView();
    } else {
      startScreen = home;
    }

    return MaterialApp(
      title: 'Nivio Desktop',
      debugShowCheckedModeBanner: false,
      theme: buildNivioDesktopTheme(accentColor: _accentController.color),
      home: startScreen,
    );
  }
}

class _StartupSplashView extends StatelessWidget {
  const _StartupSplashView();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [AppColors.surface, Colors.black],
          ),
        ),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Image.asset(
                'assets/images/app-icon.png',
                width: 220,
                height: 220,
                fit: BoxFit.contain,
              ),
              const SizedBox(height: AppSpacing.xl),
              SizedBox(
                width: 32,
                height: 32,
                child: CircularProgressIndicator(
                  strokeWidth: 3,
                  color: context.appAccent,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StartupErrorView extends StatelessWidget {
  const _StartupErrorView({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [AppColors.surface, Colors.black],
          ),
        ),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.xl),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Image.asset(
                    'assets/images/app-icon.png',
                    width: 160,
                    height: 160,
                    fit: BoxFit.contain,
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  Text(
                    'Nivio could not start',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    'Check the desktop release configuration and start the app again.',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  DecoratedBox(
                    decoration: BoxDecoration(
                      color: AppColors.surfaceVariant,
                      borderRadius: BorderRadius.circular(AppRadius.medium),
                      border: Border.all(color: AppColors.borderSubtle),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(AppSpacing.md),
                      child: SelectableText(
                        message,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ),
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

class _StartupUpdateGate extends StatefulWidget {
  const _StartupUpdateGate({required this.child});

  final Widget child;

  @override
  State<_StartupUpdateGate> createState() => _StartupUpdateGateState();
}

class _StartupUpdateGateState extends State<_StartupUpdateGate> {
  bool _hasChecked = false;

  @override
  void initState() {
    super.initState();
    if (kReleaseMode) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !_hasChecked) {
          _hasChecked = true;
          unawaited(_checkForUpdates());
        }
      });
    }
  }

  Future<void> _checkForUpdates() async {
    final result = await DesktopUpdateService.checkForUpdates(
      includeShorebird: true,
      downloadShorebirdPatch: true,
    );
    if (!mounted) return;

    final fullRelease = result.fullRelease;
    if (fullRelease.hasUpdate) {
      await showDialog<void>(
        context: context,
        builder: (context) => UpdateDialog(
          currentVersion: fullRelease.installedVersion,
          latestVersion: fullRelease.latestVersion,
          releaseNotes: fullRelease.releaseNotes?.trim().isNotEmpty == true
              ? fullRelease.releaseNotes!
              : 'A new Linux desktop release is available.',
          onLater: () => Navigator.of(context).maybePop(),
          onInstall: () {
            Navigator.of(context).maybePop();
            unawaited(DesktopUpdateService.openInstallTarget(fullRelease));
          },
        ),
      );
      return;
    }

    final patch = result.patch;
    if (patch.action == DesktopPatchUpdateAction.downloaded ||
        patch.action == DesktopPatchUpdateAction.restartRequired) {
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Restart Required'),
          content: Text(patch.message),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).maybePop(),
              child: const Text('Later'),
            ),
          ],
        ),
      );
      return;
    }

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(result.message)));
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
