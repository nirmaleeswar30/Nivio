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
          final resMatch = RegExp(r'RESOLUTION=(\d+)x(\d+)').firstMatch(line);
          String quality = 'auto';
          if (resMatch != null) {
            quality = '${resMatch.group(2)}p';
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

  static Future<M3u8Streams?> resolveStreams(
      String masterUrl, Map<String, String>? headers, String? audioLang, String? subLang) async {
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

      String? videoUrl;
      String? audioUrl;
      String? subUrl;
      String? firstAudioUrl;
      String? firstSubUrl;

      for (int i = 0; i < lines.length; i++) {
        final line = lines[i].trim();

        if (line.startsWith('#EXT-X-MEDIA:')) {
          final typeMatch = RegExp(r'TYPE=([A-Z]+)').firstMatch(line);
          final langMatch = RegExp(r'LANGUAGE="([^"]+)"').firstMatch(line);
          final nameMatch = RegExp(r'NAME="([^"]+)"').firstMatch(line);
          final uriMatch = RegExp(r'URI="([^"]+)"').firstMatch(line);

          if (typeMatch != null && uriMatch != null) {
            final type = typeMatch.group(1);
            final uri = uriMatch.group(1)!;
            final lang = (langMatch?.group(1) ?? nameMatch?.group(1) ?? '').toLowerCase();

            if (type == 'AUDIO') {
              if (firstAudioUrl == null) firstAudioUrl = _resolveUrl(masterUrl, uri);
              
              if (audioLang != null && audioLang.isNotEmpty) {
                final targetLang = audioLang.toLowerCase();
                if (lang.contains(targetLang) || targetLang.contains(lang)) {
                  audioUrl = _resolveUrl(masterUrl, uri);
                }
              }
            } else if (type == 'SUBTITLES') {
              if (firstSubUrl == null) firstSubUrl = _resolveUrl(masterUrl, uri);
              
              if (subLang != null && subLang.isNotEmpty && subLang != 'Off') {
                final targetLang = subLang.toLowerCase();
                if (lang.contains(targetLang) || targetLang.contains(lang)) {
                  subUrl = _resolveUrl(masterUrl, uri);
                }
              }
            }
          }
        }

        if (line.startsWith('#EXT-X-STREAM-INF:')) {
          if (i + 1 < lines.length) {
            final uri = lines[i + 1].trim();
            if (uri.isNotEmpty && !uri.startsWith('#')) {
              if (videoUrl == null) {
                videoUrl = _resolveUrl(masterUrl, uri);
              }
            }
          }
        }
      }

      // Default to first available tracks if a specific language wasn't matched
      audioUrl ??= firstAudioUrl;
      if (subLang != null && subLang != 'Off') {
        subUrl ??= firstSubUrl;
      }

      if (videoUrl == null) {
        return M3u8Streams(videoUrl: masterUrl);
      }

      return M3u8Streams(videoUrl: videoUrl, audioUrl: audioUrl, subtitleUrl: subUrl);
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
