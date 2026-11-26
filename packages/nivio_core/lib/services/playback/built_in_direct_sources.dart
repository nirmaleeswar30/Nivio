import 'package:nivio/models/search_result.dart';
import 'package:nivio/services/hls_proxy_service.dart';
import 'package:nivio/services/scrapers/castle_tv_source.dart';
import 'package:nivio/services/scrapers/cine_tv_source.dart';
import 'package:nivio/services/scrapers/desiflix/desiflix_scraper.dart';
import 'package:nivio/services/scrapers/hub_download_sources.dart';
import 'package:nivio/services/scrapers/movie_box_source.dart';
import 'package:nivio/services/scrapers/net_mirror_source.dart';
import 'package:nivio/services/tmdb_service.dart';

import 'stream_choice.dart';

/// Built-in Dart scrapers that return complete sets of stream variants.
abstract final class BuiltInDirectSources {
  static const _namesById = {
    '4khdhub': '4KHDHub',
    'desiflix': 'DesiFlix',
    'moviesdrive': 'MoviesDrive',
    'castletv': 'CastleTV',
    'moviebox': 'MovieBox',
    'movieboxproviderin': 'MovieBox IN',
    'cinetvprovider': 'CineTv',
  };

  static final names = List<String>.unmodifiable([
    ..._namesById.values,
    ...NetMirrorSource.names,
  ]);

  static Future<List<StreamChoice>> resolve(
    String name,
    SearchResult media, {
    required TmdbService tmdb,
    required int season,
    required int episode,
  }) async {
    if (media.mediaType != 'movie' && media.mediaType != 'tv') return [];
    final results = await _scrape(name, media, tmdb, season, episode);
    return [
      for (final (index, result) in results.indexed)
        if (StreamChoice.fromScraper(
              name,
              result,
              index,
              playbackUrl: name == 'CineTv' ? _cinePlaybackUrl : null,
              downloadUrl: name == 'CineTv' ? CineTvSource.downloadUrl : null,
            )
            case final choice?)
          choice,
    ];
  }

  static String _cinePlaybackUrl(Uri uri) =>
      HlsProxyService.instance.registerMediaRedirect(
        () => CineTvSource.signPlaybackUrl(uri),
      ) ??
      CineTvSource.signPlaybackUrl(uri).toString();

  static Future<List<Map<String, dynamic>>> _scrape(
    String name,
    SearchResult media,
    TmdbService tmdb,
    int season,
    int episode,
  ) async {
    const timeout = Duration(seconds: 60);
    switch (name) {
      case 'CastleTV':
        final scraper = CastleTvSource();
        try {
          return await scraper
              .resolve(media, season: season, episode: episode)
              .timeout(timeout);
        } finally {
          scraper.close();
        }
      case 'MovieBox':
      case 'MovieBox IN':
        final scraper = MovieBoxSource(india: name == 'MovieBox IN');
        try {
          return await scraper
              .resolve(media, season: season, episode: episode)
              .timeout(timeout);
        } finally {
          scraper.close();
        }
      case 'CineTv':
        final scraper = CineTvSource();
        try {
          return await scraper
              .resolve(media, season: season, episode: episode)
              .timeout(timeout);
        } finally {
          scraper.close();
        }
      case 'DesiFlix':
        return DesiFlixScraper(
          tmdbService: tmdb,
        ).resolve(media, season: season, episode: episode).timeout(timeout);
      case '4KHDHub':
      case 'MoviesDrive':
        final scraper = HubDownloadSources(tmdb: tmdb);
        try {
          final results = name == '4KHDHub'
              ? scraper.fetch4KHDHub(media, season: season, episode: episode)
              : scraper.fetchMoviesDrive(
                  media,
                  season: season,
                  episode: episode,
                );
          return await results.timeout(timeout);
        } finally {
          scraper.dispose();
        }
      case final provider when NetMirrorSource.names.contains(provider):
        final scraper = NetMirrorSource();
        try {
          return await scraper
              .resolve(provider, media, season: season, episode: episode)
              .timeout(timeout);
        } finally {
          scraper.close();
        }
      default:
        return [];
    }
  }

  /// Keeps existing priorities for sources previously added from these repos.
  static String? legacySourceId(String id) {
    if (id.startsWith('builtin:')) return id;
    final separator = id.lastIndexOf('#');
    if (separator < 0) return null;
    final name = _namesById[id.substring(separator + 1).toLowerCase()];
    final url = Uri.tryParse(id.substring(0, separator));
    if (name == null ||
        url == null ||
        url.host != 'raw.githubusercontent.com') {
      return null;
    }
    final path = url.path.toLowerCase();
    if (!path.endsWith('/manifest.json')) return null;
    final knownRepo =
        path.startsWith('/yoruix/nuvio-providers/') ||
        path.startsWith('/d3adlyrocket/all-in-one-nuvio/') ||
        path.startsWith('/nuvioplugin/all-in-one-nuvio/');
    return knownRepo ? 'builtin:$name' : null;
  }
}
