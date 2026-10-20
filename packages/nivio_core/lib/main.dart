import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'dart:isolate';
import 'dart:ui';
import 'dart:io';
import 'package:app_links/app_links.dart';
import 'package:flutter/foundation.dart';

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
import 'package:nivio/widgets/mini_player_overlay.dart';
import 'package:nivio/models/cache_entry.dart';
import 'package:nivio/models/watchlist_item.dart';
import 'package:nivio/models/new_episode.dart';
import 'package:nivio/models/download_item.dart';
import 'package:nivio/services/cache_service.dart';
import 'package:nivio/services/watchlist_service.dart';
import 'package:nivio/services/auth_service.dart';
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
import 'package:nivio/core/debug_log.dart';
import 'package:nivio/screens/auth_screen.dart';
import 'package:nivio/screens/library_screen.dart';
import 'package:nivio/screens/profile_screen.dart';
import 'package:nivio/screens/provider_content_screen.dart';
import 'package:nivio/screens/main_shell_screen.dart';
import 'package:nivio/screens/app_preloader_screen.dart';
import 'package:nivio/screens/watch_party_screen.dart';
import 'package:nivio/screens/tv_sports_screen.dart';
import 'package:nivio/screens/latest_releases_screen.dart';
import 'package:nivio/screens/new_episodes_screen.dart';
import 'package:nivio/services/watch_party/watch_party_models.dart';
import 'package:nivio/services/watch_party/watch_party_supabase_config.dart';
import 'package:nivio/services/download_service.dart';
import 'package:nivio/services/hls_proxy_service.dart';
import 'package:nivio/services/discord_rpc_service.dart';
import 'package:nivio/services/anilist_auth_service.dart';
import 'package:nivio/services/simkl_auth_service.dart';
import 'package:nivio/services/mal_auth_service.dart';
import 'package:media_kit/media_kit.dart';
import 'package:nivio/widgets/title_bar_overlay.dart';

import 'package:flutter_inappwebview_linux/flutter_inappwebview_linux.dart';
import 'package:window_manager/window_manager.dart';

const int _desktopIpcPort = 45328;

Future<bool> _handleDesktopSingleInstance(List<String> args) async {
  if (!Platform.isWindows && !Platform.isLinux && !Platform.isMacOS) {
    return false;
  }

  try {
    final server = await ServerSocket.bind(
      InternetAddress.loopbackIPv4,
      _desktopIpcPort,
      shared: false,
    );

    // Primary instance: listen for forwarded links
    server.listen((Socket client) {
      utf8.decoder.bind(client).listen((data) {
        final link = data.trim();
        if (link.isNotEmpty) {
          debugPrint('🔗 Received link from secondary instance: $link');
          final uri = Uri.tryParse(link);
          if (uri != null) {
            _handleDeepLink(uri);
            if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
              windowManager.show();
              windowManager.focus();
            }
          }
        }
      });
    });

    return false;
  } catch (_) {
    // Secondary instance: forward link and exit immediately without initializing Hive
    debugPrint('ℹ️ Another Nivio instance is already running. Forwarding link...');
    try {
      final client = await Socket.connect(
        InternetAddress.loopbackIPv4,
        _desktopIpcPort,
        timeout: const Duration(seconds: 2),
      );

      String linkToSend = '';
      for (final arg in args) {
        if (arg.startsWith('nivio://') || arg.contains('auth/')) {
          linkToSend = arg;
          break;
        }
      }
      if (linkToSend.isEmpty && args.isNotEmpty) {
        linkToSend = args.first;
      }

      if (linkToSend.isNotEmpty) {
        client.write(linkToSend);
        await client.flush();
      }
      await client.close();
    } catch (e) {
      debugPrint('Error sending link to primary instance: $e');
    }
    exit(0);
  }
}

void main([List<String> args = const []]) async {
  try {
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      final handled = await _handleDesktopSingleInstance(args);
      if (handled) return;
    }
    WidgetsBinding widgetsBinding = WidgetsFlutterBinding.ensureInitialized();
    if (Platform.isLinux) {
      LinuxInAppWebViewPlatform.registerWith();
      
      // Catch non-fatal internal plugin exceptions from flutter_inappwebview_linux
      final originalOnError = FlutterError.onError;
      FlutterError.onError = (details) {
        final stack = details.stack?.toString() ?? '';
        final exc = details.exception.toString();
        if (stack.contains('flutter_inappwebview_linux') ||
            stack.contains('_CustomPlatformViewState') ||
            exc.contains('InAppWebView')) {
          debugPrint('🛡️ Handled non-fatal flutter_inappwebview_linux exception: $exc');
          return;
        }
        if (originalOnError != null) {
          originalOnError(details);
        } else {
          FlutterError.presentError(details);
        }
      };

      PlatformDispatcher.instance.onError = (error, stack) {
        final stackStr = stack.toString();
        final errStr = error.toString();
        if (stackStr.contains('flutter_inappwebview_linux') ||
            stackStr.contains('_CustomPlatformViewState') ||
            errStr.contains('InAppWebView') ||
            errStr.contains('RenderObject.getTransformTo')) {
          debugPrint('🛡️ Handled async flutter_inappwebview_linux exception: $errStr');
          return true;
        }
        return false;
      };
    }
    initDebugLogFile();
    MediaKit.ensureInitialized();

    if (Platform.isLinux || Platform.isWindows || Platform.isMacOS) {
      await windowManager.ensureInitialized();
      const windowOptions = WindowOptions(
        size: Size(1920, 1080),
        minimumSize: Size(1280, 720),
        center: true,
        backgroundColor: Colors.black,
        skipTaskbar: false,
        titleBarStyle: TitleBarStyle.hidden,
      );
      windowManager.waitUntilReadyToShow(windowOptions, () async {
        await windowManager.show();
        await windowManager.focus();
      });
    }

    // Preserve splash screen while initializing
    if (Platform.isAndroid || Platform.isIOS) {
      FlutterNativeSplash.preserve(widgetsBinding: widgetsBinding);
    }

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
    // Seed synchronously-read settings (torrent toggles) with saved values
    preloadSettingsPrefs(),
  ]);

  // Initialize cache service
  final cacheService = CacheService();
  await cacheService.init();

  // Start background HLS proxy server for Cloudflare bypasses
  await HlsProxyService.instance.start();

  // Initialize episode check service (background notifications)
  await EpisodeCheckService.init();

  // Initialize anime tracking auth services (AniList & MAL)
  await AniListAuthService.instance.init();
  await MalAuthService.instance.init();
  await SimklAuthService.instance.init();

  final receivePort = ReceivePort();
  IsolateNameServer.removePortNameMapping('download_cancel_port');
  IsolateNameServer.registerPortWithName(receivePort.sendPort, 'download_cancel_port');
  receivePort.listen((message) {
    debugPrint("📥 Received message on download_cancel_port: $message");
    if (message is String) {
      DownloadService.deleteDownload(message);
    }
  });

    // Wire up deep link handling (nivio://open/...)
    _initDeepLinks();

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
  if (!Hive.isAdapterRegistered(0)) Hive.registerAdapter(CacheEntryAdapter());
  if (!Hive.isAdapterRegistered(7)) Hive.registerAdapter(WatchStatusAdapter());
  if (!Hive.isAdapterRegistered(5)) Hive.registerAdapter(WatchlistItemAdapter());
  if (!Hive.isAdapterRegistered(3)) Hive.registerAdapter(NewEpisodeAdapter());
  if (!Hive.isAdapterRegistered(4)) Hive.registerAdapter(DownloadStatusAdapter());
  if (!Hive.isAdapterRegistered(6)) Hive.registerAdapter(DownloadItemAdapter());

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

Future<void> _registerWindowsCustomProtocol() async {
  if (!Platform.isWindows) return;
  try {
    final exePath = Platform.resolvedExecutable;
    await Process.run('reg', [
      'add',
      r'HKCU\Software\Classes\nivio',
      '/ve',
      '/d',
      'URL:nivio Protocol',
      '/f',
    ]);
    await Process.run('reg', [
      'add',
      r'HKCU\Software\Classes\nivio',
      '/v',
      'URL Protocol',
      '/d',
      '',
      '/f',
    ]);
    await Process.run('reg', [
      'add',
      r'HKCU\Software\Classes\nivio\shell\open\command',
      '/ve',
      '/d',
      '"$exePath" "%1"',
      '/f',
    ]);
  } catch (e) {
    debugPrint('Error registering Windows protocol: $e');
  }
}

/// Handle incoming deep links (nivio://open/...) on all platforms.
void _initDeepLinks() {
  if (Platform.isWindows) {
    _registerWindowsCustomProtocol();
  }
  try {
    final appLinks = AppLinks();

    // Cold start: capture the URI that launched the app.
    appLinks.getInitialLink().then((uri) {
      if (uri != null) _handleDeepLink(uri);
    });

    // Warm start: listen for URIs while app is running.
    appLinks.uriLinkStream.listen((uri) {
      _handleDeepLink(uri);
    });
  } catch (e) {
    debugPrint('Deep link init error: $e');
  }
}

void _handleDeepLink(Uri uri) {
  debugPrint('🔗 Deep link received: $uri');

  // Handle OAuth authentication callbacks:
  // - AniList: nivio://auth/anilist#access_token=... OR nivio://auth/anilist?code=...
  // - MAL:     nivio://auth/mal?code=...
  final fullPath = '${uri.host}${uri.path}'.toLowerCase();
  if (fullPath.contains('auth/anilist') ||
      (uri.host == 'auth' && uri.path.contains('anilist'))) {
    String? token;
    if (uri.fragment.isNotEmpty) {
      final fragmentParams = Uri.splitQueryString(uri.fragment);
      token = fragmentParams['access_token'];
    }
    token ??= uri.queryParameters['access_token'];
    final code = uri.queryParameters['code'];

    if (token != null && token.isNotEmpty) {
      debugPrint('🔗 Deep link: Authenticating AniList via token');
      unawaited(
        AniListAuthService.instance.authenticateWithToken(token).then((ok) {
          if (ok) {
            WatchlistService(AuthService())
                .importFromAnimeTracking(pushOfflineChanges: true);
          }
        }),
      );
    } else if (code != null && code.isNotEmpty) {
      debugPrint('🔗 Deep link: Exchanging AniList auth code');
      unawaited(
        AniListAuthService.instance.exchangeCodeForToken(code).then((ok) {
          if (ok) {
            WatchlistService(AuthService())
                .importFromAnimeTracking(pushOfflineChanges: true);
          }
        }),
      );
    }
    return;
  }

  if (fullPath.contains('auth/mal') ||
      (uri.host == 'auth' && uri.path.contains('mal'))) {
    final code = uri.queryParameters['code'];
    if (code != null && code.isNotEmpty) {
      debugPrint('🔗 Deep link: Exchanging MAL auth code');
      unawaited(
        MalAuthService.instance.exchangeCodeForToken(code).then((ok) {
          if (ok) {
            WatchlistService(AuthService())
                .importFromAnimeTracking(pushOfflineChanges: true);
          }
        }),
      );
    }
    return;
  }

  // Simkl: nivio://auth/simkl?code=...
  if (fullPath.contains('auth/simkl') ||
      (uri.host == 'auth' && uri.path.contains('simkl'))) {
    final code = uri.queryParameters['code'];
    if (code != null && code.isNotEmpty) {
      debugPrint('🔗 Deep link: Exchanging Simkl auth code');
      unawaited(
        SimklAuthService.instance.exchangeCodeForToken(code).then((ok) {
          if (ok) {
            // Pull the Simkl library right after connecting (two-way sync).
            WatchlistService(AuthService()).importFromSimkl(pushOfflineChanges: true);
          }
        }),
      );
    }
    return;
  }

  // URI format: nivio://open/media/123?type=movie
  //             nivio://open/party?code=123456
  //             nivio://party?code=123456
  var path = uri.path;
  if (path.isEmpty && (uri.host == 'party' || uri.host == 'watch-party')) {
    path = '/party';
  } else if (path.isEmpty && uri.host.isNotEmpty && uri.host != 'open') {
    path = '/${uri.host}';
  }
  final query = uri.query.isNotEmpty ? '?${uri.query}' : '';
  final routePath = '$path$query';
  debugPrint('🔗 Deep link routing to: $routePath');
  appRouter.go(routePath);
}

// Auth state notifier for router refresh
class _AuthStateNotifier extends ChangeNotifier {
  _AuthStateNotifier() {
    FirebaseAuth.instance.authStateChanges().listen((_) {
      notifyListeners();
    });
  }
}

// Branch Navigator Keys
final homeNavigatorKey = GlobalKey<NavigatorState>(debugLabel: 'home');
final libraryNavigatorKey = GlobalKey<NavigatorState>(debugLabel: 'library');
final iptvNavigatorKey = GlobalKey<NavigatorState>(debugLabel: 'iptv');
final partyNavigatorKey = GlobalKey<NavigatorState>(debugLabel: 'party');

// Router configuration
final appRouter = GoRouter(
  initialLocation: '/splash',
  // Optimize: Use refreshListenable for auth state instead of checking on every navigation
  refreshListenable: _AuthStateNotifier(),
  redirect: (context, state) {
    final user = FirebaseAuth.instance.currentUser;
    final location = state.matchedLocation;
    final isSplashRoute = location == '/splash';
    final isAuthRoute = location == '/auth';

    // Allow splash/preloader screen to play uninterrupted
    if (isSplashRoute) {
      return null;
    }

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
    GoRoute(
      path: '/splash',
      pageBuilder: (context, state) => CustomTransitionPage(
        key: state.pageKey,
        transitionDuration: const Duration(milliseconds: 350),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(opacity: animation, child: child);
        },
        child: const AppPreloaderScreen(),
      ),
    ),
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
          navigatorKey: homeNavigatorKey,
          routes: [
            GoRoute(
              path: '/home',
              builder: (context, state) => const HomeScreen(),
            ),
          ],
        ),
        StatefulShellBranch(
          navigatorKey: libraryNavigatorKey,
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
          navigatorKey: iptvNavigatorKey,
          routes: [
            GoRoute(
              path: '/iptv',
              builder: (context, state) => const TvSportsScreen(),
            ),
          ],
        ),
        StatefulShellBranch(
          navigatorKey: partyNavigatorKey,
          routes: [
            GoRoute(
              path: '/party',
              builder: (context, state) {
                final autoJoinCode = state.uri.queryParameters['code'] ??
                    state.uri.queryParameters['partyCode'];
                final preselectedMediaId = int.tryParse(
                  state.uri.queryParameters['mediaId'] ?? '',
                );
                final preselectedSeason =
                    int.tryParse(state.uri.queryParameters['season'] ?? '') ??
                    1;
                return WatchPartyScreen(
                  autoJoinCode: autoJoinCode,
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
    GoRoute(
      path: '/latest-releases',
      builder: (context, state) {
        final category = state.uri.queryParameters['category'] ?? 'movie';
        return LatestReleasesScreen(initialCategory: category);
      },
    ),
    GoRoute(
      path: '/schedule',
      builder: (context, state) => const Scaffold(
        body: NewEpisodesScreen(embedded: false),
      ),
    ),
    GoRoute(path: '/new-episodes', redirect: (context, state) => '/schedule'),
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
        final initialSeason = int.tryParse(state.uri.queryParameters['season'] ?? '');
        return MediaDetailScreen(
          mediaId: int.parse(id),
          mediaType: mediaType,
          initialSeason: initialSeason,
        );
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
        final downloadStreamId = state.uri.queryParameters['downloadStreamId'];
        final directStreamUrl = state.uri.queryParameters['directStreamUrl'];
        final directStreamTitle = state.uri.queryParameters['directStreamTitle'];
        final directStreamReferer = state.uri.queryParameters['directStreamReferer'];
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
          downloadStreamId: downloadStreamId,
          directStreamUrl: directStreamUrl,
          directStreamTitle: directStreamTitle,
          directStreamReferer: directStreamReferer,
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

    // Initialize Discord Rich Presence (IPC on desktop, Gateway on mobile).
    _initDiscordRpc();
  }

  /// Starts Discord RPC if enabled, and listens for toggle changes.
  void _initDiscordRpc() {
    final clientId = dotenv.env['DISCORD_CLIENT_ID']?.trim() ?? '';
    if (clientId.isEmpty) return;

    // Check initial setting and connect if enabled
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      final enabled = ref.read(discordRpcEnabledProvider);
      if (enabled) {
        await DiscordRpcService.instance.initialize(clientId);
        DiscordRpcService.instance.setBrowsing();
      }
    });

    // Listen for toggle changes at runtime
    ref.listenManual(discordRpcEnabledProvider, (previous, next) async {
      if (next) {
        await DiscordRpcService.instance.initialize(clientId);
        DiscordRpcService.instance.setBrowsing();
      } else {
        await DiscordRpcService.instance.dispose();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final themeKey = ref.watch(appThemeProvider);
    final uiScale = ref.watch(uiScaleProvider);
    final platformBrightness = MediaQuery.platformBrightnessOf(context);
    final appTheme = NivioTheme.buildTheme(
      themeKey,
      systemBrightness: platformBrightness,
    );

    return MaterialApp.router(
      showPerformanceOverlay: false,
      scrollBehavior: DesktopScrollBehavior(),
      title: 'Nivio',
      theme: appTheme,
      darkTheme: appTheme,
      routerConfig: appRouter,
      builder: (context, child) {
        final content = _GitHubReleasePromptGate(
          child: Stack(
            children: [
              child ?? const SizedBox.shrink(),
              const MiniPlayerOverlay(),
              const TitleBarOverlay(),
            ],
          ),
        );

        Widget scaledContent;
        if (uiScale == 1.0) {
          scaledContent = content;
        } else {
          scaledContent = LayoutBuilder(
            builder: (context, constraints) {
              final origSize = constraints.biggest;
              if (origSize.isEmpty || origSize.isInfinite) {
                return content;
              }
              final scaledW = origSize.width / uiScale;
              final scaledH = origSize.height / uiScale;
              return MediaQuery(
                data: MediaQuery.of(context).copyWith(
                  size: Size(scaledW, scaledH),
                ),
                child: SizedBox(
                  width: origSize.width,
                  height: origSize.height,
                  child: FittedBox(
                    fit: BoxFit.fill,
                    alignment: Alignment.topLeft,
                    child: SizedBox(
                      width: scaledW,
                      height: scaledH,
                      child: content,
                    ),
                  ),
                ),
              );
            },
          );
        }

        return Stack(
          children: [
            ClipRect(child: scaledContent),
            const _UiScaleConfirmationOverlay(),
          ],
        );
      },
      debugShowCheckedModeBanner: false,
    );
  }
}

class _UiScaleConfirmationOverlay extends ConsumerWidget {
  const _UiScaleConfirmationOverlay();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final confirmation = ref.watch(uiScaleConfirmationProvider);
    if (!confirmation.isVisible) {
      return const SizedBox.shrink();
    }

    final accentColor = NivioTheme.accentColorOf(context);
    final percent = (confirmation.proposedScale * 100).round();
    final prevPercent = (confirmation.previousScale * 100).round();

    return Material(
      type: MaterialType.transparency,
      child: Stack(
        children: [
          // Semi-transparent backdrop barrier
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {
                // Tapping outside reverts for safety
                ref.read(uiScaleConfirmationProvider.notifier).revert();
              },
              child: Container(
                color: Colors.black54,
              ),
            ),
          ),
          // Centered unscaled confirmation dialog
          Center(
            child: Container(
              width: min(440.0, MediaQuery.sizeOf(context).width - 32),
              margin: const EdgeInsets.symmetric(horizontal: 16),
              padding: const EdgeInsets.all(22),
              decoration: BoxDecoration(
                color: NivioTheme.surfaceColorOf(context),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: Colors.white.withOpacity(0.1),
                  width: 1,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.6),
                    blurRadius: 32,
                    offset: const Offset(0, 12),
                  ),
                ],
              ),
              clipBehavior: Clip.antiAlias,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: accentColor.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(
                          Icons.aspect_ratio_rounded,
                          color: accentColor,
                          size: 24,
                        ),
                      ),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Text(
                          'Keep display settings?',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 17,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      // Countdown timer badge
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: accentColor.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: accentColor.withOpacity(0.4),
                            width: 1,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.timer_outlined,
                              size: 14,
                              color: accentColor,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              '${confirmation.secondsRemaining}s',
                              style: TextStyle(
                                color: accentColor,
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Do you want to keep this UI scale ($percent%)? It will automatically revert to $prevPercent% in ${confirmation.secondsRemaining} second${confirmation.secondsRemaining == 1 ? '' : 's'} if not confirmed.',
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 13.5,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 20),
                  // Progress bar showing 5s countdown
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: confirmation.secondsRemaining / 5.0,
                      backgroundColor: Colors.white.withOpacity(0.08),
                      valueColor: AlwaysStoppedAnimation<Color>(accentColor),
                      minHeight: 4,
                    ),
                  ),
                  const SizedBox(height: 20),
                  // Action buttons
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.white,
                          side: BorderSide(
                            color: Colors.white.withOpacity(0.2),
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 18,
                            vertical: 11,
                          ),
                        ),
                        onPressed: () {
                          ref
                              .read(uiScaleConfirmationProvider.notifier)
                              .revert();
                        },
                        child: const Text('Revert'),
                      ),
                      const SizedBox(width: 12),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: accentColor,
                          foregroundColor: Colors.white,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 20,
                            vertical: 11,
                          ),
                        ),
                        onPressed: () {
                          ref
                              .read(uiScaleConfirmationProvider.notifier)
                              .confirm();
                        },
                        child: const Text(
                          'Keep Changes',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
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

class DesktopScrollBehavior extends MaterialScrollBehavior {
  @override
  Set<PointerDeviceKind> get dragDevices => {
        PointerDeviceKind.touch,
        PointerDeviceKind.mouse,
        PointerDeviceKind.trackpad,
      };
}
