import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:nivio_desktop/features/details/controllers/detail_controller.dart';
import 'package:nivio_desktop/features/details/models/detail_models.dart';
import 'package:nivio_desktop/features/details/models/detail_route_args.dart';
import 'package:nivio_desktop/core/interfaces/details_repository.dart';
import 'fakes/media_test_fakes.dart';

class MockDetailsRepository implements DetailsRepository {
  final Map<int, List<DetailEpisode>> mockEpisodes = {};
  bool throwError = false;

  @override
  Future<DetailMedia> loadCompleteDetail(DetailRouteArgs args) async {
    if (throwError) {
      throw Exception('Network error');
    }
    final mediaIdString = '${args.mediaType}:${args.mediaId}';
    return fakeDetailMedia(mediaIdString);
  }

  @override
  Future<List<DetailEpisode>> getSeasonEpisodes({
    required int tvId,
    required int seasonNumber,
  }) async {
    if (throwError) {
      throw Exception('Network error');
    }
    return mockEpisodes[seasonNumber] ?? [];
  }
}

class DelayedEpisodesRepository implements DetailsRepository {
  final Map<int, Completer<List<DetailEpisode>>> episodeRequests = {};

  @override
  Future<DetailMedia> loadCompleteDetail(DetailRouteArgs args) async {
    return const DetailMedia(
      id: 'tv:100',
      title: 'Delayed Series',
      mediaType: DetailMediaType.tv,
      releaseYear: '2024',
      releaseDate: '2024-01-01',
      runtime: '40m',
      certification: 'TV-MA',
      rating: 7.5,
      voteCount: 10,
      popularity: 10,
      genres: ['Drama'],
      overview: 'Test series',
      tagline: '',
      providers: [],
      languages: [],
      audioTracks: [],
      subtitleTracks: [],
      productionCompanies: [],
      productionCountries: [],
      status: 'Returning Series',
      cast: [],
      crew: DetailCrew(
        director: '',
        writer: '',
        producer: '',
        composer: '',
        editor: '',
        production: '',
      ),
      related: [],
      moreLikeThis: [],
      seasons: [
        DetailSeason(number: 1, name: 'Season 1', episodes: []),
        DetailSeason(number: 2, name: 'Season 2', episodes: []),
      ],
    );
  }

  @override
  Future<List<DetailEpisode>> getSeasonEpisodes({
    required int tvId,
    required int seasonNumber,
  }) {
    return (episodeRequests[seasonNumber] ??= Completer<List<DetailEpisode>>())
        .future;
  }
}

void main() {
  group('DetailController Tests', () {
    late MockDetailsRepository mockRepository;
    late DetailController controller;

    setUp(() {
      mockRepository = MockDetailsRepository();
      controller = DetailController(repository: mockRepository);
    });

    test('initial state defaults', () {
      expect(
        controller.status,
        equals(DetailStatus.loading),
      ); // starts as loading initially
      expect(controller.media, isNull);
      expect(controller.episodes, isEmpty);
    });

    test('loadDetail success loads movie details', () async {
      final args = DetailRouteArgs(mediaType: 'movie', mediaId: 550);
      final future = controller.loadDetail(args);

      expect(controller.status, equals(DetailStatus.loading));

      await future;

      expect(controller.status, equals(DetailStatus.loaded));
      expect(controller.media, isNotNull);
    });

    test('loadDetail failure sets error state', () async {
      mockRepository.throwError = true;
      final args = DetailRouteArgs(mediaType: 'movie', mediaId: 550);

      await controller.loadDetail(args);

      expect(controller.status, equals(DetailStatus.error));
      expect(controller.errorMessage, contains('Network error'));
    });

    test('loadSeasonEpisodes success loads episodes', () async {
      final mockEpisodeList = [
        const DetailEpisode(
          number: 1,
          title: 'Test Pilot',
          runtime: '45m',
          overview: 'Overview test',
          progress: 0.0,
          status: 'Unwatched',
        ),
      ];
      mockRepository.mockEpisodes[1] = mockEpisodeList;

      final args = DetailRouteArgs(mediaType: 'tv', mediaId: 100);
      await controller.loadDetail(args);

      // Now load season 1 episodes
      final episodeFuture = controller.loadSeasonEpisodes(100, 1);
      expect(controller.isLoadingEpisodes, isTrue);

      await episodeFuture;

      expect(controller.isLoadingEpisodes, isFalse);
      expect(controller.episodes, equals(mockEpisodeList));
    });

    test('ignores stale season episode responses', () async {
      final repository = DelayedEpisodesRepository();
      final controller = DetailController(repository: repository);
      addTearDown(controller.dispose);

      final season1 = controller.loadSeasonEpisodes(100, 1);
      final season2 = controller.loadSeasonEpisodes(100, 2);

      repository.episodeRequests[2]!.complete(const [
        DetailEpisode(
          number: 1,
          title: 'Future',
          runtime: '40m',
          overview: '',
          progress: 0,
          status: 'Unwatched',
        ),
      ]);
      await season2;
      expect(controller.episodes.single.title, 'Future');

      repository.episodeRequests[1]!.complete(const [
        DetailEpisode(
          number: 1,
          title: 'Old',
          runtime: '40m',
          overview: '',
          progress: 0,
          status: 'Unwatched',
        ),
      ]);
      await season1;

      expect(controller.episodes.single.title, 'Future');
    });
  });
}
