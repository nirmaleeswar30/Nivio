import 'package:freezed_annotation/freezed_annotation.dart';

part 'api_source.freezed.dart';
part 'api_source.g.dart';

@freezed
class SubtitleTrack with _$SubtitleTrack {
  const factory SubtitleTrack({
    String? url,
    String? file,
    String? lang,
    String? language,
  }) = _SubtitleTrack;

  factory SubtitleTrack.fromJson(Map<String, dynamic> json) =>
      _$SubtitleTrackFromJson(json);
}

@freezed
class APISource with _$APISource {
  const factory APISource({
    required String url,
    required String quality,
  }) = _APISource;

  factory APISource.fromJson(Map<String, dynamic> json) =>
      _$APISourceFromJson(json);
}

@freezed
class APISourceResults with _$APISourceResults {
  const factory APISourceResults({
    List<APISource>? sources,
    List<SubtitleTrack>? subtitles,
  }) = _APISourceResults;

  factory APISourceResults.fromJson(Map<String, dynamic> json) =>
      _$APISourceResultsFromJson(json);
}
