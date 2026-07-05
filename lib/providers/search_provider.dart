import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nivio/models/search_result.dart';
import 'package:nivio/providers/service_providers.dart';

// Search query state
final searchQueryProvider = StateProvider<String>((ref) => '');

// Current page for pagination
final searchPageProvider = StateProvider<int>((ref) => 1);

// Language filter (null = all languages)
final searchLanguageFilterProvider = StateProvider<String?>((ref) => null);

// Sort option (null = default, 'popularity', 'title', 'year')
final searchSortProvider = StateProvider<String?>((ref) => null);

// All accumulated search results (for pagination)
final accumulatedSearchResultsProvider = StateProvider<List<SearchResult>>(
  (ref) => [],
);

// Total pages and results info
final searchMetadataProvider =
    StateProvider<({int totalPages, int totalResults})>((ref) {
      return (totalPages: 0, totalResults: 0);
    });

// Search results provider with pagination
final searchResultsProvider = FutureProvider<SearchResults>((ref) async {
  final query = ref.watch(searchQueryProvider);
  if (query.isEmpty) {
    ref.read(accumulatedSearchResultsProvider.notifier).state = [];
    ref.read(searchMetadataProvider.notifier).state = (
      totalPages: 0,
      totalResults: 0,
    );
    return const SearchResults(
      page: 0,
      results: [],
      totalPages: 0,
      totalResults: 0,
    );
  }

  final page = ref.watch(searchPageProvider);
  final language = ref.watch(searchLanguageFilterProvider);
  final sortBy = ref.watch(searchSortProvider);

  final tmdb = ref.watch(tmdbServiceProvider);
  final anilist = ref.watch(aniListServiceProvider);

  // Run both searches concurrently
  final responses = await Future.wait([
    tmdb.search(
      query,
      page: page,
      language: language,
      sortBy: sortBy,
    ),
    anilist.searchAnime(query, page: page),
  ]);

  final tmdbResults = responses[0];
  final anilistResults = responses[1];

  // Sort merged results by vote average (popularity proxy) or just keep TMDB first. We'll append AniList to the end or interleave them.
  // Interleaving is better for discovery.
  final interleaved = <SearchResult>[];
  final maxLength = tmdbResults.results.length > anilistResults.results.length 
      ? tmdbResults.results.length 
      : anilistResults.results.length;
      
  for (int i = 0; i < maxLength; i++) {
    if (i < anilistResults.results.length) interleaved.add(anilistResults.results[i]);
    if (i < tmdbResults.results.length) interleaved.add(tmdbResults.results[i]);
  }

  final maxTotalPages = tmdbResults.totalPages > anilistResults.totalPages ? tmdbResults.totalPages : anilistResults.totalPages;
  final totalResultsCombined = tmdbResults.totalResults + anilistResults.totalResults;

  // Update metadata
  ref.read(searchMetadataProvider.notifier).state = (
    totalPages: maxTotalPages,
    totalResults: totalResultsCombined,
  );

  final mergedData = SearchResults(
    page: page,
    results: interleaved,
    totalPages: maxTotalPages,
    totalResults: totalResultsCombined,
  );

  // Accumulate results for infinite scroll
  if (page == 1) {
    ref.read(accumulatedSearchResultsProvider.notifier).state = mergedData.results;
  } else {
    final accumulated = ref.read(accumulatedSearchResultsProvider);
    ref.read(accumulatedSearchResultsProvider.notifier).state = [
      ...accumulated,
      ...mergedData.results,
    ];
  }

  final accumulated = ref.read(accumulatedSearchResultsProvider);
  return SearchResults(
    page: page,
    results: accumulated,
    totalPages: mergedData.totalPages,
    totalResults: mergedData.totalResults,
  );
});
