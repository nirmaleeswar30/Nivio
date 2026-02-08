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

class StreamResult {
  final String url;
  final String quality;
  final String provider;
  final List<SubtitleTrack> subtitles;
  final List<String> availableQualities;
  final bool isM3U8;
  final Map<String, String> headers;
  final List<StreamSource> sources;

  StreamResult({
    required this.url,
    required this.quality,
    required this.provider,
    this.subtitles = const [],
    this.availableQualities = const ['auto'],
    this.isM3U8 = false,
    this.headers = const {},
    this.sources = const [],
  });
}
