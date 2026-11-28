import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

class M3u8Track {
  final String language;
  final String name;

  M3u8Track({required this.language, required this.name});
}

class M3u8VideoResolution {
  final String quality;
  final String url;

  M3u8VideoResolution({required this.quality, required this.url});
}

class M3u8Parser {
  static final Dio _dio = Dio();
  static final _resolution = RegExp(
    r'(?:^|[:,])\s*RESOLUTION=\d+x(\d+)',
    caseSensitive: false,
  );

  static List<int> videoHeights(String manifest) {
    final heights = <int>{};
    for (final rawLine in manifest.split('\n')) {
      final line = rawLine.trim();
      if (!line.startsWith('#EXT-X-STREAM-INF:')) continue;
      final height = int.tryParse(_resolution.firstMatch(line)?.group(1) ?? '');
      if (height != null && height > 0) heights.add(height);
    }
    return heights.toList()..sort((a, b) => b.compareTo(a));
  }

  static List<String> audioLanguages(String manifest) {
    final languages = <String>[];
    final attribute = RegExp(r'(?:^|,)\s*([A-Z-]+)=("([^"]*)"|[^,]*)');
    for (final rawLine in manifest.split('\n')) {
      final line = rawLine.trim();
      const tag = '#EXT-X-MEDIA:';
      if (!line.startsWith(tag)) continue;
      final values = {
        for (final match in attribute.allMatches(line.substring(tag.length)))
          match.group(1)!: (match.group(3) ?? match.group(2)!).trim(),
      };
      if (values['TYPE'] == 'AUDIO') {
        final language = values['LANGUAGE'];
        languages.add(
          language == null || language.isEmpty || language.toLowerCase() == 'und'
              ? values['NAME'] ?? 'und'
              : language,
        );
      }
    }
    return languages;
  }

  static Future<List<M3u8VideoResolution>> parseVideoResolutions(
      String url, Map<String, String>? headers) async {
    try {
      final response = await _dio.get(
        url,
        options: Options(headers: headers),
      );

      final content = response.data.toString();
      final lines = content.split('\n');
      final List<M3u8VideoResolution> resolutions = [];

      for (int i = 0; i < lines.length; i++) {
        final line = lines[i].trim();
        if (line.startsWith('#EXT-X-STREAM-INF:')) {
          final resMatch = _resolution.firstMatch(line);
          String quality = 'auto';
          if (resMatch != null) {
            quality = '${resMatch.group(1)}p';
          }
          if (i + 1 < lines.length) {
            final uri = lines[i + 1].trim();
            if (uri.isNotEmpty && !uri.startsWith('#')) {
              final resolvedUrl = _resolveUrl(url, uri);
              // Avoid duplicates
              if (!resolutions.any((r) => r.url == resolvedUrl)) {
                resolutions.add(M3u8VideoResolution(quality: quality, url: resolvedUrl));
              }
            }
          }
        }
      }
      return resolutions;
    } catch (e) {
      debugPrint('M3u8Parser parseVideoResolutions Error: $e');
      return [];
    }
  }

  static Future<Map<String, List<M3u8Track>>> parseTracks(
      String url, Map<String, String>? headers) async {
    try {
      final response = await _dio.get(
        url,
        options: Options(headers: headers),
      );

      final content = response.data.toString();
      final lines = content.split('\n');

      final List<M3u8Track> audios = [];
      final List<M3u8Track> subtitles = [];

      for (final line in lines) {
        if (line.startsWith('#EXT-X-MEDIA:')) {
          final typeMatch = RegExp(r'TYPE=([A-Z]+)').firstMatch(line);
          final langMatch = RegExp(r'LANGUAGE="([^"]+)"').firstMatch(line);
          final nameMatch = RegExp(r'NAME="([^"]+)"').firstMatch(line);

          if (typeMatch != null && langMatch != null && nameMatch != null) {
            final type = typeMatch.group(1);
            final lang = langMatch.group(1)!;
            final name = nameMatch.group(1)!;

            if (type == 'AUDIO') {
              audios.add(M3u8Track(language: lang, name: name));
            } else if (type == 'SUBTITLES') {
              subtitles.add(M3u8Track(language: lang, name: name));
            }
          }
        }
      }

      return {
        'audio': audios,
        'subtitle': subtitles,
      };
    } catch (e) {
      debugPrint('M3u8Parser Error: $e');
      return {'audio': [], 'subtitle': []};
    }
  }

  static String _resolveUrl(String baseUrl, String uri) {
    if (uri.startsWith('http')) return uri;
    final baseUri = Uri.parse(baseUrl);
    return baseUri.resolve(uri).toString();
  }

  /// Splits an HLS master into what a download needs: the video variant
  /// (the one matching [preferredQuality], e.g. "1080p", else the first), the
  /// audio rendition in [audioLang] from that variant's own audio group (many
  /// masters keep the sound in a separate `#EXT-X-MEDIA` playlist that the
  /// variant only references), and the subtitles in [subLang].
  static Future<M3u8Streams?> resolveStreams(
    String masterUrl,
    Map<String, String>? headers,
    String? audioLang,
    String? subLang, {
    String? preferredQuality,
  }) async {
    try {
      final response = await _dio.get(
        masterUrl,
        options: Options(headers: headers),
      );

      final content = response.data.toString();
      final lines = content.split('\n');

      if (!content.contains('#EXT-X-STREAM-INF') && !content.contains('#EXT-X-MEDIA')) {
        return M3u8Streams(videoUrl: masterUrl);
      }

      final attribute = RegExp(r'([A-Z0-9-]+)=("([^"]*)"|[^,]*)');
      Map<String, String> attributes(String body) => {
        for (final match in attribute.allMatches(body))
          match.group(1)!: (match.group(3) ?? match.group(2)!).trim(),
      };

      final audios = <Map<String, String>>[];
      final subtitles = <Map<String, String>>[];
      final variants = <({String url, int height, int bandwidth, String? audioGroup})>[];

      for (int i = 0; i < lines.length; i++) {
        final line = lines[i].trim();
        if (line.startsWith('#EXT-X-MEDIA:')) {
          final media = attributes(line.substring('#EXT-X-MEDIA:'.length));
          if (media['URI'] == null) continue;
          if (media['TYPE'] == 'AUDIO') audios.add(media);
          if (media['TYPE'] == 'SUBTITLES') subtitles.add(media);
        } else if (line.startsWith('#EXT-X-STREAM-INF:')) {
          final info = attributes(line.substring('#EXT-X-STREAM-INF:'.length));
          String? uri;
          for (int j = i + 1; j < lines.length; j++) {
            final next = lines[j].trim();
            if (next.isEmpty || next.startsWith('#')) continue;
            uri = next;
            break;
          }
          if (uri == null) continue;
          final height = int.tryParse(
                RegExp(r'\d+x(\d+)').firstMatch(info['RESOLUTION'] ?? '')?.group(1) ?? '',
              ) ??
              0;
          variants.add((
            url: _resolveUrl(masterUrl, uri),
            height: height,
            bandwidth: int.tryParse(info['BANDWIDTH'] ?? '') ?? 0,
            audioGroup: info['AUDIO'],
          ));
        }
      }

      if (variants.isEmpty) return M3u8Streams(videoUrl: masterUrl);

      // The variant: the chosen quality (highest bitrate among equals), else
      // the best one below it, else the smallest above it. No choice keeps
      // the first, as before.
      final wanted = int.tryParse(
        RegExp(r'(\d{3,4})').firstMatch(preferredQuality ?? '')?.group(1) ?? '',
      );
      var variant = variants.first;
      if (wanted != null && variants.any((v) => v.height > 0)) {
        int byBandwidth(
          ({String url, int height, int bandwidth, String? audioGroup}) a,
          ({String url, int height, int bandwidth, String? audioGroup}) b,
        ) => b.bandwidth.compareTo(a.bandwidth);
        final exact = variants.where((v) => v.height == wanted).toList()..sort(byBandwidth);
        final below = variants.where((v) => v.height > 0 && v.height < wanted).toList()
          ..sort((a, b) => b.height != a.height ? b.height.compareTo(a.height) : byBandwidth(a, b));
        final above = variants.where((v) => v.height > wanted).toList()
          ..sort((a, b) => a.height != b.height ? a.height.compareTo(b.height) : byBandwidth(a, b));
        variant = exact.firstOrNull ?? below.firstOrNull ?? above.firstOrNull ?? variant;
      }

      // Either label can carry the language: LANGUAGE="jpn", NAME="Japanese".
      bool matches(Map<String, String> media, String wanted) {
        final target = wanted.toLowerCase();
        return [media['LANGUAGE'], media['NAME']].any((value) {
          final label = (value ?? '').toLowerCase();
          return label.isNotEmpty && (label.contains(target) || target.contains(label));
        });
      }

      // Audio from the variant's own group when it names one.
      final group = variant.audioGroup;
      final audioPool = group != null && audios.any((a) => a['GROUP-ID'] == group)
          ? audios.where((a) => a['GROUP-ID'] == group).toList()
          : audios;
      Map<String, String>? audio;
      if (audioLang != null && audioLang.isNotEmpty) {
        audio = audioPool.where((a) => matches(a, audioLang)).firstOrNull;
      }
      audio ??= audioPool.where((a) => a['DEFAULT'] == 'YES').firstOrNull;
      audio ??= audioPool.firstOrNull;

      Map<String, String>? subtitle;
      if (subLang != null && subLang.isNotEmpty && subLang != 'Off') {
        subtitle = subtitles.where((t) => matches(t, subLang)).firstOrNull ??
            subtitles.firstOrNull;
      }

      return M3u8Streams(
        videoUrl: variant.url,
        audioUrl: audio == null ? null : _resolveUrl(masterUrl, audio['URI']!),
        subtitleUrl: subtitle == null ? null : _resolveUrl(masterUrl, subtitle['URI']!),
      );
    } catch (e) {
      debugPrint('M3u8Parser Error (resolveStreams): $e');
      return M3u8Streams(videoUrl: masterUrl);
    }
  }

  static Future<int> getM3u8Duration(String url, Map<String, String>? headers) async {
    try {
      final response = await _dio.get(
        url,
        options: Options(headers: headers),
      );
      final lines = response.data.toString().split('\n');
      double totalSeconds = 0;
      for (final line in lines) {
        if (line.startsWith('#EXTINF:')) {
          final val = line.replaceAll('#EXTINF:', '').split(',').first.trim();
          totalSeconds += double.tryParse(val) ?? 0;
        }
      }
      return (totalSeconds * 1000).toInt();
    } catch (e) {
      debugPrint('M3u8Parser Error (getDuration): $e');
      return 0;
    }
  }
  static Future<List<M3u8Segment>> fetchSegments(String url, Map<String, String>? headers) async {
    try {
      final response = await _dio.get(
        url,
        options: Options(headers: headers),
      );
      final lines = response.data.toString().split('\n');
      final List<M3u8Segment> segments = [];
      
      M3u8EncryptionKey? currentKey;
      double? nextDuration;

      for (int i = 0; i < lines.length; i++) {
        final line = lines[i].trim();
        if (line.isEmpty) continue;

        if (line.startsWith('#EXT-X-KEY:')) {
          final methodMatch = RegExp(r'METHOD=([^,]+)').firstMatch(line);
          final uriMatch = RegExp(r'URI="([^"]+)"').firstMatch(line);
          final ivMatch = RegExp(r'IV=([^,]+)').firstMatch(line);
          
          if (methodMatch != null && uriMatch != null) {
            final method = methodMatch.group(1)!;
            final keyUri = _resolveUrl(url, uriMatch.group(1)!);
            if (method != 'NONE') {
              currentKey = M3u8EncryptionKey(method: method, uri: keyUri, iv: ivMatch?.group(1));
            } else {
              currentKey = null;
            }
          }
        } else if (line.startsWith('#EXTINF:')) {
          final val = line.replaceAll('#EXTINF:', '').split(',').first.trim();
          nextDuration = double.tryParse(val);
        } else if (!line.startsWith('#')) {
          if (nextDuration != null) {
            segments.add(M3u8Segment(
              url: _resolveUrl(url, line),
              duration: nextDuration,
              encryptionKey: currentKey,
            ));
            nextDuration = null;
          }
        }
      }
      return segments;
    } catch (e) {
      debugPrint('M3u8Parser Error (fetchSegments): $e');
      return [];
    }
  }
}

class M3u8Streams {
  final String videoUrl;
  final String? audioUrl;
  final String? subtitleUrl;

  M3u8Streams({required this.videoUrl, this.audioUrl, this.subtitleUrl});
}

class M3u8EncryptionKey {
  final String method;
  final String uri;
  final String? iv;

  M3u8EncryptionKey({required this.method, required this.uri, this.iv});
}

class M3u8Segment {
  final String url;
  final double duration;
  final M3u8EncryptionKey? encryptionKey;

  M3u8Segment({required this.url, required this.duration, this.encryptionKey});
}
