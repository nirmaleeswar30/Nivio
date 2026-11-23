import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:nivio/models/search_result.dart';
import 'package:nivio/models/stream_result.dart';
import 'package:nivio/services/torrent/torrent_models.dart';

import 'extension_repository.dart';
import 'nuvio_script_runtime.dart';

class StreamChoice {
  const StreamChoice({
    required this.id,
    required this.providerId,
    required this.provider,
    required this.origin,
    required this.title,
    required this.quality,
    this.direct,
    this.torrent,
    this.audio,
    this.byteSize,
    this.bingeGroupHint,
  });

  final String id;
  final String providerId;
  final String provider;
  final String origin;
  final String title;
  final String quality;
  final String? audio;
  final int? byteSize;
  final String? bingeGroupHint;
  final StreamResult? direct;
  final TorrentResult? torrent;

  bool get isTorrent => torrent != null;
  bool get isDirect => direct != null;
  String? get audioType {
    final text = '${audio ?? ''} $title'.toLowerCase();
    if (RegExp(r'\bdual[ .-]?audio\b').hasMatch(text)) return 'Both';
    if (RegExp(r'\bdub(?:bed)?\b').hasMatch(text)) return 'Dub';
    if (RegExp(r'\bsub(?:bed)?\b').hasMatch(text)) return 'Sub';
    return null;
  }

  String get variant =>
      '$providerId|$quality|${audioType ?? audio ?? ''}|${torrent?.parsed.releaseGroup ?? ''}';

  static StreamChoice? fromExtension(
    ExtensionProvider provider,
    Map<String, dynamic> json,
    int index,
  ) {
    final rawUrl = json['url'];
    final url =
        (rawUrl is Map ? rawUrl['url'] : rawUrl)?.toString().trim() ?? '';
    final uri = Uri.tryParse(url);
    final type = json['type']?.toString().toLowerCase();
    final title = (json['title'] ?? json['name'] ?? provider.name).toString();
    final quality = json['quality']?.toString() ?? 'Unknown quality';
    final audio = json['language']?.toString();
    final hash = json['infoHash']?.toString().toLowerCase();
    final validHash =
        hash != null &&
        RegExp(r'^(?:[a-f0-9]{40}|[a-z2-7]{32})$').hasMatch(hash);
    final magnet =
        uri?.scheme == 'magnet' &&
        (uri?.queryParametersAll['xt'] ?? const <String>[]).any(
          (value) => value.toLowerCase().startsWith('urn:btih:'),
        );
    final web = uri != null && isExtensionWebUrl(uri);
    final torrentUrl =
        web &&
        (uri.path.toLowerCase().endsWith('.torrent') ||
            type == 'torrent' ||
            type == 'p2p');
    final size = _size(json['size'] ?? json['sizeBytes']);
    final isTorrent = validHash || magnet || torrentUrl;
    if (!isTorrent && !web) return null;
    final subs = <StreamSubtitleTrack>[];
    if (json['subtitles'] case final List subtitles) {
      for (final subtitle in subtitles.whereType<Map>()) {
        final track = StreamSubtitleTrack.fromJson(
          Map<String, dynamic>.from(subtitle),
        );
        final trackUri = Uri.tryParse(track.url);
        if (trackUri != null && isExtensionWebUrl(trackUri)) subs.add(track);
      }
    }
    return StreamChoice(
      id: '${provider.id}:$index',
      providerId: provider.id,
      provider: provider.name,
      origin: provider.repository.name,
      title: title,
      quality: quality,
      audio: audio,
      byteSize: size,
      bingeGroupHint: json['bingeGroup'] is String
          ? (json['bingeGroup'] as String).trim()
          : null,
      direct: isTorrent
          ? null
          : StreamResult(
              url: url,
              quality: quality,
              provider: provider.name,
              subtitles: subs,
              headers: _headers(json['headers']),
              selectedAudio: audio ?? '',
              isM3U8:
                  type == 'hls' ||
                  type == 'm3u8' ||
                  uri!.path.toLowerCase().endsWith('.m3u8'),
            ),
      torrent: !isTorrent
          ? null
          : TorrentResult(
              title: title,
              link: magnet || torrentUrl ? url : 'magnet:?xt=urn:btih:$hash',
              source: provider.name,
              sizeBytes: size ?? 0,
              seeders: _integer(json['seeders']) ?? 0,
              leechers: _integer(json['peers']) ?? 0,
              infoHash: validHash ? hash : null,
              fileIndex: _integer(json['fileIdx'] ?? json['fileIndex']),
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

int? _integer(dynamic value) =>
    value is num ? value.toInt() : int.tryParse('$value');

int? _size(dynamic value) {
  final bytes = _integer(value);
  if (bytes != null) return bytes > 0 ? bytes : null;
  final match = RegExp(
    r'^([0-9]+(?:\.[0-9]+)?)\s*(KB|MB|GB|TB|KIB|MIB|GIB|TIB)$',
    caseSensitive: false,
  ).firstMatch('$value'.trim());
  if (match == null) return null;
  const scale = {'K': 1024, 'M': 1048576, 'G': 1073741824, 'T': 1099511627776};
  return (double.parse(match[1]!) * scale[match[2]![0].toUpperCase()]!).round();
}

typedef ExtensionMedia = ({
  String id,
  String type,
  int? season,
  int? episode,
  String? tmdbId,
  int? absoluteEpisode,
});

Future<ExtensionMedia> extensionMedia(
  SearchResult media,
  int season,
  int episode,
) async {
  if (media.mediaType != 'anime') {
    final movie = media.mediaType == 'movie';
    return (
      id: '${media.id}',
      type: movie ? 'movie' : 'tv',
      season: movie ? null : season,
      episode: movie ? null : episode,
      tmdbId: '${media.id}',
      absoluteEpisode: null,
    );
  }
  final client = http.Client();
  try {
    final response = await client
        .get(
          Uri.https('api.ani.zip', '/mappings', {'anilist_id': '${media.id}'}),
        )
        .timeout(const Duration(seconds: 5));
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body) as Map;
      final mapping = data['mappings'] as Map?;
      final tmdb = mapping?['themoviedb_id'] ?? mapping?['tmdb_id'];
      if (_integer(tmdb) != null) {
        final entry = (data['episodes'] as Map?)?['$episode'] as Map?;
        final movie = '${mapping?['type']}'.toLowerCase() == 'movie';
        return (
          id: '$tmdb',
          type: movie ? 'movie' : 'tv',
          season: movie ? null : _integer(entry?['seasonNumber']) ?? season,
          episode: movie ? null : _integer(entry?['episodeNumber']) ?? episode,
          tmdbId: '$tmdb',
          absoluteEpisode: _integer(entry?['absoluteEpisodeNumber']),
        );
      }
    }
  } catch (_) {
    // Anime-specific providers may support the AniList ID even without TMDB.
  } finally {
    client.close();
  }
  return (
    id: 'anilist:${media.id}',
    type: 'anime',
    season: season,
    episode: episode,
    tmdbId: null,
    absoluteEpisode: episode,
  );
}

class ExtensionResolver {
  ExtensionResolver(this.repository);
  final ExtensionRepository repository;
  static const _cloudstream = MethodChannel('com.nivio/cloudstream_extensions');

  static bool supports(ExtensionFormat format) =>
      format == ExtensionFormat.javascript || Platform.isAndroid;

  Future<List<StreamChoice>> resolve(
    ExtensionProvider provider,
    ExtensionMedia target,
    SearchResult media,
  ) async {
    final format = provider.repository.format;
    if (!supports(format)) return const [];
    final types = (provider.entry['supportedTypes'] as List? ?? []).map(
      (type) => '$type'.toLowerCase(),
    );
    final animeRequest =
        media.mediaType == 'anime' &&
        provider.supports('anime') &&
        types.contains('anime');
    if (format == ExtensionFormat.javascript &&
        target.tmdbId == null &&
        !animeRequest)
      return const [];
    final package = await repository.package(provider);
    final List<dynamic> raw;
    if (format == ExtensionFormat.javascript) {
      raw = await runNuvioScript(await package.readAsString(), [
        animeRequest && target.tmdbId == null
            ? 'anilist:${media.id}'
            : target.id,
        if (animeRequest && target.tmdbId == null)
          'anime'
        else if (target.type == 'tv' && types.contains('series'))
          'series'
        else
          target.type,
        target.season,
        target.episode,
      ], const {});
    } else {
      raw =
          await _cloudstream
              .invokeListMethod<dynamic>('resolve', {
                'path': package.path,
                'id': target.tmdbId,
                'type': target.type,
                'season': target.season,
                'episode': target.episode,
                'absoluteEpisode': target.absoluteEpisode,
                'title': media.title ?? media.name ?? '',
                'year': (media.releaseDate ?? media.firstAirDate)
                    ?.split('-')
                    .first,
              })
              .timeout(const Duration(seconds: 30)) ??
          const [];
    }
    final choices = <StreamChoice>[];
    for (var i = 0; i < raw.length; i++) {
      final item = raw[i];
      if (item is! Map) continue;
      final choice = StreamChoice.fromExtension(
        provider,
        Map<String, dynamic>.from(item),
        i,
      );
      if (choice != null) choices.add(choice);
    }
    return choices;
  }
}
