import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:nivio/models/search_result.dart';
import 'package:nivio/services/cache_service.dart';
import 'package:nivio/services/tmdb_service.dart';

typedef ExtensionMedia = ({
  String id,
  String type,
  int? season,
  int? episode,
  String? tmdbId,
  int? absoluteEpisode,
});

typedef NuvioAnimeMapping = ({
  ExtensionMedia target,
  int aniListId,
  int? malId,
  String? imdbId,
  int episode,
});

/// Answers a script's mapping request from the verified playback context.
Map<String, int>? nuvioAnimeMappingResponse(
  String method,
  Uri url,
  NuvioAnimeMapping mapping,
) {
  if (method != 'GET' ||
      url.scheme != 'https' ||
      url.port != 443 ||
      url.userInfo.isNotEmpty) {
    return null;
  }
  final target = mapping.target;
  final query = url.queryParameters;
  if (query['s'] != target.season?.toString() ||
      query['e'] != target.episode?.toString()) {
    return null;
  }
  final malId = mapping.malId;
  return switch ((url.host, url.path)) {
    ('arm.haglund.dev', '/api/v2/tmdb') when query['id'] == target.id => {
      if (malId != null) 'mal_id': malId,
      'ani_id': mapping.aniListId,
      'episode': mapping.episode,
    },
    ('id-mapping-api-malid.hf.space', '/api/resolve')
        when malId != null &&
            mapping.imdbId != null &&
            query['id'] == mapping.imdbId =>
      {'mal_id': malId, 'mal_episode': mapping.episode},
    _ => null,
  };
}

/// Shared across the enabled providers, with an Ani.zip lookup only when needed.
class ExtensionAnimeMappings {
  ExtensionAnimeMappings({
    CacheService? cache,
    TmdbService? tmdb,
    http.Client Function() createClient = http.Client.new,
  }) : _cache = cache,
       _tmdb = tmdb,
       _createClient = createClient;

  final CacheService? _cache;
  final TmdbService? _tmdb;
  final http.Client Function() _createClient;
  final _pending = <int, Future<Map<String, dynamic>?>>{};

  Future<Map<String, dynamic>?> _lookup(int id) => _pending.putIfAbsent(
    id,
    () => _fetch(id).whenComplete(() {
      _pending.remove(id);
    }),
  );

  Future<Map<String, dynamic>?> _fetch(int id) async {
    final key = 'extension_anizip_v2_$id';
    try {
      final cached = await _cache?.getRaw(key);
      if (cached != null) return cached;
    } catch (_) {
      // An unavailable cache should not prevent discovery.
    }
    final client = _createClient();
    try {
      final response = await client
          .get(Uri.https('api.ani.zip', '/mappings', {'anilist_id': '$id'}))
          .timeout(const Duration(seconds: 5));
      if (response.statusCode != 200) return null;
      final data = jsonDecode(response.body) as Map;
      final mappings = data['mappings'] as Map?;
      final tmdbId = _integer(
        mappings?['themoviedb_id'] ?? mappings?['tmdb_id'],
      );
      final episodes = data['episodes'] as Map? ?? const {};
      final result = <String, dynamic>{
        'tmdbId': tmdbId,
        'malId': _integer(mappings?['mal_id']),
        'imdbId': mappings?['imdb_id']?.toString(),
        'format': mappings?['type'],
        'episodes': {
          for (final MapEntry(:key, :value) in episodes.entries)
            if (value is Map && int.tryParse('$key') != null)
              '$key': {
                'season': _integer(value['seasonNumber']),
                'episode': _integer(value['episodeNumber']),
                'absolute': _integer(value['absoluteEpisodeNumber']),
                'date':
                    _date(value['airDate']) ??
                    _date(value['airdate']) ??
                    _date(value['airDateUtc']),
                'title': value['title'] is Map ? value['title']['en'] : null,
              },
        },
      };
      if (tmdbId != null) {
        await _cache?.set(key, result, ttl: CacheService.longCache);
      }
      return result;
    } catch (_) {
      return null;
    } finally {
      client.close();
    }
  }

  Future<({int season, int episode})?> _tmdbEpisode(
    int id,
    int? season,
    Map episode,
  ) async {
    final tmdb = _tmdb;
    final date = _date(episode['date']);
    final title = _title(episode['title']);
    if (tmdb == null || date == null && title == null) return null;

    Future<({int season, int episode})?> checkSeason(int number) async {
      try {
        final info = await tmdb
            .getSeasonInfo(id, number)
            .timeout(const Duration(seconds: 4));
        final matches = info.episodes.where((candidate) {
          final candidateDate = _date(candidate.airDate);
          if (date != null && candidateDate != null)
            return date == candidateDate;
          return title != null && _title(candidate.episodeName) == title;
        }).toList();
        if (matches.length == 1) {
          return (season: number, episode: matches.single.episodeNumber);
        }
        if (title == null) return null;
        final byTitle = matches.where(
          (candidate) => _title(candidate.episodeName) == title,
        );
        return byTitle.length == 1
            ? (season: number, episode: byTitle.single.episodeNumber)
            : null;
      } catch (_) {
        return null;
      }
    }

    final preferred = season == null ? null : await checkSeason(season);
    if (preferred != null || date == null) return preferred;

    // TVDB and TMDB sometimes group the same episodes into different seasons.
    try {
      final series = await tmdb
          .getSeriesInfo(id)
          .timeout(const Duration(seconds: 4));
      final alternatives = series.seasons.where((entry) {
        final start = _date(entry.airDate);
        return entry.seasonNumber != season &&
            entry.seasonNumber > 0 &&
            (start == null || start.compareTo(date) <= 0);
      }).toList()..sort((a, b) => (b.airDate ?? '').compareTo(a.airDate ?? ''));
      final matches = (await Future.wait([
        for (final entry in alternatives.take(3))
          checkSeason(entry.seasonNumber),
      ])).nonNulls;
      return matches.length == 1 ? matches.single : null;
    } catch (_) {
      return null;
    }
  }
}

class ExtensionMediaLookup {
  ExtensionMediaLookup(this.media, this.season, this.episode, this._mappings);

  final SearchResult media;
  final int season;
  final int episode;
  final ExtensionAnimeMappings _mappings;

  bool get isAnime => media.mediaType == 'anime';
  late final _mapping = isAnime
      ? _mappings._lookup(media.id)
      : Future<Map<String, dynamic>?>.value();
  late final Future<bool> isMovie = _isMovie();
  late final Future<ExtensionMedia?> tmdb = _tmdbTarget();
  late final Future<NuvioAnimeMapping?> nuvioMapping = _nuvioMapping();
  late final Future<ExtensionMedia> cloudstream = _cloudstreamTarget();

  Future<bool> _isMovie() async {
    if (!isAnime) return media.mediaType == 'movie';
    final format = media.animeFormat ?? (await _mapping)?['format'];
    return format?.toString().toUpperCase() == 'MOVIE';
  }

  Future<ExtensionMedia?> _tmdbTarget() async {
    if (!isAnime) return _target(media.id, await isMovie);
    final mapping = await _mapping;
    final id = mapping?['tmdbId'] as int?;
    if (id == null) return null;
    final movie = await isMovie;
    final mappedFormat = mapping?['format']?.toString().toUpperCase();
    if (mappedFormat != null && movie != (mappedFormat == 'MOVIE')) return null;
    if (movie) return _target(id, true);

    final entry = (mapping?['episodes'] as Map?)?['$episode'] as Map?;
    if (entry == null) return null;
    final match = await _mappings._tmdbEpisode(
      id,
      entry['season'] as int?,
      entry,
    );
    if (match == null) return null;
    return _target(
      id,
      false,
      match.season,
      match.episode,
      entry['absolute'] as int?,
    );
  }

  Future<NuvioAnimeMapping?> _nuvioMapping() async {
    if (!isAnime) return null;
    final target = await tmdb;
    if (target == null) return null;
    final mapping = await _mapping;
    return (
      target: target,
      aniListId: media.id,
      malId: mapping?['malId'] as int?,
      imdbId: mapping?['imdbId'] as String?,
      episode: target.type == 'movie' ? 1 : episode,
    );
  }

  Future<ExtensionMedia> _cloudstreamTarget() async {
    if (!isAnime) return _target(media.id, await isMovie);
    final mapping = await _mapping;
    final id = mapping?['tmdbId'] as int?;
    if (id != null) {
      final movie = mapping?['format']?.toString().toUpperCase() == 'MOVIE';
      final entry = (mapping?['episodes'] as Map?)?['$episode'] as Map?;
      return _target(
        id,
        movie,
        entry?['season'] as int?,
        entry?['episode'] as int?,
        entry?['absolute'] as int?,
      );
    }
    return (
      id: 'anilist:${media.id}',
      type: 'anime',
      season: season,
      episode: episode,
      tmdbId: null,
      absoluteEpisode: episode,
    );
  }

  ExtensionMedia _target(
    int id,
    bool movie, [
    int? mappedSeason,
    int? mappedEpisode,
    int? absolute,
  ]) => (
    id: '$id',
    type: movie ? 'movie' : 'tv',
    season: movie ? null : mappedSeason ?? season,
    episode: movie ? null : mappedEpisode ?? episode,
    tmdbId: '$id',
    absoluteEpisode: absolute,
  );
}

int? _integer(Object? value) => int.tryParse('$value');

String? _date(Object? value) {
  final date = value is String ? value.split('T').first : null;
  return date != null && DateTime.tryParse(date) != null ? date : null;
}

String? _title(Object? value) {
  if (value is! String) return null;
  final title = value.toLowerCase().replaceAll(
    RegExp(r'[^\p{L}\p{N}]', unicode: true),
    '',
  );
  return title.isEmpty || RegExp(r'^episode\d+$').hasMatch(title)
      ? null
      : title;
}
