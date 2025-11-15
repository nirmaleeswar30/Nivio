// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'search_result.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_$SearchResultImpl _$$SearchResultImplFromJson(Map<String, dynamic> json) =>
    _$SearchResultImpl(
      adult: json['adult'] as bool? ?? false,
      id: (json['id'] as num).toInt(),
      name: json['name'] as String?,
      title: json['title'] as String?,
      originalLanguage: json['original_language'] as String?,
      mediaType: json['media_type'] as String,
      releaseDate: json['release_date'] as String?,
      firstAirDate: json['first_air_date'] as String?,
      posterPath: json['poster_path'] as String?,
      backdropPath: json['backdrop_path'] as String?,
      overview: json['overview'] as String?,
      voteAverage: (json['vote_average'] as num?)?.toDouble(),
    );

Map<String, dynamic> _$$SearchResultImplToJson(_$SearchResultImpl instance) =>
    <String, dynamic>{
      'adult': instance.adult,
      'id': instance.id,
      'name': instance.name,
      'title': instance.title,
      'original_language': instance.originalLanguage,
      'media_type': instance.mediaType,
      'release_date': instance.releaseDate,
      'first_air_date': instance.firstAirDate,
      'poster_path': instance.posterPath,
      'backdrop_path': instance.backdropPath,
      'overview': instance.overview,
      'vote_average': instance.voteAverage,
    };

_$SearchResultsImpl _$$SearchResultsImplFromJson(Map<String, dynamic> json) =>
    _$SearchResultsImpl(
      page: (json['page'] as num).toInt(),
      results: (json['results'] as List<dynamic>)
          .map((e) => SearchResult.fromJson(e as Map<String, dynamic>))
          .toList(),
      totalPages: (json['total_pages'] as num).toInt(),
      totalResults: (json['total_results'] as num).toInt(),
    );

Map<String, dynamic> _$$SearchResultsImplToJson(_$SearchResultsImpl instance) =>
    <String, dynamic>{
      'page': instance.page,
      'results': instance.results,
      'total_pages': instance.totalPages,
      'total_results': instance.totalResults,
    };
