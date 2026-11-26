import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:nivio/providers/service_providers.dart';
import 'package:nivio/services/parental_guide_service.dart';

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
        final title = media.title;
        if (title == null || title.trim().isEmpty) return const [];
        final matches = await tmdb.search(title);
        final format = media.animeFormat?.toUpperCase();
        final match = matches.results.where((candidate) {
          if (format == 'MOVIE' && candidate.mediaType != 'movie') return false;
          if (format == 'TV' && candidate.mediaType != 'tv') return false;
          final year = (candidate.releaseDate ?? candidate.firstAirDate)
              ?.split('-')
              .first;
          return _normalize(candidate.title ?? candidate.name ?? '') ==
                  _normalize(title) &&
              (media.year == null || media.year == year);
        }).singleOrNull;
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
