// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'api_source.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_$SubtitleTrackImpl _$$SubtitleTrackImplFromJson(Map<String, dynamic> json) =>
    _$SubtitleTrackImpl(
      url: json['url'] as String?,
      file: json['file'] as String?,
      lang: json['lang'] as String?,
      language: json['language'] as String?,
    );

Map<String, dynamic> _$$SubtitleTrackImplToJson(_$SubtitleTrackImpl instance) =>
    <String, dynamic>{
      'url': instance.url,
      'file': instance.file,
      'lang': instance.lang,
      'language': instance.language,
    };

_$APISourceImpl _$$APISourceImplFromJson(Map<String, dynamic> json) =>
    _$APISourceImpl(
      url: json['url'] as String,
      quality: json['quality'] as String,
    );

Map<String, dynamic> _$$APISourceImplToJson(_$APISourceImpl instance) =>
    <String, dynamic>{
      'url': instance.url,
      'quality': instance.quality,
    };

_$APISourceResultsImpl _$$APISourceResultsImplFromJson(
        Map<String, dynamic> json) =>
    _$APISourceResultsImpl(
      sources: (json['sources'] as List<dynamic>?)
          ?.map((e) => APISource.fromJson(e as Map<String, dynamic>))
          .toList(),
      subtitles: (json['subtitles'] as List<dynamic>?)
          ?.map((e) => SubtitleTrack.fromJson(e as Map<String, dynamic>))
          .toList(),
    );

Map<String, dynamic> _$$APISourceResultsImplToJson(
        _$APISourceResultsImpl instance) =>
    <String, dynamic>{
      'sources': instance.sources,
      'subtitles': instance.subtitles,
    };
