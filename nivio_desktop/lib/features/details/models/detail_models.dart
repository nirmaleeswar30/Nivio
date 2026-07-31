class DetailMedia {
  const DetailMedia({
    required this.id,
    required this.title,
    this.originalTitle,
    required this.mediaType,
    required this.releaseYear,
    required this.releaseDate,
    required this.runtime,
    required this.certification,
    required this.rating,
    required this.voteCount,
    required this.popularity,
    required this.genres,
    required this.overview,
    required this.tagline,
    required this.providers,
    required this.languages,
    required this.audioTracks,
    required this.subtitleTracks,
    required this.productionCompanies,
    required this.productionCountries,
    required this.status,
    required this.cast,
    required this.crew,
    required this.related,
    required this.moreLikeThis,
    this.seasons = const [],
    this.resumeProgress = 0,
    this.isInWatchlist = false,
    // Future-proofing fields
    this.belongsToCollection,
    this.spokenLanguages = const [],
    this.originCountry = const [],
    this.createdBy = const [],
    this.networks = const [],
    this.homepage,
    this.imdbId,
    this.externalIds,
    this.lastEpisode,
    this.nextEpisode,
    this.type,
    this.posterPath,
    this.backdropPath,
    this.logoPath,
    this.trailers = const [],
    this.images = const [],
  });

  final String id;
  final String title;
  final String? originalTitle;
  final DetailMediaType mediaType;
  final String releaseYear;
  final String releaseDate;
  final String runtime;
  final String certification;
  final double rating;
  final int voteCount;
  final double popularity;
  final List<String> genres;
  final String overview;
  final String tagline;
  final List<String> providers;
  final List<String> languages;
  final List<String> audioTracks;
  final List<String> subtitleTracks;
  final List<String> productionCompanies;
  final List<String> productionCountries;
  final String status;
  final List<DetailPerson> cast;
  final DetailCrew crew;
  final List<DetailPosterItem> related;
  final List<DetailPosterItem> moreLikeThis;
  final List<DetailSeason> seasons;
  final double resumeProgress;
  final bool isInWatchlist;

  // Future-proofing fields
  final Map<String, dynamic>? belongsToCollection;
  final List<String> spokenLanguages;
  final List<String> originCountry;
  final List<String> createdBy;
  final List<String> networks;
  final String? homepage;
  final String? imdbId;
  final Map<String, dynamic>? externalIds;
  final DetailEpisode? lastEpisode;
  final DetailEpisode? nextEpisode;
  final String? type;
  final String? posterPath;
  final String? backdropPath;
  final String? logoPath;
  final List<String> trailers;
  final List<String> images;

  bool get isSeries =>
      mediaType == DetailMediaType.tv || mediaType == DetailMediaType.anime;

  DetailMedia copyWith({bool? isInWatchlist}) {
    return DetailMedia(
      id: id,
      title: title,
      originalTitle: originalTitle,
      mediaType: mediaType,
      releaseYear: releaseYear,
      releaseDate: releaseDate,
      runtime: runtime,
      certification: certification,
      rating: rating,
      voteCount: voteCount,
      popularity: popularity,
      genres: genres,
      overview: overview,
      tagline: tagline,
      providers: providers,
      languages: languages,
      audioTracks: audioTracks,
      subtitleTracks: subtitleTracks,
      productionCompanies: productionCompanies,
      productionCountries: productionCountries,
      status: status,
      cast: cast,
      crew: crew,
      related: related,
      moreLikeThis: moreLikeThis,
      seasons: seasons,
      resumeProgress: resumeProgress,
      isInWatchlist: isInWatchlist ?? this.isInWatchlist,
      belongsToCollection: belongsToCollection,
      spokenLanguages: spokenLanguages,
      originCountry: originCountry,
      createdBy: createdBy,
      networks: networks,
      homepage: homepage,
      imdbId: imdbId,
      externalIds: externalIds,
      lastEpisode: lastEpisode,
      nextEpisode: nextEpisode,
      type: type,
      posterPath: posterPath,
      backdropPath: backdropPath,
      logoPath: logoPath,
      trailers: trailers,
      images: images,
    );
  }
}

enum DetailMediaType { movie, tv, anime, live }

extension DetailMediaTypeLabel on DetailMediaType {
  String get label => switch (this) {
    DetailMediaType.movie => 'Movie',
    DetailMediaType.tv => 'TV',
    DetailMediaType.anime => 'Anime',
    DetailMediaType.live => 'Live',
  };
}

class DetailSeason {
  const DetailSeason({
    required this.number,
    required this.name,
    required this.episodes,
    this.episodeCount,
  });

  final int number;
  final String name;
  final List<DetailEpisode> episodes;
  final int? episodeCount;
}

class DetailEpisode {
  const DetailEpisode({
    required this.number,
    required this.title,
    required this.runtime,
    required this.overview,
    required this.progress,
    required this.status,
    this.stillPath,
    this.airDate,
  });

  final int number;
  final String title;
  final String runtime;
  final String overview;
  final double progress;
  final String status;
  final String? stillPath;
  final String? airDate;
}

class DetailPerson {
  const DetailPerson({
    required this.name,
    required this.role,
    this.profilePath,
  });

  final String name;
  final String role;
  final String? profilePath;
}

class DetailCrew {
  const DetailCrew({
    required this.director,
    required this.writer,
    required this.producer,
    required this.composer,
    required this.editor,
    required this.production,
  });

  final String director;
  final String writer;
  final String producer;
  final String composer;
  final String editor;
  final String production;
}

class DetailPosterItem {
  const DetailPosterItem({
    required this.id,
    required this.title,
    required this.year,
    required this.rating,
    required this.subtitle,
    this.posterPath,
  });

  final String id;
  final String title;
  final String year;
  final String rating;
  final String subtitle;
  final String? posterPath;
}
