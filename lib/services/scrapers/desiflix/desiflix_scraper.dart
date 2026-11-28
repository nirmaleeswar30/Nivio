import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:nivio/models/search_result.dart';
import 'package:nivio/services/network_client_factory.dart';
import 'package:nivio/services/tmdb_service.dart';

/// Dart implementation of the DesiFlix movie and episode lookup.
class DesiFlixScraper {
  DesiFlixScraper({http.Client? client, TmdbService? tmdbService})
    : _client = client,
      _tmdb = tmdbService;

  static const _host = 'manifest.desitvhub.eu.org';
  static const _provider = 'DesiFlix';
  static const _userAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36';
  static const _timeout = Duration(seconds: 12);
  static final _fileSize = RegExp(r'\d+(?:\.\d+)?\s*(?:gb|mb)');
  static final _imdbId = RegExp(r'^tt\d+$');

  final http.Client? _client;
  final TmdbService? _tmdb;

  Future<List<Map<String, dynamic>>> resolve(
    SearchResult media, {
    int season = 1,
    int episode = 1,
  }) async {
    final isMovie = media.mediaType == 'movie';
    final isSeries = const {'tv', 'series'}.contains(media.mediaType);
    if (media.id <= 0 || (!isMovie && !isSeries)) return const [];
    if (isSeries && (season < 0 || episode < 1)) return const [];

    final imdbId = await _getImdbId(media.id, isMovie: isMovie);
    Uri streamUri(String id) => Uri.https(
      _host,
      isMovie
          ? '/stream/movie/$id.json'
          : '/stream/series/$id:$season:$episode.json',
    );

    final client = _client ?? NetworkClientFactory.createClient();
    try {
      var streams = await _fetchStreams(
        client,
        streamUri(imdbId ?? media.id.toString()),
      );
      if (streams.isEmpty && imdbId != null) {
        streams = await _fetchStreams(client, streamUri(media.id.toString()));
      }

      // Preserve the provider's order among streams of the same resolution.
      final byResolution = <int, List<Map<String, dynamic>>>{};
      final seen = <String>{};
      for (final stream in streams) {
        final sourceUrl = _nonempty(stream['url']);
        final url = sourceUrl ?? _nonempty(stream['externalUrl']);
        if (url == null || !_isHttpUrl(url) || !seen.add(url)) continue;

        final hint = '${stream['title'] ?? ''} ${stream['name'] ?? ''}';
        final metadata = '$hint $url'.toLowerCase();
        final height = _resolution(metadata);
        final language = _language(metadata);
        final title = _label(
          media,
          sourceUrl: sourceUrl,
          series: isSeries,
          season: season,
          episode: episode,
          height: height,
          metadata: '$hint ${sourceUrl ?? ''}'.toLowerCase(),
        );
        (byResolution[height] ??= []).add({
          'name': '$_provider | ${height}p | $language',
          'title': title,
          'description': title,
          'url': url,
          // These values are expressed in the release label in the original
          // provider. The picker extracts quality and file size from that label.
          'size': title,
          'quality': '',
          'language': '',
          'headers': const {
            'User-Agent': _userAgent,
            'Referer': 'https://$_host/',
          },
        });
      }
      return [
        for (final height in const [2160, 1080, 720, 480])
          ...?byResolution[height],
      ];
    } finally {
      if (_client == null) client.close();
    }
  }

  Future<String?> _getImdbId(int tmdbId, {required bool isMovie}) async {
    final tmdb = _tmdb;
    if (tmdb == null) return null;
    try {
      final id = await tmdb
          .getImdbId(tmdbId: tmdbId, isMovie: isMovie)
          .timeout(_timeout);
      return id != null && _imdbId.hasMatch(id) ? id : null;
    } on TimeoutException {
      return null;
    }
  }

  static Future<List<Map<String, dynamic>>> _fetchStreams(
    http.Client client,
    Uri uri,
  ) async {
    try {
      final response = await client
          .get(
            uri,
            headers: const {
              'User-Agent': _userAgent,
              'Accept': 'application/json',
            },
          )
          .timeout(_timeout);
      if (response.statusCode < 200 || response.statusCode >= 300)
        return const [];
      final data = jsonDecode(utf8.decode(response.bodyBytes));
      final streams = data is Map ? data['streams'] : null;
      if (streams is List)
        return streams.whereType<Map<String, dynamic>>().toList();
    } on FormatException {
      // Some unavailable mirror responses are HTML.
    } on http.ClientException {
      // Allow the caller to try the alternate ID.
    } on IOException {
      // An interrupted connection returns the same empty lookup result.
    } on TimeoutException {
      // Allow the caller to try the alternate ID.
    }
    return const [];
  }

  static String? _nonempty(Object? value) =>
      value is String && value.trim().isNotEmpty ? value.trim() : null;

  static bool _isHttpUrl(String value) {
    final uri = Uri.tryParse(value);
    return uri != null &&
        (uri.scheme == 'https' || uri.scheme == 'http') &&
        uri.host.isNotEmpty &&
        uri.userInfo.isEmpty;
  }

  static int _resolution(String text) {
    if (text.contains('2160') || text.contains('4k')) return 2160;
    if (text.contains('720')) return 720;
    if (text.contains('480')) return 480;
    return 1080;
  }

  static String _language(String text) {
    if (text.contains('multi')) return 'Multi-Audio';
    final english = text.contains('eng');
    final hindi = text.contains('hin');
    if (text.contains('dual') || (english && hindi)) return 'Dual-Audio';
    if (hindi) return 'Hindi';
    if (english) return 'English';
    if (text.contains('tamil')) return 'Tamil';
    if (text.contains('telugu')) return 'Telugu';
    if (text.contains('malayalam')) return 'Malayalam';
    if (text.contains('kannada')) return 'Kannada';
    return 'Original';
  }

  static String _label(
    SearchResult media, {
    required String? sourceUrl,
    required bool series,
    required int season,
    required int episode,
    required int height,
    required String metadata,
  }) {
    final name = (series
        ? media.name ?? media.title
        : media.title ?? media.name);
    final year = (series ? media.firstAirDate : media.releaseDate)
        ?.split('-')
        .first;
    final yearLabel = year == null || year.isEmpty ? '' : ' ($year)';
    final episodeLabel = series
        ? ' | S${season.toString().padLeft(2, '0')}E${episode.toString().padLeft(2, '0')}'
        : '';
    final resolutionIcon = switch (height) {
      2160 => '🌟',
      1080 => '🔥',
      _ => '💎',
    };
    final size =
        _fileSize.stringMatch(metadata)?.toUpperCase() ?? 'Variable Size';
    final language = _language(metadata);
    final usesHevc = metadata.contains('hevc');
    final videoCodec = metadata.contains('x265') || metadata.contains('h265')
        ? 'x265'
        : 'x264';
    final video = usesHevc ? 'HEVC $videoCodec' : videoCodec;
    final audio = switch (metadata) {
      _ when metadata.contains('ddp5.1') || metadata.contains('ddp 5.1') =>
        'DDP5.1',
      _ when metadata.contains('5.1') => 'DD5.1',
      _ when metadata.contains('7.1') => '7.1',
      _ when metadata.contains('truehd') => 'TrueHD',
      _ => 'AAC',
    };
    final atmos = metadata.contains('atmos') ? ' | 🔊 Atmos' : '';
    final release = switch (metadata) {
      _ when metadata.contains('web-rip') || metadata.contains('webrip') =>
        '🌐 WEB-RIP',
      _ when metadata.contains('bluray') => '💿 BluRay',
      _ when metadata.contains('hdrip') => '📺 HD-RIP',
      _ => '📥 WEB-DL',
    };
    final container = sourceUrl?.contains('.mp4') == true ? 'MP4' : 'MKV';
    final picture = switch (metadata) {
      _ when metadata.contains('10bit') || metadata.contains('10-bit') =>
        metadata.contains('hdr') ? '10bit HDR' : '10bit',
      _ when metadata.contains('hdr10+') => 'HDR10+',
      _ when metadata.contains('hdr') => 'HDR',
      _ when metadata.contains('dv') || metadata.contains('dolby vision') =>
        'Dolby Vision',
      _ => 'SDR',
    };
    return [
      '🍿 ${_nonempty(name) ?? 'DesiFlix Title'}$yearLabel$episodeLabel',
      '$resolutionIcon ${height}p | 💾 $size | 🔊 $language',
      '🎥 $video | 🎧 $audio$atmos',
      '$release | 📦 $container | 🌈 $picture',
      '📎 $_provider',
    ].join('\n');
  }
}
