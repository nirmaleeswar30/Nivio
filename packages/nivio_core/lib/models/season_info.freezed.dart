// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'season_info.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$EpisodeData {

@JsonKey(name: 'episode_number') int get episodeNumber;@JsonKey(name: 'name') String? get episodeName; String? get overview;@JsonKey(name: 'still_path') String? get stillPath;@JsonKey(name: 'vote_average') double? get voteAverage;@JsonKey(name: 'runtime') int? get runtime;@JsonKey(name: 'air_date') String? get airDate;
/// Create a copy of EpisodeData
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$EpisodeDataCopyWith<EpisodeData> get copyWith => _$EpisodeDataCopyWithImpl<EpisodeData>(this as EpisodeData, _$identity);

  /// Serializes this EpisodeData to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  final _this = this as EpisodeData;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is EpisodeData&&(identical(other.episodeNumber, _this.episodeNumber) || other.episodeNumber == _this.episodeNumber)&&(identical(other.episodeName, _this.episodeName) || other.episodeName == _this.episodeName)&&(identical(other.overview, _this.overview) || other.overview == _this.overview)&&(identical(other.stillPath, _this.stillPath) || other.stillPath == _this.stillPath)&&(identical(other.voteAverage, _this.voteAverage) || other.voteAverage == _this.voteAverage)&&(identical(other.runtime, _this.runtime) || other.runtime == _this.runtime)&&(identical(other.airDate, _this.airDate) || other.airDate == _this.airDate));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
  final _this = this as EpisodeData;
  return Object.hash(runtimeType,_this.episodeNumber,_this.episodeName,_this.overview,_this.stillPath,_this.voteAverage,_this.runtime,_this.airDate);
}

@override
String toString() {
  final _this = this as EpisodeData;
  return 'EpisodeData(episodeNumber: ${_this.episodeNumber}, episodeName: ${_this.episodeName}, overview: ${_this.overview}, stillPath: ${_this.stillPath}, voteAverage: ${_this.voteAverage}, runtime: ${_this.runtime}, airDate: ${_this.airDate})';
}


}

/// @nodoc
abstract mixin class $EpisodeDataCopyWith<$Res>  {
  factory $EpisodeDataCopyWith(EpisodeData value, $Res Function(EpisodeData) _then) = _$EpisodeDataCopyWithImpl;
@useResult
$Res call({
@JsonKey(name: 'episode_number') int episodeNumber,@JsonKey(name: 'name') String? episodeName, String? overview,@JsonKey(name: 'still_path') String? stillPath,@JsonKey(name: 'vote_average') double? voteAverage,@JsonKey(name: 'runtime') int? runtime,@JsonKey(name: 'air_date') String? airDate
});




}
/// @nodoc
class _$EpisodeDataCopyWithImpl<$Res>
    implements $EpisodeDataCopyWith<$Res> {
  _$EpisodeDataCopyWithImpl(this._self, this._then);

  final EpisodeData _self;
  final $Res Function(EpisodeData) _then;

/// Create a copy of EpisodeData
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? episodeNumber = null,Object? episodeName = freezed,Object? overview = freezed,Object? stillPath = freezed,Object? voteAverage = freezed,Object? runtime = freezed,Object? airDate = freezed,}) {
  return _then(EpisodeData(
episodeNumber: null == episodeNumber ? _self.episodeNumber : episodeNumber // ignore: cast_nullable_to_non_nullable
as int,episodeName: freezed == episodeName ? _self.episodeName : episodeName // ignore: cast_nullable_to_non_nullable
as String?,overview: freezed == overview ? _self.overview : overview // ignore: cast_nullable_to_non_nullable
as String?,stillPath: freezed == stillPath ? _self.stillPath : stillPath // ignore: cast_nullable_to_non_nullable
as String?,voteAverage: freezed == voteAverage ? _self.voteAverage : voteAverage // ignore: cast_nullable_to_non_nullable
as double?,runtime: freezed == runtime ? _self.runtime : runtime // ignore: cast_nullable_to_non_nullable
as int?,airDate: freezed == airDate ? _self.airDate : airDate // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}

}


/// Adds pattern-matching-related methods to [EpisodeData].
extension EpisodeDataPatterns on EpisodeData {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _EpisodeData value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _EpisodeData() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _EpisodeData value)  $default,){
final _that = this;
switch (_that) {
case _EpisodeData():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _EpisodeData value)?  $default,){
final _that = this;
switch (_that) {
case _EpisodeData() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function(@JsonKey(name: 'episode_number')  int episodeNumber, @JsonKey(name: 'name')  String? episodeName,  String? overview, @JsonKey(name: 'still_path')  String? stillPath, @JsonKey(name: 'vote_average')  double? voteAverage, @JsonKey(name: 'runtime')  int? runtime, @JsonKey(name: 'air_date')  String? airDate)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _EpisodeData() when $default != null:
return $default(_that.episodeNumber,_that.episodeName,_that.overview,_that.stillPath,_that.voteAverage,_that.runtime,_that.airDate);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function(@JsonKey(name: 'episode_number')  int episodeNumber, @JsonKey(name: 'name')  String? episodeName,  String? overview, @JsonKey(name: 'still_path')  String? stillPath, @JsonKey(name: 'vote_average')  double? voteAverage, @JsonKey(name: 'runtime')  int? runtime, @JsonKey(name: 'air_date')  String? airDate)  $default,) {final _that = this;
switch (_that) {
case _EpisodeData():
return $default(_that.episodeNumber,_that.episodeName,_that.overview,_that.stillPath,_that.voteAverage,_that.runtime,_that.airDate);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function(@JsonKey(name: 'episode_number')  int episodeNumber, @JsonKey(name: 'name')  String? episodeName,  String? overview, @JsonKey(name: 'still_path')  String? stillPath, @JsonKey(name: 'vote_average')  double? voteAverage, @JsonKey(name: 'runtime')  int? runtime, @JsonKey(name: 'air_date')  String? airDate)?  $default,) {final _that = this;
switch (_that) {
case _EpisodeData() when $default != null:
return $default(_that.episodeNumber,_that.episodeName,_that.overview,_that.stillPath,_that.voteAverage,_that.runtime,_that.airDate);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _EpisodeData implements EpisodeData {
  const _EpisodeData({@JsonKey(name: 'episode_number') required this.episodeNumber, @JsonKey(name: 'name') this.episodeName, this.overview, @JsonKey(name: 'still_path') this.stillPath, @JsonKey(name: 'vote_average') this.voteAverage, @JsonKey(name: 'runtime') this.runtime, @JsonKey(name: 'air_date') this.airDate});
  factory _EpisodeData.fromJson(Map<String, dynamic> json) => _$EpisodeDataFromJson(json);

@override@JsonKey(name: 'episode_number') final  int episodeNumber;
@override@JsonKey(name: 'name') final  String? episodeName;
@override final  String? overview;
@override@JsonKey(name: 'still_path') final  String? stillPath;
@override@JsonKey(name: 'vote_average') final  double? voteAverage;
@override@JsonKey(name: 'runtime') final  int? runtime;
@override@JsonKey(name: 'air_date') final  String? airDate;

/// Create a copy of EpisodeData
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$EpisodeDataCopyWith<_EpisodeData> get copyWith => __$EpisodeDataCopyWithImpl<_EpisodeData>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$EpisodeDataToJson(this, );
}

@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _EpisodeData&&(identical(other.episodeNumber, episodeNumber) || other.episodeNumber == episodeNumber)&&(identical(other.episodeName, episodeName) || other.episodeName == episodeName)&&(identical(other.overview, overview) || other.overview == overview)&&(identical(other.stillPath, stillPath) || other.stillPath == stillPath)&&(identical(other.voteAverage, voteAverage) || other.voteAverage == voteAverage)&&(identical(other.runtime, runtime) || other.runtime == runtime)&&(identical(other.airDate, airDate) || other.airDate == airDate));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
    return Object.hash(runtimeType,episodeNumber,episodeName,overview,stillPath,voteAverage,runtime,airDate);
}

@override
String toString() {
    return 'EpisodeData(episodeNumber: $episodeNumber, episodeName: $episodeName, overview: $overview, stillPath: $stillPath, voteAverage: $voteAverage, runtime: $runtime, airDate: $airDate)';
}


}

/// @nodoc
abstract mixin class _$EpisodeDataCopyWith<$Res> implements $EpisodeDataCopyWith<$Res> {
  factory _$EpisodeDataCopyWith(_EpisodeData value, $Res Function(_EpisodeData) _then) = __$EpisodeDataCopyWithImpl;
@override @useResult
$Res call({
@JsonKey(name: 'episode_number') int episodeNumber,@JsonKey(name: 'name') String? episodeName, String? overview,@JsonKey(name: 'still_path') String? stillPath,@JsonKey(name: 'vote_average') double? voteAverage,@JsonKey(name: 'runtime') int? runtime,@JsonKey(name: 'air_date') String? airDate
});




}
/// @nodoc
class __$EpisodeDataCopyWithImpl<$Res>
    implements _$EpisodeDataCopyWith<$Res> {
  __$EpisodeDataCopyWithImpl(this._self, this._then);

  final _EpisodeData _self;
  final $Res Function(_EpisodeData) _then;

/// Create a copy of EpisodeData
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? episodeNumber = null,Object? episodeName = freezed,Object? overview = freezed,Object? stillPath = freezed,Object? voteAverage = freezed,Object? runtime = freezed,Object? airDate = freezed,}) {
  return _then(_EpisodeData(
episodeNumber: null == episodeNumber ? _self.episodeNumber : episodeNumber // ignore: cast_nullable_to_non_nullable
as int,episodeName: freezed == episodeName ? _self.episodeName : episodeName // ignore: cast_nullable_to_non_nullable
as String?,overview: freezed == overview ? _self.overview : overview // ignore: cast_nullable_to_non_nullable
as String?,stillPath: freezed == stillPath ? _self.stillPath : stillPath // ignore: cast_nullable_to_non_nullable
as String?,voteAverage: freezed == voteAverage ? _self.voteAverage : voteAverage // ignore: cast_nullable_to_non_nullable
as double?,runtime: freezed == runtime ? _self.runtime : runtime // ignore: cast_nullable_to_non_nullable
as int?,airDate: freezed == airDate ? _self.airDate : airDate // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}


}


/// @nodoc
mixin _$SeasonData {

 List<EpisodeData> get episodes;
/// Create a copy of SeasonData
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$SeasonDataCopyWith<SeasonData> get copyWith => _$SeasonDataCopyWithImpl<SeasonData>(this as SeasonData, _$identity);

  /// Serializes this SeasonData to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  final _this = this as SeasonData;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is SeasonData&&const DeepCollectionEquality().equals(other.episodes, _this.episodes));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
  final _this = this as SeasonData;
  return Object.hash(runtimeType,const DeepCollectionEquality().hash(_this.episodes));
}

@override
String toString() {
  final _this = this as SeasonData;
  return 'SeasonData(episodes: ${_this.episodes})';
}


}

/// @nodoc
abstract mixin class $SeasonDataCopyWith<$Res>  {
  factory $SeasonDataCopyWith(SeasonData value, $Res Function(SeasonData) _then) = _$SeasonDataCopyWithImpl;
@useResult
$Res call({
 List<EpisodeData> episodes
});




}
/// @nodoc
class _$SeasonDataCopyWithImpl<$Res>
    implements $SeasonDataCopyWith<$Res> {
  _$SeasonDataCopyWithImpl(this._self, this._then);

  final SeasonData _self;
  final $Res Function(SeasonData) _then;

/// Create a copy of SeasonData
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? episodes = null,}) {
  return _then(SeasonData(
episodes: null == episodes ? _self.episodes : episodes // ignore: cast_nullable_to_non_nullable
as List<EpisodeData>,
  ));
}

}


/// Adds pattern-matching-related methods to [SeasonData].
extension SeasonDataPatterns on SeasonData {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _SeasonData value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _SeasonData() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _SeasonData value)  $default,){
final _that = this;
switch (_that) {
case _SeasonData():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _SeasonData value)?  $default,){
final _that = this;
switch (_that) {
case _SeasonData() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( List<EpisodeData> episodes)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _SeasonData() when $default != null:
return $default(_that.episodes);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( List<EpisodeData> episodes)  $default,) {final _that = this;
switch (_that) {
case _SeasonData():
return $default(_that.episodes);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( List<EpisodeData> episodes)?  $default,) {final _that = this;
switch (_that) {
case _SeasonData() when $default != null:
return $default(_that.episodes);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _SeasonData implements SeasonData {
  const _SeasonData({required  List<EpisodeData> episodes}): _episodes = episodes;
  factory _SeasonData.fromJson(Map<String, dynamic> json) => _$SeasonDataFromJson(json);

 final  List<EpisodeData> _episodes;
@override List<EpisodeData> get episodes {
  if (_episodes is EqualUnmodifiableListView) return _episodes;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_episodes);
}


/// Create a copy of SeasonData
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$SeasonDataCopyWith<_SeasonData> get copyWith => __$SeasonDataCopyWithImpl<_SeasonData>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$SeasonDataToJson(this, );
}

@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _SeasonData&&const DeepCollectionEquality().equals(other.episodes, _episodes));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
    return Object.hash(runtimeType,const DeepCollectionEquality().hash(_episodes));
}

@override
String toString() {
    return 'SeasonData(episodes: $episodes)';
}


}

/// @nodoc
abstract mixin class _$SeasonDataCopyWith<$Res> implements $SeasonDataCopyWith<$Res> {
  factory _$SeasonDataCopyWith(_SeasonData value, $Res Function(_SeasonData) _then) = __$SeasonDataCopyWithImpl;
@override @useResult
$Res call({
 List<EpisodeData> episodes
});




}
/// @nodoc
class __$SeasonDataCopyWithImpl<$Res>
    implements _$SeasonDataCopyWith<$Res> {
  __$SeasonDataCopyWithImpl(this._self, this._then);

  final _SeasonData _self;
  final $Res Function(_SeasonData) _then;

/// Create a copy of SeasonData
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? episodes = null,}) {
  return _then(_SeasonData(
episodes: null == episodes ? _self._episodes : episodes // ignore: cast_nullable_to_non_nullable
as List<EpisodeData>,
  ));
}


}


/// @nodoc
mixin _$SeasonInfo {

@JsonKey(name: 'episode_count') int get episodeCount; int get id; String get name;@JsonKey(name: 'season_number') int get seasonNumber;@JsonKey(name: 'air_date') String? get airDate;@JsonKey(name: 'poster_path') String? get posterPath;
/// Create a copy of SeasonInfo
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$SeasonInfoCopyWith<SeasonInfo> get copyWith => _$SeasonInfoCopyWithImpl<SeasonInfo>(this as SeasonInfo, _$identity);

  /// Serializes this SeasonInfo to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  final _this = this as SeasonInfo;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is SeasonInfo&&(identical(other.episodeCount, _this.episodeCount) || other.episodeCount == _this.episodeCount)&&(identical(other.id, _this.id) || other.id == _this.id)&&(identical(other.name, _this.name) || other.name == _this.name)&&(identical(other.seasonNumber, _this.seasonNumber) || other.seasonNumber == _this.seasonNumber)&&(identical(other.airDate, _this.airDate) || other.airDate == _this.airDate)&&(identical(other.posterPath, _this.posterPath) || other.posterPath == _this.posterPath));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
  final _this = this as SeasonInfo;
  return Object.hash(runtimeType,_this.episodeCount,_this.id,_this.name,_this.seasonNumber,_this.airDate,_this.posterPath);
}

@override
String toString() {
  final _this = this as SeasonInfo;
  return 'SeasonInfo(episodeCount: ${_this.episodeCount}, id: ${_this.id}, name: ${_this.name}, seasonNumber: ${_this.seasonNumber}, airDate: ${_this.airDate}, posterPath: ${_this.posterPath})';
}


}

/// @nodoc
abstract mixin class $SeasonInfoCopyWith<$Res>  {
  factory $SeasonInfoCopyWith(SeasonInfo value, $Res Function(SeasonInfo) _then) = _$SeasonInfoCopyWithImpl;
@useResult
$Res call({
@JsonKey(name: 'episode_count') int episodeCount, int id, String name,@JsonKey(name: 'season_number') int seasonNumber,@JsonKey(name: 'air_date') String? airDate,@JsonKey(name: 'poster_path') String? posterPath
});




}
/// @nodoc
class _$SeasonInfoCopyWithImpl<$Res>
    implements $SeasonInfoCopyWith<$Res> {
  _$SeasonInfoCopyWithImpl(this._self, this._then);

  final SeasonInfo _self;
  final $Res Function(SeasonInfo) _then;

/// Create a copy of SeasonInfo
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? episodeCount = null,Object? id = null,Object? name = null,Object? seasonNumber = null,Object? airDate = freezed,Object? posterPath = freezed,}) {
  return _then(SeasonInfo(
episodeCount: null == episodeCount ? _self.episodeCount : episodeCount // ignore: cast_nullable_to_non_nullable
as int,id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as int,name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,seasonNumber: null == seasonNumber ? _self.seasonNumber : seasonNumber // ignore: cast_nullable_to_non_nullable
as int,airDate: freezed == airDate ? _self.airDate : airDate // ignore: cast_nullable_to_non_nullable
as String?,posterPath: freezed == posterPath ? _self.posterPath : posterPath // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}

}


/// Adds pattern-matching-related methods to [SeasonInfo].
extension SeasonInfoPatterns on SeasonInfo {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _SeasonInfo value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _SeasonInfo() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _SeasonInfo value)  $default,){
final _that = this;
switch (_that) {
case _SeasonInfo():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _SeasonInfo value)?  $default,){
final _that = this;
switch (_that) {
case _SeasonInfo() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function(@JsonKey(name: 'episode_count')  int episodeCount,  int id,  String name, @JsonKey(name: 'season_number')  int seasonNumber, @JsonKey(name: 'air_date')  String? airDate, @JsonKey(name: 'poster_path')  String? posterPath)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _SeasonInfo() when $default != null:
return $default(_that.episodeCount,_that.id,_that.name,_that.seasonNumber,_that.airDate,_that.posterPath);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function(@JsonKey(name: 'episode_count')  int episodeCount,  int id,  String name, @JsonKey(name: 'season_number')  int seasonNumber, @JsonKey(name: 'air_date')  String? airDate, @JsonKey(name: 'poster_path')  String? posterPath)  $default,) {final _that = this;
switch (_that) {
case _SeasonInfo():
return $default(_that.episodeCount,_that.id,_that.name,_that.seasonNumber,_that.airDate,_that.posterPath);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function(@JsonKey(name: 'episode_count')  int episodeCount,  int id,  String name, @JsonKey(name: 'season_number')  int seasonNumber, @JsonKey(name: 'air_date')  String? airDate, @JsonKey(name: 'poster_path')  String? posterPath)?  $default,) {final _that = this;
switch (_that) {
case _SeasonInfo() when $default != null:
return $default(_that.episodeCount,_that.id,_that.name,_that.seasonNumber,_that.airDate,_that.posterPath);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _SeasonInfo implements SeasonInfo {
  const _SeasonInfo({@JsonKey(name: 'episode_count') required this.episodeCount, required this.id, required this.name, @JsonKey(name: 'season_number') required this.seasonNumber, @JsonKey(name: 'air_date') this.airDate, @JsonKey(name: 'poster_path') this.posterPath});
  factory _SeasonInfo.fromJson(Map<String, dynamic> json) => _$SeasonInfoFromJson(json);

@override@JsonKey(name: 'episode_count') final  int episodeCount;
@override final  int id;
@override final  String name;
@override@JsonKey(name: 'season_number') final  int seasonNumber;
@override@JsonKey(name: 'air_date') final  String? airDate;
@override@JsonKey(name: 'poster_path') final  String? posterPath;

/// Create a copy of SeasonInfo
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$SeasonInfoCopyWith<_SeasonInfo> get copyWith => __$SeasonInfoCopyWithImpl<_SeasonInfo>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$SeasonInfoToJson(this, );
}

@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _SeasonInfo&&(identical(other.episodeCount, episodeCount) || other.episodeCount == episodeCount)&&(identical(other.id, id) || other.id == id)&&(identical(other.name, name) || other.name == name)&&(identical(other.seasonNumber, seasonNumber) || other.seasonNumber == seasonNumber)&&(identical(other.airDate, airDate) || other.airDate == airDate)&&(identical(other.posterPath, posterPath) || other.posterPath == posterPath));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
    return Object.hash(runtimeType,episodeCount,id,name,seasonNumber,airDate,posterPath);
}

@override
String toString() {
    return 'SeasonInfo(episodeCount: $episodeCount, id: $id, name: $name, seasonNumber: $seasonNumber, airDate: $airDate, posterPath: $posterPath)';
}


}

/// @nodoc
abstract mixin class _$SeasonInfoCopyWith<$Res> implements $SeasonInfoCopyWith<$Res> {
  factory _$SeasonInfoCopyWith(_SeasonInfo value, $Res Function(_SeasonInfo) _then) = __$SeasonInfoCopyWithImpl;
@override @useResult
$Res call({
@JsonKey(name: 'episode_count') int episodeCount, int id, String name,@JsonKey(name: 'season_number') int seasonNumber,@JsonKey(name: 'air_date') String? airDate,@JsonKey(name: 'poster_path') String? posterPath
});




}
/// @nodoc
class __$SeasonInfoCopyWithImpl<$Res>
    implements _$SeasonInfoCopyWith<$Res> {
  __$SeasonInfoCopyWithImpl(this._self, this._then);

  final _SeasonInfo _self;
  final $Res Function(_SeasonInfo) _then;

/// Create a copy of SeasonInfo
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? episodeCount = null,Object? id = null,Object? name = null,Object? seasonNumber = null,Object? airDate = freezed,Object? posterPath = freezed,}) {
  return _then(_SeasonInfo(
episodeCount: null == episodeCount ? _self.episodeCount : episodeCount // ignore: cast_nullable_to_non_nullable
as int,id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as int,name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,seasonNumber: null == seasonNumber ? _self.seasonNumber : seasonNumber // ignore: cast_nullable_to_non_nullable
as int,airDate: freezed == airDate ? _self.airDate : airDate // ignore: cast_nullable_to_non_nullable
as String?,posterPath: freezed == posterPath ? _self.posterPath : posterPath // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}


}


/// @nodoc
mixin _$SeriesInfo {

@JsonKey(name: 'number_of_seasons') int get numberOfSeasons; List<SeasonInfo> get seasons;
/// Create a copy of SeriesInfo
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$SeriesInfoCopyWith<SeriesInfo> get copyWith => _$SeriesInfoCopyWithImpl<SeriesInfo>(this as SeriesInfo, _$identity);

  /// Serializes this SeriesInfo to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  final _this = this as SeriesInfo;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is SeriesInfo&&(identical(other.numberOfSeasons, _this.numberOfSeasons) || other.numberOfSeasons == _this.numberOfSeasons)&&const DeepCollectionEquality().equals(other.seasons, _this.seasons));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
  final _this = this as SeriesInfo;
  return Object.hash(runtimeType,_this.numberOfSeasons,const DeepCollectionEquality().hash(_this.seasons));
}

@override
String toString() {
  final _this = this as SeriesInfo;
  return 'SeriesInfo(numberOfSeasons: ${_this.numberOfSeasons}, seasons: ${_this.seasons})';
}


}

/// @nodoc
abstract mixin class $SeriesInfoCopyWith<$Res>  {
  factory $SeriesInfoCopyWith(SeriesInfo value, $Res Function(SeriesInfo) _then) = _$SeriesInfoCopyWithImpl;
@useResult
$Res call({
@JsonKey(name: 'number_of_seasons') int numberOfSeasons, List<SeasonInfo> seasons
});




}
/// @nodoc
class _$SeriesInfoCopyWithImpl<$Res>
    implements $SeriesInfoCopyWith<$Res> {
  _$SeriesInfoCopyWithImpl(this._self, this._then);

  final SeriesInfo _self;
  final $Res Function(SeriesInfo) _then;

/// Create a copy of SeriesInfo
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? numberOfSeasons = null,Object? seasons = null,}) {
  return _then(SeriesInfo(
numberOfSeasons: null == numberOfSeasons ? _self.numberOfSeasons : numberOfSeasons // ignore: cast_nullable_to_non_nullable
as int,seasons: null == seasons ? _self.seasons : seasons // ignore: cast_nullable_to_non_nullable
as List<SeasonInfo>,
  ));
}

}


/// Adds pattern-matching-related methods to [SeriesInfo].
extension SeriesInfoPatterns on SeriesInfo {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _SeriesInfo value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _SeriesInfo() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _SeriesInfo value)  $default,){
final _that = this;
switch (_that) {
case _SeriesInfo():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _SeriesInfo value)?  $default,){
final _that = this;
switch (_that) {
case _SeriesInfo() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function(@JsonKey(name: 'number_of_seasons')  int numberOfSeasons,  List<SeasonInfo> seasons)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _SeriesInfo() when $default != null:
return $default(_that.numberOfSeasons,_that.seasons);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function(@JsonKey(name: 'number_of_seasons')  int numberOfSeasons,  List<SeasonInfo> seasons)  $default,) {final _that = this;
switch (_that) {
case _SeriesInfo():
return $default(_that.numberOfSeasons,_that.seasons);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function(@JsonKey(name: 'number_of_seasons')  int numberOfSeasons,  List<SeasonInfo> seasons)?  $default,) {final _that = this;
switch (_that) {
case _SeriesInfo() when $default != null:
return $default(_that.numberOfSeasons,_that.seasons);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _SeriesInfo implements SeriesInfo {
  const _SeriesInfo({@JsonKey(name: 'number_of_seasons') required this.numberOfSeasons, required  List<SeasonInfo> seasons}): _seasons = seasons;
  factory _SeriesInfo.fromJson(Map<String, dynamic> json) => _$SeriesInfoFromJson(json);

@override@JsonKey(name: 'number_of_seasons') final  int numberOfSeasons;
 final  List<SeasonInfo> _seasons;
@override List<SeasonInfo> get seasons {
  if (_seasons is EqualUnmodifiableListView) return _seasons;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_seasons);
}


/// Create a copy of SeriesInfo
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$SeriesInfoCopyWith<_SeriesInfo> get copyWith => __$SeriesInfoCopyWithImpl<_SeriesInfo>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$SeriesInfoToJson(this, );
}

@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _SeriesInfo&&(identical(other.numberOfSeasons, numberOfSeasons) || other.numberOfSeasons == numberOfSeasons)&&const DeepCollectionEquality().equals(other.seasons, _seasons));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
    return Object.hash(runtimeType,numberOfSeasons,const DeepCollectionEquality().hash(_seasons));
}

@override
String toString() {
    return 'SeriesInfo(numberOfSeasons: $numberOfSeasons, seasons: $seasons)';
}


}

/// @nodoc
abstract mixin class _$SeriesInfoCopyWith<$Res> implements $SeriesInfoCopyWith<$Res> {
  factory _$SeriesInfoCopyWith(_SeriesInfo value, $Res Function(_SeriesInfo) _then) = __$SeriesInfoCopyWithImpl;
@override @useResult
$Res call({
@JsonKey(name: 'number_of_seasons') int numberOfSeasons, List<SeasonInfo> seasons
});




}
/// @nodoc
class __$SeriesInfoCopyWithImpl<$Res>
    implements _$SeriesInfoCopyWith<$Res> {
  __$SeriesInfoCopyWithImpl(this._self, this._then);

  final _SeriesInfo _self;
  final $Res Function(_SeriesInfo) _then;

/// Create a copy of SeriesInfo
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? numberOfSeasons = null,Object? seasons = null,}) {
  return _then(_SeriesInfo(
numberOfSeasons: null == numberOfSeasons ? _self.numberOfSeasons : numberOfSeasons // ignore: cast_nullable_to_non_nullable
as int,seasons: null == seasons ? _self._seasons : seasons // ignore: cast_nullable_to_non_nullable
as List<SeasonInfo>,
  ));
}


}

// dart format on
