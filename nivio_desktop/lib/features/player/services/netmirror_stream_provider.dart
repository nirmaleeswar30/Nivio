import 'package:dio/dio.dart';

import '../../../shared/models/stream_result.dart';
import '../models/playback_request.dart';

class NetMirrorStreamProvider {
  NetMirrorStreamProvider({Dio? dio})
    : _dio =
          dio ??
          Dio(
            BaseOptions(
              connectTimeout: const Duration(seconds: 15),
              receiveTimeout: const Duration(seconds: 20),
              validateStatus: (status) => status != null && status < 600,
            ),
          );

  final Dio _dio;

  Future<StreamResult?> resolve(PlaybackRequest request) async {
    final id = request.numericMediaId;
    if (id == null) return null;

    final isSeries = request.mediaType != PlaybackMediaType.movie;
    final season = request.season ?? 1;
    final episode = request.episode ?? 1;

    try {
      final variantsUrl = isSeries
          ? 'https://net27.cc/api/variants-tmdb/tv/$id?se=$season&ep=$episode'
          : 'https://net27.cc/api/variants-tmdb/movie/$id';
      final variantsResponse = await _dio.get<Object?>(
        variantsUrl,
        options: Options(headers: const {'Accept': 'application/json'}),
      );

      final variants = _asMap(variantsResponse.data);
      final defaultSubjectId = variants?['defaultSubjectId']?.toString();
      final defaultDetailPath = variants?['defaultDetailPath']?.toString();
      final variantList = _variantsFrom(variants?['variants']);
      final availableAudios = <String>[
        for (final variant in variantList) variant.language,
      ];
      final selectedVariant = _selectVariant(
        variantList,
        request.preferredAudioTrack,
      );
      final selectedAudio = selectedVariant?.language ?? 'Default';
      final selectedSubjectId = selectedVariant?.subjectId;
      var selectedDetailPath = selectedVariant?.detailPath;

      if (selectedSubjectId != null &&
          selectedSubjectId != defaultSubjectId &&
          (selectedDetailPath == null || selectedDetailPath.isEmpty) &&
          defaultDetailPath != null) {
        selectedDetailPath = await _fetchDubDetailPath(
          defaultDetailPath: defaultDetailPath,
          subjectId: selectedSubjectId,
        );
      }

      var url =
          'https://net27.cc/api/embed-tmdb/$id?type=${isSeries ? 'tv' : 'movie'}&se=$season&ep=$episode';
      if (selectedSubjectId != null &&
          selectedSubjectId != defaultSubjectId &&
          selectedDetailPath != null &&
          selectedDetailPath.isNotEmpty &&
          defaultSubjectId != null &&
          defaultDetailPath != null) {
        url +=
            '&dub=${Uri.encodeQueryComponent(selectedSubjectId)}'
            '&dubdp=${Uri.encodeQueryComponent(selectedDetailPath)}'
            '&sid=${Uri.encodeQueryComponent(defaultSubjectId)}'
            '&dp=${Uri.encodeQueryComponent(defaultDetailPath)}';
      } else if (defaultSubjectId != null && defaultDetailPath != null) {
        url +=
            '&sid=${Uri.encodeQueryComponent(defaultSubjectId)}&dp=${Uri.encodeQueryComponent(defaultDetailPath)}';
      }

      final response = await _dio.get<Object?>(
        url,
        options: Options(
          headers: const {
            'Accept': 'application/json',
            'User-Agent': _desktopUserAgent,
          },
        ),
      );
      if (response.statusCode != 200) return null;

      final data = _asMap(response.data);
      if (data == null || data['ok'] != true) return null;

      final sources = <StreamSource>[];
      final mp4 = data['mp4']?.toString();
      if (mp4 != null && mp4.isNotEmpty) {
        final resolution = data['resolution']?.toString() ?? 'auto';
        sources.add(
          StreamSource(
            url: mp4,
            quality: resolution.endsWith('p') ? resolution : '${resolution}p',
            isM3U8: _isHls(mp4),
          ),
        );
      }

      final rawStreams = data['streams'];
      if (rawStreams is List) {
        for (final raw in rawStreams) {
          final stream = _asMap(raw);
          final streamUrl = stream?['url']?.toString();
          if (streamUrl == null || streamUrl.isEmpty) continue;
          final resolution = stream?['resolution']?.toString() ?? 'auto';
          sources.add(
            StreamSource(
              url: streamUrl,
              quality: resolution.endsWith('p') ? resolution : '${resolution}p',
              isM3U8: _isHls(streamUrl),
            ),
          );
        }
      }

      if (sources.isEmpty) return null;

      sources.sort((a, b) {
        final quality = _resolution(
          b.quality,
        ).compareTo(_resolution(a.quality));
        if (quality != 0) return quality;
        return _sourceReliability(b.url).compareTo(_sourceReliability(a.url));
      });

      final subtitles = <SubtitleTrack>[];
      final captions = data['captions'];
      if (captions is List) {
        for (final raw in captions) {
          final caption = _asMap(raw);
          var subtitleUrl = caption?['url']?.toString();
          if (subtitleUrl == null || subtitleUrl.isEmpty) continue;
          if (subtitleUrl.startsWith('/')) {
            subtitleUrl = 'https://net27.cc$subtitleUrl';
          }
          subtitles.add(
            SubtitleTrack(
              url: subtitleUrl,
              lang:
                  caption?['name']?.toString() ??
                  caption?['lang']?.toString() ??
                  'Unknown',
            ),
          );
        }
      }

      final selected = sources.first;
      return StreamResult(
        url: selected.url,
        quality: selected.quality,
        provider: 'Nivio',
        subtitles: subtitles,
        availableQualities: sources.map((source) => source.quality).toList(),
        availableAudios: _dedupe(availableAudios),
        selectedAudio: selectedAudio,
        isM3U8: selected.isM3U8,
        headers: const {
          'Referer': 'https://videodownloader.site/',
          'User-Agent': _desktopUserAgent,
        },
        sources: sources,
      );
    } on DioException {
      return null;
    } on FormatException {
      return null;
    }
  }

  static Map<String, dynamic>? _asMap(Object? value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) return Map<String, dynamic>.from(value);
    return null;
  }

  static List<_NetMirrorVariant> _variantsFrom(Object? rawVariants) {
    if (rawVariants is! List) return const [];
    final variants = <_NetMirrorVariant>[];
    for (final raw in rawVariants) {
      final item = _asMap(raw);
      final language = item?['language']?.toString().trim();
      final subjectId =
          item?['dubSubjectId']?.toString() ?? item?['subjectId']?.toString();
      if (language == null || language.isEmpty) continue;
      variants.add(
        _NetMirrorVariant(
          language: language,
          subjectId: subjectId,
          detailPath: item?['detailPath']?.toString(),
        ),
      );
    }
    return variants;
  }

  static _NetMirrorVariant? _selectVariant(
    List<_NetMirrorVariant> variants,
    String? preferredAudio,
  ) {
    if (variants.isEmpty) return null;
    final preferred = preferredAudio?.trim();
    if (preferred != null && preferred.isNotEmpty) {
      for (final variant in variants) {
        if (_audioMatches(variant.language, preferred)) return variant;
      }
    }
    return variants.firstWhere(
      (variant) => variant.language.toLowerCase() == 'default',
      orElse: () => variants.first,
    );
  }

  static bool _audioMatches(String language, String preferred) {
    final audio = language.toLowerCase().trim();
    final target = preferred.toLowerCase().trim();
    if (audio == target || audio.contains(target) || target.contains(audio)) {
      return true;
    }
    final audioBase = audio
        .replaceAll(RegExp(r'\b(dub|sub|audio|language)\b'), '')
        .trim();
    final targetBase = target
        .replaceAll(RegExp(r'\b(dub|sub|audio|language)\b'), '')
        .trim();
    return audioBase.isNotEmpty &&
        targetBase.isNotEmpty &&
        (audioBase == targetBase ||
            audioBase.contains(targetBase) ||
            targetBase.contains(audioBase));
  }

  Future<String?> _fetchDubDetailPath({
    required String defaultDetailPath,
    required String subjectId,
  }) async {
    try {
      final response = await _dio.get<Object?>(
        'https://h5-api.aoneroom.com/wefeed-h5api-bff/detail',
        queryParameters: {'detailPath': defaultDetailPath},
        options: Options(headers: const {'Accept': 'application/json'}),
      );
      final data = _asMap(_asMap(response.data)?['data']);
      final subject = _asMap(data?['subject']);
      final dubs = subject?['dubs'];
      if (dubs is! List) return null;
      for (final raw in dubs) {
        final dub = _asMap(raw);
        if (dub?['subjectId']?.toString() == subjectId) {
          return dub?['detailPath']?.toString();
        }
      }
    } on DioException {
      return null;
    } on FormatException {
      return null;
    }
    return null;
  }

  static List<String> _dedupe(List<String> values) {
    final seen = <String>{};
    final result = <String>[];
    for (final value in values) {
      final trimmed = value.trim();
      final key = trimmed.toLowerCase();
      if (trimmed.isEmpty || !seen.add(key)) continue;
      result.add(trimmed);
    }
    return result;
  }

  static bool _isHls(String url) =>
      url.toLowerCase().contains('.m3u8') ||
      url.toLowerCase().contains('application/vnd.apple.mpegurl');

  static int _resolution(String quality) =>
      int.tryParse(quality.replaceAll(RegExp('[^0-9]'), '')) ?? 0;

  static int _sourceReliability(String url) {
    final host = Uri.tryParse(url)?.host.toLowerCase() ?? '';
    return host.contains('net27-r2-cache') ? 1 : 0;
  }
}

const String _desktopUserAgent =
    'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 '
    '(KHTML, like Gecko) Chrome/137.0.0.0 Safari/537.36';

class _NetMirrorVariant {
  const _NetMirrorVariant({
    required this.language,
    required this.subjectId,
    required this.detailPath,
  });

  final String language;
  final String? subjectId;
  final String? detailPath;
}
