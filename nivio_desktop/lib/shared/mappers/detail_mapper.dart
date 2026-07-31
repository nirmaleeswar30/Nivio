import '../../features/details/data/detail_dtos.dart';
import '../../features/details/models/detail_models.dart';
import '../../features/search/models/search_media_item.dart';
import '../dto/media_dto.dart';
import 'media_mapper.dart';

class DetailMapper {
  static DetailMedia toDetailMedia({
    required DetailDto detailDto,
    required CreditsDto creditsDto,
    required VideosDto videosDto,
    required ProvidersDto providersDto,
    required ImagesDto imagesDto,
    required List<Map<String, dynamic>> recommendationsRaw,
  }) {
    final mediaType = detailDto.raw['media_type'] == 'tv'
        ? DetailMediaType.tv
        : DetailMediaType.movie;

    // Genres mapping
    final genres = detailDto.genres;

    // Runtime formatted string
    final runtimeMinutes = detailDto.runtime;
    final runtimeStr = runtimeMinutes != null && runtimeMinutes > 0
        ? (runtimeMinutes >= 60
              ? '${runtimeMinutes ~/ 60}h ${runtimeMinutes % 60}m'
              : '${runtimeMinutes}m')
        : 'N/A';

    // Release Date and Year
    final releaseDate = detailDto.releaseDate ?? '';
    final releaseYear = releaseDate.length >= 4
        ? releaseDate.substring(0, 4)
        : 'N/A';

    // Languages
    final languages = detailDto.spokenLanguages;
    final originCountries = detailDto.originCountry;

    // Watch providers (check US region, fallback to any first available)
    final providersList = <String>[];
    final usProviders = providersDto.results['US'] as Map?;
    final targetProviders =
        usProviders ??
        (providersDto.results.isNotEmpty
            ? providersDto.results.values.first as Map?
            : null);
    if (targetProviders != null) {
      final flatrate = targetProviders['flatrate'] as List?;
      final free = targetProviders['free'] as List?;
      final ads = targetProviders['ads'] as List?;
      if (flatrate != null) {
        for (final p in flatrate) {
          if (p is Map && p['provider_name'] != null) {
            providersList.add(p['provider_name'] as String);
          }
        }
      }
      if (free != null && providersList.isEmpty) {
        for (final p in free) {
          if (p is Map && p['provider_name'] != null) {
            providersList.add(p['provider_name'] as String);
          }
        }
      }
      if (ads != null && providersList.isEmpty) {
        for (final p in ads) {
          if (p is Map && p['provider_name'] != null) {
            providersList.add(p['provider_name'] as String);
          }
        }
      }
    }
    if (providersList.isEmpty) {
      providersList.add('Not Available');
    }

    // Cast mapping
    final cast = creditsDto.cast.take(12).map((c) {
      return DetailPerson(
        name: (c['name'] ?? '') as String,
        role: (c['character'] ?? '') as String,
        profilePath: c['profile_path'] as String?,
      );
    }).toList();

    // Crew mapping
    String director = 'N/A';
    String writer = 'N/A';
    String producer = 'N/A';
    String composer = 'N/A';
    String editor = 'N/A';

    for (final c in creditsDto.crew) {
      final job = c['job'] as String?;
      final name = c['name'] as String?;
      if (job == 'Director') director = name ?? director;
      if (job == 'Writer' || job == 'Screenplay') writer = name ?? writer;
      if (job == 'Producer') producer = name ?? producer;
      if (job == 'Original Music Composer') composer = name ?? composer;
      if (job == 'Editor') editor = name ?? editor;
    }

    final crew = DetailCrew(
      director: director,
      writer: writer,
      producer: producer,
      composer: composer,
      editor: editor,
      production: detailDto.productionCompanies.isNotEmpty
          ? detailDto.productionCompanies.first
          : 'N/A',
    );

    // Videos / Trailers (YouTube keys)
    final trailers = videosDto.results
        .where(
          (v) =>
              v['site'] == 'YouTube' &&
              (v['type'] == 'Trailer' || v['type'] == 'Teaser'),
        )
        .map((v) => v['key'] as String? ?? '')
        .where((key) => key.isNotEmpty)
        .toList();

    // Logos / Images
    String? logoPath;
    final logos = imagesDto.logos;
    if (logos.isNotEmpty) {
      // Find the first logo, preferably english
      final enLogo = logos.firstWhere(
        (l) => l['iso_639_1'] == 'en',
        orElse: () => logos.first,
      );
      logoPath = enLogo['file_path'] as String?;
    }

    // Map recommendations raw JSON to SearchMediaItem
    final List<SearchMediaItem> recommendations = recommendationsRaw.map((
      item,
    ) {
      // Inject media_type if missing in result
      if (item['media_type'] == null) {
        item['media_type'] = detailDto.raw['media_type'];
      }
      return MediaMapper.toSearchMediaItem(MediaDto.fromJson(item));
    }).toList();

    // Map recommendations to DetailPosterItem
    final relatedItems = recommendations.map((item) {
      return DetailPosterItem(
        id: item.id,
        title: item.title,
        year: item.year.toString(),
        rating: item.rating.toStringAsFixed(1),
        subtitle: item.mediaTypeLabel,
        posterPath: item.posterPath,
      );
    }).toList();

    final seasons = _mapTvSeasons(detailDto, mediaType);

    final certification = _certification(detailDto, mediaType);

    return DetailMedia(
      id: '${detailDto.raw['media_type']}:${detailDto.id}',
      title: detailDto.title,
      originalTitle: detailDto.originalTitle,
      mediaType: mediaType,
      releaseYear: releaseYear,
      releaseDate: releaseDate,
      runtime: runtimeStr,
      certification: certification,
      rating: detailDto.voteAverage,
      voteCount: detailDto.voteCount,
      popularity: detailDto.popularity,
      genres: genres,
      overview: detailDto.overview ?? 'No overview available.',
      tagline: detailDto.tagline ?? '',
      providers: providersList,
      languages: languages,
      audioTracks: const ['English 5.1'],
      subtitleTracks: const ['English CC'],
      productionCompanies: detailDto.productionCompanies,
      productionCountries: detailDto.productionCountries,
      status: detailDto.status ?? 'Released',
      cast: cast,
      crew: crew,
      related: relatedItems,
      moreLikeThis: relatedItems,
      seasons: seasons,
      resumeProgress: 0.0,
      isInWatchlist: false,
      belongsToCollection: detailDto.belongsToCollection,
      spokenLanguages: detailDto.spokenLanguages,
      originCountry: originCountries,
      createdBy: detailDto.createdBy,
      networks: detailDto.networks,
      homepage: detailDto.homepage,
      imdbId: detailDto.imdbId,
      externalIds: _mapStringKeyedMap(detailDto.raw['external_ids']),
      lastEpisode: _mapEpisodeObject(detailDto.raw['last_episode_to_air']),
      nextEpisode: _mapEpisodeObject(detailDto.raw['next_episode_to_air']),
      type: detailDto.type,
      posterPath: detailDto.posterPath,
      backdropPath: detailDto.backdropPath,
      logoPath: logoPath,
      trailers: trailers,
      images: imagesDto.backdrops
          .map((i) => i['file_path'] as String? ?? '')
          .where((p) => p.isNotEmpty)
          .toList(),
    );
  }

  static List<DetailEpisode> toEpisodeList(List<dynamic> rawEpisodes) {
    return rawEpisodes.map((e) {
      final runMinutes = e['runtime'] as int? ?? 0;
      final runStr = runMinutes > 0 ? '${runMinutes}m' : '';
      return DetailEpisode(
        number: e['episode_number'] as int? ?? 0,
        title: (e['name'] ?? 'Episode ${e['episode_number']}') as String,
        runtime: runStr,
        overview: (e['overview'] ?? '') as String,
        progress: 0.0,
        status: 'Unwatched',
        stillPath: e['still_path'] as String?,
        airDate: e['air_date'] as String?,
      );
    }).toList();
  }

  static DetailEpisode? _mapEpisodeObject(Object? value) {
    if (value is! Map) return null;
    return DetailEpisode(
      number: (value['episode_number'] as num?)?.toInt() ?? 0,
      title: value['name']?.toString() ?? 'Episode',
      runtime: ((value['runtime'] as num?)?.toInt() ?? 0) > 0
          ? '${(value['runtime'] as num).toInt()}m'
          : '',
      overview: value['overview']?.toString() ?? '',
      progress: 0,
      status: 'Unwatched',
      stillPath: value['still_path']?.toString(),
      airDate: value['air_date']?.toString(),
    );
  }

  static String _certification(DetailDto detailDto, DetailMediaType mediaType) {
    if (mediaType == DetailMediaType.tv) {
      final contentRatings = detailDto.raw['content_ratings'];
      if (contentRatings is Map) {
        final rating = _countryRating(
          contentRatings['results'],
          countryKey: 'iso_3166_1',
          valueKey: 'rating',
        );
        if (rating != null) return rating;
      }
      return 'TV';
    }

    final releaseDates = detailDto.raw['release_dates'];
    if (releaseDates is Map) {
      final results = releaseDates['results'];
      if (results is List) {
        final us = results.whereType<Map>().firstWhere(
          (entry) => entry['iso_3166_1'] == 'US',
          orElse: () => const {},
        );
        final dates = us['release_dates'];
        if (dates is List) {
          for (final rawDate in dates.whereType<Map>()) {
            final certification = rawDate['certification']?.toString().trim();
            if (certification != null && certification.isNotEmpty) {
              return certification;
            }
          }
        }
      }
    }
    return 'NR';
  }

  static String? _countryRating(
    Object? entries, {
    required String countryKey,
    required String valueKey,
  }) {
    if (entries is! List) return null;
    final us = entries.whereType<Map>().firstWhere(
      (entry) => entry[countryKey] == 'US',
      orElse: () => const {},
    );
    final rating = us[valueKey]?.toString().trim();
    return rating == null || rating.isEmpty ? null : rating;
  }

  static Map<String, dynamic>? _mapStringKeyedMap(Object? value) {
    if (value is! Map) return null;
    return Map<String, dynamic>.from(value);
  }

  static List<DetailSeason> _mapTvSeasons(
    DetailDto detailDto,
    DetailMediaType mediaType,
  ) {
    if (mediaType != DetailMediaType.tv) return const [];

    final seasons = detailDto.seasons.map((season) {
      final number = (season['season_number'] as num?)?.toInt() ?? 0;
      final episodeCount = (season['episode_count'] as num?)?.toInt();
      return DetailSeason(
        number: number,
        name: (season['name'] ?? 'Season $number') as String,
        episodeCount: episodeCount,
        episodes: const [],
      );
    }).toList();

    final expectedSeasonCount =
        (detailDto.raw['number_of_seasons'] as num?)?.toInt() ?? 0;
    final existingSeasonNumbers = seasons
        .map((season) => season.number)
        .toSet();
    for (
      var seasonNumber = 1;
      seasonNumber <= expectedSeasonCount;
      seasonNumber++
    ) {
      if (existingSeasonNumbers.contains(seasonNumber)) continue;
      seasons.add(
        DetailSeason(
          number: seasonNumber,
          name: 'Season $seasonNumber',
          episodes: const [],
        ),
      );
    }

    final episodeCount =
        (detailDto.raw['number_of_episodes'] as num?)?.toInt() ?? 0;
    if (seasons.isEmpty && episodeCount > 0) {
      seasons.add(
        DetailSeason(
          number: 1,
          name: 'Season 1',
          episodeCount: episodeCount,
          episodes: const [],
        ),
      );
    }

    return seasons;
  }
}
