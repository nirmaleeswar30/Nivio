import 'dart:async';
import 'dart:collection';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:nivio/core/debug_log.dart';
import 'package:nivio/models/search_result.dart';
import 'package:nivio/models/stream_result.dart';
import 'package:nivio/models/stream_size.dart';
import 'package:nivio/services/torrent/torrent_models.dart';

import 'cnc_direct_sources.dart';
import 'extension_anime_mapping.dart';
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
    this.videoHeights = const [],
    this.audioTracks = const [],
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
  final List<int> videoHeights;
  final List<String> audioTracks;
  final StreamResult? direct;
  final TorrentResult? torrent;

  bool get isTorrent => torrent != null;
  bool get isDirect => direct != null;
  int? get displaySizeBytes => byteSize ?? StreamSize.fromTitle(title);

  StreamChoice withMetadata({
    List<int>? videoHeights,
    List<String>? audioTracks,
  }) => StreamChoice(
    id: id,
    providerId: providerId,
    provider: provider,
    origin: origin,
    title: title,
    quality: quality,
    direct: direct,
    torrent: torrent,
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
    final size =
        StreamSize.parse(json['sizeBytes']) ?? StreamSize.parse(json['size']);
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
      id: '${provider.sourceId}:$index',
      providerId: provider.sourceId,
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

final extensionResolverProvider = Provider(
  (ref) => ExtensionResolver(ref.watch(extensionRepositoryProvider)),
);

class ExtensionResolver {
  ExtensionResolver(this.repository);
  final ExtensionRepository repository;
  static const _cloudstream = MethodChannel('com.nivio/cloudstream_extensions');
  static const _maxConcurrentLookups = 10;
  static const _scriptLookupTimeout = Duration(seconds: 60);
  static final _waitingLookups = Queue<Completer<void>>();
  static int _activeLookups = 0;

  Future<void> _probeQueue = Future.value();
  final _probing = <String>{};
  final _recentProbes = <String, DateTime>{};

  static bool supports(ExtensionFormat format) =>
      format == ExtensionFormat.javascript || Platform.isAndroid;

  ExtensionMediaLookup lookup(SearchResult media, int season, int episode) =>
      ExtensionMediaLookup(media, season, episode, repository.animeMappings);

  static Future<T> _withLookupSlot<T>(Future<T> Function() run) async {
    if (_activeLookups < _maxConcurrentLookups) {
      _activeLookups++;
    } else {
      final slot = Completer<void>();
      _waitingLookups.addLast(slot);
      await slot.future;
    }
    try {
      return await run();
    } finally {
      if (_waitingLookups.isEmpty) {
        _activeLookups--;
      } else {
        // Transfer the slot directly so new requests cannot jump the queue.
        _waitingLookups.removeFirst().complete();
      }
    }
  }

  Future<void> resolveAll(
    List<ExtensionProvider> providers,
    ExtensionMediaLookup lookup, {
    required bool wantTorrent,
    required void Function(ExtensionProvider, List<StreamChoice>) onResult,
    void Function(ExtensionProvider)? onError,
    bool Function()? isCurrent,
  }) async {
    bool current() => isCurrent?.call() ?? true;

    void failed(ExtensionProvider provider, String stage, [Object? error]) {
      if (!current()) return;
      final reason = switch (error) {
        PlatformException(:final code) => ' ($code)',
        null => '',
        _ => ' (${error.runtimeType})',
      };
      appDebugLog('[Extensions] ${provider.name}: $stage failed$reason');
      onError?.call(provider);
    }

    Future<void> search(ExtensionProvider provider) async {
      try {
        final choices = await resolve(
          provider,
          lookup,
          wantTorrent: wantTorrent,
          isCurrent: isCurrent,
        );
        if (current()) onResult(provider, choices);
      } catch (error) {
        failed(provider, 'lookup', error);
      }
    }

    final nativeProviders = providers.where(
      (provider) =>
          provider.repository.format == ExtensionFormat.cloudstream &&
          supports(ExtensionFormat.cloudstream),
    );
    Future<void> searchCloudstream() async {
      final installed = await Future.wait([
        for (final provider in nativeProviders)
          _withLookupSlot(() async {
            if (!current()) return null;
            try {
              final file = await _nativePackage(
                provider,
              ).timeout(const Duration(seconds: 30));
              return (provider, file.path);
            } catch (error) {
              failed(provider, 'package preparation', error);
              return null;
            }
          }),
      ]);
      final available = installed.nonNulls.toList();
      if (available.isEmpty || !current()) return;
      // The SDK's extractor registry is shared. Register the batch before
      // dispatching its lookups so they can read it concurrently.
      Set<String> registered;
      try {
        registered =
            (await _cloudstream.invokeListMethod<String>('prepare', {
              'paths': available.map((entry) => entry.$2).toList(),
            }))?.toSet() ??
            const {};
      } catch (error) {
        for (final (provider, _) in available) {
          failed(provider, 'registration', error);
        }
        return;
      }
      if (!current()) return;
      await Future.wait(
        available.map((entry) async {
          final (provider, path) = entry;
          if (registered.contains(path)) {
            await search(provider);
          } else {
            failed(provider, 'registration');
          }
        }),
      );
    }

    await Future.wait([
      for (final provider in providers)
        if (provider.repository.format == ExtensionFormat.javascript)
          search(provider),
      if (nativeProviders.isNotEmpty) searchCloudstream(),
    ]);
  }

  Future<List<StreamChoice>> resolve(
    ExtensionProvider provider,
    ExtensionMediaLookup lookup, {
    bool? wantTorrent,
    bool Function()? isCurrent,
  }) => _withLookupSlot(() async {
    if (isCurrent?.call() == false) return const [];
    return _resolve(provider, lookup, wantTorrent);
  });

  Future<List<StreamChoice>> _resolve(
    ExtensionProvider provider,
    ExtensionMediaLookup lookup,
    bool? wantTorrent,
  ) async {
    final format = provider.repository.format;
    if (!supports(format)) return const [];

    if (format == ExtensionFormat.javascript) {
      final watch = Stopwatch()..start();
      Duration remaining() {
        final time = _scriptLookupTimeout - watch.elapsed;
        return time > Duration.zero ? time : Duration.zero;
      }

      if (lookup.isAnime) {
        final movie = await lookup.isMovie.timeout(remaining());
        if (_aniListTypes(provider, movie).isEmpty) return const [];
        final script =
            await (await repository.package(provider).timeout(remaining()))
                .readAsString();
        return _resolveAnime(
          provider,
          script,
          lookup,
          movie,
          wantTorrent,
          remaining,
        );
      }

      final package = await repository.package(provider).timeout(remaining());
      final target = (await lookup.tmdb)!;
      final code = await package.readAsString();
      final timeout = remaining();
      if (timeout == Duration.zero) {
        throw TimeoutException('Extension lookup timed out');
      }
      final raw = await runNuvioScript(
        code,
        [
          target.id,
          _tmdbType(provider, target.type),
          target.season,
          target.episode,
        ],
        const {},
        timeout: timeout,
      );
      return _choices(provider, raw);
    }
    final package = await _nativePackage(provider);
    final promoted = provider.builtIn
        ? null
        : CncDirectSource.forPackage(provider);
    final target = await lookup.cloudstream;
    final media = lookup.media;
    // Android starts the lookup timeout after its native slot is available.
    final raw = await _cloudstream.invokeListMethod<dynamic>('resolve', {
      'path': package.path,
      if (provider.nativeProviderName case final name?) 'provider': name,
      if (promoted != null) 'excludeProviders': promoted.packageProviderNames,
      'id': target.tmdbId,
      'type': target.type,
      'season': target.season,
      'episode': target.episode,
      'absoluteEpisode': target.absoluteEpisode,
      'title': media.title ?? media.name ?? '',
      'year': (media.releaseDate ?? media.firstAirDate)?.split('-').first,
    });
    return _choices(provider, raw ?? const []);
  }

  Future<File> _nativePackage(ExtensionProvider provider) {
    final source = provider.builtIn
        ? null
        : CncDirectSource.forPackage(provider);
    if (source != null &&
        provider.contentHash?.toLowerCase() == 'sha256-${source.sha256}') {
      return repository.package(source.provider);
    }
    return repository.package(provider);
  }

  /// Rechecks newly enabled or updated providers without blocking the settings UI.
  void checkEnabledAnimeProviders(Iterable<ExtensionProvider> providers) {
    final now = DateTime.now();
    for (final provider in providers) {
      if (!provider.enabled ||
          provider.repository.format != ExtensionFormat.javascript ||
          !provider.supports('anime') ||
          provider.entry['filename'] is! String)
        continue;
      final key = provider.packageKey;
      if (_recentProbes[key]?.isAfter(now) == true || !_probing.add(key))
        continue;
      _probeQueue = _probeQueue.then((_) async {
        try {
          final repos = await repository.list();
          if (!repos
              .expand((repo) => repo.providers)
              .any(
                (current) =>
                    current.enabled &&
                    current.id == provider.id &&
                    current.entry['filename'] is String &&
                    current.packageKey == key,
              ))
            return;
          await _probe(provider);
          _recentProbes[key] = DateTime.now().add(const Duration(minutes: 10));
        } catch (_) {
          // Playback can still learn the route from an actual title.
        } finally {
          _probing.remove(key);
        }
      });
    }
  }

  Future<void> _probe(ExtensionProvider provider) async {
    for (final media in const [
      SearchResult(
        id: 21519,
        mediaType: 'anime',
        animeFormat: 'MOVIE',
      ), // Your Name.
      SearchResult(
        id: 154587,
        mediaType: 'anime',
        animeFormat: 'TV',
      ), // Frieren, episode 1.
    ]) {
      final lookup = this.lookup(media, 1, 1);
      final movie = await lookup.isMovie;
      if (_aniListTypes(provider, movie).isEmpty) continue;
      final routes = await repository.animeRoutes(provider, movie: movie);
      if (routes.aniList != null && routes.tmdb != null) continue;
      final script = await (await repository.package(provider)).readAsString();
      await Future.wait([
        if (routes.aniList == null)
          _tryAnimeId(
            provider,
            script,
            lookup,
            movie,
            ExtensionAnimeId.aniList,
            probe: true,
          ),
        if (routes.tmdb == null)
          _tryAnimeId(
            provider,
            script,
            lookup,
            movie,
            ExtensionAnimeId.tmdb,
            probe: true,
          ),
      ]);
    }
  }

  Future<List<StreamChoice>> _resolveAnime(
    ExtensionProvider provider,
    String script,
    ExtensionMediaLookup lookup,
    bool movie,
    bool? wantTorrent,
    Duration Function() remaining,
  ) async {
    final routes = await repository
        .animeRoutes(provider, movie: movie)
        .timeout(remaining());
    var finished = false;
    Duration timeLeft() => finished ? Duration.zero : remaining();
    Future<List<StreamChoice>> tryAniList() => _tryAnimeId(
      provider,
      script,
      lookup,
      movie,
      ExtensionAnimeId.aniList,
      preferredType: routes.aniList,
      wantTorrent: wantTorrent,
      remaining: timeLeft,
    );
    Future<List<StreamChoice>> tryTmdb() => _tryAnimeId(
      provider,
      script,
      lookup,
      movie,
      ExtensionAnimeId.tmdb,
      preferredType: routes.tmdb,
      wantTorrent: wantTorrent,
      remaining: timeLeft,
    );

    try {
      if (routes.aniList != null) {
        final choices = await tryAniList();
        return choices.isNotEmpty ? choices : await tryTmdb();
      }
      if (routes.tmdb != null) {
        final choices = await tryTmdb();
        return choices.isNotEmpty ? choices : await tryAniList();
      }

      // An unknown provider can learn from either ID, even while Ani.zip is slow.
      final aniList = tryAniList();
      final tmdb = tryTmdb();
      final (choices, other) = await Future.any([
        aniList.then((choices) => (choices, tmdb)),
        tmdb.then((choices) => (choices, aniList)),
      ]);
      return choices.isNotEmpty ? choices : await other;
    } finally {
      finished = true;
    }
  }

  Future<List<StreamChoice>> _tryAnimeId(
    ExtensionProvider provider,
    String script,
    ExtensionMediaLookup lookup,
    bool movie,
    ExtensionAnimeId idType, {
    String? preferredType,
    bool probe = false,
    bool? wantTorrent,
    Duration Function()? remaining,
  }) async {
    final direct = idType == ExtensionAnimeId.aniList;
    final target = direct ? null : await lookup.tmdb;
    if (!direct && target == null) return const [];
    final animeMapping = direct ? null : await lookup.nuvioMapping;
    final types = direct
        ? _aniListTypes(provider, movie)
        : {
            _tmdbType(provider, target!.type),
            target.type,
            if (provider.nuvioTypes.contains('anime')) 'anime',
          }.toList();
    final requestTypes = [
      if (types.contains(preferredType)) preferredType!,
      ...types.where((type) => type != preferredType),
    ];
    for (final type in requestTypes) {
      var timeout = Duration(
        seconds: probe ? 6 : (preferredType == type ? 24 : 12),
      );
      if (remaining != null) {
        final left = remaining();
        if (left == Duration.zero) break;
        if (left < timeout) timeout = left;
      }
      final List<StreamChoice> choices;
      try {
        final raw = await runNuvioScript(
          script,
          [
            direct ? 'anilist:${lookup.media.id}' : target!.id,
            type,
            direct ? (movie ? null : lookup.season) : target!.season,
            direct ? (movie ? null : lookup.episode) : target!.episode,
          ],
          const {},
          animeMapping: animeMapping,
          timeout: timeout,
        );
        choices = _choices(provider, raw);
      } catch (_) {
        continue;
      }
      if (choices.isEmpty) continue;
      try {
        await repository.rememberAnimeRoute(
          provider,
          idType,
          type,
          movie: movie,
        );
      } catch (_) {
        // The stream is still usable when settings cannot be saved.
      }
      if (wantTorrent == null) return choices;
      final matching = choices
          .where((choice) => wantTorrent ? choice.isTorrent : choice.isDirect)
          .toList();
      if (matching.isNotEmpty) return matching;
    }
    return const [];
  }

  List<String> _aniListTypes(ExtensionProvider provider, bool movie) {
    final type = movie ? 'movie' : 'tv';
    final anime = provider.nuvioTypes.contains('anime');
    final standard = provider.supports(type);
    return {
      if (standard) _tmdbType(provider, type),
      if (anime) 'anime',
      if (standard || anime) type,
    }.toList();
  }

  String _tmdbType(ExtensionProvider provider, String type) =>
      type == 'tv' && provider.nuvioTypes.contains('series') ? 'series' : type;

  List<StreamChoice> _choices(ExtensionProvider provider, List<dynamic> raw) {
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
