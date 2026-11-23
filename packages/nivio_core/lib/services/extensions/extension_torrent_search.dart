import 'dart:async';

import 'package:nivio/models/search_result.dart';
import 'package:nivio/services/torrent/media_ranking.dart';
import 'package:nivio/services/torrent/media_torrent_models.dart';
import 'package:nivio/services/torrent/torrent_models.dart';
import 'package:nivio/services/torrent/torrent_stream_service.dart';

import 'extension_repository.dart';
import 'extension_resolver.dart';
import 'stream_selection_settings.dart';

/// Supplies the picker with extension results and movie/TV format preferences.
class ExtensionTorrentSearch extends TorrentStreamService {
  ExtensionTorrentSearch._({
    required this.builtIn,
    required this.media,
    required this.providers,
    required this.repository,
    required this.timeout,
    required this.preferredFormats,
  }) : super(
         queryBuilder: builtIn.queryBuilder,
         tmdbService: builtIn.tmdbService,
       );

  final TorrentStreamService builtIn;
  final SearchResult media;
  final List<ExtensionProvider> providers;
  final ExtensionRepository repository;
  final Duration timeout;
  final List<RegExp> preferredFormats;
  final Map<(int, int), Future<List<TorrentResult>>> _results = {};

  static Future<TorrentStreamService> forPicker({
    required TorrentStreamService builtIn,
    required SearchResult media,
    required ExtensionRepository repository,
    required StreamSelectionSettings settings,
  }) async {
    var providers = <ExtensionProvider>[];
    try {
      providers = (await repository.list())
          .expand((repo) => repo.providers)
          .where(
            (provider) =>
                provider.enabled &&
                ExtensionResolver.supports(provider.repository.format) &&
                provider.supports(media.mediaType),
          )
          .toList();
    } catch (_) {
      // Built-in search can still use the format preferences.
    }
    final formats = [
      if (media.mediaType == 'movie' || media.mediaType == 'tv')
        for (final feature in settings.features)
          RegExp(feature.pattern, caseSensitive: false),
    ];
    if (providers.isEmpty && formats.isEmpty) return builtIn;
    final indexed = providers.indexed.toList()
      ..sort((a, b) {
        final rank = settings
            .sourceRank(a.$2.id)
            .compareTo(settings.sourceRank(b.$2.id));
        return rank == 0 ? a.$1.compareTo(b.$1) : rank;
      });
    return ExtensionTorrentSearch._(
      builtIn: builtIn,
      media: media,
      providers: indexed.map((entry) => entry.$2).toList(),
      repository: repository,
      timeout: Duration(seconds: settings.timeoutSeconds),
      preferredFormats: formats,
    );
  }

  @override
  Future<List<TorrentResult>> searchTorrents({
    required AnimeQuery query,
    void Function(String status)? onStatus,
  }) {
    final results = builtIn.searchTorrents(query: query, onStatus: onStatus);
    if (query.isManual) return results;
    return _merge(results, query.season, query.episode);
  }

  @override
  Future<List<TorrentResult>> searchMediaTorrents({
    required MediaTorrentQuery query,
    void Function(String status)? onStatus,
    bool rank = true,
  }) async {
    if (query.isManual || !rank) {
      return builtIn.searchMediaTorrents(
        query: query,
        onStatus: onStatus,
        rank: rank,
      );
    }
    final builtInResults = builtIn.searchMediaTorrents(
      query: query,
      onStatus: onStatus,
      rank: false,
    );
    final results = await _merge(
      builtInResults,
      query.season ?? 1,
      query.episode ?? 1,
    );
    return MediaRanking.rank(
      results,
      query,
      preferredFormats: preferredFormats,
    );
  }

  Future<List<TorrentResult>> _merge(
    Future<List<TorrentResult>> builtInResults,
    int season,
    int episode,
  ) async {
    if (providers.isEmpty) return builtInResults;
    final results = await Future.wait([
      builtInResults,
      _results.putIfAbsent((season, episode), () => _fetch(season, episode)),
    ]);
    final seen = <(String, int?)>{};
    return [
      for (final torrent in results.expand((items) => items))
        if (seen.add((
          torrent.infoHash?.toLowerCase() ?? torrent.link,
          torrent.fileIndex,
        )))
          torrent,
    ];
  }

  Future<List<TorrentResult>> _fetch(int season, int episode) async {
    final clock = Stopwatch()..start();
    final ExtensionMedia target;
    try {
      target = await extensionMedia(media, season, episode).timeout(timeout);
    } on TimeoutException {
      return [];
    }
    final resolver = ExtensionResolver(repository);
    var next = 0;
    final results = List<List<TorrentResult>>.generate(
      providers.length,
      (_) => [],
    );
    Future<void> fetch() async {
      while (next < providers.length) {
        final remaining = timeout - clock.elapsed;
        if (remaining <= Duration.zero) return;
        final index = next++;
        try {
          final streams = await resolver
              .resolve(providers[index], target, media)
              .timeout(remaining);
          results[index] = streams
              .map((choice) => choice.torrent)
              .nonNulls
              .toList();
        } catch (_) {
          // Keep results from the built-in and other extension sources.
        }
      }
    }

    await Future.wait(List.generate(4, (_) => fetch()));
    return results.expand((items) => items).toList();
  }
}
