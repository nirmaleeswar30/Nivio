import 'package:nivio/models/stream_result.dart';
import 'package:nivio/models/stream_size.dart';
import 'package:nivio/services/public_web_client.dart';

class StreamChoice {
  const StreamChoice({
    required this.id,
    required this.providerId,
    required this.provider,
    required this.title,
    required this.quality,
    required this.direct,
    this.audio,
    this.byteSize,
    this.bingeGroupHint,
    this.videoHeights = const [],
    this.audioTracks = const [],
  });

  final String id;
  final String providerId;
  final String provider;
  final String title;
  final String quality;
  final String? audio;
  final int? byteSize;
  final String? bingeGroupHint;
  final List<int> videoHeights;
  final List<String> audioTracks;
  final StreamResult direct;

  int? get displaySizeBytes => byteSize ?? StreamSize.fromTitle(title);

  StreamChoice withMetadata({
    List<int>? videoHeights,
    List<String>? audioTracks,
  }) => StreamChoice(
    id: id,
    providerId: providerId,
    provider: provider,
    title: title,
    quality: quality,
    direct: direct,
    audio: audio,
    byteSize: byteSize,
    bingeGroupHint: bingeGroupHint,
    videoHeights: videoHeights ?? this.videoHeights,
    audioTracks: audioTracks ?? this.audioTracks,
  );
  String? get audioType {
    final text = '${audio ?? ''} $title'.toLowerCase();
    if (RegExp(r'\bdual[ .-]?audio\b').hasMatch(text)) return 'Both';
    if (RegExp(r'\bdub(?:bed)?\b').hasMatch(text)) return 'Dub';
    if (RegExp(r'\bsub(?:bed)?\b').hasMatch(text)) return 'Sub';
    return null;
  }

  static StreamChoice? fromScraper(
    String provider,
    Map<String, dynamic> data,
    int index,
  ) {
    final raw = data['url'];
    final url = (raw is Map ? raw['url'] : raw)?.toString().trim() ?? '';
    final uri = Uri.tryParse(url);
    if (uri == null || !isPublicWebUrl(uri)) return null;
    final quality = data['quality']?.toString() ?? 'Unknown quality';
    final audio = data['language']?.toString();
    final type = data['type']?.toString().toLowerCase();
    final subtitles = <StreamSubtitleTrack>[];
    if (data['subtitles'] case final List items) {
      for (final item in items.whereType<Map>()) {
        final track = StreamSubtitleTrack.fromJson(
          Map<String, dynamic>.from(item),
        );
        final trackUrl = Uri.tryParse(track.url);
        if (trackUrl != null && isPublicWebUrl(trackUrl)) subtitles.add(track);
      }
    }
    return StreamChoice(
      id: 'builtin:$provider:$index',
      providerId: 'builtin:$provider',
      provider: provider,
      title: (data['title'] ?? data['name'] ?? provider).toString(),
      quality: quality,
      audio: audio,
      byteSize:
          StreamSize.parse(data['sizeBytes']) ?? StreamSize.parse(data['size']),
      bingeGroupHint: data['bingeGroup'] is String
          ? (data['bingeGroup'] as String).trim()
          : null,
      direct: StreamResult(
        url: url,
        quality: quality,
        provider: provider,
        subtitles: subtitles,
        headers: _headers(data['headers']),
        selectedAudio: audio ?? '',
        isM3U8:
            type == 'hls' ||
            type == 'm3u8' ||
            uri.path.toLowerCase().endsWith('.m3u8'),
      ),
    );
  }
}

Map<String, String> _headers(dynamic value) {
  if (value is! Map) return const {};
  final validName = RegExp(r"^[!#$%&'*+.^_`|~0-9A-Za-z-]+$");
  final invalidValue = RegExp(r'[\r\n\x00]');
  return {
    for (final entry in value.entries)
      if (entry.key is String &&
          entry.value is String &&
          validName.hasMatch(entry.key) &&
          !invalidValue.hasMatch(entry.value) &&
          !const {
            'host',
            'connection',
            'range',
            'content-length',
          }.contains(entry.key.toString().toLowerCase()))
        entry.key as String: entry.value as String,
  };
}
