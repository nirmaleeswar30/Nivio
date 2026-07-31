import '../interfaces/details_repository.dart';
import '../../features/details/models/detail_models.dart';
import '../../features/details/models/detail_route_args.dart';
import '../../features/details/data/detail_dtos.dart';
import '../../shared/mappers/detail_mapper.dart';
import '../network/anilist_client.dart';
import '../network/tmdb_client.dart';

class TmdbDetailsRepository implements DetailsRepository {
  final TmdbClient client;
  final AniListClient aniListClient;
  final Map<int, List<DetailEpisode>> _animeEpisodesCache = {};

  TmdbDetailsRepository({required this.client, AniListClient? aniListClient})
    : aniListClient = aniListClient ?? AniListClient();

  @override
  Future<DetailMedia> loadCompleteDetail(DetailRouteArgs args) async {
    if (args.mediaType == 'anime') {
      return _loadAnimeDetail(args.mediaId);
    }

    final detailFuture = client.getDetails(
      args.mediaId,
      args.mediaType,
      appendToResponse:
          'credits,videos,external_ids,content_ratings,release_dates',
    );
    final providersFuture = client.getWatchProviders(
      args.mediaId,
      args.mediaType,
    );
    final recommendationsFuture = client.getRecommendations(
      args.mediaId,
      args.mediaType,
    );
    final imagesFuture = client.getImages(args.mediaId, args.mediaType);

    final results = await Future.wait([
      detailFuture,
      providersFuture,
      recommendationsFuture,
      imagesFuture,
    ]);

    final detailMap = Map<String, dynamic>.from(results[0]);
    detailMap['media_type'] = args.mediaType;
    final detailDto = DetailDto(detailMap);
    final creditsDto = CreditsDto(results[0]['credits'] ?? {});
    final videosDto = VideosDto(results[0]['videos'] ?? {});
    final providersDto = ProvidersDto(results[1]);
    final imagesDto = ImagesDto(results[3]);
    final recommendationsList = (results[2]['results'] as List? ?? [])
        .map((r) => Map<String, dynamic>.from(r))
        .toList();

    return DetailMapper.toDetailMedia(
      detailDto: detailDto,
      creditsDto: creditsDto,
      videosDto: videosDto,
      providersDto: providersDto,
      imagesDto: imagesDto,
      recommendationsRaw: recommendationsList,
    );
  }

  @override
  Future<List<DetailEpisode>> getSeasonEpisodes({
    required int tvId,
    required int seasonNumber,
  }) async {
    final cachedAnimeEpisodes = _animeEpisodesCache[tvId];
    if (cachedAnimeEpisodes != null) return cachedAnimeEpisodes;

    final response = await client.getSeasonInfo(tvId, seasonNumber);
    final rawEpisodes = response['episodes'] as List? ?? [];
    return DetailMapper.toEpisodeList(rawEpisodes);
  }

  Future<DetailMedia> _loadAnimeDetail(int anilistId) async {
    const query = '''
      query (\$id: Int) {
        Media(id: \$id, type: ANIME) {
          id
          idMal
          title { romaji english native }
          description
          coverImage { extraLarge large }
          bannerImage
          averageScore
          popularity
          favourites
          seasonYear
          startDate { year month day }
          endDate { year month day }
          episodes
          duration
          status
          format
          genres
          nextAiringEpisode { episode }
          airingSchedule(page: 1, perPage: 50, notYetAired: false) {
            nodes { episode airingAt }
          }
          studios(isMain: true) { nodes { name } }
          trailer { site id }
          recommendations(sort: RATING_DESC, perPage: 12) {
            nodes {
              mediaRecommendation {
                id
                title { romaji english }
                coverImage { extraLarge large }
                bannerImage
                averageScore
                seasonYear
                description
              }
            }
          }
        }
      }
    ''';
    final response = await aniListClient.query(
      query,
      variables: {'id': anilistId},
    );
    final media = response['data']?['Media'];
    if (media is! Map) throw Exception('Anime details not found');

    final title = media['title'] as Map?;
    final cover = media['coverImage'] as Map?;
    final studios = media['studios'] is Map
        ? (media['studios']['nodes'] as List? ?? const [])
        : const [];
    final genres = (media['genres'] as List? ?? const [])
        .map((value) => value.toString())
        .toList();
    final episodesCount = (media['episodes'] as num?)?.toInt() ?? 0;
    final durationMinutes = (media['duration'] as num?)?.toInt() ?? 0;
    final format = media['format']?.toString();
    final startDate = _dateFromAniList(media['startDate']);
    final releaseYear = (media['seasonYear'] ?? startDate.split('-').first)
        .toString();
    final rating = ((media['averageScore'] as num?)?.toDouble() ?? 0) / 10;
    final trailer = media['trailer'] as Map?;

    final aniZipEpisodes = await _loadAniZipEpisodes(
      anilistId,
      fallbackRuntimeMinutes: durationMinutes,
    );
    final airDatesByEpisode = _airDatesByEpisode(media['airingSchedule']);
    final knownEpisodesCount = _knownAnimeEpisodeCount(
      episodesCount: episodesCount,
      nextAiringEpisode: _nextAiringEpisode(media['nextAiringEpisode']),
      airedEpisodeNumbers: airDatesByEpisode.keys,
      format: format,
    );
    final episodes = aniZipEpisodes.isNotEmpty
        ? aniZipEpisodes
        : knownEpisodesCount > 0
        ? [
            for (var index = 1; index <= knownEpisodesCount; index++)
              DetailEpisode(
                number: index,
                title: 'Episode $index',
                runtime: durationMinutes > 0 ? '${durationMinutes}m' : '',
                overview: '',
                progress: 0,
                status: 'Unwatched',
                airDate: airDatesByEpisode[index],
              ),
          ]
        : const <DetailEpisode>[];
    _animeEpisodesCache[anilistId] = episodes;

    final related = <DetailPosterItem>[];
    final recommendationNodes = media['recommendations'] is Map
        ? (media['recommendations']['nodes'] as List? ?? const [])
        : const [];
    for (final rawNode in recommendationNodes) {
      final node = rawNode is Map ? rawNode['mediaRecommendation'] : null;
      if (node is! Map) continue;
      final recTitle = node['title'] as Map?;
      final recCover = node['coverImage'] as Map?;
      final id = (node['id'] as num?)?.toInt();
      if (id == null) continue;
      related.add(
        DetailPosterItem(
          id: 'anime:$id',
          title:
              recTitle?['english']?.toString() ??
              recTitle?['romaji']?.toString() ??
              'Unknown',
          year: node['seasonYear']?.toString() ?? 'N/A',
          rating: (((node['averageScore'] as num?)?.toDouble() ?? 0) / 10)
              .toStringAsFixed(1),
          subtitle: 'Anime',
          posterPath:
              recCover?['extraLarge']?.toString() ??
              recCover?['large']?.toString(),
        ),
      );
    }

    return DetailMedia(
      id: 'anime:$anilistId',
      title:
          title?['english']?.toString() ??
          title?['romaji']?.toString() ??
          'Unknown',
      originalTitle:
          title?['romaji']?.toString() ?? title?['native']?.toString(),
      mediaType: DetailMediaType.anime,
      releaseYear: releaseYear,
      releaseDate: startDate,
      runtime: durationMinutes > 0 ? '${durationMinutes}m' : 'N/A',
      certification: 'TV',
      rating: rating,
      voteCount: (media['favourites'] as num?)?.toInt() ?? 0,
      popularity: (media['popularity'] as num?)?.toDouble() ?? 0,
      genres: genres,
      overview: _stripHtml(media['description']?.toString() ?? ''),
      tagline: media['format']?.toString() ?? '',
      providers: const ['AniList'],
      languages: const ['Japanese'],
      audioTracks: const ['Sub', 'Dub'],
      subtitleTracks: const ['English'],
      productionCompanies: studios
          .whereType<Map>()
          .map((studio) => studio['name']?.toString() ?? '')
          .where((name) => name.isNotEmpty)
          .toList(),
      productionCountries: const ['Japan'],
      status: media['status']?.toString() ?? 'Unknown',
      cast: const [],
      crew: const DetailCrew(
        director: 'N/A',
        writer: 'N/A',
        producer: 'N/A',
        composer: 'N/A',
        editor: 'N/A',
        production: 'N/A',
      ),
      related: related,
      moreLikeThis: related,
      seasons: episodes.isEmpty
          ? const []
          : [
              DetailSeason(
                number: 1,
                name: 'Episodes',
                episodeCount: episodes.length,
                episodes: episodes,
              ),
            ],
      posterPath:
          cover?['extraLarge']?.toString() ?? cover?['large']?.toString(),
      backdropPath: media['bannerImage']?.toString(),
      trailers:
          trailer?['site']?.toString().toLowerCase() == 'youtube' &&
              trailer?['id'] != null
          ? [trailer!['id'].toString()]
          : const [],
      images: [
        if (media['bannerImage'] != null) media['bannerImage'].toString(),
      ],
    );
  }

  String _dateFromAniList(Object? value) {
    if (value is! Map) return '';
    final year = (value['year'] as num?)?.toInt();
    if (year == null) return '';
    final month = ((value['month'] as num?)?.toInt() ?? 1).toString().padLeft(
      2,
      '0',
    );
    final day = ((value['day'] as num?)?.toInt() ?? 1).toString().padLeft(
      2,
      '0',
    );
    return '$year-$month-$day';
  }

  String _stripHtml(String value) =>
      value.replaceAll(RegExp(r'<[^>]*>'), '').trim();

  Future<List<DetailEpisode>> _loadAniZipEpisodes(
    int anilistId, {
    required int fallbackRuntimeMinutes,
  }) async {
    try {
      final mappings = await aniListClient.getAniZipMappings(anilistId);
      final rawEpisodes = mappings['episodes'];
      if (rawEpisodes is! Map || rawEpisodes.isEmpty) {
        return const [];
      }

      final sortedKeys =
          rawEpisodes.keys
              .map((key) => key.toString())
              .where((key) => int.tryParse(key) != null)
              .toList()
            ..sort((a, b) => int.parse(a).compareTo(int.parse(b)));

      final episodes = <DetailEpisode>[];
      for (final key in sortedKeys) {
        final rawEpisode = rawEpisodes[key];
        if (rawEpisode is! Map) continue;

        final number = int.parse(key);
        final runtimeMinutes =
            (rawEpisode['runtime'] as num?)?.toInt() ??
            (rawEpisode['length'] as num?)?.toInt() ??
            fallbackRuntimeMinutes;
        episodes.add(
          DetailEpisode(
            number: number,
            title: _aniZipTitle(rawEpisode['title']) ?? 'Episode $number',
            runtime: runtimeMinutes > 0 ? '${runtimeMinutes}m' : '',
            overview:
                rawEpisode['overview']?.toString() ??
                rawEpisode['summary']?.toString() ??
                '',
            progress: 0,
            status: 'Unwatched',
            stillPath: rawEpisode['image']?.toString(),
            airDate:
                rawEpisode['airDate']?.toString() ??
                rawEpisode['airdate']?.toString(),
          ),
        );
      }
      return episodes;
    } catch (_) {
      return const [];
    }
  }

  String? _aniZipTitle(Object? value) {
    if (value is String && value.trim().isNotEmpty) return value.trim();
    if (value is! Map) return null;
    for (final key in const ['en', 'x-jat', 'ja']) {
      final title = value[key]?.toString().trim();
      if (title != null && title.isNotEmpty) return title;
    }
    return null;
  }

  Map<int, String> _airDatesByEpisode(Object? value) {
    if (value is! Map) return const {};
    final nodes = value['nodes'] as List? ?? const [];
    final dates = <int, String>{};
    for (final node in nodes) {
      if (node is! Map) continue;
      final episode = (node['episode'] as num?)?.toInt();
      final airingAt = (node['airingAt'] as num?)?.toInt();
      if (episode == null || episode <= 0 || airingAt == null) continue;
      dates[episode] = DateTime.fromMillisecondsSinceEpoch(
        airingAt * 1000,
        isUtc: true,
      ).toIso8601String().split('T').first;
    }
    return dates;
  }

  int? _nextAiringEpisode(Object? value) {
    if (value is! Map) return null;
    final episode = (value['episode'] as num?)?.toInt();
    return episode != null && episode > 0 ? episode : null;
  }

  int _knownAnimeEpisodeCount({
    required int episodesCount,
    required int? nextAiringEpisode,
    required Iterable<int> airedEpisodeNumbers,
    required String? format,
  }) {
    if (episodesCount > 0) return episodesCount;
    if (nextAiringEpisode != null && nextAiringEpisode > 1) {
      return nextAiringEpisode - 1;
    }

    var highestAiredEpisode = 0;
    for (final episode in airedEpisodeNumbers) {
      if (episode > highestAiredEpisode) highestAiredEpisode = episode;
    }
    if (highestAiredEpisode > 0) return highestAiredEpisode;

    return _canUseDefaultAnimeEpisodeCount(format) ? 12 : 0;
  }

  bool _canUseDefaultAnimeEpisodeCount(String? format) {
    return switch (format) {
      'TV' || 'TV_SHORT' || 'ONA' || 'OVA' => true,
      _ => false,
    };
  }
}
