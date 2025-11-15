import 'package:freezed_annotation/freezed_annotation.dart';

part 'season_info.freezed.dart';
part 'season_info.g.dart';

@freezed
class EpisodeData with _$EpisodeData {
  const factory EpisodeData({
    @JsonKey(name: 'episode_number') required int episodeNumber,
    @JsonKey(name: 'name') String? episodeName,
    String? overview,
    @JsonKey(name: 'still_path') String? stillPath,
    @JsonKey(name: 'vote_average') double? voteAverage,
    @JsonKey(name: 'runtime') int? runtime,
    @JsonKey(name: 'air_date') String? airDate,
  }) = _EpisodeData;

  factory EpisodeData.fromJson(Map<String, dynamic> json) =>
      _$EpisodeDataFromJson(json);
}

@freezed
class SeasonData with _$SeasonData {
  const factory SeasonData({
    required List<EpisodeData> episodes,
  }) = _SeasonData;

  factory SeasonData.fromJson(Map<String, dynamic> json) =>
      _$SeasonDataFromJson(json);
}

@freezed
class SeasonInfo with _$SeasonInfo {
  const factory SeasonInfo({
    @JsonKey(name: 'episode_count') required int episodeCount,
    required int id,
    required String name,
    @JsonKey(name: 'season_number') required int seasonNumber,
    @JsonKey(name: 'air_date') String? airDate,
    @JsonKey(name: 'poster_path') String? posterPath,
  }) = _SeasonInfo;

  factory SeasonInfo.fromJson(Map<String, dynamic> json) =>
      _$SeasonInfoFromJson(json);
}

@freezed
class SeriesInfo with _$SeriesInfo {
  const factory SeriesInfo({
    @JsonKey(name: 'number_of_seasons') required int numberOfSeasons,
    required List<SeasonInfo> seasons,
  }) = _SeriesInfo;

  factory SeriesInfo.fromJson(Map<String, dynamic> json) =>
      _$SeriesInfoFromJson(json);
}
