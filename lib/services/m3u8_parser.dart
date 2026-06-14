import 'package:dio/dio.dart';

class M3u8Track {
  final String language;
  final String name;

  M3u8Track({required this.language, required this.name});
}

class M3u8Parser {
  static final Dio _dio = Dio();

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
      print('M3u8Parser Error: $e');
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
      print('M3u8Parser Error (resolveStreams): $e');
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
      print('M3u8Parser Error (getDuration): $e');
      return 0;
    }
  }
}

class M3u8Streams {
  final String videoUrl;
  final String? audioUrl;
  final String? subtitleUrl;

  M3u8Streams({required this.videoUrl, this.audioUrl, this.subtitleUrl});
}
