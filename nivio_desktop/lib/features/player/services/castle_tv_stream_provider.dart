import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:pointycastle/export.dart';

import '../../../shared/models/stream_result.dart';
import '../models/playback_request.dart';

class CastleTvStreamProvider {
  CastleTvStreamProvider({Dio? dio})
    : _dio =
          dio ??
          Dio(
            BaseOptions(
              baseUrl: _mainUrl,
              connectTimeout: const Duration(seconds: 15),
              receiveTimeout: const Duration(seconds: 20),
              validateStatus: (status) => status != null && status < 600,
              headers: const {
                'Accept': 'application/json',
                'User-Agent': _desktopUserAgent,
              },
            ),
          );

  static const String providerName = 'CastleTV';
  static const String _mainUrl = 'https://api.hlowb.com';
  static const String _channel = 'IndiaA';
  static const String _packageName = 'com.external.castle';
  static const String _keySuffix = 'T!BgJB';
  static const String _desktopUserAgent =
      'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36';

  final Dio _dio;
  Uint8List? _cachedCipherKey;

  Future<StreamResult?> resolve(PlaybackRequest request) async {
    if (!_supports(request)) return null;

    try {
      final securityKey = await _securityKey();
      if (securityKey == null) return null;

      final searchResults = await _search(request.title, securityKey);
      final candidate = _selectCandidate(searchResults, request);
      if (candidate == null) return null;

      final details = await _details(candidate.id, securityKey);
      if (details == null) return null;

      final episode = _selectEpisode(details, request);
      if (episode == null) return null;

      final tracks = _tracksFrom(episode);
      final selectedTrack = _selectTrack(tracks, request.preferredAudioTrack);
      final selectedQuality = _selectQuality(
        _qualitiesFrom(episode),
        episode,
        request.preferredQuality,
      );

      final video = await _loadVideo(
        movieId: candidate.id,
        episodeId: episode.id,
        languageId: selectedTrack?.languageId,
        resolution: selectedQuality?.resolution,
        securityKey: securityKey,
      );
      final sources = _sourcesFrom(video, selectedQuality);
      if (sources.isEmpty) return null;

      final subtitles = [..._subtitlesFrom(episode), ..._subtitlesFrom(video)];
      final selected = _selectSource(sources, request.preferredQuality);

      return StreamResult(
        url: selected.url,
        quality: selected.quality,
        provider: providerName,
        subtitles: _dedupeSubtitles(subtitles),
        availableQualities: _dedupe(sources.map((source) => source.quality)),
        availableAudios: _dedupe(tracks.map((track) => track.languageName)),
        selectedAudio: selectedTrack?.languageName ?? '',
        isM3U8: _isHls(selected.url),
        headers: const {
          'Referer': 'https://api.hlowb.com/',
          'Origin': 'https://api.hlowb.com',
          'User-Agent': _desktopUserAgent,
        },
        sources: sources,
      );
    } on DioException {
      return null;
    } on FormatException {
      return null;
    } on ArgumentError {
      return null;
    }
  }

  bool _supports(PlaybackRequest request) =>
      request.mediaType == PlaybackMediaType.movie ||
      request.mediaType == PlaybackMediaType.tv ||
      request.mediaType == PlaybackMediaType.unknown;

  Future<Uint8List?> _securityKey() async {
    final cached = _cachedCipherKey;
    if (cached != null) return cached;

    final response = await _dio.get<Object?>(
      '/v0.1/system/getSecurityKey/1',
      queryParameters: const {
        'channel': _channel,
        'clientType': 1,
        'lang': 'en-US',
      },
    );
    if (response.statusCode != 200) return null;
    final data = _asMap(response.data)?['data']?.toString();
    if (data == null || data.isEmpty) return null;

    final key = Uint8List.fromList([
      ...base64Decode(data),
      ...utf8.encode(_keySuffix),
    ]);
    if (key.length != 16) return null;
    _cachedCipherKey = key;
    return key;
  }

  Future<List<_CastleSearchResult>> _search(
    String title,
    Uint8List securityKey,
  ) async {
    final response = await _dio.get<String>(
      '/film-api/v1.1.0/movie/searchByKeyword',
      queryParameters: {
        'channel': _channel,
        'clientType': 1,
        'keyword': title,
        'lang': 'en-US',
        'mode': 1,
        'packageName': _packageName,
        'page': 1,
        'size': 30,
      },
      options: Options(responseType: ResponseType.plain),
    );
    if (response.statusCode != 200 || response.data == null) return const [];
    final decoded = _decryptJson(response.data!, securityKey);
    final data = _asMap(decoded?['data']);
    final list = _asList(data?['rows']).isNotEmpty
        ? _asList(data?['rows'])
        : _asList(data?['list']);
    final results = <_CastleSearchResult>[];
    for (final raw in list) {
      final item = _CastleSearchResult.fromJson(raw);
      if (item != null) results.add(item);
    }
    return results;
  }

  Future<Map<String, dynamic>?> _details(
    int movieId,
    Uint8List securityKey,
  ) async {
    final response = await _dio.get<String>(
      '/film-api/v1.9.9/movie',
      queryParameters: {
        'channel': _channel,
        'clientType': 1,
        'lang': 'en-US',
        'movieId': movieId,
        'packageName': _packageName,
      },
      options: Options(responseType: ResponseType.plain),
    );
    if (response.statusCode != 200 || response.data == null) return null;
    return _asMap(_decryptJson(response.data!, securityKey)?['data']);
  }

  Future<Map<String, dynamic>?> _loadVideo({
    required int movieId,
    required int episodeId,
    required int? languageId,
    required int? resolution,
    required Uint8List securityKey,
  }) async {
    final body = <String, Object?>{
      'mode': '1',
      'appMarket': 'GuanWang',
      'clientType': '1',
      'woolUser': 'false',
      'apkSignKey': 'ED0955EB04E67A1D9F3305B95454FED485261475',
      'androidVersion': '13',
      if (languageId != null) 'languageId': '$languageId',
      'movieId': '$movieId',
      'episodeId': '$episodeId',
      'isNewUser': 'true',
      'resolution': '${resolution ?? 2}',
      'packageName': _packageName,
    };

    final response = await _dio.post<String>(
      '/film-api/v2.0.1/movie/getVideo2',
      queryParameters: const {
        'clientType': 1,
        'packageName': _packageName,
        'channel': _channel,
        'lang': 'en-US',
      },
      data: body,
      options: Options(
        contentType: Headers.jsonContentType,
        responseType: ResponseType.plain,
      ),
    );
    if (response.statusCode != 200 || response.data == null) return null;
    final decoded = _decryptJson(response.data!, securityKey);
    final data = _asMap(decoded?['data']);
    if (_firstUrl(data) == null) return null;
    return data;
  }

  Map<String, dynamic>? _decryptJson(String encrypted, Uint8List securityKey) {
    final cipher =
        PaddedBlockCipherImpl(PKCS7Padding(), CBCBlockCipher(AESEngine()))
          ..init(
            false,
            PaddedBlockCipherParameters<ParametersWithIV<KeyParameter>, Null>(
              ParametersWithIV<KeyParameter>(
                KeyParameter(securityKey),
                securityKey,
              ),
              null,
            ),
          );
    final clear = cipher.process(base64Decode(encrypted.trim()));
    return _asMap(jsonDecode(utf8.decode(clear)));
  }

  _CastleSearchResult? _selectCandidate(
    List<_CastleSearchResult> results,
    PlaybackRequest request,
  ) {
    if (results.isEmpty) return null;
    final sorted = [...results]
      ..sort((a, b) {
        final media = _mediaScore(
          b,
          request,
        ).compareTo(_mediaScore(a, request));
        if (media != 0) return media;
        return _titleScore(
          b.title,
          request.title,
        ).compareTo(_titleScore(a.title, request.title));
      });
    return sorted.first;
  }

  int _mediaScore(_CastleSearchResult result, PlaybackRequest request) {
    if (request.mediaType == PlaybackMediaType.movie && result.movieType == 2) {
      return 4;
    }
    if (request.mediaType == PlaybackMediaType.tv && result.movieType != 2) {
      return 4;
    }
    return 0;
  }

  int _titleScore(String candidate, String target) {
    final a = _normalizeTitle(candidate);
    final b = _normalizeTitle(target);
    if (a == b) return 10;
    if (a.contains(b) || b.contains(a)) return 5;
    return 0;
  }

  _CastleEpisode? _selectEpisode(
    Map<String, dynamic> details,
    PlaybackRequest request,
  ) {
    final episodes = <_CastleEpisode>[];
    for (final raw in _asList(details['episodes'])) {
      final episode = _CastleEpisode.fromJson(raw);
      if (episode != null) episodes.add(episode);
    }
    if (episodes.isEmpty) return null;
    if (request.mediaType == PlaybackMediaType.movie) return episodes.first;
    final requestedEpisode = request.episode ?? 1;
    return episodes.firstWhere(
      (episode) => episode.number == requestedEpisode,
      orElse: () => episodes.first,
    );
  }

  List<_CastleTrack> _tracksFrom(_CastleEpisode episode) {
    final tracks = <_CastleTrack>[];
    for (final raw in _asList(episode.raw['tracks'])) {
      final track = _CastleTrack.fromJson(raw);
      if (track != null) tracks.add(track);
    }
    tracks.sort((a, b) => a.order.compareTo(b.order));
    return tracks;
  }

  List<_CastleQuality> _qualitiesFrom(_CastleEpisode episode) {
    final qualities = <_CastleQuality>[];
    for (final raw in _asList(episode.raw['videos'])) {
      final quality = _CastleQuality.fromJson(raw);
      if (quality != null) qualities.add(quality);
    }
    qualities.sort((a, b) => b.height.compareTo(a.height));
    return qualities;
  }

  _CastleTrack? _selectTrack(
    List<_CastleTrack> tracks,
    String? preferredAudio,
  ) {
    if (tracks.isEmpty) return null;
    final preferred = preferredAudio?.trim();
    if (preferred != null && preferred.isNotEmpty) {
      for (final track in tracks) {
        if (_languageMatches(track.languageName, preferred)) return track;
      }
    }
    return tracks.firstWhere(
      (track) => track.isDefault,
      orElse: () => tracks.first,
    );
  }

  _CastleQuality? _selectQuality(
    List<_CastleQuality> qualities,
    _CastleEpisode episode,
    String? preferredQuality,
  ) {
    if (qualities.isEmpty) return null;
    final playable = qualities
        .where((quality) => !quality.premiumOnly)
        .toList();
    final preferred = preferredQuality?.trim();
    if (preferred != null && preferred.isNotEmpty) {
      for (final quality in playable) {
        if (quality.label.toLowerCase().contains(preferred.toLowerCase())) {
          return quality;
        }
      }
    }
    if (playable.isNotEmpty) {
      for (final quality in playable) {
        if (quality.resolution == episode.playResolution) return quality;
      }
      return playable.first;
    }
    if (preferred != null && preferred.isNotEmpty) {
      for (final quality in qualities) {
        if (quality.label.toLowerCase().contains(preferred.toLowerCase())) {
          return quality;
        }
      }
    }
    return qualities.first;
  }

  List<StreamSource> _sourcesFrom(
    Map<String, dynamic>? video,
    _CastleQuality? selectedQuality,
  ) {
    if (video == null) return const [];
    final sources = <StreamSource>[];
    final baseUrl = _firstUrl(video);
    if (baseUrl != null) {
      sources.add(
        StreamSource(
          url: baseUrl,
          quality: selectedQuality?.label ?? 'Auto',
          isM3U8: _isHls(baseUrl),
        ),
      );
    }
    for (final raw in _asList(video['videos'])) {
      final item = _asMap(raw);
      final url = _firstUrl(item);
      if (url == null || sources.any((source) => source.url == url)) continue;
      final quality =
          item?['resolutionDescription']?.toString() ??
          item?['quality']?.toString() ??
          item?['label']?.toString() ??
          selectedQuality?.label ??
          'Auto';
      sources.add(
        StreamSource(url: url, quality: quality, isM3U8: _isHls(url)),
      );
    }
    sources.sort(
      (a, b) => _resolution(b.quality).compareTo(_resolution(a.quality)),
    );
    return sources;
  }

  StreamSource _selectSource(List<StreamSource> sources, String? preferred) {
    final target = preferred?.trim().toLowerCase();
    if (target != null && target.isNotEmpty) {
      for (final source in sources) {
        if (source.quality.toLowerCase().contains(target)) return source;
      }
    }
    return sources.first;
  }

  List<SubtitleTrack> _subtitlesFrom(Object? raw) {
    final container = raw is _CastleEpisode ? raw.raw : _asMap(raw);
    final subtitles = <SubtitleTrack>[];
    for (final item in _asList(container?['subtitles'])) {
      final data = _asMap(item);
      final url = data?['url']?.toString().trim();
      if (url == null || url.isEmpty) continue;
      subtitles.add(
        SubtitleTrack(
          url: url,
          lang:
              data?['title']?.toString() ??
              data?['abbreviate']?.toString() ??
              'Unknown',
        ),
      );
    }
    return subtitles;
  }

  List<SubtitleTrack> _dedupeSubtitles(List<SubtitleTrack> subtitles) {
    final seen = <String>{};
    final deduped = <SubtitleTrack>[];
    for (final subtitle in subtitles) {
      if (seen.add('${subtitle.lang}|${subtitle.url}')) deduped.add(subtitle);
    }
    return deduped;
  }

  static List<String> _dedupe(Iterable<String> values) {
    final seen = <String>{};
    final deduped = <String>[];
    for (final value in values) {
      final trimmed = value.trim();
      if (trimmed.isNotEmpty && seen.add(trimmed.toLowerCase())) {
        deduped.add(trimmed);
      }
    }
    return deduped;
  }

  static String? _firstUrl(Map<String, dynamic>? data) {
    if (data == null) return null;
    for (final key in const ['videoUrl', 'url', 'playUrl', 'file', 'link']) {
      final value = data[key]?.toString().trim();
      if (value != null && value.startsWith('http')) return value;
    }
    return null;
  }

  static bool _languageMatches(String language, String preferred) {
    final source = language.toLowerCase();
    final target = preferred.toLowerCase();
    return source == target ||
        source.contains(target) ||
        target.contains(source);
  }

  static bool _isHls(String url) => Uri.parse(url).path.endsWith('.m3u8');

  static int _resolution(String quality) {
    final match = RegExp(r'(\d{3,4})').firstMatch(quality);
    return match == null ? 0 : int.tryParse(match.group(1)!) ?? 0;
  }

  static String _normalizeTitle(String value) => value
      .toLowerCase()
      .replaceAll(RegExp(r'\[[^\]]+\]'), '')
      .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
      .trim();

  static Map<String, dynamic>? _asMap(Object? value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) return Map<String, dynamic>.from(value);
    return null;
  }

  static List<Object?> _asList(Object? value) {
    if (value is List) return value;
    return const [];
  }
}

class _CastleSearchResult {
  const _CastleSearchResult({
    required this.id,
    required this.title,
    required this.movieType,
  });

  final int id;
  final String title;
  final int? movieType;

  static _CastleSearchResult? fromJson(Object? raw) {
    final json = CastleTvStreamProvider._asMap(raw);
    final id = int.tryParse(json?['id']?.toString() ?? '');
    final title = json?['title']?.toString().trim();
    if (id == null || title == null || title.isEmpty) return null;
    return _CastleSearchResult(
      id: id,
      title: title,
      movieType: int.tryParse(json?['movieType']?.toString() ?? ''),
    );
  }
}

class _CastleEpisode {
  const _CastleEpisode({
    required this.id,
    required this.number,
    required this.playResolution,
    required this.raw,
  });

  final int id;
  final int number;
  final int? playResolution;
  final Map<String, dynamic> raw;

  static _CastleEpisode? fromJson(Object? raw) {
    final json = CastleTvStreamProvider._asMap(raw);
    final id = int.tryParse(json?['id']?.toString() ?? '');
    if (json == null || id == null) return null;
    return _CastleEpisode(
      id: id,
      number: int.tryParse(json['number']?.toString() ?? '') ?? 1,
      playResolution: int.tryParse(json['playResolution']?.toString() ?? ''),
      raw: json,
    );
  }
}

class _CastleTrack {
  const _CastleTrack({
    required this.languageId,
    required this.languageName,
    required this.isDefault,
    required this.order,
  });

  final int languageId;
  final String languageName;
  final bool isDefault;
  final int order;

  static _CastleTrack? fromJson(Object? raw) {
    final json = CastleTvStreamProvider._asMap(raw);
    final languageId = int.tryParse(json?['languageId']?.toString() ?? '');
    final languageName = json?['languageName']?.toString().trim();
    if (languageId == null || languageName == null || languageName.isEmpty) {
      return null;
    }
    return _CastleTrack(
      languageId: languageId,
      languageName: languageName,
      isDefault: json?['isDefault'] == true,
      order: int.tryParse(json?['order']?.toString() ?? '') ?? 999,
    );
  }
}

class _CastleQuality {
  const _CastleQuality({
    required this.resolution,
    required this.label,
    required this.premiumOnly,
  });

  final int resolution;
  final String label;
  final bool premiumOnly;

  int get height => CastleTvStreamProvider._resolution(label);

  static _CastleQuality? fromJson(Object? raw) {
    final json = CastleTvStreamProvider._asMap(raw);
    final resolution = int.tryParse(json?['resolution']?.toString() ?? '');
    if (resolution == null) return null;
    return _CastleQuality(
      resolution: resolution,
      label: json?['resolutionDescription']?.toString() ?? '${resolution}p',
      premiumOnly: json?['premiumProPermission'] == true,
    );
  }
}
