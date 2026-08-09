import 'skip_times_models.dart';

class SubtitleTrack {
  final String url;
  final String lang;

  SubtitleTrack({required this.url, required this.lang});

  factory SubtitleTrack.fromJson(Map<String, dynamic> json) {
    return SubtitleTrack(
      url: json['url'] ?? '',
      lang: json['lang'] ?? 'Unknown',
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

class StreamSegment {
  final String url;
  final Duration start;
  final Duration duration;

  const StreamSegment({
    required this.url,
    required this.start,
    required this.duration,
  });

  Duration get end => start + duration;
}

class StreamResult {
  final String url;
  final String quality;
  final String provider;
  final List<SubtitleTrack> subtitles;
  final List<String> availableQualities;
  final List<String> availableAudios;
  final String selectedAudio;
  final bool isM3U8;
  final Map<String, String> headers;
  final List<StreamSource> sources;
  final List<SkipTime> skipTimes;
  final Duration? duration;
  final List<StreamSegment> segments;
  final int? providerIndex;
  final String? providerGroup;
  final String? serverName;
  final bool isDirect;
  final bool isIframe;
  Map<String, StreamResult>? preloadedSources;

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
    this.duration,
    this.segments = const [],
    this.providerIndex,
    this.providerGroup,
    this.serverName,
    this.isDirect = true,
    this.isIframe = false,
    this.preloadedSources,
  });

  StreamResult copyWith({
    String? url,
    String? quality,
    String? provider,
    List<SubtitleTrack>? subtitles,
    List<String>? availableQualities,
    List<String>? availableAudios,
    String? selectedAudio,
    bool? isM3U8,
    Map<String, String>? headers,
    List<StreamSource>? sources,
    List<SkipTime>? skipTimes,
    Duration? duration,
    List<StreamSegment>? segments,
    int? providerIndex,
    String? providerGroup,
    String? serverName,
    bool? isDirect,
    bool? isIframe,
    Map<String, StreamResult>? preloadedSources,
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
      skipTimes: skipTimes ?? this.skipTimes,
      duration: duration ?? this.duration,
      segments: segments ?? this.segments,
      providerIndex: providerIndex ?? this.providerIndex,
      providerGroup: providerGroup ?? this.providerGroup,
      serverName: serverName ?? this.serverName,
      isDirect: isDirect ?? this.isDirect,
      isIframe: isIframe ?? this.isIframe,
      preloadedSources: preloadedSources ?? this.preloadedSources,
    );
  }
}
