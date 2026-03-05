import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:nivio/core/theme.dart';
import 'package:nivio/firebase_options.dart';
import 'package:nivio/models/cache_entry.dart';
import 'package:nivio/models/watchlist_item.dart';
import 'package:nivio/models/new_episode.dart';
import 'package:nivio/services/cache_service.dart';
import 'package:nivio/services/watchlist_service.dart';
import 'package:nivio/services/episode_check_service.dart';
import 'package:nivio/services/github_release_update_service.dart';
import 'package:nivio/services/shorebird_update_service.dart';
import 'package:nivio/providers/service_providers.dart';
import 'package:nivio/providers/settings_providers.dart';
import 'package:nivio/screens/home_screen.dart';
import 'package:nivio/screens/search_screen.dart';
import 'package:nivio/screens/media_detail_screen.dart';
import 'package:nivio/screens/player_screen.dart';
import 'package:nivio/screens/auth_screen.dart';
import 'package:nivio/screens/library_screen.dart';
import 'package:nivio/screens/profile_screen.dart';
import 'package:nivio/screens/main_shell_screen.dart';
import 'package:nivio/screens/watch_party_screen.dart';
import 'package:nivio/services/watch_party/watch_party_models.dart';
import 'package:nivio/services/watch_party/watch_party_supabase_config.dart';

void main() async {
  WidgetsBinding widgetsBinding = WidgetsFlutterBinding.ensureInitialized();

  // Preserve splash screen while initializing
  FlutterNativeSplash.preserve(widgetsBinding: widgetsBinding);

  // Load .env first so downstream services (e.g. watch party Supabase)
  // can read credentials during initialization.
  try {
    await dotenv.load(fileName: '.env');
  } catch (_) {
    // Keep app booting even when .env is missing.
  }

  // Parallelize initialization for faster startup
  await Future.wait([
    // Initialize Firebase
    Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform),
    // Initialize Hive in parallel
    _initHive(),
    // Optional: initialize Supabase for watch party if configured
    WatchPartySupabaseConfig.initializeIfConfigured(),
  ]);

  // Initialize cache service
  final cacheService = CacheService();
  await cacheService.init();

  // Initialize episode check service (background notifications)
  await EpisodeCheckService.init();

  runApp(
    ProviderScope(
      overrides: [cacheServiceProvider.overrideWithValue(cacheService)],
      child: const NivioApp(),
    ),
  );

  // Non-blocking OTA check at startup for Shorebird release builds.
  unawaited(ShorebirdUpdateService.checkAndUpdateInBackground());

  // Remove splash screen after app is ready
  FlutterNativeSplash.remove();
}

Future<void> _initHive() async {
  await Hive.initFlutter();
  Hive.registerAdapter(CacheEntryAdapter());
  Hive.registerAdapter(WatchlistItemAdapter());
  Hive.registerAdapter(NewEpisodeAdapter());
  // Initialize watchlist box
  await WatchlistService.init();
}

// Auth state notifier for router refresh
class _AuthStateNotifier extends ChangeNotifier {
  _AuthStateNotifier() {
    FirebaseAuth.instance.authStateChanges().listen((_) {
      notifyListeners();
    });
  }
}

// Router configuration
final _router = GoRouter(
  initialLocation: '/home',
  // Optimize: Use refreshListenable for auth state instead of checking on every navigation
  refreshListenable: _AuthStateNotifier(),
  redirect: (context, state) {
    final user = FirebaseAuth.instance.currentUser;
    final isAuthRoute = state.matchedLocation == '/auth';

    // If not signed in and not on auth route, redirect to auth
    if (user == null && !isAuthRoute) {
      return '/auth';
    }

    // If signed in and on auth route, redirect to home
    if (user != null && isAuthRoute) {
      return '/home';
    }

    // Otherwise, no redirect needed
    return null;
  },
  routes: [
    GoRoute(path: '/auth', builder: (context, state) => const AuthScreen()),
    GoRoute(path: '/', redirect: (context, state) => '/home'),
    StatefulShellRoute.indexedStack(
      builder: (context, state, navigationShell) =>
          MainShellScreen(navigationShell: navigationShell),
      branches: [
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/home',
              builder: (context, state) => const HomeScreen(),
            ),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/search',
              builder: (context, state) => const SearchScreen(),
            ),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/library',
              builder: (context, state) {
                final tab = state.uri.queryParameters['tab'];
                final initialTab = tab == 'watchlist' ? 1 : 0;
                return LibraryScreen(initialTab: initialTab);
              },
            ),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/party',
              builder: (context, state) {
                final preselectedMediaId = int.tryParse(
                  state.uri.queryParameters['mediaId'] ?? '',
                );
                final preselectedSeason =
                    int.tryParse(state.uri.queryParameters['season'] ?? '') ??
                    1;
                return WatchPartyScreen(
                  preselectedMediaId: preselectedMediaId,
                  preselectedMediaType: state.uri.queryParameters['type'],
                  preselectedSeason: preselectedSeason,
                  preselectedMediaTitle: state.uri.queryParameters['title'],
                );
              },
            ),
          ],
        ),
      ],
    ),
    GoRoute(
      path: '/profile',
      builder: (context, state) => const ProfileScreen(),
    ),
    GoRoute(
      path: '/watchlist',
      redirect: (context, state) => '/library?tab=watchlist',
    ),
    GoRoute(path: '/new-episodes', redirect: (context, state) => '/library'),
    GoRoute(
      path: '/watch-party',
      redirect: (context, state) {
        final query = state.uri.query;
        return query.isEmpty ? '/party' : '/party?$query';
      },
    ),
    GoRoute(
      path: '/media/:id',
      builder: (context, state) {
        final id = state.pathParameters['id']!;
        final mediaType = state.uri.queryParameters['type'];
        return MediaDetailScreen(mediaId: int.parse(id), mediaType: mediaType);
      },
    ),
    GoRoute(
      path: '/player/:id',
      builder: (context, state) {
        final id = state.pathParameters['id']!;
        final season = int.parse(state.uri.queryParameters['season'] ?? '1');
        final episode = int.parse(state.uri.queryParameters['episode'] ?? '1');
        final mediaType = state.uri.queryParameters['type'];
        final providerIndex = int.tryParse(
          state.uri.queryParameters['provider'] ?? '',
        );
        final partyCode = state.uri.queryParameters['partyCode'];
        final partyRole = WatchPartyRoleX.fromQuery(
          state.uri.queryParameters['partyRole'],
        );
        return PlayerScreen(
          mediaId: int.parse(id),
          season: season,
          episode: episode,
          mediaType: mediaType,
          providerIndex: providerIndex,
          watchPartyCode: partyCode,
          watchPartyRole: partyRole,
        );
      },
    ),
  ],
);

class NivioApp extends ConsumerWidget {
  const NivioApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accentKey = ref.watch(appAccentColorProvider);
    final accentColor = appAccentColorFromKey(accentKey);
    final appTheme = NivioTheme.buildDarkTheme(accentColor: accentColor);

    return MaterialApp.router(
      title: 'Nivio',
      theme: appTheme,
      darkTheme: appTheme,
      routerConfig: _router,
      builder: (context, child) {
        return _GitHubReleasePromptGate(
          child: child ?? const SizedBox.shrink(),
        );
      },
      debugShowCheckedModeBanner: false,
    );
  }
}

class _GitHubReleasePromptGate extends StatefulWidget {
  const _GitHubReleasePromptGate({required this.child});

  final Widget child;

  @override
  State<_GitHubReleasePromptGate> createState() =>
      _GitHubReleasePromptGateState();
}

class _GitHubReleasePromptGateState extends State<_GitHubReleasePromptGate> {
  static bool _dialogShownThisSession = false;
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    _checkForGitHubReleaseUpdate();
  }

  Future<void> _checkForGitHubReleaseUpdate() async {
    final result = await GitHubReleaseUpdateService.checkForUpdate(
      forceRefresh: true,
    );
    if (!mounted || !result.hasUpdate || _dialogShownThisSession) return;

    _dialogShownThisSession = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;

      await showDialog<void>(
        context: context,
        barrierDismissible: true,
        builder: (dialogContext) {
          return AlertDialog(
            title: const Text('Update Available'),
            content: Text(
              'Current: ${result.installedVersion}\n'
              'Latest: ${result.latestVersion}\n\n'
              'A newer app release is available on GitHub.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('Later'),
              ),
              FilledButton(
                onPressed: () async {
                  await GitHubReleaseUpdateService.openReleasePage(
                    result.releaseUrl,
                  );
                  if (dialogContext.mounted) {
                    Navigator.of(dialogContext).pop();
                  }
                },
                child: const Text('Install'),
              ),
            ],
          );
        },
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}
