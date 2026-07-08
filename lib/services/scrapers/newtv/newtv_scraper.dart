import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nivio/core/debug_log.dart';
import 'package:nivio/models/stream_result.dart';

final netMirrorScraperProvider = Provider((ref) => NetMirrorScraperService(providerName: 'Nivio'));

class NetMirrorScraperService {
  final String providerName;

  NetMirrorScraperService({this.providerName = 'Nivio'});

  final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 20),
      validateStatus: (status) => status != null && status < 600,
    ),
  );

  Future<StreamResult?> fetchStreamUrl({
    required String tmdbId,
    required String title,
    required String mediaType,
    String? year,
    String? preferredAudio,
    int season = 1,
    int episode = 1,
  }) async {
    try {
      if (tmdbId.isEmpty) {
        appDebugLog('NetMirror: Missing TMDB ID');
        return null;
      }

      final isTv = mediaType != 'movie';
      
      // Fetch variants to get default paths and available dubs
      final variantsUrl = isTv 
          ? 'https://net27.cc/api/variants-tmdb/tv/$tmdbId?se=$season&ep=$episode'
          : 'https://net27.cc/api/variants-tmdb/movie/$tmdbId';
          
      final variantsRes = await _dio.get(variantsUrl, options: Options(headers: {'Accept': 'application/json'}));
      
      String? defaultSubjectId;
      String? defaultDetailPath;
      String? dubSubjectId;
      String? dubDetailPath;
      List<String> availableAudios = [];
      String actualAudio = 'Default';

      if (variantsRes.statusCode == 200 && variantsRes.data['ok'] == true) {
        defaultSubjectId = variantsRes.data['defaultSubjectId']?.toString();
        defaultDetailPath = variantsRes.data['defaultDetailPath']?.toString();
        
        final variants = variantsRes.data['variants'];
        if (variants is List) {
          for (var v in variants) {
             final lang = v['language']?.toString() ?? 'Unknown';
             availableAudios.add(lang);
             if (preferredAudio != null && lang.toLowerCase() == preferredAudio.toLowerCase()) {
                 dubSubjectId = v['dubSubjectId']?.toString();
                 actualAudio = lang;
             }
          }
        }
      }

      // Fetch dub detail path from aoneroom if a specific dub is requested
      if (dubSubjectId != null && defaultDetailPath != null) {
          final detailUrl = 'https://h5-api.aoneroom.com/wefeed-h5api-bff/detail?detailPath=$defaultDetailPath';
          final detailRes = await _dio.get(detailUrl, options: Options(headers: {'Accept': 'application/json'}));
          if (detailRes.statusCode == 200) {
             final dubs = detailRes.data['data']?['subject']?['dubs'];
             if (dubs is List) {
                for (var d in dubs) {
                   if (d['subjectId']?.toString() == dubSubjectId) {
                      dubDetailPath = d['detailPath']?.toString();
                      break;
                   }
                }
             }
          }
      }

      var url = 'https://net27.cc/api/embed-tmdb/$tmdbId?type=${isTv ? 'tv' : 'movie'}&se=$season&ep=$episode';
      if (dubSubjectId != null && dubDetailPath != null && defaultSubjectId != null && defaultDetailPath != null) {
          url += '&dub=$dubSubjectId&dubdp=$dubDetailPath&sid=$defaultSubjectId&dp=$defaultDetailPath';
      }

      appDebugLog('NetMirror: Fetching API - $url');
      
      final response = await _dio.get(
        url,
        options: Options(headers: {
          'Accept': 'application/json',
          'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/116.0.0.0 Safari/537.36',
        }),
      );

      if (response.statusCode != 200) {
        appDebugLog('NetMirror: API failed with status ${response.statusCode}');
        return null;
      }

      final data = response.data;
      if (data is! Map<String, dynamic>) {
        appDebugLog('NetMirror: Unexpected response format');
        return null;
      }

      if (data['ok'] != true || data['mp4'] == null) {
        appDebugLog('NetMirror: API returned error or missing mp4 - ${data['error'] ?? 'Unknown Error'}');
        return null;
      }

      final sources = <StreamSource>[];
      final streams = data['streams'];
      
      if (streams is List && streams.isNotEmpty) {
        for (final stream in streams) {
          if (stream is! Map<String, dynamic>) continue;
          
          final streamUrl = stream['url']?.toString();
          final resolution = stream['resolution']?.toString() ?? 'auto';
          
          if (streamUrl != null && streamUrl.isNotEmpty) {
            sources.add(StreamSource(
              url: streamUrl,
              quality: '${resolution}p',
              isM3U8: streamUrl.contains('.m3u8'),
            ));
          }
        }
      } else {
        final mp4Url = data['mp4'].toString();
        if (mp4Url.isNotEmpty) {
          sources.add(StreamSource(
            url: mp4Url,
            quality: '${data['resolution'] ?? 'auto'}p',
            isM3U8: mp4Url.contains('.m3u8'),
          ));
        }
      }

      if (sources.isEmpty) {
        appDebugLog('NetMirror: No valid sources found in response');
        return null;
      }

      // Sort sources by resolution (highest first)
      sources.sort((a, b) {
        final resA = int.tryParse(a.quality.replaceAll('p', '')) ?? 0;
        final resB = int.tryParse(b.quality.replaceAll('p', '')) ?? 0;
        return resB.compareTo(resA);
      });

      final subtitles = <SubtitleTrack>[];
      final captions = data['captions'];
      if (captions is List) {
        for (final caption in captions) {
          if (caption is! Map<String, dynamic>) continue;
          final lang = caption['name']?.toString() ?? caption['lang']?.toString() ?? 'Unknown';
          var subUrl = caption['url']?.toString();
          if (subUrl != null && subUrl.isNotEmpty) {
            if (subUrl.startsWith('/')) {
              subUrl = 'https://net27.cc$subUrl';
            }
            subtitles.add(SubtitleTrack(url: subUrl, lang: lang));
          }
        }
      }

      appDebugLog('NetMirror: SUCCESS! Found ${sources.length} sources and ${subtitles.length} subtitles. Best: ${sources.first.quality}');

      return StreamResult(
        url: sources.first.url,
        quality: sources.first.quality,
        provider: providerName,
        subtitles: subtitles, 
        availableQualities: sources.map((s) => s.quality).toList(),
        availableAudios: availableAudios,
        selectedAudio: actualAudio,
        isM3U8: sources.first.isM3U8,
        headers: {'Referer': 'https://videodownloader.site/'},
        sources: sources,
      );
    } catch (e) {
      appDebugLog('NetMirror error: $e');
      return null;
    }
  }
}

