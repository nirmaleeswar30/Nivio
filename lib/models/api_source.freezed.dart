// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'api_source.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

T _$identity<T>(T value) => value;

final _privateConstructorUsedError = UnsupportedError(
    'It seems like you constructed your class using `MyClass._()`. This constructor is only meant to be used by freezed and you are not supposed to need it nor use it.\nPlease check the documentation here for more information: https://github.com/rrousselGit/freezed#adding-getters-and-methods-to-our-models');

SubtitleTrack _$SubtitleTrackFromJson(Map<String, dynamic> json) {
  return _SubtitleTrack.fromJson(json);
}

/// @nodoc
mixin _$SubtitleTrack {
  String? get url => throw _privateConstructorUsedError;
  String? get file => throw _privateConstructorUsedError;
  String? get lang => throw _privateConstructorUsedError;
  String? get language => throw _privateConstructorUsedError;

  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;
  @JsonKey(ignore: true)
  $SubtitleTrackCopyWith<SubtitleTrack> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $SubtitleTrackCopyWith<$Res> {
  factory $SubtitleTrackCopyWith(
          SubtitleTrack value, $Res Function(SubtitleTrack) then) =
      _$SubtitleTrackCopyWithImpl<$Res, SubtitleTrack>;
  @useResult
  $Res call({String? url, String? file, String? lang, String? language});
}

/// @nodoc
class _$SubtitleTrackCopyWithImpl<$Res, $Val extends SubtitleTrack>
    implements $SubtitleTrackCopyWith<$Res> {
  _$SubtitleTrackCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? url = freezed,
    Object? file = freezed,
    Object? lang = freezed,
    Object? language = freezed,
  }) {
    return _then(_value.copyWith(
      url: freezed == url
          ? _value.url
          : url // ignore: cast_nullable_to_non_nullable
              as String?,
      file: freezed == file
          ? _value.file
          : file // ignore: cast_nullable_to_non_nullable
              as String?,
      lang: freezed == lang
          ? _value.lang
          : lang // ignore: cast_nullable_to_non_nullable
              as String?,
      language: freezed == language
          ? _value.language
          : language // ignore: cast_nullable_to_non_nullable
              as String?,
    ) as $Val);
  }
}

/// @nodoc
abstract class _$$SubtitleTrackImplCopyWith<$Res>
    implements $SubtitleTrackCopyWith<$Res> {
  factory _$$SubtitleTrackImplCopyWith(
          _$SubtitleTrackImpl value, $Res Function(_$SubtitleTrackImpl) then) =
      __$$SubtitleTrackImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call({String? url, String? file, String? lang, String? language});
}

/// @nodoc
class __$$SubtitleTrackImplCopyWithImpl<$Res>
    extends _$SubtitleTrackCopyWithImpl<$Res, _$SubtitleTrackImpl>
    implements _$$SubtitleTrackImplCopyWith<$Res> {
  __$$SubtitleTrackImplCopyWithImpl(
      _$SubtitleTrackImpl _value, $Res Function(_$SubtitleTrackImpl) _then)
      : super(_value, _then);

  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? url = freezed,
    Object? file = freezed,
    Object? lang = freezed,
    Object? language = freezed,
  }) {
    return _then(_$SubtitleTrackImpl(
      url: freezed == url
          ? _value.url
          : url // ignore: cast_nullable_to_non_nullable
              as String?,
      file: freezed == file
          ? _value.file
          : file // ignore: cast_nullable_to_non_nullable
              as String?,
      lang: freezed == lang
          ? _value.lang
          : lang // ignore: cast_nullable_to_non_nullable
              as String?,
      language: freezed == language
          ? _value.language
          : language // ignore: cast_nullable_to_non_nullable
              as String?,
    ));
  }
}

/// @nodoc
@JsonSerializable()
class _$SubtitleTrackImpl implements _SubtitleTrack {
  const _$SubtitleTrackImpl({this.url, this.file, this.lang, this.language});

  factory _$SubtitleTrackImpl.fromJson(Map<String, dynamic> json) =>
      _$$SubtitleTrackImplFromJson(json);

  @override
  final String? url;
  @override
  final String? file;
  @override
  final String? lang;
  @override
  final String? language;

  @override
  String toString() {
    return 'SubtitleTrack(url: $url, file: $file, lang: $lang, language: $language)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$SubtitleTrackImpl &&
            (identical(other.url, url) || other.url == url) &&
            (identical(other.file, file) || other.file == file) &&
            (identical(other.lang, lang) || other.lang == lang) &&
            (identical(other.language, language) ||
                other.language == language));
  }

  @JsonKey(ignore: true)
  @override
  int get hashCode => Object.hash(runtimeType, url, file, lang, language);

  @JsonKey(ignore: true)
  @override
  @pragma('vm:prefer-inline')
  _$$SubtitleTrackImplCopyWith<_$SubtitleTrackImpl> get copyWith =>
      __$$SubtitleTrackImplCopyWithImpl<_$SubtitleTrackImpl>(this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$$SubtitleTrackImplToJson(
      this,
    );
  }
}

abstract class _SubtitleTrack implements SubtitleTrack {
  const factory _SubtitleTrack(
      {final String? url,
      final String? file,
      final String? lang,
      final String? language}) = _$SubtitleTrackImpl;

  factory _SubtitleTrack.fromJson(Map<String, dynamic> json) =
      _$SubtitleTrackImpl.fromJson;

  @override
  String? get url;
  @override
  String? get file;
  @override
  String? get lang;
  @override
  String? get language;
  @override
  @JsonKey(ignore: true)
  _$$SubtitleTrackImplCopyWith<_$SubtitleTrackImpl> get copyWith =>
      throw _privateConstructorUsedError;
}

APISource _$APISourceFromJson(Map<String, dynamic> json) {
  return _APISource.fromJson(json);
}

/// @nodoc
mixin _$APISource {
  String get url => throw _privateConstructorUsedError;
  String get quality => throw _privateConstructorUsedError;

  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;
  @JsonKey(ignore: true)
  $APISourceCopyWith<APISource> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $APISourceCopyWith<$Res> {
  factory $APISourceCopyWith(APISource value, $Res Function(APISource) then) =
      _$APISourceCopyWithImpl<$Res, APISource>;
  @useResult
  $Res call({String url, String quality});
}

/// @nodoc
class _$APISourceCopyWithImpl<$Res, $Val extends APISource>
    implements $APISourceCopyWith<$Res> {
  _$APISourceCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? url = null,
    Object? quality = null,
  }) {
    return _then(_value.copyWith(
      url: null == url
          ? _value.url
          : url // ignore: cast_nullable_to_non_nullable
              as String,
      quality: null == quality
          ? _value.quality
          : quality // ignore: cast_nullable_to_non_nullable
              as String,
    ) as $Val);
  }
}

/// @nodoc
abstract class _$$APISourceImplCopyWith<$Res>
    implements $APISourceCopyWith<$Res> {
  factory _$$APISourceImplCopyWith(
          _$APISourceImpl value, $Res Function(_$APISourceImpl) then) =
      __$$APISourceImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call({String url, String quality});
}

/// @nodoc
class __$$APISourceImplCopyWithImpl<$Res>
    extends _$APISourceCopyWithImpl<$Res, _$APISourceImpl>
    implements _$$APISourceImplCopyWith<$Res> {
  __$$APISourceImplCopyWithImpl(
      _$APISourceImpl _value, $Res Function(_$APISourceImpl) _then)
      : super(_value, _then);

  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? url = null,
    Object? quality = null,
  }) {
    return _then(_$APISourceImpl(
      url: null == url
          ? _value.url
          : url // ignore: cast_nullable_to_non_nullable
              as String,
      quality: null == quality
          ? _value.quality
          : quality // ignore: cast_nullable_to_non_nullable
              as String,
    ));
  }
}

/// @nodoc
@JsonSerializable()
class _$APISourceImpl implements _APISource {
  const _$APISourceImpl({required this.url, required this.quality});

  factory _$APISourceImpl.fromJson(Map<String, dynamic> json) =>
      _$$APISourceImplFromJson(json);

  @override
  final String url;
  @override
  final String quality;

  @override
  String toString() {
    return 'APISource(url: $url, quality: $quality)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$APISourceImpl &&
            (identical(other.url, url) || other.url == url) &&
            (identical(other.quality, quality) || other.quality == quality));
  }

  @JsonKey(ignore: true)
  @override
  int get hashCode => Object.hash(runtimeType, url, quality);

  @JsonKey(ignore: true)
  @override
  @pragma('vm:prefer-inline')
  _$$APISourceImplCopyWith<_$APISourceImpl> get copyWith =>
      __$$APISourceImplCopyWithImpl<_$APISourceImpl>(this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$$APISourceImplToJson(
      this,
    );
  }
}

abstract class _APISource implements APISource {
  const factory _APISource(
      {required final String url,
      required final String quality}) = _$APISourceImpl;

  factory _APISource.fromJson(Map<String, dynamic> json) =
      _$APISourceImpl.fromJson;

  @override
  String get url;
  @override
  String get quality;
  @override
  @JsonKey(ignore: true)
  _$$APISourceImplCopyWith<_$APISourceImpl> get copyWith =>
      throw _privateConstructorUsedError;
}

APISourceResults _$APISourceResultsFromJson(Map<String, dynamic> json) {
  return _APISourceResults.fromJson(json);
}

/// @nodoc
mixin _$APISourceResults {
  List<APISource>? get sources => throw _privateConstructorUsedError;
  List<SubtitleTrack>? get subtitles => throw _privateConstructorUsedError;

  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;
  @JsonKey(ignore: true)
  $APISourceResultsCopyWith<APISourceResults> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $APISourceResultsCopyWith<$Res> {
  factory $APISourceResultsCopyWith(
          APISourceResults value, $Res Function(APISourceResults) then) =
      _$APISourceResultsCopyWithImpl<$Res, APISourceResults>;
  @useResult
  $Res call({List<APISource>? sources, List<SubtitleTrack>? subtitles});
}

/// @nodoc
class _$APISourceResultsCopyWithImpl<$Res, $Val extends APISourceResults>
    implements $APISourceResultsCopyWith<$Res> {
  _$APISourceResultsCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? sources = freezed,
    Object? subtitles = freezed,
  }) {
    return _then(_value.copyWith(
      sources: freezed == sources
          ? _value.sources
          : sources // ignore: cast_nullable_to_non_nullable
              as List<APISource>?,
      subtitles: freezed == subtitles
          ? _value.subtitles
          : subtitles // ignore: cast_nullable_to_non_nullable
              as List<SubtitleTrack>?,
    ) as $Val);
  }
}

/// @nodoc
abstract class _$$APISourceResultsImplCopyWith<$Res>
    implements $APISourceResultsCopyWith<$Res> {
  factory _$$APISourceResultsImplCopyWith(_$APISourceResultsImpl value,
          $Res Function(_$APISourceResultsImpl) then) =
      __$$APISourceResultsImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call({List<APISource>? sources, List<SubtitleTrack>? subtitles});
}

/// @nodoc
class __$$APISourceResultsImplCopyWithImpl<$Res>
    extends _$APISourceResultsCopyWithImpl<$Res, _$APISourceResultsImpl>
    implements _$$APISourceResultsImplCopyWith<$Res> {
  __$$APISourceResultsImplCopyWithImpl(_$APISourceResultsImpl _value,
      $Res Function(_$APISourceResultsImpl) _then)
      : super(_value, _then);

  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? sources = freezed,
    Object? subtitles = freezed,
  }) {
    return _then(_$APISourceResultsImpl(
      sources: freezed == sources
          ? _value._sources
          : sources // ignore: cast_nullable_to_non_nullable
              as List<APISource>?,
      subtitles: freezed == subtitles
          ? _value._subtitles
          : subtitles // ignore: cast_nullable_to_non_nullable
              as List<SubtitleTrack>?,
    ));
  }
}

/// @nodoc
@JsonSerializable()
class _$APISourceResultsImpl implements _APISourceResults {
  const _$APISourceResultsImpl(
      {final List<APISource>? sources, final List<SubtitleTrack>? subtitles})
      : _sources = sources,
        _subtitles = subtitles;

  factory _$APISourceResultsImpl.fromJson(Map<String, dynamic> json) =>
      _$$APISourceResultsImplFromJson(json);

  final List<APISource>? _sources;
  @override
  List<APISource>? get sources {
    final value = _sources;
    if (value == null) return null;
    if (_sources is EqualUnmodifiableListView) return _sources;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableListView(value);
  }

  final List<SubtitleTrack>? _subtitles;
  @override
  List<SubtitleTrack>? get subtitles {
    final value = _subtitles;
    if (value == null) return null;
    if (_subtitles is EqualUnmodifiableListView) return _subtitles;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableListView(value);
  }

  @override
  String toString() {
    return 'APISourceResults(sources: $sources, subtitles: $subtitles)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$APISourceResultsImpl &&
            const DeepCollectionEquality().equals(other._sources, _sources) &&
            const DeepCollectionEquality()
                .equals(other._subtitles, _subtitles));
  }

  @JsonKey(ignore: true)
  @override
  int get hashCode => Object.hash(
      runtimeType,
      const DeepCollectionEquality().hash(_sources),
      const DeepCollectionEquality().hash(_subtitles));

  @JsonKey(ignore: true)
  @override
  @pragma('vm:prefer-inline')
  _$$APISourceResultsImplCopyWith<_$APISourceResultsImpl> get copyWith =>
      __$$APISourceResultsImplCopyWithImpl<_$APISourceResultsImpl>(
          this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$$APISourceResultsImplToJson(
      this,
    );
  }
}

abstract class _APISourceResults implements APISourceResults {
  const factory _APISourceResults(
      {final List<APISource>? sources,
      final List<SubtitleTrack>? subtitles}) = _$APISourceResultsImpl;

  factory _APISourceResults.fromJson(Map<String, dynamic> json) =
      _$APISourceResultsImpl.fromJson;

  @override
  List<APISource>? get sources;
  @override
  List<SubtitleTrack>? get subtitles;
  @override
  @JsonKey(ignore: true)
  _$$APISourceResultsImplCopyWith<_$APISourceResultsImpl> get copyWith =>
      throw _privateConstructorUsedError;
}
