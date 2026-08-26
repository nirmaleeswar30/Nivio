// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'season_info.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_$EpisodeDataImpl _$$EpisodeDataImplFromJson(Map<String, dynamic> json) =>
    _$EpisodeDataImpl(
      episodeNumber: (json['episode_number'] as num).toInt(),
      episodeName: json['name'] as String?,
      overview: json['overview'] as String?,
      stillPath: json['still_path'] as String?,
      voteAverage: (json['vote_average'] as num?)?.toDouble(),
      runtime: (json['runtime'] as num?)?.toInt(),
      airDate: json['air_date'] as String?,
    );

Map<String, dynamic> _$$EpisodeDataImplToJson(_$EpisodeDataImpl instance) =>
    <String, dynamic>{
      'episode_number': instance.episodeNumber,
      'name': instance.episodeName,
      'overview': instance.overview,
      'still_path': instance.stillPath,
      'vote_average': instance.voteAverage,
      'runtime': instance.runtime,
      'air_date': instance.airDate,
    };

_$SeasonDataImpl _$$SeasonDataImplFromJson(Map<String, dynamic> json) =>
    _$SeasonDataImpl(
      episodes: (json['episodes'] as List<dynamic>)
          .map((e) => EpisodeData.fromJson(e as Map<String, dynamic>))
          .toList(),
    );

Map<String, dynamic> _$$SeasonDataImplToJson(_$SeasonDataImpl instance) =>
    <String, dynamic>{
      'episodes': instance.episodes,
    };

_$SeasonInfoImpl _$$SeasonInfoImplFromJson(Map<String, dynamic> json) =>
    _$SeasonInfoImpl(
      episodeCount: (json['episode_count'] as num).toInt(),
      id: (json['id'] as num).toInt(),
      name: json['name'] as String,
      seasonNumber: (json['season_number'] as num).toInt(),
      airDate: json['air_date'] as String?,
      posterPath: json['poster_path'] as String?,
    );

Map<String, dynamic> _$$SeasonInfoImplToJson(_$SeasonInfoImpl instance) =>
    <String, dynamic>{
      'episode_count': instance.episodeCount,
      'id': instance.id,
      'name': instance.name,
      'season_number': instance.seasonNumber,
      'air_date': instance.airDate,
      'poster_path': instance.posterPath,
    };

_$SeriesInfoImpl _$$SeriesInfoImplFromJson(Map<String, dynamic> json) =>
    _$SeriesInfoImpl(
      numberOfSeasons: (json['number_of_seasons'] as num).toInt(),
      seasons: (json['seasons'] as List<dynamic>)
          .map((e) => SeasonInfo.fromJson(e as Map<String, dynamic>))
          .toList(),
    );

Map<String, dynamic> _$$SeriesInfoImplToJson(_$SeriesInfoImpl instance) =>
    <String, dynamic>{
      'number_of_seasons': instance.numberOfSeasons,
      'seasons': instance.seasons,
    };
