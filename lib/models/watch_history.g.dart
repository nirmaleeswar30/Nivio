// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'watch_history.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_$WatchHistoryImpl _$$WatchHistoryImplFromJson(Map<String, dynamic> json) =>
    _$WatchHistoryImpl(
      id: json['id'] as String,
      tmdbId: (json['tmdbId'] as num).toInt(),
      mediaType: json['mediaType'] as String,
      title: json['title'] as String,
      posterPath: json['posterPath'] as String?,
      currentSeason: (json['currentSeason'] as num).toInt(),
      currentEpisode: (json['currentEpisode'] as num).toInt(),
      totalSeasons: (json['totalSeasons'] as num).toInt(),
      totalEpisodes: (json['totalEpisodes'] as num?)?.toInt(),
      lastPositionSeconds: (json['lastPositionSeconds'] as num).toInt(),
      totalDurationSeconds: (json['totalDurationSeconds'] as num).toInt(),
      progressPercent: (json['progressPercent'] as num).toDouble(),
      lastWatchedAt: _dateTimeFromJson(json['lastWatchedAt']),
      createdAt: _dateTimeFromJson(json['createdAt']),
      isCompleted: json['isCompleted'] as bool,
      episodes: json['episodes'] == null
          ? const {}
          : _episodesFromJson(json['episodes']),
    );

Map<String, dynamic> _$$WatchHistoryImplToJson(_$WatchHistoryImpl instance) =>
    <String, dynamic>{
      'id': instance.id,
      'tmdbId': instance.tmdbId,
      'mediaType': instance.mediaType,
      'title': instance.title,
      'posterPath': instance.posterPath,
      'currentSeason': instance.currentSeason,
      'currentEpisode': instance.currentEpisode,
      'totalSeasons': instance.totalSeasons,
      'totalEpisodes': instance.totalEpisodes,
      'lastPositionSeconds': instance.lastPositionSeconds,
      'totalDurationSeconds': instance.totalDurationSeconds,
      'progressPercent': instance.progressPercent,
      'lastWatchedAt': _dateTimeToJson(instance.lastWatchedAt),
      'createdAt': _dateTimeToJson(instance.createdAt),
      'isCompleted': instance.isCompleted,
      'episodes': _episodesToJson(instance.episodes),
    };

_$EpisodeProgressImpl _$$EpisodeProgressImplFromJson(
        Map<String, dynamic> json) =>
    _$EpisodeProgressImpl(
      season: (json['season'] as num).toInt(),
      episode: (json['episode'] as num).toInt(),
      lastPositionSeconds: (json['lastPositionSeconds'] as num).toInt(),
      totalDurationSeconds: (json['totalDurationSeconds'] as num).toInt(),
      isCompleted: json['isCompleted'] as bool,
      watchedAt: _dateTimeFromJson(json['watchedAt']),
    );

Map<String, dynamic> _$$EpisodeProgressImplToJson(
        _$EpisodeProgressImpl instance) =>
    <String, dynamic>{
      'season': instance.season,
      'episode': instance.episode,
      'lastPositionSeconds': instance.lastPositionSeconds,
      'totalDurationSeconds': instance.totalDurationSeconds,
      'isCompleted': instance.isCompleted,
      'watchedAt': _dateTimeToJson(instance.watchedAt),
    };
