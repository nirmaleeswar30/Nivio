// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'season_info.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

T _$identity<T>(T value) => value;

final _privateConstructorUsedError = UnsupportedError(
  'It seems like you constructed your class using `MyClass._()`. This constructor is only meant to be used by freezed and you are not supposed to need it nor use it.\nPlease check the documentation here for more information: https://github.com/rrousselGit/freezed#adding-getters-and-methods-to-our-models',
);

EpisodeData _$EpisodeDataFromJson(Map<String, dynamic> json) {
  return _EpisodeData.fromJson(json);
}

/// @nodoc
mixin _$EpisodeData {
  @JsonKey(name: 'episode_number')
  int get episodeNumber => throw _privateConstructorUsedError;
  @JsonKey(name: 'name')
  String? get episodeName => throw _privateConstructorUsedError;
  String? get overview => throw _privateConstructorUsedError;
  @JsonKey(name: 'still_path')
  String? get stillPath => throw _privateConstructorUsedError;
  @JsonKey(name: 'vote_average')
  double? get voteAverage => throw _privateConstructorUsedError;
  @JsonKey(name: 'runtime')
  int? get runtime => throw _privateConstructorUsedError;
  @JsonKey(name: 'air_date')
  String? get airDate => throw _privateConstructorUsedError;

  /// Serializes this EpisodeData to a JSON map.
  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;

  /// Create a copy of EpisodeData
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $EpisodeDataCopyWith<EpisodeData> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $EpisodeDataCopyWith<$Res> {
  factory $EpisodeDataCopyWith(
    EpisodeData value,
    $Res Function(EpisodeData) then,
  ) = _$EpisodeDataCopyWithImpl<$Res, EpisodeData>;
  @useResult
  $Res call({
    @JsonKey(name: 'episode_number') int episodeNumber,
    @JsonKey(name: 'name') String? episodeName,
    String? overview,
    @JsonKey(name: 'still_path') String? stillPath,
    @JsonKey(name: 'vote_average') double? voteAverage,
    @JsonKey(name: 'runtime') int? runtime,
    @JsonKey(name: 'air_date') String? airDate,
  });
}

/// @nodoc
class _$EpisodeDataCopyWithImpl<$Res, $Val extends EpisodeData>
    implements $EpisodeDataCopyWith<$Res> {
  _$EpisodeDataCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of EpisodeData
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? episodeNumber = null,
    Object? episodeName = freezed,
    Object? overview = freezed,
    Object? stillPath = freezed,
    Object? voteAverage = freezed,
    Object? runtime = freezed,
    Object? airDate = freezed,
  }) {
    return _then(
      _value.copyWith(
            episodeNumber: null == episodeNumber
                ? _value.episodeNumber
                : episodeNumber // ignore: cast_nullable_to_non_nullable
                      as int,
            episodeName: freezed == episodeName
                ? _value.episodeName
                : episodeName // ignore: cast_nullable_to_non_nullable
                      as String?,
            overview: freezed == overview
                ? _value.overview
                : overview // ignore: cast_nullable_to_non_nullable
                      as String?,
            stillPath: freezed == stillPath
                ? _value.stillPath
                : stillPath // ignore: cast_nullable_to_non_nullable
                      as String?,
            voteAverage: freezed == voteAverage
                ? _value.voteAverage
                : voteAverage // ignore: cast_nullable_to_non_nullable
                      as double?,
            runtime: freezed == runtime
                ? _value.runtime
                : runtime // ignore: cast_nullable_to_non_nullable
                      as int?,
            airDate: freezed == airDate
                ? _value.airDate
                : airDate // ignore: cast_nullable_to_non_nullable
                      as String?,
          )
          as $Val,
    );
  }
}

/// @nodoc
abstract class _$$EpisodeDataImplCopyWith<$Res>
    implements $EpisodeDataCopyWith<$Res> {
  factory _$$EpisodeDataImplCopyWith(
    _$EpisodeDataImpl value,
    $Res Function(_$EpisodeDataImpl) then,
  ) = __$$EpisodeDataImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call({
    @JsonKey(name: 'episode_number') int episodeNumber,
    @JsonKey(name: 'name') String? episodeName,
    String? overview,
    @JsonKey(name: 'still_path') String? stillPath,
    @JsonKey(name: 'vote_average') double? voteAverage,
    @JsonKey(name: 'runtime') int? runtime,
    @JsonKey(name: 'air_date') String? airDate,
  });
}

/// @nodoc
class __$$EpisodeDataImplCopyWithImpl<$Res>
    extends _$EpisodeDataCopyWithImpl<$Res, _$EpisodeDataImpl>
    implements _$$EpisodeDataImplCopyWith<$Res> {
  __$$EpisodeDataImplCopyWithImpl(
    _$EpisodeDataImpl _value,
    $Res Function(_$EpisodeDataImpl) _then,
  ) : super(_value, _then);

  /// Create a copy of EpisodeData
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? episodeNumber = null,
    Object? episodeName = freezed,
    Object? overview = freezed,
    Object? stillPath = freezed,
    Object? voteAverage = freezed,
    Object? runtime = freezed,
    Object? airDate = freezed,
  }) {
    return _then(
      _$EpisodeDataImpl(
        episodeNumber: null == episodeNumber
            ? _value.episodeNumber
            : episodeNumber // ignore: cast_nullable_to_non_nullable
                  as int,
        episodeName: freezed == episodeName
            ? _value.episodeName
            : episodeName // ignore: cast_nullable_to_non_nullable
                  as String?,
        overview: freezed == overview
            ? _value.overview
            : overview // ignore: cast_nullable_to_non_nullable
                  as String?,
        stillPath: freezed == stillPath
            ? _value.stillPath
            : stillPath // ignore: cast_nullable_to_non_nullable
                  as String?,
        voteAverage: freezed == voteAverage
            ? _value.voteAverage
            : voteAverage // ignore: cast_nullable_to_non_nullable
                  as double?,
        runtime: freezed == runtime
            ? _value.runtime
            : runtime // ignore: cast_nullable_to_non_nullable
                  as int?,
        airDate: freezed == airDate
            ? _value.airDate
            : airDate // ignore: cast_nullable_to_non_nullable
                  as String?,
      ),
    );
  }
}

/// @nodoc
@JsonSerializable()
class _$EpisodeDataImpl implements _EpisodeData {
  const _$EpisodeDataImpl({
    @JsonKey(name: 'episode_number') required this.episodeNumber,
    @JsonKey(name: 'name') this.episodeName,
    this.overview,
    @JsonKey(name: 'still_path') this.stillPath,
    @JsonKey(name: 'vote_average') this.voteAverage,
    @JsonKey(name: 'runtime') this.runtime,
    @JsonKey(name: 'air_date') this.airDate,
  });

  factory _$EpisodeDataImpl.fromJson(Map<String, dynamic> json) =>
      _$$EpisodeDataImplFromJson(json);

  @override
  @JsonKey(name: 'episode_number')
  final int episodeNumber;
  @override
  @JsonKey(name: 'name')
  final String? episodeName;
  @override
  final String? overview;
  @override
  @JsonKey(name: 'still_path')
  final String? stillPath;
  @override
  @JsonKey(name: 'vote_average')
  final double? voteAverage;
  @override
  @JsonKey(name: 'runtime')
  final int? runtime;
  @override
  @JsonKey(name: 'air_date')
  final String? airDate;

  @override
  String toString() {
    return 'EpisodeData(episodeNumber: $episodeNumber, episodeName: $episodeName, overview: $overview, stillPath: $stillPath, voteAverage: $voteAverage, runtime: $runtime, airDate: $airDate)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$EpisodeDataImpl &&
            (identical(other.episodeNumber, episodeNumber) ||
                other.episodeNumber == episodeNumber) &&
            (identical(other.episodeName, episodeName) ||
                other.episodeName == episodeName) &&
            (identical(other.overview, overview) ||
                other.overview == overview) &&
            (identical(other.stillPath, stillPath) ||
                other.stillPath == stillPath) &&
            (identical(other.voteAverage, voteAverage) ||
                other.voteAverage == voteAverage) &&
            (identical(other.runtime, runtime) || other.runtime == runtime) &&
            (identical(other.airDate, airDate) || other.airDate == airDate));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode => Object.hash(
    runtimeType,
    episodeNumber,
    episodeName,
    overview,
    stillPath,
    voteAverage,
    runtime,
    airDate,
  );

  /// Create a copy of EpisodeData
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$EpisodeDataImplCopyWith<_$EpisodeDataImpl> get copyWith =>
      __$$EpisodeDataImplCopyWithImpl<_$EpisodeDataImpl>(this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$$EpisodeDataImplToJson(this);
  }
}

abstract class _EpisodeData implements EpisodeData {
  const factory _EpisodeData({
    @JsonKey(name: 'episode_number') required final int episodeNumber,
    @JsonKey(name: 'name') final String? episodeName,
    final String? overview,
    @JsonKey(name: 'still_path') final String? stillPath,
    @JsonKey(name: 'vote_average') final double? voteAverage,
    @JsonKey(name: 'runtime') final int? runtime,
    @JsonKey(name: 'air_date') final String? airDate,
  }) = _$EpisodeDataImpl;

  factory _EpisodeData.fromJson(Map<String, dynamic> json) =
      _$EpisodeDataImpl.fromJson;

  @override
  @JsonKey(name: 'episode_number')
  int get episodeNumber;
  @override
  @JsonKey(name: 'name')
  String? get episodeName;
  @override
  String? get overview;
  @override
  @JsonKey(name: 'still_path')
  String? get stillPath;
  @override
  @JsonKey(name: 'vote_average')
  double? get voteAverage;
  @override
  @JsonKey(name: 'runtime')
  int? get runtime;
  @override
  @JsonKey(name: 'air_date')
  String? get airDate;

  /// Create a copy of EpisodeData
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$EpisodeDataImplCopyWith<_$EpisodeDataImpl> get copyWith =>
      throw _privateConstructorUsedError;
}

SeasonData _$SeasonDataFromJson(Map<String, dynamic> json) {
  return _SeasonData.fromJson(json);
}

/// @nodoc
mixin _$SeasonData {
  List<EpisodeData> get episodes => throw _privateConstructorUsedError;

  /// Serializes this SeasonData to a JSON map.
  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;

  /// Create a copy of SeasonData
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $SeasonDataCopyWith<SeasonData> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $SeasonDataCopyWith<$Res> {
  factory $SeasonDataCopyWith(
    SeasonData value,
    $Res Function(SeasonData) then,
  ) = _$SeasonDataCopyWithImpl<$Res, SeasonData>;
  @useResult
  $Res call({List<EpisodeData> episodes});
}

/// @nodoc
class _$SeasonDataCopyWithImpl<$Res, $Val extends SeasonData>
    implements $SeasonDataCopyWith<$Res> {
  _$SeasonDataCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of SeasonData
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({Object? episodes = null}) {
    return _then(
      _value.copyWith(
            episodes: null == episodes
                ? _value.episodes
                : episodes // ignore: cast_nullable_to_non_nullable
                      as List<EpisodeData>,
          )
          as $Val,
    );
  }
}

/// @nodoc
abstract class _$$SeasonDataImplCopyWith<$Res>
    implements $SeasonDataCopyWith<$Res> {
  factory _$$SeasonDataImplCopyWith(
    _$SeasonDataImpl value,
    $Res Function(_$SeasonDataImpl) then,
  ) = __$$SeasonDataImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call({List<EpisodeData> episodes});
}

/// @nodoc
class __$$SeasonDataImplCopyWithImpl<$Res>
    extends _$SeasonDataCopyWithImpl<$Res, _$SeasonDataImpl>
    implements _$$SeasonDataImplCopyWith<$Res> {
  __$$SeasonDataImplCopyWithImpl(
    _$SeasonDataImpl _value,
    $Res Function(_$SeasonDataImpl) _then,
  ) : super(_value, _then);

  /// Create a copy of SeasonData
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({Object? episodes = null}) {
    return _then(
      _$SeasonDataImpl(
        episodes: null == episodes
            ? _value._episodes
            : episodes // ignore: cast_nullable_to_non_nullable
                  as List<EpisodeData>,
      ),
    );
  }
}

/// @nodoc
@JsonSerializable()
class _$SeasonDataImpl implements _SeasonData {
  const _$SeasonDataImpl({required final List<EpisodeData> episodes})
    : _episodes = episodes;

  factory _$SeasonDataImpl.fromJson(Map<String, dynamic> json) =>
      _$$SeasonDataImplFromJson(json);

  final List<EpisodeData> _episodes;
  @override
  List<EpisodeData> get episodes {
    if (_episodes is EqualUnmodifiableListView) return _episodes;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableListView(_episodes);
  }

  @override
  String toString() {
    return 'SeasonData(episodes: $episodes)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$SeasonDataImpl &&
            const DeepCollectionEquality().equals(other._episodes, _episodes));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode =>
      Object.hash(runtimeType, const DeepCollectionEquality().hash(_episodes));

  /// Create a copy of SeasonData
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$SeasonDataImplCopyWith<_$SeasonDataImpl> get copyWith =>
      __$$SeasonDataImplCopyWithImpl<_$SeasonDataImpl>(this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$$SeasonDataImplToJson(this);
  }
}

abstract class _SeasonData implements SeasonData {
  const factory _SeasonData({required final List<EpisodeData> episodes}) =
      _$SeasonDataImpl;

  factory _SeasonData.fromJson(Map<String, dynamic> json) =
      _$SeasonDataImpl.fromJson;

  @override
  List<EpisodeData> get episodes;

  /// Create a copy of SeasonData
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$SeasonDataImplCopyWith<_$SeasonDataImpl> get copyWith =>
      throw _privateConstructorUsedError;
}

SeasonInfo _$SeasonInfoFromJson(Map<String, dynamic> json) {
  return _SeasonInfo.fromJson(json);
}

/// @nodoc
mixin _$SeasonInfo {
  @JsonKey(name: 'episode_count')
  int get episodeCount => throw _privateConstructorUsedError;
  int get id => throw _privateConstructorUsedError;
  String get name => throw _privateConstructorUsedError;
  @JsonKey(name: 'season_number')
  int get seasonNumber => throw _privateConstructorUsedError;
  @JsonKey(name: 'air_date')
  String? get airDate => throw _privateConstructorUsedError;
  @JsonKey(name: 'poster_path')
  String? get posterPath => throw _privateConstructorUsedError;

  /// Serializes this SeasonInfo to a JSON map.
  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;

  /// Create a copy of SeasonInfo
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $SeasonInfoCopyWith<SeasonInfo> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $SeasonInfoCopyWith<$Res> {
  factory $SeasonInfoCopyWith(
    SeasonInfo value,
    $Res Function(SeasonInfo) then,
  ) = _$SeasonInfoCopyWithImpl<$Res, SeasonInfo>;
  @useResult
  $Res call({
    @JsonKey(name: 'episode_count') int episodeCount,
    int id,
    String name,
    @JsonKey(name: 'season_number') int seasonNumber,
    @JsonKey(name: 'air_date') String? airDate,
    @JsonKey(name: 'poster_path') String? posterPath,
  });
}

/// @nodoc
class _$SeasonInfoCopyWithImpl<$Res, $Val extends SeasonInfo>
    implements $SeasonInfoCopyWith<$Res> {
  _$SeasonInfoCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of SeasonInfo
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? episodeCount = null,
    Object? id = null,
    Object? name = null,
    Object? seasonNumber = null,
    Object? airDate = freezed,
    Object? posterPath = freezed,
  }) {
    return _then(
      _value.copyWith(
            episodeCount: null == episodeCount
                ? _value.episodeCount
                : episodeCount // ignore: cast_nullable_to_non_nullable
                      as int,
            id: null == id
                ? _value.id
                : id // ignore: cast_nullable_to_non_nullable
                      as int,
            name: null == name
                ? _value.name
                : name // ignore: cast_nullable_to_non_nullable
                      as String,
            seasonNumber: null == seasonNumber
                ? _value.seasonNumber
                : seasonNumber // ignore: cast_nullable_to_non_nullable
                      as int,
            airDate: freezed == airDate
                ? _value.airDate
                : airDate // ignore: cast_nullable_to_non_nullable
                      as String?,
            posterPath: freezed == posterPath
                ? _value.posterPath
                : posterPath // ignore: cast_nullable_to_non_nullable
                      as String?,
          )
          as $Val,
    );
  }
}

/// @nodoc
abstract class _$$SeasonInfoImplCopyWith<$Res>
    implements $SeasonInfoCopyWith<$Res> {
  factory _$$SeasonInfoImplCopyWith(
    _$SeasonInfoImpl value,
    $Res Function(_$SeasonInfoImpl) then,
  ) = __$$SeasonInfoImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call({
    @JsonKey(name: 'episode_count') int episodeCount,
    int id,
    String name,
    @JsonKey(name: 'season_number') int seasonNumber,
    @JsonKey(name: 'air_date') String? airDate,
    @JsonKey(name: 'poster_path') String? posterPath,
  });
}

/// @nodoc
class __$$SeasonInfoImplCopyWithImpl<$Res>
    extends _$SeasonInfoCopyWithImpl<$Res, _$SeasonInfoImpl>
    implements _$$SeasonInfoImplCopyWith<$Res> {
  __$$SeasonInfoImplCopyWithImpl(
    _$SeasonInfoImpl _value,
    $Res Function(_$SeasonInfoImpl) _then,
  ) : super(_value, _then);

  /// Create a copy of SeasonInfo
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? episodeCount = null,
    Object? id = null,
    Object? name = null,
    Object? seasonNumber = null,
    Object? airDate = freezed,
    Object? posterPath = freezed,
  }) {
    return _then(
      _$SeasonInfoImpl(
        episodeCount: null == episodeCount
            ? _value.episodeCount
            : episodeCount // ignore: cast_nullable_to_non_nullable
                  as int,
        id: null == id
            ? _value.id
            : id // ignore: cast_nullable_to_non_nullable
                  as int,
        name: null == name
            ? _value.name
            : name // ignore: cast_nullable_to_non_nullable
                  as String,
        seasonNumber: null == seasonNumber
            ? _value.seasonNumber
            : seasonNumber // ignore: cast_nullable_to_non_nullable
                  as int,
        airDate: freezed == airDate
            ? _value.airDate
            : airDate // ignore: cast_nullable_to_non_nullable
                  as String?,
        posterPath: freezed == posterPath
            ? _value.posterPath
            : posterPath // ignore: cast_nullable_to_non_nullable
                  as String?,
      ),
    );
  }
}

/// @nodoc
@JsonSerializable()
class _$SeasonInfoImpl implements _SeasonInfo {
  const _$SeasonInfoImpl({
    @JsonKey(name: 'episode_count') required this.episodeCount,
    required this.id,
    required this.name,
    @JsonKey(name: 'season_number') required this.seasonNumber,
    @JsonKey(name: 'air_date') this.airDate,
    @JsonKey(name: 'poster_path') this.posterPath,
  });

  factory _$SeasonInfoImpl.fromJson(Map<String, dynamic> json) =>
      _$$SeasonInfoImplFromJson(json);

  @override
  @JsonKey(name: 'episode_count')
  final int episodeCount;
  @override
  final int id;
  @override
  final String name;
  @override
  @JsonKey(name: 'season_number')
  final int seasonNumber;
  @override
  @JsonKey(name: 'air_date')
  final String? airDate;
  @override
  @JsonKey(name: 'poster_path')
  final String? posterPath;

  @override
  String toString() {
    return 'SeasonInfo(episodeCount: $episodeCount, id: $id, name: $name, seasonNumber: $seasonNumber, airDate: $airDate, posterPath: $posterPath)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$SeasonInfoImpl &&
            (identical(other.episodeCount, episodeCount) ||
                other.episodeCount == episodeCount) &&
            (identical(other.id, id) || other.id == id) &&
            (identical(other.name, name) || other.name == name) &&
            (identical(other.seasonNumber, seasonNumber) ||
                other.seasonNumber == seasonNumber) &&
            (identical(other.airDate, airDate) || other.airDate == airDate) &&
            (identical(other.posterPath, posterPath) ||
                other.posterPath == posterPath));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode => Object.hash(
    runtimeType,
    episodeCount,
    id,
    name,
    seasonNumber,
    airDate,
    posterPath,
  );

  /// Create a copy of SeasonInfo
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$SeasonInfoImplCopyWith<_$SeasonInfoImpl> get copyWith =>
      __$$SeasonInfoImplCopyWithImpl<_$SeasonInfoImpl>(this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$$SeasonInfoImplToJson(this);
  }
}

abstract class _SeasonInfo implements SeasonInfo {
  const factory _SeasonInfo({
    @JsonKey(name: 'episode_count') required final int episodeCount,
    required final int id,
    required final String name,
    @JsonKey(name: 'season_number') required final int seasonNumber,
    @JsonKey(name: 'air_date') final String? airDate,
    @JsonKey(name: 'poster_path') final String? posterPath,
  }) = _$SeasonInfoImpl;

  factory _SeasonInfo.fromJson(Map<String, dynamic> json) =
      _$SeasonInfoImpl.fromJson;

  @override
  @JsonKey(name: 'episode_count')
  int get episodeCount;
  @override
  int get id;
  @override
  String get name;
  @override
  @JsonKey(name: 'season_number')
  int get seasonNumber;
  @override
  @JsonKey(name: 'air_date')
  String? get airDate;
  @override
  @JsonKey(name: 'poster_path')
  String? get posterPath;

  /// Create a copy of SeasonInfo
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$SeasonInfoImplCopyWith<_$SeasonInfoImpl> get copyWith =>
      throw _privateConstructorUsedError;
}

SeriesInfo _$SeriesInfoFromJson(Map<String, dynamic> json) {
  return _SeriesInfo.fromJson(json);
}

/// @nodoc
mixin _$SeriesInfo {
  @JsonKey(name: 'number_of_seasons')
  int get numberOfSeasons => throw _privateConstructorUsedError;
  List<SeasonInfo> get seasons => throw _privateConstructorUsedError;

  /// Serializes this SeriesInfo to a JSON map.
  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;

  /// Create a copy of SeriesInfo
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $SeriesInfoCopyWith<SeriesInfo> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $SeriesInfoCopyWith<$Res> {
  factory $SeriesInfoCopyWith(
    SeriesInfo value,
    $Res Function(SeriesInfo) then,
  ) = _$SeriesInfoCopyWithImpl<$Res, SeriesInfo>;
  @useResult
  $Res call({
    @JsonKey(name: 'number_of_seasons') int numberOfSeasons,
    List<SeasonInfo> seasons,
  });
}

/// @nodoc
class _$SeriesInfoCopyWithImpl<$Res, $Val extends SeriesInfo>
    implements $SeriesInfoCopyWith<$Res> {
  _$SeriesInfoCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of SeriesInfo
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({Object? numberOfSeasons = null, Object? seasons = null}) {
    return _then(
      _value.copyWith(
            numberOfSeasons: null == numberOfSeasons
                ? _value.numberOfSeasons
                : numberOfSeasons // ignore: cast_nullable_to_non_nullable
                      as int,
            seasons: null == seasons
                ? _value.seasons
                : seasons // ignore: cast_nullable_to_non_nullable
                      as List<SeasonInfo>,
          )
          as $Val,
    );
  }
}

/// @nodoc
abstract class _$$SeriesInfoImplCopyWith<$Res>
    implements $SeriesInfoCopyWith<$Res> {
  factory _$$SeriesInfoImplCopyWith(
    _$SeriesInfoImpl value,
    $Res Function(_$SeriesInfoImpl) then,
  ) = __$$SeriesInfoImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call({
    @JsonKey(name: 'number_of_seasons') int numberOfSeasons,
    List<SeasonInfo> seasons,
  });
}

/// @nodoc
class __$$SeriesInfoImplCopyWithImpl<$Res>
    extends _$SeriesInfoCopyWithImpl<$Res, _$SeriesInfoImpl>
    implements _$$SeriesInfoImplCopyWith<$Res> {
  __$$SeriesInfoImplCopyWithImpl(
    _$SeriesInfoImpl _value,
    $Res Function(_$SeriesInfoImpl) _then,
  ) : super(_value, _then);

  /// Create a copy of SeriesInfo
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({Object? numberOfSeasons = null, Object? seasons = null}) {
    return _then(
      _$SeriesInfoImpl(
        numberOfSeasons: null == numberOfSeasons
            ? _value.numberOfSeasons
            : numberOfSeasons // ignore: cast_nullable_to_non_nullable
                  as int,
        seasons: null == seasons
            ? _value._seasons
            : seasons // ignore: cast_nullable_to_non_nullable
                  as List<SeasonInfo>,
      ),
    );
  }
}

/// @nodoc
@JsonSerializable()
class _$SeriesInfoImpl implements _SeriesInfo {
  const _$SeriesInfoImpl({
    @JsonKey(name: 'number_of_seasons') required this.numberOfSeasons,
    required final List<SeasonInfo> seasons,
  }) : _seasons = seasons;

  factory _$SeriesInfoImpl.fromJson(Map<String, dynamic> json) =>
      _$$SeriesInfoImplFromJson(json);

  @override
  @JsonKey(name: 'number_of_seasons')
  final int numberOfSeasons;
  final List<SeasonInfo> _seasons;
  @override
  List<SeasonInfo> get seasons {
    if (_seasons is EqualUnmodifiableListView) return _seasons;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableListView(_seasons);
  }

  @override
  String toString() {
    return 'SeriesInfo(numberOfSeasons: $numberOfSeasons, seasons: $seasons)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$SeriesInfoImpl &&
            (identical(other.numberOfSeasons, numberOfSeasons) ||
                other.numberOfSeasons == numberOfSeasons) &&
            const DeepCollectionEquality().equals(other._seasons, _seasons));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode => Object.hash(
    runtimeType,
    numberOfSeasons,
    const DeepCollectionEquality().hash(_seasons),
  );

  /// Create a copy of SeriesInfo
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$SeriesInfoImplCopyWith<_$SeriesInfoImpl> get copyWith =>
      __$$SeriesInfoImplCopyWithImpl<_$SeriesInfoImpl>(this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$$SeriesInfoImplToJson(this);
  }
}

abstract class _SeriesInfo implements SeriesInfo {
  const factory _SeriesInfo({
    @JsonKey(name: 'number_of_seasons') required final int numberOfSeasons,
    required final List<SeasonInfo> seasons,
  }) = _$SeriesInfoImpl;

  factory _SeriesInfo.fromJson(Map<String, dynamic> json) =
      _$SeriesInfoImpl.fromJson;

  @override
  @JsonKey(name: 'number_of_seasons')
  int get numberOfSeasons;
  @override
  List<SeasonInfo> get seasons;

  /// Create a copy of SeriesInfo
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$SeriesInfoImplCopyWith<_$SeriesInfoImpl> get copyWith =>
      throw _privateConstructorUsedError;
}
