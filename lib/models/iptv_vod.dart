/// On-demand content from IPTV playlists: Xtream VOD/series, or `/movie/` and
/// `/series/` entries of an M3U playlist.
class IptvMovie {
  final String name;
  final String url;
  final String poster;
  final String group;
  final String rating;

  const IptvMovie({
    required this.name,
    required this.url,
    this.poster = '',
    this.group = 'Uncategorized',
    this.rating = '',
  });

  factory IptvMovie.fromJson(Map<String, dynamic> j) => IptvMovie(
        name: j['name'] ?? '',
        url: j['url'] ?? '',
        poster: j['poster'] ?? '',
        group: j['group'] ?? 'Uncategorized',
        rating: j['rating'] ?? '',
      );

  Map<String, dynamic> toJson() => {'name': name, 'url': url, 'poster': poster, 'group': group, 'rating': rating};
}

class IptvEpisode {
  final int season;
  final int episode;
  final String title;
  final String url;
  final String image;
  final String plot;

  const IptvEpisode({
    required this.season,
    required this.episode,
    required this.title,
    required this.url,
    this.image = '',
    this.plot = '',
  });

  factory IptvEpisode.fromJson(Map<String, dynamic> j) => IptvEpisode(
        season: j['season'] ?? 1,
        episode: j['episode'] ?? 0,
        title: j['title'] ?? '',
        url: j['url'] ?? '',
        image: j['image'] ?? '',
        plot: j['plot'] ?? '',
      );

  Map<String, dynamic> toJson() =>
      {'season': season, 'episode': episode, 'title': title, 'url': url, 'image': image, 'plot': plot};
}

class IptvSeries {
  final String name;
  final String poster;
  final String group;
  final String rating;
  final String plot;

  /// Xtream series: episodes are fetched on demand with these.
  final String? playlistId;
  final String? seriesId;

  /// M3U series: episodes come from the playlist itself.
  final List<IptvEpisode> episodes;

  const IptvSeries({
    required this.name,
    this.poster = '',
    this.group = 'Uncategorized',
    this.rating = '',
    this.plot = '',
    this.playlistId,
    this.seriesId,
    this.episodes = const [],
  });

  factory IptvSeries.fromJson(Map<String, dynamic> j) => IptvSeries(
        name: j['name'] ?? '',
        poster: j['poster'] ?? '',
        group: j['group'] ?? 'Uncategorized',
        rating: j['rating'] ?? '',
        plot: j['plot'] ?? '',
        playlistId: j['playlistId'],
        seriesId: j['seriesId'],
        episodes: ((j['episodes'] as List?) ?? const [])
            .map((e) => IptvEpisode.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList(),
      );

  Map<String, dynamic> toJson() => {
        'name': name,
        'poster': poster,
        'group': group,
        'rating': rating,
        'plot': plot,
        if (playlistId != null) 'playlistId': playlistId,
        if (seriesId != null) 'seriesId': seriesId,
        if (episodes.isNotEmpty) 'episodes': episodes.map((e) => e.toJson()).toList(),
      };
}

class IptvVodLibrary {
  final List<IptvMovie> movies;
  final List<IptvSeries> series;

  const IptvVodLibrary({this.movies = const [], this.series = const []});

  bool get isEmpty => movies.isEmpty && series.isEmpty;
}
