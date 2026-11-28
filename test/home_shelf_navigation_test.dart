import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:nivio/models/search_result.dart';
import 'package:nivio/providers/auth_provider.dart';
import 'package:nivio/providers/home_providers.dart';
import 'package:nivio/providers/watchlist_provider.dart';
import 'package:nivio/screens/home_shelf_screen.dart';
import 'package:nivio/screens/profile_screen.dart';
import 'package:nivio/widgets/content_row.dart';
import 'package:nivio/widgets/search_result_card.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _SettingsUser extends Fake implements User {
  @override
  String? get photoURL => null;

  @override
  String get displayName => 'Test user';
}

void main() {
  testWidgets('Android Back clears Settings search before leaving Settings', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferences.setMockInitialValues({});
    final user = StreamController<User?>();
    addTearDown(user.close);

    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (context, _) => Scaffold(
            body: TextButton(
              onPressed: () => context.push('/profile'),
              child: const Text('Open Settings'),
            ),
          ),
        ),
        GoRoute(path: '/profile', builder: (_, _) => const ProfileScreen()),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [authStateProvider.overrideWith((ref) => user.stream)],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.tap(find.text('Open Settings'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    user.add(_SettingsUser());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Settings'), findsOneWidget);

    final search = find.byType(TextField);
    await tester.enterText(search, 'does not match any setting');
    await tester.pump();
    expect(find.text('SEARCH RESULTS'), findsOneWidget);

    await tester.binding.handlePopRoute();
    await tester.pump();
    expect(find.text('Settings'), findsOneWidget);
    expect(find.text('SEARCH RESULTS'), findsNothing);
    expect(tester.widget<TextField>(search).controller!.text, isEmpty);
    expect(tester.widget<TextField>(search).focusNode!.hasFocus, isFalse);

    await tester.tap(search);
    await tester.pump();
    await tester.binding.handlePopRoute();
    await tester.pump();
    expect(find.text('Settings'), findsOneWidget);
    expect(tester.widget<TextField>(search).focusNode!.hasFocus, isFalse);

    await tester.binding.handlePopRoute();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Open Settings'), findsOneWidget);
  }, variant: TargetPlatformVariant.only(TargetPlatform.android));

  testWidgets('More opens the shelf grid and loads the next distinct titles as it scrolls', (
    tester,
  ) async {
    const shelf = HomeShelf.popularMovies;
    const first = SearchResult(id: 1, mediaType: 'movie', title: 'First movie');
    const second = SearchResult(
      id: 2,
      mediaType: 'movie',
      title: 'Second movie',
    );
    final requests = <int>[];
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (context, _) => Scaffold(
            body: ContentRow(
              title: shelf.title,
              items: const [first],
              onSeeAll: () => context.push('/home/shelf/${shelf.id}'),
            ),
          ),
        ),
        GoRoute(
          path: '/home/shelf/:id',
          builder: (_, state) => HomeShelfScreen(
            shelf: HomeShelf.fromId(state.pathParameters['id'])!,
          ),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          isInWatchlistProvider(first.id).overrideWithValue(false),
          homeShelfLoaderProvider(shelf).overrideWithValue((page) async {
            requests.add(page);
            return page == 1
                ? (items: const [first], hasMore: true)
                : (items: const [first, second], hasMore: false);
          }),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.tap(find.text('More'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(AppBar, shelf.title), findsOneWidget);
    // One title doesn't fill the screen, so the next page loads by itself.
    expect(requests, [1, 2]);
    expect(find.byType(SearchResultCard), findsNWidgets(2));
    expect(find.text('First movie'), findsOneWidget);
    expect(find.text('Second movie'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);

    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(find.byType(ContentRow), findsOneWidget);
  });
}
