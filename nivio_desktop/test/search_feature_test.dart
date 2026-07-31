import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nivio_desktop/app/app.dart';

import 'package:nivio_desktop/core/interfaces/details_repository.dart';
import 'package:nivio_desktop/core/interfaces/search_repository.dart';
import 'package:nivio_desktop/features/search/models/search_media_item.dart';
import 'package:nivio_desktop/features/search/search_feature.dart' as search;
import 'package:nivio_desktop/features/details/models/detail_models.dart';
import 'package:nivio_desktop/features/details/models/detail_route_args.dart';
import 'package:nivio_desktop/shared/widgets/cards/media_card.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'fakes/media_test_fakes.dart';
import 'test_helper.dart';

class _SearchDetailsRepository implements DetailsRepository {
  DetailRouteArgs? lastArgs;

  @override
  Future<DetailMedia> loadCompleteDetail(DetailRouteArgs args) async {
    lastArgs = args;
    return fakeDetailMedia('signal-lost');
  }

  @override
  Future<List<DetailEpisode>> getSeasonEpisodes({
    required int tvId,
    required int seasonNumber,
  }) async {
    return const [];
  }
}

class _DelayedSearchRepository implements SearchRepository {
  final Map<String, Completer<List<SearchMediaItem>>> requests = {};

  @override
  Future<List<SearchMediaItem>> search({
    required String query,
    required SearchLanguageFilter language,
    required SearchMediaTypeFilter mediaType,
    required SearchSortOption sort,
    int page = 1,
  }) {
    return (requests[query] ??= Completer<List<SearchMediaItem>>()).future;
  }
}

void main() {
  setUpAll(() {
    HttpOverrides.global = MockHttpOverrides();
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('keeps loading while a newer debounced search is pending', () async {
    final repository = _DelayedSearchRepository();
    final controller = search.SearchController(repository: repository);
    addTearDown(controller.dispose);

    controller.setQuery('old');
    final oldSearch = controller.submitQuery();
    controller.setQuery('signal');
    expect(controller.isLoading, isTrue);
    expect(controller.results, isEmpty);

    repository.requests['old']!.complete(const []);
    await oldSearch;
    expect(controller.isLoading, isTrue);

    final signalSearch = controller.submitQuery();
    repository.requests['signal']!.complete([fakeSearchItems.first]);
    await signalSearch;

    expect(controller.isLoading, isFalse);
    expect(controller.results.single.title, 'Signal Lost');
  });

  test('loads and saves recent searches', () async {
    SharedPreferences.setMockInitialValues({
      'recent_searches': <String>['old search'],
    });
    final controller = search.SearchController(
      repository: FakeSearchRepository(),
    );
    addTearDown(controller.dispose);

    await controller.initialize();
    expect(controller.recentSearches, ['old search']);

    controller.setQuery('signal');
    await controller.submitQuery();

    expect(controller.recentSearches, ['signal', 'old search']);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getStringList('recent_searches'), ['signal', 'old search']);
  });

  testWidgets('opens the search page and shows search results', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      NivioDesktopApp(
        requireAuthentication: false,
        searchRepository: FakeSearchRepository(),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('desktop_sidebar_1')));
    await tester.pumpAndSettle();

    final searchField = find.byType(TextField).first;
    await tester.enterText(searchField, 'signal');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();

    expect(find.text('Filters'), findsNothing);

    Finder mediaCard(String title) => find.byWidgetPredicate(
      (widget) => widget is MediaCard && widget.title == title,
    );

    expect(mediaCard('Signal Lost'), findsOneWidget);
    await tester.scrollUntilVisible(
      mediaCard('Halo Signal'),
      400,
      scrollable: find.byType(Scrollable).last,
    );
    expect(mediaCard('Halo Signal'), findsOneWidget);
    expect(mediaCard('Blackout City'), findsNothing);

    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('search result cards open details with typed media ids', (
    WidgetTester tester,
  ) async {
    final detailsRepository = _SearchDetailsRepository();
    const item = SearchMediaItem(
      id: 'movie:550',
      title: 'Signal Lost',
      year: 2026,
      rating: 8.4,
      language: SearchLanguageFilter.english,
      mediaType: SearchMediaTypeFilter.movie,
      provider: 'Prime Video',
      genres: ['Drama'],
      posterLabel: 'Signal Lost',
      overview: 'An ex-operator uncovers a hidden broadcast network.',
      runtimeLabel: '1h 56m',
    );

    await tester.pumpWidget(
      NivioDesktopApp(
        requireAuthentication: false,
        searchRepository: FakeSearchRepository(items: const [item]),
        detailsRepository: detailsRepository,
      ),
    );

    await tester.tap(find.byKey(const ValueKey('desktop_sidebar_1')));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).first, 'signal');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle(const Duration(seconds: 2));

    await tester.tap(
      find.byWidgetPredicate(
        (widget) => widget is MediaCard && widget.title == 'Signal Lost',
      ),
    );
    await tester.pumpAndSettle();

    expect(
      detailsRepository.lastArgs,
      const DetailRouteArgs(mediaType: 'movie', mediaId: 550),
    );
    expect(find.text('Signal Lost'), findsWidgets);
  });
}
