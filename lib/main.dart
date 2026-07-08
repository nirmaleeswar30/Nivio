import 'dart:async';

import 'dart:isolate';
import 'dart:ui';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:media_kit/media_kit.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:nivio/core/theme.dart';
import 'package:nivio/firebase_options.dart';
import 'package:nivio/models/cache_entry.dart';
import 'package:nivio/models/watchlist_item.dart';
import 'package:nivio/models/new_episode.dart';
import 'package:nivio/models/download_item.dart';
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
import 'package:nivio/screens/similar_content_screen.dart';
import 'package:nivio/screens/all_providers_screen.dart';
import 'package:nivio/screens/player_screen.dart';
import 'package:nivio/screens/auth_screen.dart';
import 'package:nivio/screens/library_screen.dart';
import 'package:nivio/screens/profile_screen.dart';
import 'package:nivio/screens/provider_content_screen.dart';
import 'package:nivio/screens/main_shell_screen.dart';
import 'package:nivio/screens/watch_party_screen.dart';
import 'package:nivio/screens/iptv_screen.dart';
import 'package:nivio/services/watch_party/watch_party_models.dart';
import 'package:nivio/services/watch_party/watch_party_supabase_config.dart';
import 'package:nivio/services/download_service.dart';
import 'package:nivio/services/hls_proxy_service.dart';

void main() async {
  try {
    WidgetsBinding widgetsBinding = WidgetsFlutterBinding.ensureInitialized();
    MediaKit.ensureInitialized();

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

  // Start background HLS proxy server for Cloudflare bypasses
  await HlsProxyService.instance.start();

  // Initialize episode check service (background notifications)
  await EpisodeCheckService.init();

  final receivePort = ReceivePort();
  IsolateNameServer.removePortNameMapping('download_cancel_port');
  IsolateNameServer.registerPortWithName(receivePort.sendPort, 'download_cancel_port');
  receivePort.listen((message) {
    debugPrint("📥 Received message on download_cancel_port: $message");
    if (message is String) {
      DownloadService.deleteDownload(message);
    }
  });

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
  } catch (e, stack) {
    debugPrint('Fatal Startup Error: $e\n$stack');
    runApp(
      MaterialApp(
        home: Scaffold(
          backgroundColor: Colors.black,
          body: SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16.0),
              child: Text(
                'Fatal Error During Startup:\n\n$e\n\n$stack',
                style: const TextStyle(color: Colors.red, fontSize: 12),
              ),
            ),
          ),
        ),
      ),
    );
    FlutterNativeSplash.remove();
  }
}

Future<void> _initHive() async {
  await Hive.initFlutter();
  Hive.registerAdapter(CacheEntryAdapter());
  Hive.registerAdapter(WatchlistItemAdapter());
  Hive.registerAdapter(NewEpisodeAdapter());
  Hive.registerAdapter(DownloadStatusAdapter());
  Hive.registerAdapter(DownloadItemAdapter());

  await Future.wait([
    Hive.openBox<CacheEntry>('cache'),
    Hive.openBox<WatchlistItem>('watchlist'),
    Hive.openBox<NewEpisode>('new_episodes'),
    Hive.openBox('settings'),
    Hive.openBox<DownloadItem>('downloads'),
  ]);
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
final appRouter = GoRouter(
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
    GoRoute(
      path: '/search',
      pageBuilder: (context, state) => CustomTransitionPage(
        opaque: false,
        transitionDuration: const Duration(milliseconds: 300),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(opacity: animation, child: child);
        },
        child: const SearchScreen(),
      ),
    ),
    GoRoute(path: '/all-providers', builder: (context, state) => const AllProvidersScreen()),
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
              path: '/library',
              builder: (context, state) {
                final tab = state.uri.queryParameters['tab'];
                int initialTab = 0;
                if (tab == 'watchlist') initialTab = 1;
                if (tab == 'downloads') initialTab = 2;
                return LibraryScreen(key: ValueKey(state.uri.toString()), initialTab: initialTab);
              },
            ),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/iptv',
              builder: (context, state) => const IptvScreen(),
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
      path: '/provider/:id',
      builder: (context, state) {
        final id = int.tryParse(state.pathParameters['id'] ?? '0') ?? 0;
        final name = state.uri.queryParameters['name'] ?? 'Provider';
        return ProviderContentScreen(providerId: id, providerName: name);
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
      path: '/similar/:id',
      pageBuilder: (context, state) {
        final id = state.pathParameters['id']!;
        final mediaType = state.uri.queryParameters['type'] ?? 'movie';
        final title = state.uri.queryParameters['title'] ?? '';
        return CustomTransitionPage(
          opaque: false,
          transitionDuration: const Duration(milliseconds: 300),
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            return FadeTransition(opacity: animation, child: child);
          },
          child: SimilarContentScreen(
            mediaId: int.parse(id),
            mediaType: mediaType,
            title: title,
          ),
        );
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
        final localPath = state.uri.queryParameters['localPath'];
        final directStreamUrl = state.uri.queryParameters['directStreamUrl'];
        final directStreamTitle = state.uri.queryParameters['directStreamTitle'];
        final isLive = state.uri.queryParameters['isLive'] == 'true';
        return PlayerScreen(
          mediaId: int.parse(id),
          season: season,
          episode: episode,
          mediaType: mediaType,
          providerIndex: providerIndex,
          watchPartyCode: partyCode,
          watchPartyRole: partyRole,
          localPath: localPath,
          directStreamUrl: directStreamUrl,
          directStreamTitle: directStreamTitle,
          isLive: isLive,
        );
      },
    ),
  ],
);

class NivioApp extends ConsumerStatefulWidget {
  const NivioApp({super.key});

  @override
  ConsumerState<NivioApp> createState() => _NivioAppState();
}

class _NivioAppState extends ConsumerState<NivioApp> {
  @override
  void initState() {
    super.initState();
    // Initialize the background Cloudflare bypass service silently
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        // ref.read(cloudflareBypassProvider).init();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final accentKey = ref.watch(appAccentColorProvider);
    final accentColor = appAccentColorFromKey(accentKey);
    final appTheme = NivioTheme.buildDarkTheme(accentColor: accentColor);

    return MaterialApp.router(
      title: 'Nivio',
      theme: appTheme,
      darkTheme: appTheme,
      routerConfig: appRouter,
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
