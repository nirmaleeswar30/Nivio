import 'torrent_models.dart';

/// Context for searching movie and TV show torrents via Stremio providers
/// (Torrentio).
class MediaTorrentQuery {
  MediaTorrentQuery({
    required this.title,
    this.year,
    this.imdbId,
    this.tmdbId,
    this.season,
    this.episode,
    required this.isMovie,
    this.resolution = '1080',
    this.isManual = false,
    this.rawQuery,
  });

  /// Primary media title (e.g. "The Shawshank Redemption", "Breaking Bad").
  final String title;

  /// Release year (e.g. 1994, 2022) to avoid matching remakes or same-named titles.
  final int? year;

  /// IMDb identifier (e.g. "tt0111161", "tt0944947").
  /// Torrentio indexes directly by IMDb ID.
  final String? imdbId;

  /// TMDB numeric identifier.
  final int? tmdbId;

  /// Season number (for TV series, 1-indexed). Null for movies.
  final int? season;

  /// Episode number (for TV series, 1-indexed). Null for movies.
  final int? episode;

  /// Whether this query targets a movie (`true`) or a TV series episode (`false`).
  final bool isMovie;

  /// Preferred resolution string: '2160', '1080', '720', etc.
  final String resolution;

  /// Whether this was manually entered by the user in the search box.
  final bool isManual;

  /// Raw search query override if the user typed a manual text search.
  final String? rawQuery;

  int? get preferredResolution => int.tryParse(resolution);

  /// Builds the Stremio stream URL path segment (e.g. `movie/tt0111161.json` or `series/tt0944947:1:5.json`).
  String? get stremioPathSegment {
    if (imdbId == null || imdbId!.isEmpty) return null;
    if (isMovie) {
      return 'movie/$imdbId.json';
    } else {
      final s = season ?? 1;
      final e = episode ?? 1;
      return 'series/$imdbId:$s:$e.json';
    }
  }
}

/// Interface for movie and TV show torrent providers (Torrentio).
abstract class MediaTorrentSource {
  /// Unique source id, e.g. 'torrentio'.
  String get name;

  /// Human-friendly display label, e.g. 'Torrentio'.
  String get displayName;

  /// Searches for torrents matching the [query].
  /// Defensive: returns empty list on network or parse failure, never throws.
  Future<List<TorrentResult>> searchMedia(MediaTorrentQuery query);
}
