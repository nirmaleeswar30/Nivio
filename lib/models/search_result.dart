import 'package:freezed_annotation/freezed_annotation.dart';

part 'search_result.freezed.dart';
part 'search_result.g.dart';

@freezed
class SearchResult with _$SearchResult {
  const factory SearchResult({
    @Default(false) bool adult,
    required int id,
    String? name,
    String? title,
    @JsonKey(name: 'original_language') String? originalLanguage,
    @JsonKey(name: 'media_type') required String mediaType,
    @JsonKey(name: 'release_date') String? releaseDate,
    @JsonKey(name: 'first_air_date') String? firstAirDate,
    @JsonKey(name: 'poster_path') String? posterPath,
    @JsonKey(name: 'backdrop_path') String? backdropPath,
    String? overview,
    @JsonKey(name: 'vote_average') double? voteAverage,
  }) = _SearchResult;

  factory SearchResult.fromJson(Map<String, dynamic> json) =>
      _$SearchResultFromJson(json);
}

@freezed
class SearchResults with _$SearchResults {
  const factory SearchResults({
    required int page,
    required List<SearchResult> results,
    @JsonKey(name: 'total_pages') required int totalPages,
    @JsonKey(name: 'total_results') required int totalResults,
  }) = _SearchResults;

  factory SearchResults.fromJson(Map<String, dynamic> json) =>
      _$SearchResultsFromJson(json);
}
