import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:nivio/core/theme.dart';
import 'package:nivio/firebase_options.dart';
import 'package:nivio/screens/home_screen.dart';
import 'package:nivio/screens/search_screen.dart';
import 'package:nivio/screens/media_detail_screen.dart';
import 'package:nivio/screens/player_screen.dart';
import 'package:nivio/screens/auth_screen.dart';
import 'package:nivio/screens/settings_screen.dart';

void main() async {
  WidgetsBinding widgetsBinding = WidgetsFlutterBinding.ensureInitialized();
  
  // Preserve splash screen while initializing
  FlutterNativeSplash.preserve(widgetsBinding: widgetsBinding);
  
  // Initialize Firebase with generated options
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  runApp(
    const ProviderScope(
      child: NivioApp(),
    ),
  );
  
  // Remove splash screen after app is ready
  FlutterNativeSplash.remove();
}

// Router configuration
final _router = GoRouter(
  initialLocation: '/',
  redirect: (context, state) {
    final user = FirebaseAuth.instance.currentUser;
    final isAuthRoute = state.matchedLocation == '/auth';
    
    // If not signed in and not on auth route, redirect to auth
    if (user == null && !isAuthRoute) {
      return '/auth';
    }
    
    // If signed in and on auth route, redirect to home
    if (user != null && isAuthRoute) {
      return '/';
    }
    
    // Otherwise, no redirect needed
    return null;
  },
  routes: [
    GoRoute(
      path: '/auth',
      builder: (context, state) => const AuthScreen(),
    ),
    GoRoute(
      path: '/',
      builder: (context, state) => const HomeScreen(),
    ),
    GoRoute(
      path: '/search',
      builder: (context, state) => const SearchScreen(),
    ),
    GoRoute(
      path: '/settings',
      builder: (context, state) => const SettingsScreen(),
    ),
    GoRoute(
      path: '/media/:id',
      builder: (context, state) {
        final id = state.pathParameters['id']!;
        final mediaType = state.uri.queryParameters['type'];
        return MediaDetailScreen(
          mediaId: int.parse(id),
          mediaType: mediaType,
        );
      },
    ),
    GoRoute(
      path: '/player/:id',
      builder: (context, state) {
        final id = state.pathParameters['id']!;
        final season = int.parse(state.uri.queryParameters['season'] ?? '1');
        final episode = int.parse(state.uri.queryParameters['episode'] ?? '1');
        return PlayerScreen(
          mediaId: int.parse(id),
          season: season,
          episode: episode,
        );
      },
    ),
  ],
);

class NivioApp extends StatelessWidget {
  const NivioApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'Nivio',
      theme: NivioTheme.darkTheme,
      routerConfig: _router,
      debugShowCheckedModeBanner: false,
    );
  }
}
