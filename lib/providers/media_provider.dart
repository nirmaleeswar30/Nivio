import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nivio/models/search_result.dart';
import 'package:nivio/models/season_info.dart';
import 'package:nivio/providers/service_providers.dart';

// Selected media state
final selectedMediaProvider = StateProvider<SearchResult?>((ref) => null);

// Selected season state
final selectedSeasonProvider = StateProvider<int>((ref) => 1);

// Selected episode state
final selectedEpisodeProvider = StateProvider<int>((ref) => 1);

// Selected quality state
final selectedQualityProvider = StateProvider<String?>((ref) => null);

// Series info provider (for TV shows)
final seriesInfoProvider = FutureProvider.family<SeriesInfo, int>((
  ref,
  showId,
) async {
  final selectedMedia = ref.watch(selectedMediaProvider);
  final isAnime = selectedMedia?.mediaType == 'anime';

  if (isAnime) {
    final anilist = ref.watch(aniListServiceProvider);
    int targetId = showId;
    if (selectedMedia?.mediaType == 'tv') {
      final title = selectedMedia?.title ?? selectedMedia?.name ?? '';
      final year = selectedMedia?.firstAirDate?.split('-').first;
      final result = await anilist.getAniListIdFromTMDB(title: title, year: year, tmdbId: targetId);
      if (result != null) {
        targetId = result.id;
      }
    }
    return await anilist.getAnimeSeriesInfo(targetId);
  }

  final tmdb = ref.watch(tmdbServiceProvider);
  return await tmdb.getSeriesInfo(showId);
});

// Season data provider (episodes for a specific season)
final seasonDataProvider =
    FutureProvider.family<SeasonData, ({int showId, int seasonNumber})>((
      ref,
      params,
    ) async {
      final selectedMedia = ref.watch(selectedMediaProvider);
      final isAnime = selectedMedia?.mediaType == 'anime';

      if (isAnime) {
        final anilist = ref.watch(aniListServiceProvider);
        int targetId = params.showId;
        if (selectedMedia?.mediaType == 'tv') {
          final title = selectedMedia?.title ?? selectedMedia?.name ?? '';
          final year = selectedMedia?.firstAirDate?.split('-').first;
          final result = await anilist.getAniListIdFromTMDB(title: title, year: year, tmdbId: targetId);
          if (result != null) {
            targetId = result.id;
          }
        }
        return await anilist.getAnimeSeasonData(targetId);
      }

      final tmdb = ref.watch(tmdbServiceProvider);
      return await tmdb.getSeasonInfo(params.showId, params.seasonNumber);
    });
