// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'api_source.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_SubtitleTrack _$SubtitleTrackFromJson(Map<String, dynamic> json) =>
    _SubtitleTrack(
      url: json['url'] as String?,
      file: json['file'] as String?,
      lang: json['lang'] as String?,
      language: json['language'] as String?,
    );

Map<String, dynamic> _$SubtitleTrackToJson(_SubtitleTrack instance) =>
    <String, dynamic>{
      'url': instance.url,
      'file': instance.file,
      'lang': instance.lang,
      'language': instance.language,
    };

_APISource _$APISourceFromJson(Map<String, dynamic> json) =>
    _APISource(url: json['url'] as String, quality: json['quality'] as String);

Map<String, dynamic> _$APISourceToJson(_APISource instance) =>
    <String, dynamic>{'url': instance.url, 'quality': instance.quality};

_APISourceResults _$APISourceResultsFromJson(Map<String, dynamic> json) =>
    _APISourceResults(
      sources: (json['sources'] as List<dynamic>?)
          ?.map((e) => APISource.fromJson(e as Map<String, dynamic>))
          .toList(),
      subtitles: (json['subtitles'] as List<dynamic>?)
          ?.map((e) => SubtitleTrack.fromJson(e as Map<String, dynamic>))
          .toList(),
    );

Map<String, dynamic> _$APISourceResultsToJson(_APISourceResults instance) =>
    <String, dynamic>{
      'sources': instance.sources,
      'subtitles': instance.subtitles,
    };
