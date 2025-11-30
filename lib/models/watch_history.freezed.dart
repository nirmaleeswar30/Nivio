// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'watch_history.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

T _$identity<T>(T value) => value;

final _privateConstructorUsedError = UnsupportedError(
    'It seems like you constructed your class using `MyClass._()`. This constructor is only meant to be used by freezed and you are not supposed to need it nor use it.\nPlease check the documentation here for more information: https://github.com/rrousselGit/freezed#adding-getters-and-methods-to-our-models');

WatchHistory _$WatchHistoryFromJson(Map<String, dynamic> json) {
  return _WatchHistory.fromJson(json);
}

/// @nodoc
mixin _$WatchHistory {
  String get id => throw _privateConstructorUsedError;
  int get tmdbId => throw _privateConstructorUsedError;
  String get mediaType => throw _privateConstructorUsedError;
  String get title => throw _privateConstructorUsedError;
  String? get posterPath => throw _privateConstructorUsedError;
  int get currentSeason => throw _privateConstructorUsedError;
  int get currentEpisode => throw _privateConstructorUsedError;
  int get totalSeasons => throw _privateConstructorUsedError;
  int? get totalEpisodes => throw _privateConstructorUsedError;
  int get lastPositionSeconds => throw _privateConstructorUsedError;
  int get totalDurationSeconds => throw _privateConstructorUsedError;
  double get progressPercent => throw _privateConstructorUsedError;
  @JsonKey(fromJson: _dateTimeFromJson, toJson: _dateTimeToJson)
  DateTime get lastWatchedAt => throw _privateConstructorUsedError;
  @JsonKey(fromJson: _dateTimeFromJson, toJson: _dateTimeToJson)
  DateTime get createdAt => throw _privateConstructorUsedError;
  bool get isCompleted => throw _privateConstructorUsedError;
  @JsonKey(fromJson: _episodesFromJson, toJson: _episodesToJson)
  Map<String, EpisodeProgress> get episodes =>
      throw _privateConstructorUsedError;

  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;
  @JsonKey(ignore: true)
  $WatchHistoryCopyWith<WatchHistory> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $WatchHistoryCopyWith<$Res> {
  factory $WatchHistoryCopyWith(
          WatchHistory value, $Res Function(WatchHistory) then) =
      _$WatchHistoryCopyWithImpl<$Res, WatchHistory>;
  @useResult
  $Res call(
      {String id,
      int tmdbId,
      String mediaType,
      String title,
      String? posterPath,
      int currentSeason,
      int currentEpisode,
      int totalSeasons,
      int? totalEpisodes,
      int lastPositionSeconds,
      int totalDurationSeconds,
      double progressPercent,
      @JsonKey(fromJson: _dateTimeFromJson, toJson: _dateTimeToJson)
      DateTime lastWatchedAt,
      @JsonKey(fromJson: _dateTimeFromJson, toJson: _dateTimeToJson)
      DateTime createdAt,
      bool isCompleted,
      @JsonKey(fromJson: _episodesFromJson, toJson: _episodesToJson)
      Map<String, EpisodeProgress> episodes});
}

/// @nodoc
class _$WatchHistoryCopyWithImpl<$Res, $Val extends WatchHistory>
    implements $WatchHistoryCopyWith<$Res> {
  _$WatchHistoryCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? id = null,
    Object? tmdbId = null,
    Object? mediaType = null,
    Object? title = null,
    Object? posterPath = freezed,
    Object? currentSeason = null,
    Object? currentEpisode = null,
    Object? totalSeasons = null,
    Object? totalEpisodes = freezed,
    Object? lastPositionSeconds = null,
    Object? totalDurationSeconds = null,
    Object? progressPercent = null,
    Object? lastWatchedAt = null,
    Object? createdAt = null,
    Object? isCompleted = null,
    Object? episodes = null,
  }) {
    return _then(_value.copyWith(
      id: null == id
          ? _value.id
          : id // ignore: cast_nullable_to_non_nullable
              as String,
      tmdbId: null == tmdbId
          ? _value.tmdbId
          : tmdbId // ignore: cast_nullable_to_non_nullable
              as int,
      mediaType: null == mediaType
          ? _value.mediaType
          : mediaType // ignore: cast_nullable_to_non_nullable
              as String,
      title: null == title
          ? _value.title
          : title // ignore: cast_nullable_to_non_nullable
              as String,
      posterPath: freezed == posterPath
          ? _value.posterPath
          : posterPath // ignore: cast_nullable_to_non_nullable
              as String?,
      currentSeason: null == currentSeason
          ? _value.currentSeason
          : currentSeason // ignore: cast_nullable_to_non_nullable
              as int,
      currentEpisode: null == currentEpisode
          ? _value.currentEpisode
          : currentEpisode // ignore: cast_nullable_to_non_nullable
              as int,
      totalSeasons: null == totalSeasons
          ? _value.totalSeasons
          : totalSeasons // ignore: cast_nullable_to_non_nullable
              as int,
      totalEpisodes: freezed == totalEpisodes
          ? _value.totalEpisodes
          : totalEpisodes // ignore: cast_nullable_to_non_nullable
              as int?,
      lastPositionSeconds: null == lastPositionSeconds
          ? _value.lastPositionSeconds
          : lastPositionSeconds // ignore: cast_nullable_to_non_nullable
              as int,
      totalDurationSeconds: null == totalDurationSeconds
          ? _value.totalDurationSeconds
          : totalDurationSeconds // ignore: cast_nullable_to_non_nullable
              as int,
      progressPercent: null == progressPercent
          ? _value.progressPercent
          : progressPercent // ignore: cast_nullable_to_non_nullable
              as double,
      lastWatchedAt: null == lastWatchedAt
          ? _value.lastWatchedAt
          : lastWatchedAt // ignore: cast_nullable_to_non_nullable
              as DateTime,
      createdAt: null == createdAt
          ? _value.createdAt
          : createdAt // ignore: cast_nullable_to_non_nullable
              as DateTime,
      isCompleted: null == isCompleted
          ? _value.isCompleted
          : isCompleted // ignore: cast_nullable_to_non_nullable
              as bool,
      episodes: null == episodes
          ? _value.episodes
          : episodes // ignore: cast_nullable_to_non_nullable
              as Map<String, EpisodeProgress>,
    ) as $Val);
  }
}

/// @nodoc
abstract class _$$WatchHistoryImplCopyWith<$Res>
    implements $WatchHistoryCopyWith<$Res> {
  factory _$$WatchHistoryImplCopyWith(
          _$WatchHistoryImpl value, $Res Function(_$WatchHistoryImpl) then) =
      __$$WatchHistoryImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call(
      {String id,
      int tmdbId,
      String mediaType,
      String title,
      String? posterPath,
      int currentSeason,
      int currentEpisode,
      int totalSeasons,
      int? totalEpisodes,
      int lastPositionSeconds,
      int totalDurationSeconds,
      double progressPercent,
      @JsonKey(fromJson: _dateTimeFromJson, toJson: _dateTimeToJson)
      DateTime lastWatchedAt,
      @JsonKey(fromJson: _dateTimeFromJson, toJson: _dateTimeToJson)
      DateTime createdAt,
      bool isCompleted,
      @JsonKey(fromJson: _episodesFromJson, toJson: _episodesToJson)
      Map<String, EpisodeProgress> episodes});
}

/// @nodoc
class __$$WatchHistoryImplCopyWithImpl<$Res>
    extends _$WatchHistoryCopyWithImpl<$Res, _$WatchHistoryImpl>
    implements _$$WatchHistoryImplCopyWith<$Res> {
  __$$WatchHistoryImplCopyWithImpl(
      _$WatchHistoryImpl _value, $Res Function(_$WatchHistoryImpl) _then)
      : super(_value, _then);

  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? id = null,
    Object? tmdbId = null,
    Object? mediaType = null,
    Object? title = null,
    Object? posterPath = freezed,
    Object? currentSeason = null,
    Object? currentEpisode = null,
    Object? totalSeasons = null,
    Object? totalEpisodes = freezed,
    Object? lastPositionSeconds = null,
    Object? totalDurationSeconds = null,
    Object? progressPercent = null,
    Object? lastWatchedAt = null,
    Object? createdAt = null,
    Object? isCompleted = null,
    Object? episodes = null,
  }) {
    return _then(_$WatchHistoryImpl(
      id: null == id
          ? _value.id
          : id // ignore: cast_nullable_to_non_nullable
              as String,
      tmdbId: null == tmdbId
          ? _value.tmdbId
          : tmdbId // ignore: cast_nullable_to_non_nullable
              as int,
      mediaType: null == mediaType
          ? _value.mediaType
          : mediaType // ignore: cast_nullable_to_non_nullable
              as String,
      title: null == title
          ? _value.title
          : title // ignore: cast_nullable_to_non_nullable
              as String,
      posterPath: freezed == posterPath
          ? _value.posterPath
          : posterPath // ignore: cast_nullable_to_non_nullable
              as String?,
      currentSeason: null == currentSeason
          ? _value.currentSeason
          : currentSeason // ignore: cast_nullable_to_non_nullable
              as int,
      currentEpisode: null == currentEpisode
          ? _value.currentEpisode
          : currentEpisode // ignore: cast_nullable_to_non_nullable
              as int,
      totalSeasons: null == totalSeasons
          ? _value.totalSeasons
          : totalSeasons // ignore: cast_nullable_to_non_nullable
              as int,
      totalEpisodes: freezed == totalEpisodes
          ? _value.totalEpisodes
          : totalEpisodes // ignore: cast_nullable_to_non_nullable
              as int?,
      lastPositionSeconds: null == lastPositionSeconds
          ? _value.lastPositionSeconds
          : lastPositionSeconds // ignore: cast_nullable_to_non_nullable
              as int,
      totalDurationSeconds: null == totalDurationSeconds
          ? _value.totalDurationSeconds
          : totalDurationSeconds // ignore: cast_nullable_to_non_nullable
              as int,
      progressPercent: null == progressPercent
          ? _value.progressPercent
          : progressPercent // ignore: cast_nullable_to_non_nullable
              as double,
      lastWatchedAt: null == lastWatchedAt
          ? _value.lastWatchedAt
          : lastWatchedAt // ignore: cast_nullable_to_non_nullable
              as DateTime,
      createdAt: null == createdAt
          ? _value.createdAt
          : createdAt // ignore: cast_nullable_to_non_nullable
              as DateTime,
      isCompleted: null == isCompleted
          ? _value.isCompleted
          : isCompleted // ignore: cast_nullable_to_non_nullable
              as bool,
      episodes: null == episodes
          ? _value._episodes
          : episodes // ignore: cast_nullable_to_non_nullable
              as Map<String, EpisodeProgress>,
    ));
  }
}

/// @nodoc
@JsonSerializable()
class _$WatchHistoryImpl implements _WatchHistory {
  const _$WatchHistoryImpl(
      {required this.id,
      required this.tmdbId,
      required this.mediaType,
      required this.title,
      this.posterPath,
      required this.currentSeason,
      required this.currentEpisode,
      required this.totalSeasons,
      this.totalEpisodes,
      required this.lastPositionSeconds,
      required this.totalDurationSeconds,
      required this.progressPercent,
      @JsonKey(fromJson: _dateTimeFromJson, toJson: _dateTimeToJson)
      required this.lastWatchedAt,
      @JsonKey(fromJson: _dateTimeFromJson, toJson: _dateTimeToJson)
      required this.createdAt,
      required this.isCompleted,
      @JsonKey(fromJson: _episodesFromJson, toJson: _episodesToJson)
      final Map<String, EpisodeProgress> episodes = const {}})
      : _episodes = episodes;

  factory _$WatchHistoryImpl.fromJson(Map<String, dynamic> json) =>
      _$$WatchHistoryImplFromJson(json);

  @override
  final String id;
  @override
  final int tmdbId;
  @override
  final String mediaType;
  @override
  final String title;
  @override
  final String? posterPath;
  @override
  final int currentSeason;
  @override
  final int currentEpisode;
  @override
  final int totalSeasons;
  @override
  final int? totalEpisodes;
  @override
  final int lastPositionSeconds;
  @override
  final int totalDurationSeconds;
  @override
  final double progressPercent;
  @override
  @JsonKey(fromJson: _dateTimeFromJson, toJson: _dateTimeToJson)
  final DateTime lastWatchedAt;
  @override
  @JsonKey(fromJson: _dateTimeFromJson, toJson: _dateTimeToJson)
  final DateTime createdAt;
  @override
  final bool isCompleted;
  final Map<String, EpisodeProgress> _episodes;
  @override
  @JsonKey(fromJson: _episodesFromJson, toJson: _episodesToJson)
  Map<String, EpisodeProgress> get episodes {
    if (_episodes is EqualUnmodifiableMapView) return _episodes;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableMapView(_episodes);
  }

  @override
  String toString() {
    return 'WatchHistory(id: $id, tmdbId: $tmdbId, mediaType: $mediaType, title: $title, posterPath: $posterPath, currentSeason: $currentSeason, currentEpisode: $currentEpisode, totalSeasons: $totalSeasons, totalEpisodes: $totalEpisodes, lastPositionSeconds: $lastPositionSeconds, totalDurationSeconds: $totalDurationSeconds, progressPercent: $progressPercent, lastWatchedAt: $lastWatchedAt, createdAt: $createdAt, isCompleted: $isCompleted, episodes: $episodes)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$WatchHistoryImpl &&
            (identical(other.id, id) || other.id == id) &&
            (identical(other.tmdbId, tmdbId) || other.tmdbId == tmdbId) &&
            (identical(other.mediaType, mediaType) ||
                other.mediaType == mediaType) &&
            (identical(other.title, title) || other.title == title) &&
            (identical(other.posterPath, posterPath) ||
                other.posterPath == posterPath) &&
            (identical(other.currentSeason, currentSeason) ||
                other.currentSeason == currentSeason) &&
            (identical(other.currentEpisode, currentEpisode) ||
                other.currentEpisode == currentEpisode) &&
            (identical(other.totalSeasons, totalSeasons) ||
                other.totalSeasons == totalSeasons) &&
            (identical(other.totalEpisodes, totalEpisodes) ||
                other.totalEpisodes == totalEpisodes) &&
            (identical(other.lastPositionSeconds, lastPositionSeconds) ||
                other.lastPositionSeconds == lastPositionSeconds) &&
            (identical(other.totalDurationSeconds, totalDurationSeconds) ||
                other.totalDurationSeconds == totalDurationSeconds) &&
            (identical(other.progressPercent, progressPercent) ||
                other.progressPercent == progressPercent) &&
            (identical(other.lastWatchedAt, lastWatchedAt) ||
                other.lastWatchedAt == lastWatchedAt) &&
            (identical(other.createdAt, createdAt) ||
                other.createdAt == createdAt) &&
            (identical(other.isCompleted, isCompleted) ||
                other.isCompleted == isCompleted) &&
            const DeepCollectionEquality().equals(other._episodes, _episodes));
  }

  @JsonKey(ignore: true)
  @override
  int get hashCode => Object.hash(
      runtimeType,
      id,
      tmdbId,
      mediaType,
      title,
      posterPath,
      currentSeason,
      currentEpisode,
      totalSeasons,
      totalEpisodes,
      lastPositionSeconds,
      totalDurationSeconds,
      progressPercent,
      lastWatchedAt,
      createdAt,
      isCompleted,
      const DeepCollectionEquality().hash(_episodes));

  @JsonKey(ignore: true)
  @override
  @pragma('vm:prefer-inline')
  _$$WatchHistoryImplCopyWith<_$WatchHistoryImpl> get copyWith =>
      __$$WatchHistoryImplCopyWithImpl<_$WatchHistoryImpl>(this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$$WatchHistoryImplToJson(
      this,
    );
  }
}

abstract class _WatchHistory implements WatchHistory {
  const factory _WatchHistory(
      {required final String id,
      required final int tmdbId,
      required final String mediaType,
      required final String title,
      final String? posterPath,
      required final int currentSeason,
      required final int currentEpisode,
      required final int totalSeasons,
      final int? totalEpisodes,
      required final int lastPositionSeconds,
      required final int totalDurationSeconds,
      required final double progressPercent,
      @JsonKey(fromJson: _dateTimeFromJson, toJson: _dateTimeToJson)
      required final DateTime lastWatchedAt,
      @JsonKey(fromJson: _dateTimeFromJson, toJson: _dateTimeToJson)
      required final DateTime createdAt,
      required final bool isCompleted,
      @JsonKey(fromJson: _episodesFromJson, toJson: _episodesToJson)
      final Map<String, EpisodeProgress> episodes}) = _$WatchHistoryImpl;

  factory _WatchHistory.fromJson(Map<String, dynamic> json) =
      _$WatchHistoryImpl.fromJson;

  @override
  String get id;
  @override
  int get tmdbId;
  @override
  String get mediaType;
  @override
  String get title;
  @override
  String? get posterPath;
  @override
  int get currentSeason;
  @override
  int get currentEpisode;
  @override
  int get totalSeasons;
  @override
  int? get totalEpisodes;
  @override
  int get lastPositionSeconds;
  @override
  int get totalDurationSeconds;
  @override
  double get progressPercent;
  @override
  @JsonKey(fromJson: _dateTimeFromJson, toJson: _dateTimeToJson)
  DateTime get lastWatchedAt;
  @override
  @JsonKey(fromJson: _dateTimeFromJson, toJson: _dateTimeToJson)
  DateTime get createdAt;
  @override
  bool get isCompleted;
  @override
  @JsonKey(fromJson: _episodesFromJson, toJson: _episodesToJson)
  Map<String, EpisodeProgress> get episodes;
  @override
  @JsonKey(ignore: true)
  _$$WatchHistoryImplCopyWith<_$WatchHistoryImpl> get copyWith =>
      throw _privateConstructorUsedError;
}

EpisodeProgress _$EpisodeProgressFromJson(Map<String, dynamic> json) {
  return _EpisodeProgress.fromJson(json);
}

/// @nodoc
mixin _$EpisodeProgress {
  int get season => throw _privateConstructorUsedError;
  int get episode => throw _privateConstructorUsedError;
  int get lastPositionSeconds => throw _privateConstructorUsedError;
  int get totalDurationSeconds => throw _privateConstructorUsedError;
  bool get isCompleted => throw _privateConstructorUsedError;
  @JsonKey(fromJson: _dateTimeFromJson, toJson: _dateTimeToJson)
  DateTime get watchedAt => throw _privateConstructorUsedError;

  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;
  @JsonKey(ignore: true)
  $EpisodeProgressCopyWith<EpisodeProgress> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $EpisodeProgressCopyWith<$Res> {
  factory $EpisodeProgressCopyWith(
          EpisodeProgress value, $Res Function(EpisodeProgress) then) =
      _$EpisodeProgressCopyWithImpl<$Res, EpisodeProgress>;
  @useResult
  $Res call(
      {int season,
      int episode,
      int lastPositionSeconds,
      int totalDurationSeconds,
      bool isCompleted,
      @JsonKey(fromJson: _dateTimeFromJson, toJson: _dateTimeToJson)
      DateTime watchedAt});
}

/// @nodoc
class _$EpisodeProgressCopyWithImpl<$Res, $Val extends EpisodeProgress>
    implements $EpisodeProgressCopyWith<$Res> {
  _$EpisodeProgressCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? season = null,
    Object? episode = null,
    Object? lastPositionSeconds = null,
    Object? totalDurationSeconds = null,
    Object? isCompleted = null,
    Object? watchedAt = null,
  }) {
    return _then(_value.copyWith(
      season: null == season
          ? _value.season
          : season // ignore: cast_nullable_to_non_nullable
              as int,
      episode: null == episode
          ? _value.episode
          : episode // ignore: cast_nullable_to_non_nullable
              as int,
      lastPositionSeconds: null == lastPositionSeconds
          ? _value.lastPositionSeconds
          : lastPositionSeconds // ignore: cast_nullable_to_non_nullable
              as int,
      totalDurationSeconds: null == totalDurationSeconds
          ? _value.totalDurationSeconds
          : totalDurationSeconds // ignore: cast_nullable_to_non_nullable
              as int,
      isCompleted: null == isCompleted
          ? _value.isCompleted
          : isCompleted // ignore: cast_nullable_to_non_nullable
              as bool,
      watchedAt: null == watchedAt
          ? _value.watchedAt
          : watchedAt // ignore: cast_nullable_to_non_nullable
              as DateTime,
    ) as $Val);
  }
}

/// @nodoc
abstract class _$$EpisodeProgressImplCopyWith<$Res>
    implements $EpisodeProgressCopyWith<$Res> {
  factory _$$EpisodeProgressImplCopyWith(_$EpisodeProgressImpl value,
          $Res Function(_$EpisodeProgressImpl) then) =
      __$$EpisodeProgressImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call(
      {int season,
      int episode,
      int lastPositionSeconds,
      int totalDurationSeconds,
      bool isCompleted,
      @JsonKey(fromJson: _dateTimeFromJson, toJson: _dateTimeToJson)
      DateTime watchedAt});
}

/// @nodoc
class __$$EpisodeProgressImplCopyWithImpl<$Res>
    extends _$EpisodeProgressCopyWithImpl<$Res, _$EpisodeProgressImpl>
    implements _$$EpisodeProgressImplCopyWith<$Res> {
  __$$EpisodeProgressImplCopyWithImpl(
      _$EpisodeProgressImpl _value, $Res Function(_$EpisodeProgressImpl) _then)
      : super(_value, _then);

  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? season = null,
    Object? episode = null,
    Object? lastPositionSeconds = null,
    Object? totalDurationSeconds = null,
    Object? isCompleted = null,
    Object? watchedAt = null,
  }) {
    return _then(_$EpisodeProgressImpl(
      season: null == season
          ? _value.season
          : season // ignore: cast_nullable_to_non_nullable
              as int,
      episode: null == episode
          ? _value.episode
          : episode // ignore: cast_nullable_to_non_nullable
              as int,
      lastPositionSeconds: null == lastPositionSeconds
          ? _value.lastPositionSeconds
          : lastPositionSeconds // ignore: cast_nullable_to_non_nullable
              as int,
      totalDurationSeconds: null == totalDurationSeconds
          ? _value.totalDurationSeconds
          : totalDurationSeconds // ignore: cast_nullable_to_non_nullable
              as int,
      isCompleted: null == isCompleted
          ? _value.isCompleted
          : isCompleted // ignore: cast_nullable_to_non_nullable
              as bool,
      watchedAt: null == watchedAt
          ? _value.watchedAt
          : watchedAt // ignore: cast_nullable_to_non_nullable
              as DateTime,
    ));
  }
}

/// @nodoc
@JsonSerializable()
class _$EpisodeProgressImpl implements _EpisodeProgress {
  const _$EpisodeProgressImpl(
      {required this.season,
      required this.episode,
      required this.lastPositionSeconds,
      required this.totalDurationSeconds,
      required this.isCompleted,
      @JsonKey(fromJson: _dateTimeFromJson, toJson: _dateTimeToJson)
      required this.watchedAt});

  factory _$EpisodeProgressImpl.fromJson(Map<String, dynamic> json) =>
      _$$EpisodeProgressImplFromJson(json);

  @override
  final int season;
  @override
  final int episode;
  @override
  final int lastPositionSeconds;
  @override
  final int totalDurationSeconds;
  @override
  final bool isCompleted;
  @override
  @JsonKey(fromJson: _dateTimeFromJson, toJson: _dateTimeToJson)
  final DateTime watchedAt;

  @override
  String toString() {
    return 'EpisodeProgress(season: $season, episode: $episode, lastPositionSeconds: $lastPositionSeconds, totalDurationSeconds: $totalDurationSeconds, isCompleted: $isCompleted, watchedAt: $watchedAt)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$EpisodeProgressImpl &&
            (identical(other.season, season) || other.season == season) &&
            (identical(other.episode, episode) || other.episode == episode) &&
            (identical(other.lastPositionSeconds, lastPositionSeconds) ||
                other.lastPositionSeconds == lastPositionSeconds) &&
            (identical(other.totalDurationSeconds, totalDurationSeconds) ||
                other.totalDurationSeconds == totalDurationSeconds) &&
            (identical(other.isCompleted, isCompleted) ||
                other.isCompleted == isCompleted) &&
            (identical(other.watchedAt, watchedAt) ||
                other.watchedAt == watchedAt));
  }

  @JsonKey(ignore: true)
  @override
  int get hashCode => Object.hash(runtimeType, season, episode,
      lastPositionSeconds, totalDurationSeconds, isCompleted, watchedAt);

  @JsonKey(ignore: true)
  @override
  @pragma('vm:prefer-inline')
  _$$EpisodeProgressImplCopyWith<_$EpisodeProgressImpl> get copyWith =>
      __$$EpisodeProgressImplCopyWithImpl<_$EpisodeProgressImpl>(
          this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$$EpisodeProgressImplToJson(
      this,
    );
  }
}

abstract class _EpisodeProgress implements EpisodeProgress {
  const factory _EpisodeProgress(
      {required final int season,
      required final int episode,
      required final int lastPositionSeconds,
      required final int totalDurationSeconds,
      required final bool isCompleted,
      @JsonKey(fromJson: _dateTimeFromJson, toJson: _dateTimeToJson)
      required final DateTime watchedAt}) = _$EpisodeProgressImpl;

  factory _EpisodeProgress.fromJson(Map<String, dynamic> json) =
      _$EpisodeProgressImpl.fromJson;

  @override
  int get season;
  @override
  int get episode;
  @override
  int get lastPositionSeconds;
  @override
  int get totalDurationSeconds;
  @override
  bool get isCompleted;
  @override
  @JsonKey(fromJson: _dateTimeFromJson, toJson: _dateTimeToJson)
  DateTime get watchedAt;
  @override
  @JsonKey(ignore: true)
  _$$EpisodeProgressImplCopyWith<_$EpisodeProgressImpl> get copyWith =>
      throw _privateConstructorUsedError;
}
