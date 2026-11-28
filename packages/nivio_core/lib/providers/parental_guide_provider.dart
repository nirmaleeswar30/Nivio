import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:nivio/providers/service_providers.dart';
import 'package:nivio/models/search_result.dart';
import 'package:nivio/services/parental_guide_service.dart';
import 'package:nivio/services/tmdb_service.dart';

typedef ParentalGuideMedia = ({
  int id,
  String type,
  String? title,
  String? year,
  String? animeFormat,
});

final _parentalGuideServiceProvider = Provider((ref) {
  final client = http.Client();
  ref.onDispose(client.close);
  return ParentalGuideService(client);
});

final parentalGuideProvider = FutureProvider.autoDispose
    .family<List<ParentalWarning>, ParentalGuideMedia>((ref, media) async {
      final tmdb = ref.watch(tmdbServiceProvider);
      final guide = ref.watch(_parentalGuideServiceProvider);
      var id = media.id;
      var type = media.type;
      if (type == 'anime') {
        final match = await _matchAnimeOnTmdb(tmdb, media);
        if (match == null) return const [];
        id = match.id;
        type = match.mediaType;
      }
      if (type != 'movie' && type != 'tv') return const [];
      final imdbId = await tmdb.getImdbId(tmdbId: id, isMovie: type == 'movie');
      return imdbId == null ? const [] : guide.fetch(imdbId);
    });

final _punctuation = RegExp(r'[^\p{L}\p{N}]+', unicode: true);
String _normalize(String title) =>
    title.toLowerCase().replaceAll(_punctuation, '');

/// AniList lists each season on its own ("Attack on Titan Season 2", 2017)
/// while TMDB and IMDb, where the parental guide lives, have one show
/// ("Attack on Titan", 2013). Season and part markers are dropped so the
/// show is found.
final _seasonMarker = RegExp(
  r'\s*(?:[:\-–]\s*)?\b(?:(?:the\s+)?final\s+season|season\s*\d+|\d+(?:st|nd|rd|th)\s+season|part\s*\d+|cour\s*\d+|s\d+)\b.*$',
  caseSensitive: false,
);

Future<SearchResult?> _matchAnimeOnTmdb(
  TmdbService tmdb,
  ParentalGuideMedia media,
) async {
  final title = media.title?.trim();
  if (title == null || title.isEmpty) return null;
  final format = media.animeFormat?.toUpperCase();
  final isMovie = format == 'MOVIE';
  final base = title.replaceFirst(_seasonMarker, '').trim();
  final beforeColon = base.split(':').first.trim();
  final queries = {
    if (base.isNotEmpty) base,
    if (beforeColon.isNotEmpty && beforeColon.length >= 3) beforeColon,
  };

  SearchResult? best;
  var bestScore = 0;
  for (final query in queries) {
    final wanted = _normalize(query);
    if (wanted.isEmpty) continue;
    final matches = await tmdb.searchTitlesIncludingAnime(query);
    for (final candidate in matches) {
      if (candidate.mediaType != 'movie' && candidate.mediaType != 'tv') continue;
      if (isMovie && candidate.mediaType != 'movie') continue;
      if (!isMovie && format != null && candidate.mediaType != 'tv') continue;
      final name = _normalize(candidate.title ?? candidate.name ?? '');
      if (name.isEmpty) continue;
      var score = 0;
      if (name == wanted) {
        score += 4;
      } else if (name.startsWith(wanted) || wanted.startsWith(name)) {
        score += 2;
      } else {
        continue;
      }
      if (const {'ja', 'ko', 'zh', 'cn'}.contains(candidate.originalLanguage)) {
        score += 2;
      }
      final year = (candidate.releaseDate ?? candidate.firstAirDate)
          ?.split('-')
          .first;
      if (media.year != null && year == media.year) score += 1;
      // Films are remade under the same name; only a matching year is safe.
      if (isMovie && media.year != null && year != null && year != media.year) {
        continue;
      }
      if (score > bestScore) {
        bestScore = score;
        best = candidate;
      }
    }
    if (bestScore >= 6) break;
  }
  return bestScore >= 4 ? best : null;
}
