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
final seriesInfoProvider = FutureProvider.family<SeriesInfo, int>((ref, showId) async {
  final tmdb = ref.watch(tmdbServiceProvider);
  return await tmdb.getSeriesInfo(showId);
});

// Season data provider (episodes for a specific season)
final seasonDataProvider = FutureProvider.family<SeasonData, ({int showId, int seasonNumber})>((ref, params) async {
  final tmdb = ref.watch(tmdbServiceProvider);
  return await tmdb.getSeasonInfo(params.showId, params.seasonNumber);
});
