// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'watch_history.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$WatchHistory {

 String get id; int get tmdbId; String get mediaType; String get title; String? get posterPath; int get currentSeason; int get currentEpisode; int get totalSeasons; int? get totalEpisodes; int get lastPositionSeconds; int get totalDurationSeconds; double get progressPercent;@JsonKey(fromJson: _dateTimeFromJson, toJson: _dateTimeToJson) DateTime get lastWatchedAt;@JsonKey(fromJson: _dateTimeFromJson, toJson: _dateTimeToJson) DateTime get createdAt; bool get isCompleted; String? get preferredAudioTrack; String? get preferredSubtitleTrack; String? get preferredResolution; int? get preferredProviderIndex;@JsonKey(fromJson: _episodesFromJson, toJson: _episodesToJson) Map<String, EpisodeProgress> get episodes;
/// Create a copy of WatchHistory
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$WatchHistoryCopyWith<WatchHistory> get copyWith => _$WatchHistoryCopyWithImpl<WatchHistory>(this as WatchHistory, _$identity);

  /// Serializes this WatchHistory to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  final _this = this as WatchHistory;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is WatchHistory&&(identical(other.id, _this.id) || other.id == _this.id)&&(identical(other.tmdbId, _this.tmdbId) || other.tmdbId == _this.tmdbId)&&(identical(other.mediaType, _this.mediaType) || other.mediaType == _this.mediaType)&&(identical(other.title, _this.title) || other.title == _this.title)&&(identical(other.posterPath, _this.posterPath) || other.posterPath == _this.posterPath)&&(identical(other.currentSeason, _this.currentSeason) || other.currentSeason == _this.currentSeason)&&(identical(other.currentEpisode, _this.currentEpisode) || other.currentEpisode == _this.currentEpisode)&&(identical(other.totalSeasons, _this.totalSeasons) || other.totalSeasons == _this.totalSeasons)&&(identical(other.totalEpisodes, _this.totalEpisodes) || other.totalEpisodes == _this.totalEpisodes)&&(identical(other.lastPositionSeconds, _this.lastPositionSeconds) || other.lastPositionSeconds == _this.lastPositionSeconds)&&(identical(other.totalDurationSeconds, _this.totalDurationSeconds) || other.totalDurationSeconds == _this.totalDurationSeconds)&&(identical(other.progressPercent, _this.progressPercent) || other.progressPercent == _this.progressPercent)&&(identical(other.lastWatchedAt, _this.lastWatchedAt) || other.lastWatchedAt == _this.lastWatchedAt)&&(identical(other.createdAt, _this.createdAt) || other.createdAt == _this.createdAt)&&(identical(other.isCompleted, _this.isCompleted) || other.isCompleted == _this.isCompleted)&&(identical(other.preferredAudioTrack, _this.preferredAudioTrack) || other.preferredAudioTrack == _this.preferredAudioTrack)&&(identical(other.preferredSubtitleTrack, _this.preferredSubtitleTrack) || other.preferredSubtitleTrack == _this.preferredSubtitleTrack)&&(identical(other.preferredResolution, _this.preferredResolution) || other.preferredResolution == _this.preferredResolution)&&(identical(other.preferredProviderIndex, _this.preferredProviderIndex) || other.preferredProviderIndex == _this.preferredProviderIndex)&&const DeepCollectionEquality().equals(other.episodes, _this.episodes));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
  final _this = this as WatchHistory;
  return Object.hashAll([runtimeType,_this.id,_this.tmdbId,_this.mediaType,_this.title,_this.posterPath,_this.currentSeason,_this.currentEpisode,_this.totalSeasons,_this.totalEpisodes,_this.lastPositionSeconds,_this.totalDurationSeconds,_this.progressPercent,_this.lastWatchedAt,_this.createdAt,_this.isCompleted,_this.preferredAudioTrack,_this.preferredSubtitleTrack,_this.preferredResolution,_this.preferredProviderIndex,const DeepCollectionEquality().hash(_this.episodes)]);
}

@override
String toString() {
  final _this = this as WatchHistory;
  return 'WatchHistory(id: ${_this.id}, tmdbId: ${_this.tmdbId}, mediaType: ${_this.mediaType}, title: ${_this.title}, posterPath: ${_this.posterPath}, currentSeason: ${_this.currentSeason}, currentEpisode: ${_this.currentEpisode}, totalSeasons: ${_this.totalSeasons}, totalEpisodes: ${_this.totalEpisodes}, lastPositionSeconds: ${_this.lastPositionSeconds}, totalDurationSeconds: ${_this.totalDurationSeconds}, progressPercent: ${_this.progressPercent}, lastWatchedAt: ${_this.lastWatchedAt}, createdAt: ${_this.createdAt}, isCompleted: ${_this.isCompleted}, preferredAudioTrack: ${_this.preferredAudioTrack}, preferredSubtitleTrack: ${_this.preferredSubtitleTrack}, preferredResolution: ${_this.preferredResolution}, preferredProviderIndex: ${_this.preferredProviderIndex}, episodes: ${_this.episodes})';
}


}

/// @nodoc
abstract mixin class $WatchHistoryCopyWith<$Res>  {
  factory $WatchHistoryCopyWith(WatchHistory value, $Res Function(WatchHistory) _then) = _$WatchHistoryCopyWithImpl;
@useResult
$Res call({
 String id, int tmdbId, String mediaType, String title, String? posterPath, int currentSeason, int currentEpisode, int totalSeasons, int? totalEpisodes, int lastPositionSeconds, int totalDurationSeconds, double progressPercent,@JsonKey(fromJson: _dateTimeFromJson, toJson: _dateTimeToJson) DateTime lastWatchedAt,@JsonKey(fromJson: _dateTimeFromJson, toJson: _dateTimeToJson) DateTime createdAt, bool isCompleted, String? preferredAudioTrack, String? preferredSubtitleTrack, String? preferredResolution, int? preferredProviderIndex,@JsonKey(fromJson: _episodesFromJson, toJson: _episodesToJson) Map<String, EpisodeProgress> episodes
});




}
/// @nodoc
class _$WatchHistoryCopyWithImpl<$Res>
    implements $WatchHistoryCopyWith<$Res> {
  _$WatchHistoryCopyWithImpl(this._self, this._then);

  final WatchHistory _self;
  final $Res Function(WatchHistory) _then;

/// Create a copy of WatchHistory
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? tmdbId = null,Object? mediaType = null,Object? title = null,Object? posterPath = freezed,Object? currentSeason = null,Object? currentEpisode = null,Object? totalSeasons = null,Object? totalEpisodes = freezed,Object? lastPositionSeconds = null,Object? totalDurationSeconds = null,Object? progressPercent = null,Object? lastWatchedAt = null,Object? createdAt = null,Object? isCompleted = null,Object? preferredAudioTrack = freezed,Object? preferredSubtitleTrack = freezed,Object? preferredResolution = freezed,Object? preferredProviderIndex = freezed,Object? episodes = null,}) {
  return _then(WatchHistory(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,tmdbId: null == tmdbId ? _self.tmdbId : tmdbId // ignore: cast_nullable_to_non_nullable
as int,mediaType: null == mediaType ? _self.mediaType : mediaType // ignore: cast_nullable_to_non_nullable
as String,title: null == title ? _self.title : title // ignore: cast_nullable_to_non_nullable
as String,posterPath: freezed == posterPath ? _self.posterPath : posterPath // ignore: cast_nullable_to_non_nullable
as String?,currentSeason: null == currentSeason ? _self.currentSeason : currentSeason // ignore: cast_nullable_to_non_nullable
as int,currentEpisode: null == currentEpisode ? _self.currentEpisode : currentEpisode // ignore: cast_nullable_to_non_nullable
as int,totalSeasons: null == totalSeasons ? _self.totalSeasons : totalSeasons // ignore: cast_nullable_to_non_nullable
as int,totalEpisodes: freezed == totalEpisodes ? _self.totalEpisodes : totalEpisodes // ignore: cast_nullable_to_non_nullable
as int?,lastPositionSeconds: null == lastPositionSeconds ? _self.lastPositionSeconds : lastPositionSeconds // ignore: cast_nullable_to_non_nullable
as int,totalDurationSeconds: null == totalDurationSeconds ? _self.totalDurationSeconds : totalDurationSeconds // ignore: cast_nullable_to_non_nullable
as int,progressPercent: null == progressPercent ? _self.progressPercent : progressPercent // ignore: cast_nullable_to_non_nullable
as double,lastWatchedAt: null == lastWatchedAt ? _self.lastWatchedAt : lastWatchedAt // ignore: cast_nullable_to_non_nullable
as DateTime,createdAt: null == createdAt ? _self.createdAt : createdAt // ignore: cast_nullable_to_non_nullable
as DateTime,isCompleted: null == isCompleted ? _self.isCompleted : isCompleted // ignore: cast_nullable_to_non_nullable
as bool,preferredAudioTrack: freezed == preferredAudioTrack ? _self.preferredAudioTrack : preferredAudioTrack // ignore: cast_nullable_to_non_nullable
as String?,preferredSubtitleTrack: freezed == preferredSubtitleTrack ? _self.preferredSubtitleTrack : preferredSubtitleTrack // ignore: cast_nullable_to_non_nullable
as String?,preferredResolution: freezed == preferredResolution ? _self.preferredResolution : preferredResolution // ignore: cast_nullable_to_non_nullable
as String?,preferredProviderIndex: freezed == preferredProviderIndex ? _self.preferredProviderIndex : preferredProviderIndex // ignore: cast_nullable_to_non_nullable
as int?,episodes: null == episodes ? _self.episodes : episodes // ignore: cast_nullable_to_non_nullable
as Map<String, EpisodeProgress>,
  ));
}

}


/// Adds pattern-matching-related methods to [WatchHistory].
extension WatchHistoryPatterns on WatchHistory {
/// A variant of `map` that fallback to returning `orElse`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _WatchHistory value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _WatchHistory() when $default != null:
return $default(_that);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// Callbacks receives the raw object, upcasted.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case final Subclass2 value:
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _WatchHistory value)  $default,){
final _that = this;
switch (_that) {
case _WatchHistory():
return $default(_that);case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `map` that fallback to returning `null`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _WatchHistory value)?  $default,){
final _that = this;
switch (_that) {
case _WatchHistory() when $default != null:
return $default(_that);case _:
  return null;

}
}
/// A variant of `when` that fallback to an `orElse` callback.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String id,  int tmdbId,  String mediaType,  String title,  String? posterPath,  int currentSeason,  int currentEpisode,  int totalSeasons,  int? totalEpisodes,  int lastPositionSeconds,  int totalDurationSeconds,  double progressPercent, @JsonKey(fromJson: _dateTimeFromJson, toJson: _dateTimeToJson)  DateTime lastWatchedAt, @JsonKey(fromJson: _dateTimeFromJson, toJson: _dateTimeToJson)  DateTime createdAt,  bool isCompleted,  String? preferredAudioTrack,  String? preferredSubtitleTrack,  String? preferredResolution,  int? preferredProviderIndex, @JsonKey(fromJson: _episodesFromJson, toJson: _episodesToJson)  Map<String, EpisodeProgress> episodes)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _WatchHistory() when $default != null:
return $default(_that.id,_that.tmdbId,_that.mediaType,_that.title,_that.posterPath,_that.currentSeason,_that.currentEpisode,_that.totalSeasons,_that.totalEpisodes,_that.lastPositionSeconds,_that.totalDurationSeconds,_that.progressPercent,_that.lastWatchedAt,_that.createdAt,_that.isCompleted,_that.preferredAudioTrack,_that.preferredSubtitleTrack,_that.preferredResolution,_that.preferredProviderIndex,_that.episodes);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// As opposed to `map`, this offers destructuring.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case Subclass2(:final field2):
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String id,  int tmdbId,  String mediaType,  String title,  String? posterPath,  int currentSeason,  int currentEpisode,  int totalSeasons,  int? totalEpisodes,  int lastPositionSeconds,  int totalDurationSeconds,  double progressPercent, @JsonKey(fromJson: _dateTimeFromJson, toJson: _dateTimeToJson)  DateTime lastWatchedAt, @JsonKey(fromJson: _dateTimeFromJson, toJson: _dateTimeToJson)  DateTime createdAt,  bool isCompleted,  String? preferredAudioTrack,  String? preferredSubtitleTrack,  String? preferredResolution,  int? preferredProviderIndex, @JsonKey(fromJson: _episodesFromJson, toJson: _episodesToJson)  Map<String, EpisodeProgress> episodes)  $default,) {final _that = this;
switch (_that) {
case _WatchHistory():
return $default(_that.id,_that.tmdbId,_that.mediaType,_that.title,_that.posterPath,_that.currentSeason,_that.currentEpisode,_that.totalSeasons,_that.totalEpisodes,_that.lastPositionSeconds,_that.totalDurationSeconds,_that.progressPercent,_that.lastWatchedAt,_that.createdAt,_that.isCompleted,_that.preferredAudioTrack,_that.preferredSubtitleTrack,_that.preferredResolution,_that.preferredProviderIndex,_that.episodes);case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `when` that fallback to returning `null`
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String id,  int tmdbId,  String mediaType,  String title,  String? posterPath,  int currentSeason,  int currentEpisode,  int totalSeasons,  int? totalEpisodes,  int lastPositionSeconds,  int totalDurationSeconds,  double progressPercent, @JsonKey(fromJson: _dateTimeFromJson, toJson: _dateTimeToJson)  DateTime lastWatchedAt, @JsonKey(fromJson: _dateTimeFromJson, toJson: _dateTimeToJson)  DateTime createdAt,  bool isCompleted,  String? preferredAudioTrack,  String? preferredSubtitleTrack,  String? preferredResolution,  int? preferredProviderIndex, @JsonKey(fromJson: _episodesFromJson, toJson: _episodesToJson)  Map<String, EpisodeProgress> episodes)?  $default,) {final _that = this;
switch (_that) {
case _WatchHistory() when $default != null:
return $default(_that.id,_that.tmdbId,_that.mediaType,_that.title,_that.posterPath,_that.currentSeason,_that.currentEpisode,_that.totalSeasons,_that.totalEpisodes,_that.lastPositionSeconds,_that.totalDurationSeconds,_that.progressPercent,_that.lastWatchedAt,_that.createdAt,_that.isCompleted,_that.preferredAudioTrack,_that.preferredSubtitleTrack,_that.preferredResolution,_that.preferredProviderIndex,_that.episodes);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _WatchHistory implements WatchHistory {
  const _WatchHistory({required this.id, required this.tmdbId, required this.mediaType, required this.title, this.posterPath, required this.currentSeason, required this.currentEpisode, required this.totalSeasons, this.totalEpisodes, required this.lastPositionSeconds, required this.totalDurationSeconds, required this.progressPercent, @JsonKey(fromJson: _dateTimeFromJson, toJson: _dateTimeToJson) required this.lastWatchedAt, @JsonKey(fromJson: _dateTimeFromJson, toJson: _dateTimeToJson) required this.createdAt, required this.isCompleted, this.preferredAudioTrack, this.preferredSubtitleTrack, this.preferredResolution, this.preferredProviderIndex, @JsonKey(fromJson: _episodesFromJson, toJson: _episodesToJson)  Map<String, EpisodeProgress> episodes = const {}}): _episodes = episodes;
  factory _WatchHistory.fromJson(Map<String, dynamic> json) => _$WatchHistoryFromJson(json);

@override final  String id;
@override final  int tmdbId;
@override final  String mediaType;
@override final  String title;
@override final  String? posterPath;
@override final  int currentSeason;
@override final  int currentEpisode;
@override final  int totalSeasons;
@override final  int? totalEpisodes;
@override final  int lastPositionSeconds;
@override final  int totalDurationSeconds;
@override final  double progressPercent;
@override@JsonKey(fromJson: _dateTimeFromJson, toJson: _dateTimeToJson) final  DateTime lastWatchedAt;
@override@JsonKey(fromJson: _dateTimeFromJson, toJson: _dateTimeToJson) final  DateTime createdAt;
@override final  bool isCompleted;
@override final  String? preferredAudioTrack;
@override final  String? preferredSubtitleTrack;
@override final  String? preferredResolution;
@override final  int? preferredProviderIndex;
 final  Map<String, EpisodeProgress> _episodes;
@override@JsonKey(fromJson: _episodesFromJson, toJson: _episodesToJson) Map<String, EpisodeProgress> get episodes {
  if (_episodes is EqualUnmodifiableMapView) return _episodes;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableMapView(_episodes);
}


/// Create a copy of WatchHistory
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$WatchHistoryCopyWith<_WatchHistory> get copyWith => __$WatchHistoryCopyWithImpl<_WatchHistory>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$WatchHistoryToJson(this, );
}

@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _WatchHistory&&(identical(other.id, id) || other.id == id)&&(identical(other.tmdbId, tmdbId) || other.tmdbId == tmdbId)&&(identical(other.mediaType, mediaType) || other.mediaType == mediaType)&&(identical(other.title, title) || other.title == title)&&(identical(other.posterPath, posterPath) || other.posterPath == posterPath)&&(identical(other.currentSeason, currentSeason) || other.currentSeason == currentSeason)&&(identical(other.currentEpisode, currentEpisode) || other.currentEpisode == currentEpisode)&&(identical(other.totalSeasons, totalSeasons) || other.totalSeasons == totalSeasons)&&(identical(other.totalEpisodes, totalEpisodes) || other.totalEpisodes == totalEpisodes)&&(identical(other.lastPositionSeconds, lastPositionSeconds) || other.lastPositionSeconds == lastPositionSeconds)&&(identical(other.totalDurationSeconds, totalDurationSeconds) || other.totalDurationSeconds == totalDurationSeconds)&&(identical(other.progressPercent, progressPercent) || other.progressPercent == progressPercent)&&(identical(other.lastWatchedAt, lastWatchedAt) || other.lastWatchedAt == lastWatchedAt)&&(identical(other.createdAt, createdAt) || other.createdAt == createdAt)&&(identical(other.isCompleted, isCompleted) || other.isCompleted == isCompleted)&&(identical(other.preferredAudioTrack, preferredAudioTrack) || other.preferredAudioTrack == preferredAudioTrack)&&(identical(other.preferredSubtitleTrack, preferredSubtitleTrack) || other.preferredSubtitleTrack == preferredSubtitleTrack)&&(identical(other.preferredResolution, preferredResolution) || other.preferredResolution == preferredResolution)&&(identical(other.preferredProviderIndex, preferredProviderIndex) || other.preferredProviderIndex == preferredProviderIndex)&&const DeepCollectionEquality().equals(other.episodes, _episodes));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
    return Object.hashAll([runtimeType,id,tmdbId,mediaType,title,posterPath,currentSeason,currentEpisode,totalSeasons,totalEpisodes,lastPositionSeconds,totalDurationSeconds,progressPercent,lastWatchedAt,createdAt,isCompleted,preferredAudioTrack,preferredSubtitleTrack,preferredResolution,preferredProviderIndex,const DeepCollectionEquality().hash(_episodes)]);
}

@override
String toString() {
    return 'WatchHistory(id: $id, tmdbId: $tmdbId, mediaType: $mediaType, title: $title, posterPath: $posterPath, currentSeason: $currentSeason, currentEpisode: $currentEpisode, totalSeasons: $totalSeasons, totalEpisodes: $totalEpisodes, lastPositionSeconds: $lastPositionSeconds, totalDurationSeconds: $totalDurationSeconds, progressPercent: $progressPercent, lastWatchedAt: $lastWatchedAt, createdAt: $createdAt, isCompleted: $isCompleted, preferredAudioTrack: $preferredAudioTrack, preferredSubtitleTrack: $preferredSubtitleTrack, preferredResolution: $preferredResolution, preferredProviderIndex: $preferredProviderIndex, episodes: $episodes)';
}


}

/// @nodoc
abstract mixin class _$WatchHistoryCopyWith<$Res> implements $WatchHistoryCopyWith<$Res> {
  factory _$WatchHistoryCopyWith(_WatchHistory value, $Res Function(_WatchHistory) _then) = __$WatchHistoryCopyWithImpl;
@override @useResult
$Res call({
 String id, int tmdbId, String mediaType, String title, String? posterPath, int currentSeason, int currentEpisode, int totalSeasons, int? totalEpisodes, int lastPositionSeconds, int totalDurationSeconds, double progressPercent,@JsonKey(fromJson: _dateTimeFromJson, toJson: _dateTimeToJson) DateTime lastWatchedAt,@JsonKey(fromJson: _dateTimeFromJson, toJson: _dateTimeToJson) DateTime createdAt, bool isCompleted, String? preferredAudioTrack, String? preferredSubtitleTrack, String? preferredResolution, int? preferredProviderIndex,@JsonKey(fromJson: _episodesFromJson, toJson: _episodesToJson) Map<String, EpisodeProgress> episodes
});




}
/// @nodoc
class __$WatchHistoryCopyWithImpl<$Res>
    implements _$WatchHistoryCopyWith<$Res> {
  __$WatchHistoryCopyWithImpl(this._self, this._then);

  final _WatchHistory _self;
  final $Res Function(_WatchHistory) _then;

/// Create a copy of WatchHistory
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? tmdbId = null,Object? mediaType = null,Object? title = null,Object? posterPath = freezed,Object? currentSeason = null,Object? currentEpisode = null,Object? totalSeasons = null,Object? totalEpisodes = freezed,Object? lastPositionSeconds = null,Object? totalDurationSeconds = null,Object? progressPercent = null,Object? lastWatchedAt = null,Object? createdAt = null,Object? isCompleted = null,Object? preferredAudioTrack = freezed,Object? preferredSubtitleTrack = freezed,Object? preferredResolution = freezed,Object? preferredProviderIndex = freezed,Object? episodes = null,}) {
  return _then(_WatchHistory(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,tmdbId: null == tmdbId ? _self.tmdbId : tmdbId // ignore: cast_nullable_to_non_nullable
as int,mediaType: null == mediaType ? _self.mediaType : mediaType // ignore: cast_nullable_to_non_nullable
as String,title: null == title ? _self.title : title // ignore: cast_nullable_to_non_nullable
as String,posterPath: freezed == posterPath ? _self.posterPath : posterPath // ignore: cast_nullable_to_non_nullable
as String?,currentSeason: null == currentSeason ? _self.currentSeason : currentSeason // ignore: cast_nullable_to_non_nullable
as int,currentEpisode: null == currentEpisode ? _self.currentEpisode : currentEpisode // ignore: cast_nullable_to_non_nullable
as int,totalSeasons: null == totalSeasons ? _self.totalSeasons : totalSeasons // ignore: cast_nullable_to_non_nullable
as int,totalEpisodes: freezed == totalEpisodes ? _self.totalEpisodes : totalEpisodes // ignore: cast_nullable_to_non_nullable
as int?,lastPositionSeconds: null == lastPositionSeconds ? _self.lastPositionSeconds : lastPositionSeconds // ignore: cast_nullable_to_non_nullable
as int,totalDurationSeconds: null == totalDurationSeconds ? _self.totalDurationSeconds : totalDurationSeconds // ignore: cast_nullable_to_non_nullable
as int,progressPercent: null == progressPercent ? _self.progressPercent : progressPercent // ignore: cast_nullable_to_non_nullable
as double,lastWatchedAt: null == lastWatchedAt ? _self.lastWatchedAt : lastWatchedAt // ignore: cast_nullable_to_non_nullable
as DateTime,createdAt: null == createdAt ? _self.createdAt : createdAt // ignore: cast_nullable_to_non_nullable
as DateTime,isCompleted: null == isCompleted ? _self.isCompleted : isCompleted // ignore: cast_nullable_to_non_nullable
as bool,preferredAudioTrack: freezed == preferredAudioTrack ? _self.preferredAudioTrack : preferredAudioTrack // ignore: cast_nullable_to_non_nullable
as String?,preferredSubtitleTrack: freezed == preferredSubtitleTrack ? _self.preferredSubtitleTrack : preferredSubtitleTrack // ignore: cast_nullable_to_non_nullable
as String?,preferredResolution: freezed == preferredResolution ? _self.preferredResolution : preferredResolution // ignore: cast_nullable_to_non_nullable
as String?,preferredProviderIndex: freezed == preferredProviderIndex ? _self.preferredProviderIndex : preferredProviderIndex // ignore: cast_nullable_to_non_nullable
as int?,episodes: null == episodes ? _self._episodes : episodes // ignore: cast_nullable_to_non_nullable
as Map<String, EpisodeProgress>,
  ));
}


}


/// @nodoc
mixin _$EpisodeProgress {

 int get season; int get episode; int get lastPositionSeconds; int get totalDurationSeconds; bool get isCompleted;@JsonKey(fromJson: _dateTimeFromJson, toJson: _dateTimeToJson) DateTime get watchedAt; String? get preferredAudioTrack; String? get preferredSubtitleTrack; String? get preferredResolution; int? get preferredProviderIndex;
/// Create a copy of EpisodeProgress
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$EpisodeProgressCopyWith<EpisodeProgress> get copyWith => _$EpisodeProgressCopyWithImpl<EpisodeProgress>(this as EpisodeProgress, _$identity);

  /// Serializes this EpisodeProgress to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  final _this = this as EpisodeProgress;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is EpisodeProgress&&(identical(other.season, _this.season) || other.season == _this.season)&&(identical(other.episode, _this.episode) || other.episode == _this.episode)&&(identical(other.lastPositionSeconds, _this.lastPositionSeconds) || other.lastPositionSeconds == _this.lastPositionSeconds)&&(identical(other.totalDurationSeconds, _this.totalDurationSeconds) || other.totalDurationSeconds == _this.totalDurationSeconds)&&(identical(other.isCompleted, _this.isCompleted) || other.isCompleted == _this.isCompleted)&&(identical(other.watchedAt, _this.watchedAt) || other.watchedAt == _this.watchedAt)&&(identical(other.preferredAudioTrack, _this.preferredAudioTrack) || other.preferredAudioTrack == _this.preferredAudioTrack)&&(identical(other.preferredSubtitleTrack, _this.preferredSubtitleTrack) || other.preferredSubtitleTrack == _this.preferredSubtitleTrack)&&(identical(other.preferredResolution, _this.preferredResolution) || other.preferredResolution == _this.preferredResolution)&&(identical(other.preferredProviderIndex, _this.preferredProviderIndex) || other.preferredProviderIndex == _this.preferredProviderIndex));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
  final _this = this as EpisodeProgress;
  return Object.hash(runtimeType,_this.season,_this.episode,_this.lastPositionSeconds,_this.totalDurationSeconds,_this.isCompleted,_this.watchedAt,_this.preferredAudioTrack,_this.preferredSubtitleTrack,_this.preferredResolution,_this.preferredProviderIndex);
}

@override
String toString() {
  final _this = this as EpisodeProgress;
  return 'EpisodeProgress(season: ${_this.season}, episode: ${_this.episode}, lastPositionSeconds: ${_this.lastPositionSeconds}, totalDurationSeconds: ${_this.totalDurationSeconds}, isCompleted: ${_this.isCompleted}, watchedAt: ${_this.watchedAt}, preferredAudioTrack: ${_this.preferredAudioTrack}, preferredSubtitleTrack: ${_this.preferredSubtitleTrack}, preferredResolution: ${_this.preferredResolution}, preferredProviderIndex: ${_this.preferredProviderIndex})';
}


}

/// @nodoc
abstract mixin class $EpisodeProgressCopyWith<$Res>  {
  factory $EpisodeProgressCopyWith(EpisodeProgress value, $Res Function(EpisodeProgress) _then) = _$EpisodeProgressCopyWithImpl;
@useResult
$Res call({
 int season, int episode, int lastPositionSeconds, int totalDurationSeconds, bool isCompleted,@JsonKey(fromJson: _dateTimeFromJson, toJson: _dateTimeToJson) DateTime watchedAt, String? preferredAudioTrack, String? preferredSubtitleTrack, String? preferredResolution, int? preferredProviderIndex
});




}
/// @nodoc
class _$EpisodeProgressCopyWithImpl<$Res>
    implements $EpisodeProgressCopyWith<$Res> {
  _$EpisodeProgressCopyWithImpl(this._self, this._then);

  final EpisodeProgress _self;
  final $Res Function(EpisodeProgress) _then;

/// Create a copy of EpisodeProgress
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? season = null,Object? episode = null,Object? lastPositionSeconds = null,Object? totalDurationSeconds = null,Object? isCompleted = null,Object? watchedAt = null,Object? preferredAudioTrack = freezed,Object? preferredSubtitleTrack = freezed,Object? preferredResolution = freezed,Object? preferredProviderIndex = freezed,}) {
  return _then(EpisodeProgress(
season: null == season ? _self.season : season // ignore: cast_nullable_to_non_nullable
as int,episode: null == episode ? _self.episode : episode // ignore: cast_nullable_to_non_nullable
as int,lastPositionSeconds: null == lastPositionSeconds ? _self.lastPositionSeconds : lastPositionSeconds // ignore: cast_nullable_to_non_nullable
as int,totalDurationSeconds: null == totalDurationSeconds ? _self.totalDurationSeconds : totalDurationSeconds // ignore: cast_nullable_to_non_nullable
as int,isCompleted: null == isCompleted ? _self.isCompleted : isCompleted // ignore: cast_nullable_to_non_nullable
as bool,watchedAt: null == watchedAt ? _self.watchedAt : watchedAt // ignore: cast_nullable_to_non_nullable
as DateTime,preferredAudioTrack: freezed == preferredAudioTrack ? _self.preferredAudioTrack : preferredAudioTrack // ignore: cast_nullable_to_non_nullable
as String?,preferredSubtitleTrack: freezed == preferredSubtitleTrack ? _self.preferredSubtitleTrack : preferredSubtitleTrack // ignore: cast_nullable_to_non_nullable
as String?,preferredResolution: freezed == preferredResolution ? _self.preferredResolution : preferredResolution // ignore: cast_nullable_to_non_nullable
as String?,preferredProviderIndex: freezed == preferredProviderIndex ? _self.preferredProviderIndex : preferredProviderIndex // ignore: cast_nullable_to_non_nullable
as int?,
  ));
}

}


/// Adds pattern-matching-related methods to [EpisodeProgress].
extension EpisodeProgressPatterns on EpisodeProgress {
/// A variant of `map` that fallback to returning `orElse`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _EpisodeProgress value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _EpisodeProgress() when $default != null:
return $default(_that);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// Callbacks receives the raw object, upcasted.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case final Subclass2 value:
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _EpisodeProgress value)  $default,){
final _that = this;
switch (_that) {
case _EpisodeProgress():
return $default(_that);case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `map` that fallback to returning `null`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _EpisodeProgress value)?  $default,){
final _that = this;
switch (_that) {
case _EpisodeProgress() when $default != null:
return $default(_that);case _:
  return null;

}
}
/// A variant of `when` that fallback to an `orElse` callback.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( int season,  int episode,  int lastPositionSeconds,  int totalDurationSeconds,  bool isCompleted, @JsonKey(fromJson: _dateTimeFromJson, toJson: _dateTimeToJson)  DateTime watchedAt,  String? preferredAudioTrack,  String? preferredSubtitleTrack,  String? preferredResolution,  int? preferredProviderIndex)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _EpisodeProgress() when $default != null:
return $default(_that.season,_that.episode,_that.lastPositionSeconds,_that.totalDurationSeconds,_that.isCompleted,_that.watchedAt,_that.preferredAudioTrack,_that.preferredSubtitleTrack,_that.preferredResolution,_that.preferredProviderIndex);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// As opposed to `map`, this offers destructuring.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case Subclass2(:final field2):
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( int season,  int episode,  int lastPositionSeconds,  int totalDurationSeconds,  bool isCompleted, @JsonKey(fromJson: _dateTimeFromJson, toJson: _dateTimeToJson)  DateTime watchedAt,  String? preferredAudioTrack,  String? preferredSubtitleTrack,  String? preferredResolution,  int? preferredProviderIndex)  $default,) {final _that = this;
switch (_that) {
case _EpisodeProgress():
return $default(_that.season,_that.episode,_that.lastPositionSeconds,_that.totalDurationSeconds,_that.isCompleted,_that.watchedAt,_that.preferredAudioTrack,_that.preferredSubtitleTrack,_that.preferredResolution,_that.preferredProviderIndex);case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `when` that fallback to returning `null`
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( int season,  int episode,  int lastPositionSeconds,  int totalDurationSeconds,  bool isCompleted, @JsonKey(fromJson: _dateTimeFromJson, toJson: _dateTimeToJson)  DateTime watchedAt,  String? preferredAudioTrack,  String? preferredSubtitleTrack,  String? preferredResolution,  int? preferredProviderIndex)?  $default,) {final _that = this;
switch (_that) {
case _EpisodeProgress() when $default != null:
return $default(_that.season,_that.episode,_that.lastPositionSeconds,_that.totalDurationSeconds,_that.isCompleted,_that.watchedAt,_that.preferredAudioTrack,_that.preferredSubtitleTrack,_that.preferredResolution,_that.preferredProviderIndex);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _EpisodeProgress implements EpisodeProgress {
  const _EpisodeProgress({required this.season, required this.episode, required this.lastPositionSeconds, required this.totalDurationSeconds, required this.isCompleted, @JsonKey(fromJson: _dateTimeFromJson, toJson: _dateTimeToJson) required this.watchedAt, this.preferredAudioTrack, this.preferredSubtitleTrack, this.preferredResolution, this.preferredProviderIndex});
  factory _EpisodeProgress.fromJson(Map<String, dynamic> json) => _$EpisodeProgressFromJson(json);

@override final  int season;
@override final  int episode;
@override final  int lastPositionSeconds;
@override final  int totalDurationSeconds;
@override final  bool isCompleted;
@override@JsonKey(fromJson: _dateTimeFromJson, toJson: _dateTimeToJson) final  DateTime watchedAt;
@override final  String? preferredAudioTrack;
@override final  String? preferredSubtitleTrack;
@override final  String? preferredResolution;
@override final  int? preferredProviderIndex;

/// Create a copy of EpisodeProgress
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$EpisodeProgressCopyWith<_EpisodeProgress> get copyWith => __$EpisodeProgressCopyWithImpl<_EpisodeProgress>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$EpisodeProgressToJson(this, );
}

@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _EpisodeProgress&&(identical(other.season, season) || other.season == season)&&(identical(other.episode, episode) || other.episode == episode)&&(identical(other.lastPositionSeconds, lastPositionSeconds) || other.lastPositionSeconds == lastPositionSeconds)&&(identical(other.totalDurationSeconds, totalDurationSeconds) || other.totalDurationSeconds == totalDurationSeconds)&&(identical(other.isCompleted, isCompleted) || other.isCompleted == isCompleted)&&(identical(other.watchedAt, watchedAt) || other.watchedAt == watchedAt)&&(identical(other.preferredAudioTrack, preferredAudioTrack) || other.preferredAudioTrack == preferredAudioTrack)&&(identical(other.preferredSubtitleTrack, preferredSubtitleTrack) || other.preferredSubtitleTrack == preferredSubtitleTrack)&&(identical(other.preferredResolution, preferredResolution) || other.preferredResolution == preferredResolution)&&(identical(other.preferredProviderIndex, preferredProviderIndex) || other.preferredProviderIndex == preferredProviderIndex));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
    return Object.hash(runtimeType,season,episode,lastPositionSeconds,totalDurationSeconds,isCompleted,watchedAt,preferredAudioTrack,preferredSubtitleTrack,preferredResolution,preferredProviderIndex);
}

@override
String toString() {
    return 'EpisodeProgress(season: $season, episode: $episode, lastPositionSeconds: $lastPositionSeconds, totalDurationSeconds: $totalDurationSeconds, isCompleted: $isCompleted, watchedAt: $watchedAt, preferredAudioTrack: $preferredAudioTrack, preferredSubtitleTrack: $preferredSubtitleTrack, preferredResolution: $preferredResolution, preferredProviderIndex: $preferredProviderIndex)';
}


}

/// @nodoc
abstract mixin class _$EpisodeProgressCopyWith<$Res> implements $EpisodeProgressCopyWith<$Res> {
  factory _$EpisodeProgressCopyWith(_EpisodeProgress value, $Res Function(_EpisodeProgress) _then) = __$EpisodeProgressCopyWithImpl;
@override @useResult
$Res call({
 int season, int episode, int lastPositionSeconds, int totalDurationSeconds, bool isCompleted,@JsonKey(fromJson: _dateTimeFromJson, toJson: _dateTimeToJson) DateTime watchedAt, String? preferredAudioTrack, String? preferredSubtitleTrack, String? preferredResolution, int? preferredProviderIndex
});




}
/// @nodoc
class __$EpisodeProgressCopyWithImpl<$Res>
    implements _$EpisodeProgressCopyWith<$Res> {
  __$EpisodeProgressCopyWithImpl(this._self, this._then);

  final _EpisodeProgress _self;
  final $Res Function(_EpisodeProgress) _then;

/// Create a copy of EpisodeProgress
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? season = null,Object? episode = null,Object? lastPositionSeconds = null,Object? totalDurationSeconds = null,Object? isCompleted = null,Object? watchedAt = null,Object? preferredAudioTrack = freezed,Object? preferredSubtitleTrack = freezed,Object? preferredResolution = freezed,Object? preferredProviderIndex = freezed,}) {
  return _then(_EpisodeProgress(
season: null == season ? _self.season : season // ignore: cast_nullable_to_non_nullable
as int,episode: null == episode ? _self.episode : episode // ignore: cast_nullable_to_non_nullable
as int,lastPositionSeconds: null == lastPositionSeconds ? _self.lastPositionSeconds : lastPositionSeconds // ignore: cast_nullable_to_non_nullable
as int,totalDurationSeconds: null == totalDurationSeconds ? _self.totalDurationSeconds : totalDurationSeconds // ignore: cast_nullable_to_non_nullable
as int,isCompleted: null == isCompleted ? _self.isCompleted : isCompleted // ignore: cast_nullable_to_non_nullable
as bool,watchedAt: null == watchedAt ? _self.watchedAt : watchedAt // ignore: cast_nullable_to_non_nullable
as DateTime,preferredAudioTrack: freezed == preferredAudioTrack ? _self.preferredAudioTrack : preferredAudioTrack // ignore: cast_nullable_to_non_nullable
as String?,preferredSubtitleTrack: freezed == preferredSubtitleTrack ? _self.preferredSubtitleTrack : preferredSubtitleTrack // ignore: cast_nullable_to_non_nullable
as String?,preferredResolution: freezed == preferredResolution ? _self.preferredResolution : preferredResolution // ignore: cast_nullable_to_non_nullable
as String?,preferredProviderIndex: freezed == preferredProviderIndex ? _self.preferredProviderIndex : preferredProviderIndex // ignore: cast_nullable_to_non_nullable
as int?,
  ));
}


}

// dart format on
