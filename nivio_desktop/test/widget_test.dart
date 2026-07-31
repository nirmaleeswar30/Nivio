import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nivio_desktop/app/app.dart';

import 'package:nivio_desktop/features/search/models/search_media_item.dart';
import 'package:nivio_desktop/core/interfaces/home_repository.dart';
import 'fakes/media_test_fakes.dart';
import 'test_helper.dart';

class MockHomeRepository implements HomeRepository {
  @override
  Future<List<SearchMediaItem>> getPopularMovies() async => [];

  @override
  Future<List<SearchMediaItem>> getTrendingMovies() async => [];

  @override
  Future<List<SearchMediaItem>> getTopRatedMovies() async => [];

  @override
  Future<List<SearchMediaItem>> getPopularTv() async => [];

  @override
  Future<List<SearchMediaItem>> getTrendingTv() async => [];

  @override
  Future<List<SearchMediaItem>> getPopularAnime() async => [];

  @override
  Future<List<SearchMediaItem>> getTrendingAnime() async => [];

  @override
  Future<List<SearchMediaItem>> getTamilPicks() async => [];

  @override
  Future<List<SearchMediaItem>> getTeluguPicks() async => [];

  @override
  Future<List<SearchMediaItem>> getHindiPicks() async => [];

  @override
  Future<List<SearchMediaItem>> getMalayalamPicks() async => [];

  @override
  Future<List<SearchMediaItem>> getKoreanDramas() async => [];

  @override
  Future<List<SearchMediaItem>> getFeaturedContent() async => [];

  @override
  Future<List<SearchMediaItem>> getRecommendationsForHistory(
    List<Map<String, dynamic>> history,
  ) async => [];
}

void main() {
  setUpAll(() {
    HttpOverrides.global = MockHttpOverrides();
  });

  testWidgets('shows the desktop home surface', (WidgetTester tester) async {
    await tester.pumpWidget(
      NivioDesktopApp(
        requireAuthentication: false,
        searchRepository: FakeSearchRepository(),
        homeRepository: MockHomeRepository(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Nivio Desktop'), findsNothing);
    expect(find.byKey(const ValueKey('desktop_sidebar_1')), findsOneWidget);
    expect(find.text('Continue Watching'), findsNothing);
    expect(find.text('Trending Now'), findsOneWidget);
    expect(find.text('Trending TV Shows'), findsOneWidget);
    expect(find.text('Trending Anime'), findsOneWidget);
    expect(find.text('Tamil Picks'), findsOneWidget);
    expect(find.text('Upcoming Movies'), findsNothing);
    expect(find.text('Airing Today'), findsNothing);
    expect(find.text('Studios'), findsOneWidget);
    expect(find.bySemanticsLabel('Netflix'), findsOneWidget);
  });
}
