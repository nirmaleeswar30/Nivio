// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'api_source.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$SubtitleTrack {

 String? get url; String? get file; String? get lang; String? get language;
/// Create a copy of SubtitleTrack
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$SubtitleTrackCopyWith<SubtitleTrack> get copyWith => _$SubtitleTrackCopyWithImpl<SubtitleTrack>(this as SubtitleTrack, _$identity);

  /// Serializes this SubtitleTrack to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  final _this = this as SubtitleTrack;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is SubtitleTrack&&(identical(other.url, _this.url) || other.url == _this.url)&&(identical(other.file, _this.file) || other.file == _this.file)&&(identical(other.lang, _this.lang) || other.lang == _this.lang)&&(identical(other.language, _this.language) || other.language == _this.language));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
  final _this = this as SubtitleTrack;
  return Object.hash(runtimeType,_this.url,_this.file,_this.lang,_this.language);
}

@override
String toString() {
  final _this = this as SubtitleTrack;
  return 'SubtitleTrack(url: ${_this.url}, file: ${_this.file}, lang: ${_this.lang}, language: ${_this.language})';
}


}

/// @nodoc
abstract mixin class $SubtitleTrackCopyWith<$Res>  {
  factory $SubtitleTrackCopyWith(SubtitleTrack value, $Res Function(SubtitleTrack) _then) = _$SubtitleTrackCopyWithImpl;
@useResult
$Res call({
 String? url, String? file, String? lang, String? language
});




}
/// @nodoc
class _$SubtitleTrackCopyWithImpl<$Res>
    implements $SubtitleTrackCopyWith<$Res> {
  _$SubtitleTrackCopyWithImpl(this._self, this._then);

  final SubtitleTrack _self;
  final $Res Function(SubtitleTrack) _then;

/// Create a copy of SubtitleTrack
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? url = freezed,Object? file = freezed,Object? lang = freezed,Object? language = freezed,}) {
  return _then(SubtitleTrack(
url: freezed == url ? _self.url : url // ignore: cast_nullable_to_non_nullable
as String?,file: freezed == file ? _self.file : file // ignore: cast_nullable_to_non_nullable
as String?,lang: freezed == lang ? _self.lang : lang // ignore: cast_nullable_to_non_nullable
as String?,language: freezed == language ? _self.language : language // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}

}


/// Adds pattern-matching-related methods to [SubtitleTrack].
extension SubtitleTrackPatterns on SubtitleTrack {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _SubtitleTrack value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _SubtitleTrack() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _SubtitleTrack value)  $default,){
final _that = this;
switch (_that) {
case _SubtitleTrack():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _SubtitleTrack value)?  $default,){
final _that = this;
switch (_that) {
case _SubtitleTrack() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String? url,  String? file,  String? lang,  String? language)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _SubtitleTrack() when $default != null:
return $default(_that.url,_that.file,_that.lang,_that.language);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String? url,  String? file,  String? lang,  String? language)  $default,) {final _that = this;
switch (_that) {
case _SubtitleTrack():
return $default(_that.url,_that.file,_that.lang,_that.language);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String? url,  String? file,  String? lang,  String? language)?  $default,) {final _that = this;
switch (_that) {
case _SubtitleTrack() when $default != null:
return $default(_that.url,_that.file,_that.lang,_that.language);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _SubtitleTrack implements SubtitleTrack {
  const _SubtitleTrack({this.url, this.file, this.lang, this.language});
  factory _SubtitleTrack.fromJson(Map<String, dynamic> json) => _$SubtitleTrackFromJson(json);

@override final  String? url;
@override final  String? file;
@override final  String? lang;
@override final  String? language;

/// Create a copy of SubtitleTrack
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$SubtitleTrackCopyWith<_SubtitleTrack> get copyWith => __$SubtitleTrackCopyWithImpl<_SubtitleTrack>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$SubtitleTrackToJson(this, );
}

@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _SubtitleTrack&&(identical(other.url, url) || other.url == url)&&(identical(other.file, file) || other.file == file)&&(identical(other.lang, lang) || other.lang == lang)&&(identical(other.language, language) || other.language == language));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
    return Object.hash(runtimeType,url,file,lang,language);
}

@override
String toString() {
    return 'SubtitleTrack(url: $url, file: $file, lang: $lang, language: $language)';
}


}

/// @nodoc
abstract mixin class _$SubtitleTrackCopyWith<$Res> implements $SubtitleTrackCopyWith<$Res> {
  factory _$SubtitleTrackCopyWith(_SubtitleTrack value, $Res Function(_SubtitleTrack) _then) = __$SubtitleTrackCopyWithImpl;
@override @useResult
$Res call({
 String? url, String? file, String? lang, String? language
});




}
/// @nodoc
class __$SubtitleTrackCopyWithImpl<$Res>
    implements _$SubtitleTrackCopyWith<$Res> {
  __$SubtitleTrackCopyWithImpl(this._self, this._then);

  final _SubtitleTrack _self;
  final $Res Function(_SubtitleTrack) _then;

/// Create a copy of SubtitleTrack
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? url = freezed,Object? file = freezed,Object? lang = freezed,Object? language = freezed,}) {
  return _then(_SubtitleTrack(
url: freezed == url ? _self.url : url // ignore: cast_nullable_to_non_nullable
as String?,file: freezed == file ? _self.file : file // ignore: cast_nullable_to_non_nullable
as String?,lang: freezed == lang ? _self.lang : lang // ignore: cast_nullable_to_non_nullable
as String?,language: freezed == language ? _self.language : language // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}


}


/// @nodoc
mixin _$APISource {

 String get url; String get quality;
/// Create a copy of APISource
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$APISourceCopyWith<APISource> get copyWith => _$APISourceCopyWithImpl<APISource>(this as APISource, _$identity);

  /// Serializes this APISource to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  final _this = this as APISource;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is APISource&&(identical(other.url, _this.url) || other.url == _this.url)&&(identical(other.quality, _this.quality) || other.quality == _this.quality));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
  final _this = this as APISource;
  return Object.hash(runtimeType,_this.url,_this.quality);
}

@override
String toString() {
  final _this = this as APISource;
  return 'APISource(url: ${_this.url}, quality: ${_this.quality})';
}


}

/// @nodoc
abstract mixin class $APISourceCopyWith<$Res>  {
  factory $APISourceCopyWith(APISource value, $Res Function(APISource) _then) = _$APISourceCopyWithImpl;
@useResult
$Res call({
 String url, String quality
});




}
/// @nodoc
class _$APISourceCopyWithImpl<$Res>
    implements $APISourceCopyWith<$Res> {
  _$APISourceCopyWithImpl(this._self, this._then);

  final APISource _self;
  final $Res Function(APISource) _then;

/// Create a copy of APISource
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? url = null,Object? quality = null,}) {
  return _then(APISource(
url: null == url ? _self.url : url // ignore: cast_nullable_to_non_nullable
as String,quality: null == quality ? _self.quality : quality // ignore: cast_nullable_to_non_nullable
as String,
  ));
}

}


/// Adds pattern-matching-related methods to [APISource].
extension APISourcePatterns on APISource {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _APISource value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _APISource() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _APISource value)  $default,){
final _that = this;
switch (_that) {
case _APISource():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _APISource value)?  $default,){
final _that = this;
switch (_that) {
case _APISource() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String url,  String quality)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _APISource() when $default != null:
return $default(_that.url,_that.quality);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String url,  String quality)  $default,) {final _that = this;
switch (_that) {
case _APISource():
return $default(_that.url,_that.quality);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String url,  String quality)?  $default,) {final _that = this;
switch (_that) {
case _APISource() when $default != null:
return $default(_that.url,_that.quality);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _APISource implements APISource {
  const _APISource({required this.url, required this.quality});
  factory _APISource.fromJson(Map<String, dynamic> json) => _$APISourceFromJson(json);

@override final  String url;
@override final  String quality;

/// Create a copy of APISource
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$APISourceCopyWith<_APISource> get copyWith => __$APISourceCopyWithImpl<_APISource>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$APISourceToJson(this, );
}

@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _APISource&&(identical(other.url, url) || other.url == url)&&(identical(other.quality, quality) || other.quality == quality));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
    return Object.hash(runtimeType,url,quality);
}

@override
String toString() {
    return 'APISource(url: $url, quality: $quality)';
}


}

/// @nodoc
abstract mixin class _$APISourceCopyWith<$Res> implements $APISourceCopyWith<$Res> {
  factory _$APISourceCopyWith(_APISource value, $Res Function(_APISource) _then) = __$APISourceCopyWithImpl;
@override @useResult
$Res call({
 String url, String quality
});




}
/// @nodoc
class __$APISourceCopyWithImpl<$Res>
    implements _$APISourceCopyWith<$Res> {
  __$APISourceCopyWithImpl(this._self, this._then);

  final _APISource _self;
  final $Res Function(_APISource) _then;

/// Create a copy of APISource
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? url = null,Object? quality = null,}) {
  return _then(_APISource(
url: null == url ? _self.url : url // ignore: cast_nullable_to_non_nullable
as String,quality: null == quality ? _self.quality : quality // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}


/// @nodoc
mixin _$APISourceResults {

 List<APISource>? get sources; List<SubtitleTrack>? get subtitles;
/// Create a copy of APISourceResults
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$APISourceResultsCopyWith<APISourceResults> get copyWith => _$APISourceResultsCopyWithImpl<APISourceResults>(this as APISourceResults, _$identity);

  /// Serializes this APISourceResults to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  final _this = this as APISourceResults;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is APISourceResults&&const DeepCollectionEquality().equals(other.sources, _this.sources)&&const DeepCollectionEquality().equals(other.subtitles, _this.subtitles));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
  final _this = this as APISourceResults;
  return Object.hash(runtimeType,const DeepCollectionEquality().hash(_this.sources),const DeepCollectionEquality().hash(_this.subtitles));
}

@override
String toString() {
  final _this = this as APISourceResults;
  return 'APISourceResults(sources: ${_this.sources}, subtitles: ${_this.subtitles})';
}


}

/// @nodoc
abstract mixin class $APISourceResultsCopyWith<$Res>  {
  factory $APISourceResultsCopyWith(APISourceResults value, $Res Function(APISourceResults) _then) = _$APISourceResultsCopyWithImpl;
@useResult
$Res call({
 List<APISource>? sources, List<SubtitleTrack>? subtitles
});




}
/// @nodoc
class _$APISourceResultsCopyWithImpl<$Res>
    implements $APISourceResultsCopyWith<$Res> {
  _$APISourceResultsCopyWithImpl(this._self, this._then);

  final APISourceResults _self;
  final $Res Function(APISourceResults) _then;

/// Create a copy of APISourceResults
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? sources = freezed,Object? subtitles = freezed,}) {
  return _then(APISourceResults(
sources: freezed == sources ? _self.sources : sources // ignore: cast_nullable_to_non_nullable
as List<APISource>?,subtitles: freezed == subtitles ? _self.subtitles : subtitles // ignore: cast_nullable_to_non_nullable
as List<SubtitleTrack>?,
  ));
}

}


/// Adds pattern-matching-related methods to [APISourceResults].
extension APISourceResultsPatterns on APISourceResults {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _APISourceResults value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _APISourceResults() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _APISourceResults value)  $default,){
final _that = this;
switch (_that) {
case _APISourceResults():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _APISourceResults value)?  $default,){
final _that = this;
switch (_that) {
case _APISourceResults() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( List<APISource>? sources,  List<SubtitleTrack>? subtitles)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _APISourceResults() when $default != null:
return $default(_that.sources,_that.subtitles);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( List<APISource>? sources,  List<SubtitleTrack>? subtitles)  $default,) {final _that = this;
switch (_that) {
case _APISourceResults():
return $default(_that.sources,_that.subtitles);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( List<APISource>? sources,  List<SubtitleTrack>? subtitles)?  $default,) {final _that = this;
switch (_that) {
case _APISourceResults() when $default != null:
return $default(_that.sources,_that.subtitles);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _APISourceResults implements APISourceResults {
  const _APISourceResults({ List<APISource>? sources,  List<SubtitleTrack>? subtitles}): _sources = sources,_subtitles = subtitles;
  factory _APISourceResults.fromJson(Map<String, dynamic> json) => _$APISourceResultsFromJson(json);

 final  List<APISource>? _sources;
@override List<APISource>? get sources {
  final value = _sources;
  if (value == null) return null;
  if (_sources is EqualUnmodifiableListView) return _sources;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(value);
}

 final  List<SubtitleTrack>? _subtitles;
@override List<SubtitleTrack>? get subtitles {
  final value = _subtitles;
  if (value == null) return null;
  if (_subtitles is EqualUnmodifiableListView) return _subtitles;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(value);
}


/// Create a copy of APISourceResults
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$APISourceResultsCopyWith<_APISourceResults> get copyWith => __$APISourceResultsCopyWithImpl<_APISourceResults>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$APISourceResultsToJson(this, );
}

@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _APISourceResults&&const DeepCollectionEquality().equals(other.sources, _sources)&&const DeepCollectionEquality().equals(other.subtitles, _subtitles));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
    return Object.hash(runtimeType,const DeepCollectionEquality().hash(_sources),const DeepCollectionEquality().hash(_subtitles));
}

@override
String toString() {
    return 'APISourceResults(sources: $sources, subtitles: $subtitles)';
}


}

/// @nodoc
abstract mixin class _$APISourceResultsCopyWith<$Res> implements $APISourceResultsCopyWith<$Res> {
  factory _$APISourceResultsCopyWith(_APISourceResults value, $Res Function(_APISourceResults) _then) = __$APISourceResultsCopyWithImpl;
@override @useResult
$Res call({
 List<APISource>? sources, List<SubtitleTrack>? subtitles
});




}
/// @nodoc
class __$APISourceResultsCopyWithImpl<$Res>
    implements _$APISourceResultsCopyWith<$Res> {
  __$APISourceResultsCopyWithImpl(this._self, this._then);

  final _APISourceResults _self;
  final $Res Function(_APISourceResults) _then;

/// Create a copy of APISourceResults
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? sources = freezed,Object? subtitles = freezed,}) {
  return _then(_APISourceResults(
sources: freezed == sources ? _self._sources : sources // ignore: cast_nullable_to_non_nullable
as List<APISource>?,subtitles: freezed == subtitles ? _self._subtitles : subtitles // ignore: cast_nullable_to_non_nullable
as List<SubtitleTrack>?,
  ));
}


}

// dart format on
