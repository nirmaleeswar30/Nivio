import 'package:freezed_annotation/freezed_annotation.dart';

part 'watch_history.freezed.dart';
part 'watch_history.g.dart';

@freezed
class WatchHistory with _$WatchHistory {
  const factory WatchHistory({
    required String id,
    required int tmdbId,
    required String mediaType,
    required String title,
    String? posterPath,
    required int currentSeason,
    required int currentEpisode,
    required int totalSeasons,
    int? totalEpisodes,
    required int lastPositionSeconds,
    required int totalDurationSeconds,
    required double progressPercent,
    @JsonKey(fromJson: _dateTimeFromJson, toJson: _dateTimeToJson) required DateTime lastWatchedAt,
    @JsonKey(fromJson: _dateTimeFromJson, toJson: _dateTimeToJson) required DateTime createdAt,
    required bool isCompleted,
    @JsonKey(fromJson: _episodesFromJson, toJson: _episodesToJson) @Default({}) Map<String, EpisodeProgress> episodes,
  }) = _WatchHistory;

  factory WatchHistory.fromJson(Map<String, dynamic> json) =>
      _$WatchHistoryFromJson(json);
}

@freezed
class EpisodeProgress with _$EpisodeProgress {
  const factory EpisodeProgress({
    required int season,
    required int episode,
    required int lastPositionSeconds,
    required int totalDurationSeconds,
    required bool isCompleted,
    @JsonKey(fromJson: _dateTimeFromJson, toJson: _dateTimeToJson) required DateTime watchedAt,
  }) = _EpisodeProgress;

  factory EpisodeProgress.fromJson(Map<String, dynamic> json) =>
      _$EpisodeProgressFromJson(json);
}

// Firestore timestamp helpers
DateTime _dateTimeFromJson(dynamic timestamp) {
  if (timestamp is int) {
    return DateTime.fromMillisecondsSinceEpoch(timestamp);
  } else if (timestamp is Map) {
    // Firestore Timestamp format
    return DateTime.fromMillisecondsSinceEpoch(
      (timestamp['_seconds'] as int) * 1000 +
          (timestamp['_nanoseconds'] as int) ~/ 1000000,
    );
  }
  return DateTime.parse(timestamp.toString());
}

int _dateTimeToJson(DateTime dateTime) {
  return dateTime.millisecondsSinceEpoch;
}

// Episodes map converters
Map<String, EpisodeProgress> _episodesFromJson(dynamic json) {
  if (json == null || json is! Map) return {};
  
  final result = <String, EpisodeProgress>{};
  (json as Map).forEach((key, value) {
    if (value is Map<String, dynamic>) {
      result[key.toString()] = EpisodeProgress.fromJson(value);
    }
  });
  return result;
}

Map<String, dynamic> _episodesToJson(Map<String, EpisodeProgress> episodes) {
  final result = <String, dynamic>{};
  episodes.forEach((key, value) {
    result[key] = value.toJson();
  });
  return result;
}
