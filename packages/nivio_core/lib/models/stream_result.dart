import 'package:nivio/services/skip_times_models.dart';
class StreamSubtitleTrack {
  final String url;
  final String lang;

  StreamSubtitleTrack({required this.url, required this.lang});

  factory StreamSubtitleTrack.fromJson(Map<String, dynamic> json) {
    final rawLang = (json['lang'] ?? json['language'] ?? json['label'] ?? '').toString().trim();
    final lang = (rawLang.isEmpty || rawLang.toLowerCase() == 'auto' || rawLang.toLowerCase() == 'und' || rawLang.toLowerCase() == 'unknown')
        ? 'Default Subtitle'
        : rawLang;
    return StreamSubtitleTrack(
      url: json['url'] ?? '',
      lang: lang,
    );
  }
}

class StreamSource {
  final String url;
  final String quality;
  final bool isM3U8;
  final bool isDub;

  StreamSource({
    required this.url,
    required this.quality,
    this.isM3U8 = false,
    this.isDub = false,
  });

  factory StreamSource.fromJson(Map<String, dynamic> json) {
    return StreamSource(
      url: json['url']?.toString() ?? '',
      quality: json['quality']?.toString() ?? 'auto',
      isM3U8: json['isM3U8'] ?? false,
      isDub: json['isDub'] == true,
    );
  }
}

class StreamResult {
  final String url;
  final String quality;
  final String provider;
  final List<StreamSubtitleTrack> subtitles;
  final List<String> availableQualities;
  final List<String> availableAudios;
  final String selectedAudio;
  final bool isM3U8;
  final Map<String, String> headers;
  final List<StreamSource> sources;
  final List<SkipTime> skipTimes;
  Map<String, StreamResult>? preloadedSources;

  /// WebVTT seek-preview track (cues pointing at sprite-sheet tiles), when the
  /// server provides one, and the headers its CDN needs (usually the stream's
  /// Referer/Origin).
  final String? thumbnailsVtt;
  final Map<String, String> thumbnailsHeaders;

  StreamResult({
    required this.url,
    required this.quality,
    required this.provider,
    this.subtitles = const [],
    this.availableQualities = const ['auto'],
    this.availableAudios = const [],
    this.selectedAudio = '',
    this.isM3U8 = false,
    this.headers = const {},
    this.sources = const [],
    this.skipTimes = const [],
    this.preloadedSources,
    this.thumbnailsVtt,
    this.thumbnailsHeaders = const {},
  });

  StreamResult copyWith({
    String? url,
    String? quality,
    String? provider,
    List<StreamSubtitleTrack>? subtitles,
    List<String>? availableQualities,
    List<String>? availableAudios,
    String? selectedAudio,
    bool? isM3U8,
    Map<String, String>? headers,
    List<StreamSource>? sources,
    Map<String, StreamResult>? preloadedSources,
    List<SkipTime>? skipTimes,
    String? thumbnailsVtt,
    Map<String, String>? thumbnailsHeaders,
  }) {
    return StreamResult(
      url: url ?? this.url,
      quality: quality ?? this.quality,
      provider: provider ?? this.provider,
      subtitles: subtitles ?? this.subtitles,
      availableQualities: availableQualities ?? this.availableQualities,
      availableAudios: availableAudios ?? this.availableAudios,
      selectedAudio: selectedAudio ?? this.selectedAudio,
      isM3U8: isM3U8 ?? this.isM3U8,
      headers: headers ?? this.headers,
      sources: sources ?? this.sources,
      preloadedSources: preloadedSources ?? this.preloadedSources,
      // Was missing, so picking a quality dropped the provider's skip times.
      skipTimes: skipTimes ?? this.skipTimes,
      thumbnailsVtt: thumbnailsVtt ?? this.thumbnailsVtt,
      thumbnailsHeaders: thumbnailsHeaders ?? this.thumbnailsHeaders,
    );
  }
}
