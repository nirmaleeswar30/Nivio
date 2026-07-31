import 'package:nivio_desktop/core/interfaces/search_repository.dart';
import 'package:nivio_desktop/features/details/models/detail_models.dart';
import 'package:nivio_desktop/features/search/models/search_media_item.dart';

class FakeSearchRepository implements SearchRepository {
  FakeSearchRepository({List<SearchMediaItem>? items})
    : _items = items ?? fakeSearchItems;

  final List<SearchMediaItem> _items;

  @override
  Future<List<SearchMediaItem>> search({
    required String query,
    required SearchLanguageFilter language,
    required SearchMediaTypeFilter mediaType,
    required SearchSortOption sort,
    int page = 1,
  }) async {
    if (query == '__error__') throw StateError('Fake search failed.');
    if (page > 1) return const [];

    final normalizedQuery = query.trim().toLowerCase();
    var results = _items
        .where((item) {
          final matchesQuery =
              normalizedQuery.isEmpty ||
              item.title.toLowerCase().contains(normalizedQuery);
          final matchesLanguage =
              language == SearchLanguageFilter.all || item.language == language;
          final matchesMediaType =
              mediaType == SearchMediaTypeFilter.all ||
              item.mediaType == mediaType;
          return matchesQuery && matchesLanguage && matchesMediaType;
        })
        .toList(growable: false);

    switch (sort) {
      case SearchSortOption.defaultOrder:
        break;
      case SearchSortOption.title:
        results = results.toList()
          ..sort(
            (left, right) =>
                left.title.toLowerCase().compareTo(right.title.toLowerCase()),
          );
        break;
      case SearchSortOption.year:
        results = results.toList()
          ..sort((left, right) => right.year.compareTo(left.year));
        break;
      case SearchSortOption.rating:
        results = results.toList()
          ..sort((left, right) => right.rating.compareTo(left.rating));
        break;
    }

    return results;
  }
}

const fakeSearchItems = [
  SearchMediaItem(
    id: 'movie:550',
    title: 'Signal Lost',
    year: 2026,
    rating: 8.4,
    language: SearchLanguageFilter.english,
    mediaType: SearchMediaTypeFilter.movie,
    provider: 'Prime Video',
    genres: ['Drama', 'Action'],
    posterLabel: 'Signal Lost',
    overview: 'An ex-operator uncovers a hidden broadcast network.',
    runtimeLabel: '1h 56m',
  ),
  SearchMediaItem(
    id: 'movie:551',
    title: 'Halo Signal',
    year: 2025,
    rating: 7.8,
    language: SearchLanguageFilter.english,
    mediaType: SearchMediaTypeFilter.movie,
    provider: 'Nivio',
    genres: ['Sci-Fi'],
    posterLabel: 'Halo Signal',
    overview: 'A test fixture movie used by search widget coverage.',
    runtimeLabel: '2h 01m',
  ),
  SearchMediaItem(
    id: 'movie:552',
    title: 'Blackout City',
    year: 2026,
    rating: 8.6,
    language: SearchLanguageFilter.english,
    mediaType: SearchMediaTypeFilter.movie,
    provider: 'Nivio',
    genres: ['Action', 'Sci-Fi'],
    posterLabel: 'Blackout City',
    overview: 'A courier crosses a neon city with a stolen memory vault.',
    runtimeLabel: '2h 18m',
  ),
];

DetailMedia fakeDetailMedia(String id) => DetailMedia(
  id: id,
  title: id.contains('signal') || id.contains('550')
      ? 'Signal Lost'
      : 'Test Movie',
  mediaType: DetailMediaType.movie,
  releaseYear: '2026',
  releaseDate: '2026-01-01',
  runtime: '1h 56m',
  certification: 'PG-13',
  rating: 8.4,
  voteCount: 100,
  popularity: 50,
  genres: const ['Drama'],
  overview: 'Test fixture detail item.',
  tagline: '',
  providers: const ['Nivio'],
  languages: const ['English'],
  audioTracks: const ['English'],
  subtitleTracks: const ['English'],
  productionCompanies: const ['Nivio'],
  productionCountries: const ['US'],
  status: 'Released',
  cast: const [],
  crew: const DetailCrew(
    director: '',
    writer: '',
    producer: '',
    composer: '',
    editor: '',
    production: '',
  ),
  related: const [],
  moreLikeThis: const [],
);
