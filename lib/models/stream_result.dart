class StreamResult {
  final String url;
  final String quality;
  final String provider;
  final List<dynamic> subtitles;
  final List<String> availableQualities;

  StreamResult({
    required this.url,
    required this.quality,
    required this.provider,
    required this.subtitles,
    required this.availableQualities,
  });
}
