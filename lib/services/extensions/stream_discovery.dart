import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:nivio/models/search_result.dart';
import 'package:nivio/models/stream_result.dart';
import 'package:nivio/services/streaming_service.dart';
import 'package:nivio/services/torrent/media_torrent_models.dart';
import 'package:nivio/services/torrent/torrent_models.dart';

import 'extension_repository.dart';
import 'extension_resolver.dart';
import 'stream_selection.dart';
import 'stream_selection_settings.dart';

class StreamDiscovery extends ChangeNotifier {
  StreamDiscovery({
    required this.media,
    required this.season,
    required this.episode,
    required this.streaming,
    required this.repository,
    required this.torrentsEnabled,
    required this.subDub,
    required this.preferredQuality,
    this.previous,
    this.selection = const StreamSelectionSettings(),
  });

  final SearchResult media;
  final int season;
  final int episode;
  final StreamingService streaming;
  final ExtensionRepository repository;
  final bool torrentsEnabled;
  final String subDub;
  final String? preferredQuality;
  final StreamChoice? previous;
  final StreamSelectionSettings selection;

  final choices = <StreamChoice>[];
  final failures = <String>{};
  final unavailable = <String>{};
  bool searching = true;
  bool _closed = false;
  int _generation = 0;
  Future<Object>? _torrentRequest;

  bool get isAnime => media.mediaType == 'anime';

  List<StreamChoice> get availableChoices =>
      choices.where((choice) => !unavailable.contains(choice.id)).toList();

  List<StreamChoice> orderForPicker(List<StreamChoice> visible) {
    final ordered = visible.indexed.toList();
    ordered.sort((a, b) {
      final rankA = selection.sourceRank(a.$2.selectionSourceId);
      final rankB = selection.sourceRank(b.$2.selectionSourceId);
      if (rankA != rankB) return rankA.compareTo(rankB);
      if (a.$2.isWebPlayer != b.$2.isWebPlayer)
        return a.$2.isWebPlayer ? 1 : -1;
      return a.$1.compareTo(b.$1);
    });
    return ordered.map((entry) => entry.$2).toList();
  }

  Future<void> waitForResults(
    Duration timeout, {
    bool Function()? ready,
  }) async {
    if (!searching ||
        _closed ||
        timeout <= Duration.zero ||
        ready?.call() == true)
      return;
    final done = Completer<void>();
    void check() {
      if (!done.isCompleted && (!searching || ready?.call() == true))
        done.complete();
    }

    addListener(check);
    try {
      await done.future.timeout(timeout, onTimeout: () {});
    } finally {
      removeListener(check);
    }
  }

  Future<StreamChoice?> firstReachable(
    StreamSelection policy,
    Duration timeout,
    Future<bool> Function(StreamChoice) probe,
  ) async {
    if (_closed || timeout <= Duration.zero) return null;
    final result = Completer<StreamChoice?>();
    final checked = <String>{};
    var active = 0;

    void pump() {
      if (result.isCompleted) return;
      if (_closed) {
        result.complete(null);
        return;
      }
      for (final choice in availableChoices) {
        if (active >= 5) break;
        if (!choice.isDirect ||
            !policy.eligible(choice) ||
            !policy.prefers(choice) ||
            !policy.confirmedAudio(choice) ||
            !checked.add(choice.id))
          continue;
        active++;
        unawaited(() async {
          var reachable = false;
          try {
            reachable = await probe(choice);
          } catch (_) {
            // Continue racing the other direct sources.
          }
          active--;
          if (result.isCompleted) return;
          if (reachable) {
            result.complete(choice);
          } else {
            markFailed(choice);
          }
        }());
      }
      if (!searching && active == 0) result.complete(null);
    }

    addListener(pump);
    try {
      pump();
      return await result.future.timeout(
        timeout,
        onTimeout: () {
          result.complete(null);
          return null;
        },
      );
    } finally {
      removeListener(pump);
    }
  }

  Future<void> search() async {
    final generation = ++_generation;
    searching = true;
    choices.clear();
    failures.clear();
    unavailable.clear();
    notifyListeners();
    await Future.wait([
      _searchBuiltIn(generation),
      _searchExtensions(generation),
      if (torrentsEnabled && streaming.isTorrentEnabledForMedia(media))
        _searchTorrents(generation),
    ]);
    if (_current(generation)) {
      searching = false;
      notifyListeners();
    }
  }

  void stop() {
    _generation++;
    searching = false;
    if (!_closed) notifyListeners();
  }

  void markFailed(StreamChoice choice) {
    if (_closed) return;
    unavailable.add(choice.id);
    notifyListeners();
  }

  bool _current(int generation) => !_closed && generation == _generation;

  void _add(int generation, List<StreamChoice> results) {
    if (!_current(generation)) return;
    choices.addAll(
      results.where((choice) => !choice.isTorrent || torrentsEnabled),
    );
    notifyListeners();
  }

  void _failed(int generation, String name) {
    if (!_current(generation)) return;
    failures.add(name);
    notifyListeners();
  }

  Future<void> _searchBuiltIn(int generation) async {
    if (isAnime) {
      try {
        await streaming
            .prepareProviders(
              media: media,
              season: season,
              episode: episode,
              subDubPreference: subDub,
            )
            .timeout(const Duration(seconds: 10));
      } catch (_) {
        // The streaming service retains its default anime servers on failure.
      }
    }
    if (!_current(generation)) return;
    final providers =
        [
              for (
                var i = 0;
                i < streaming.totalProvidersFor(isAnime: isAnime);
                i++
              )
                if (streaming.getProviderName(i, isAnime: isAnime) !=
                    'Nivio Torrents')
                  i,
            ]
            .map(
              (index) =>
                  (index, streaming.getProviderName(index, isAnime: isAnime)),
            )
            .toList();
    if (selection.mode != StreamSelectionMode.first) {
      providers.sort((a, b) {
        final rank = selection
            .sourceRank(streamSelectionSourceId('builtin:${a.$2}'))
            .compareTo(
              selection.sourceRank(streamSelectionSourceId('builtin:${b.$2}')),
            );
        return rank != 0 ? rank : a.$1.compareTo(b.$1);
      });
    }
    await _concurrently(providers, 5, generation, (provider) async {
      final (index, name) = provider;
      final isWebPlayer = !streaming.isDirectStream(index, isAnime: isAnime);
      try {
        final result = await streaming
            .fetchStreamUrl(
              media: media,
              season: season,
              episode: episode,
              providerIndex: index,
              preferredQuality: preferredQuality,
              subDubPreference: subDub,
            )
            .timeout(const Duration(seconds: 24));
        if (result == null || result.url.isEmpty) return;
        final urls = <String>{result.url};
        final selected = [
          result.copyWith(sources: const []),
          for (final source in result.sources)
            if (source.url.isNotEmpty && urls.add(source.url))
              result.copyWith(
                url: source.url,
                quality: source.quality,
                isM3U8: source.isM3U8,
                sources: const [],
                selectedAudio: isAnime
                    ? (source.isDub ? 'Dub' : 'Sub')
                    : result.selectedAudio,
              ),
        ];
        _add(generation, [
          for (var i = 0; i < selected.length; i++)
            StreamChoice(
              id: 'builtin:$name:$i',
              providerId: 'builtin:$name',
              provider: result.provider,
              origin: 'Built-in source',
              title: result.provider,
              quality: selected[i].quality,
              audio: selected[i].selectedAudio.isEmpty
                  ? null
                  : selected[i].selectedAudio,
              direct: selected[i],
              isWebPlayer: isWebPlayer,
            ),
        ]);
      } catch (_) {
        _failed(generation, name);
      }
    });
  }

  Future<void> _searchExtensions(int generation) async {
    try {
      final repositories = await repository.list();
      final providers = repositories
          .expand((repo) => repo.providers)
          .where(
            (provider) =>
                provider.enabled &&
                ExtensionResolver.supports(provider.repository.format) &&
                provider.supports(media.mediaType),
          )
          .toList();
      if (providers.isEmpty || !_current(generation)) return;
      if (selection.mode != StreamSelectionMode.first) {
        final ranked = providers.indexed.toList()
          ..sort((a, b) {
            final rank = selection
                .sourceRank(a.$2.id)
                .compareTo(selection.sourceRank(b.$2.id));
            return rank != 0 ? rank : a.$1.compareTo(b.$1);
          });
        providers.setAll(0, ranked.map((entry) => entry.$2));
      }
      final target = await extensionMedia(media, season, episode);
      final resolver = ExtensionResolver(repository);
      await _concurrently(providers, 4, generation, (provider) async {
        try {
          _add(
            generation,
            await resolver
                .resolve(provider, target, media)
                .timeout(const Duration(seconds: 38)),
          );
        } catch (_) {
          _failed(generation, provider.name);
        }
      });
    } catch (_) {
      _failed(generation, 'Extensions');
    }
  }

  Future<void> _concurrently<T>(
    List<T> items,
    int workers,
    int generation,
    Future<void> Function(T) task,
  ) async {
    var next = 0;
    Future<void> work() async {
      while (_current(generation) && next < items.length) {
        await task(items[next++]);
      }
    }

    await Future.wait(List.generate(workers, (_) => work()));
  }

  Future<Object> _buildTorrentRequest() async {
    final torrent = streaming.torrentStreamService;
    final resolution =
        RegExp(r'\d{3,4}').firstMatch(preferredQuality ?? '')?.group(0) ??
        '1080';
    if (isAnime)
      return torrent.queryBuilder.build(
        media,
        episode,
        season: season,
        resolution: resolution,
      );
    final movie = media.mediaType == 'movie';
    return MediaTorrentQuery(
      imdbId:
          await streaming.tmdbService.getImdbId(
            tmdbId: media.id,
            isMovie: movie,
          ) ??
          '',
      tmdbId: media.id,
      title: media.title ?? media.name ?? '',
      isMovie: movie,
      season: movie ? null : season,
      episode: movie ? null : episode,
      resolution: resolution,
    );
  }

  Future<void> _searchTorrents(int generation) async {
    try {
      final request = await (_torrentRequest ??= _buildTorrentRequest());
      if (!_current(generation)) return;
      final torrent = streaming.torrentStreamService;
      if (request is MediaTorrentQuery && (request.imdbId?.isEmpty ?? true))
        return;
      final results =
          await (request is AnimeQuery
                  ? torrent.searchTorrents(query: request)
                  : torrent.searchMediaTorrents(
                      query: request as MediaTorrentQuery,
                    ))
              .timeout(const Duration(seconds: 25));
      _add(generation, [
        for (final release in results.take(80))
          StreamChoice(
            id: 'torrent:${release.infoHash ?? release.link}:${release.fileIndex}',
            providerId: 'torrent:${release.source}',
            provider: release.source,
            origin: 'Built-in source',
            title: release.title,
            quality: release.parsed.resolution == null
                ? 'Unknown quality'
                : '${release.parsed.resolution}p',
            byteSize: release.sizeBytes > 0 ? release.sizeBytes : null,
            torrent: release,
          ),
      ]);
    } catch (_) {
      _failed(generation, 'Built-in torrent sources');
    }
  }

  Future<StreamResult?> open(
    StreamChoice choice,
    void Function(String) status, {
    Duration? torrentMetadataTimeout,
  }) async {
    if (choice.direct case final StreamResult direct) return direct;
    final release = choice.torrent;
    if (!torrentsEnabled || release == null) return null;
    final service = streaming.torrentStreamService;
    status('Connecting to peers…');
    final request = await (_torrentRequest ??= _buildTorrentRequest());
    final active = previous?.torrent;
    final sameRelease = active != null && active.link == release.link;
    final reused = sameRelease && release.isBatch
        ? await service.nextEpisodeInActiveTorrent(
            media: media,
            episode: episode,
            season: season,
            absoluteEpisode: request is AnimeQuery
                ? request.absoluteEpisode
                : null,
            preferredGroup: active.parsed.releaseGroup,
          )
        : null;
    final handle =
        reused ??
        await service.startTorrent(
          release,
          request,
          episode,
          status,
          media: media,
          requireEpisodeMatch: media.mediaType != 'movie' && release.isBatch,
          metadataTimeout: torrentMetadataTimeout,
          cancelled: () => _closed,
        );
    if (handle == null) return null;
    await service.rememberReleaseGroup(
      media,
      release,
      fileName: handle.fileName,
    );
    return StreamResult(
      url: handle.url,
      quality: choice.quality,
      provider: 'Nivio Torrents',
    );
  }

  @override
  void dispose() {
    _closed = true;
    _generation++;
    super.dispose();
  }
}
