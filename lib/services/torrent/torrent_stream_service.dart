import 'dart:async';

import 'package:rqbit_ffi/rqbit_ffi.dart';

import '../../core/debug_log.dart';
import '../../models/search_result.dart';
import 'anime_query_builder.dart';
import 'ranking.dart';
import 'resolver.dart';
import 'sources/animetosho_source.dart';
import 'sources/nyaa_source.dart';
import 'sources/seadex_source.dart';
import 'sources/torrent_source.dart';
import 'torrent_models.dart';

/// The result of resolving a torrent stream: a localhost URL ready for the
/// player, plus the handles needed for stats and teardown.
class TorrentStreamHandle {
  TorrentStreamHandle({
    required this.url,
    required this.torrentId,
    required this.fileIndex,
    required this.fileName,
    required this.client,
    required this.title,
    this.resolution,
  });

  final String url;
  final int torrentId;
  final int fileIndex;
  final String fileName;
  final RqbitClient client;
  final String title;
  final int? resolution;

  Future<TorrentStats> stats() => client.getStats(torrentId);
}

/// Orchestrates the anime-torrent streaming pipeline (Hayase-style):
/// build query → search sources → merge/rank → add to rqbit → resolve the
/// episode file → return a seekable localhost stream URL for media_kit.
class TorrentStreamService {
  TorrentStreamService({
    List<TorrentSource>? sources,
    AnimeQueryBuilder? queryBuilder,
  })  : _sources = sources ??
            [NyaaSource()], // AnimeToshoSource(), SeaDexSource() commented out as requested
        _queryBuilder = queryBuilder ?? AnimeQueryBuilder();

  final List<TorrentSource> _sources;
  final AnimeQueryBuilder _queryBuilder;
  AnimeQueryBuilder get queryBuilder => _queryBuilder;

  int? _activeTorrentId;
  RqbitClient? _client;

  void _log(String m) => appDebugLog('🌀 [TORRENT] $m');

  /// Finds and starts the best torrent for [media] episode [episode], returning
  /// a playable handle, or null if nothing suitable/streamable was found.
  Future<TorrentStreamHandle?> resolveStream({
    required SearchResult media,
    required int episode,
    required int season,
    String resolution = '1080',
    List<String> exclusions = const [],
    int? absoluteEpisode,
    void Function(String status)? onStatus,
  }) async {
    final query = await _queryBuilder.build(
      media,
      episode,
      season: season,
      resolution: resolution,
      exclusions: exclusions,
      absoluteEpisode: absoluteEpisode,
    );

    final results = await searchTorrents(query: query, onStatus: onStatus);
    if (results.isEmpty) return null;

    final best = TorrentRanking.best(results, query);
    if (best == null) {
      _log('=> ${results.length} candidates but none passed ranking/episode filter');
      onStatus?.call('No suitable release found');
      return null;
    }

    return startTorrent(best, query, episode, onStatus);
  }

  /// Searches and ranks torrents for a given query, returning all candidates.
  Future<List<TorrentResult>> searchTorrents({
    required AnimeQuery query,
    void Function(String status)? onStatus,
  }) async {
    onStatus?.call('Searching sources…');
    _log('query anilistId=${query.anilistId} titles=${query.titles} episodeCount=${query.episodeCount}');

    final all = await _gather(query);
    _log('gathered ${all.length} total results from sources');
    if (all.isEmpty) {
      _log('=> NO torrents found from any source; giving up (engine not started)');
      onStatus?.call('No torrents found');
      return [];
    }

    final merged = _dedupe(_enrichSeeders(all));
    var ranked = TorrentRanking.rank(merged, query, requireEpisodeCoverage: true);
    if (ranked.isEmpty && merged.isNotEmpty) {
      _log('=> strict episode filtering dropped all results; falling back to unfiltered list');
      ranked = TorrentRanking.rank(merged, query, requireEpisodeCoverage: false);
    }
    return ranked;
  }

  /// Starts downloading the [best] torrent and resolves the [episode] file to stream.
  Future<TorrentStreamHandle?> startTorrent(
    TorrentResult best,
    AnimeQuery query,
    int episode,
    void Function(String status)? onStatus,
  ) async {
    _log('best="${best.title}" src=${best.source} seeders=${best.seeders} '
        'res=${best.parsed.resolution} type=${best.type} link=${best.link.substring(0, best.link.length.clamp(0, 60))}…');

    onStatus?.call('Starting: ${best.title}');
    _log('starting rqbit engine…');
    final client = await RqbitEngine.instance.ensureStarted();
    _log('engine ready at ${RqbitEngine.instance.baseUrl}; adding torrent…');
    _client = client;

    final add = await client.addTorrent(
      best.link,
      isUrl: best.link.startsWith('http') ? true : null,
    );
    final id = add.id ?? 0;
    _log('torrent added id=$id; waiting for metadata/files…');

    // Stop any previously-playing torrent (keep files for resume).
    final prev = _activeTorrentId;
    if (prev != null && prev != id) {
      client.forget(prev).catchError((_) {});
    }
    _activeTorrentId = id;

    // Magnets resolve metadata from peers — wait for the file list.
    var details = await client.getDetails(id);
    for (var i = 0; details.files.isEmpty && i < 60; i++) {
      onStatus?.call('Fetching metadata from peers… (${i}s)');
      await Future.delayed(const Duration(seconds: 1));
      details = await client.getDetails(id);
    }
    if (details.files.isEmpty) {
      _log('=> metadata never arrived (no peers?) after 60s for id=$id');
      onStatus?.call('Could not fetch metadata (no peers?)');
      return null;
    }
    _log('metadata ready: ${details.files.length} file(s) in torrent');

    final file = TorrentFileResolver.resolve(
      details.files,
      episode: episode,
      absoluteEpisode: query.absoluteEpisode,
    );
    if (file == null) {
      _log('=> resolver found no playable episode file');
      onStatus?.call('No playable episode file in torrent');
      return null;
    }
    _log('resolved file[${file.index}]="${file.name}" -> streaming');

    // Restrict download to just the target file (faster, less disk).
    try {
      await client.updateOnlyFiles(id, [file.index]);
    } catch (_) {/* single-file torrents / older state: ignore */}

    // Keep the process alive for peers while backgrounded (Android; no-op else).
    unawaited(TorrentForegroundService.instance
        .start(text: 'Streaming: ${best.title}'));

    onStatus?.call('Streaming: ${file.name}');
    return TorrentStreamHandle(
      url: client.streamUrl(id, file.index),
      torrentId: id,
      fileIndex: file.index,
      fileName: file.name,
      client: client,
      title: best.title,
      resolution: best.parsed.resolution,
    );
  }

  /// The id of the torrent currently being streamed, if any.
  int? get activeTorrentId => _activeTorrentId;

  bool get hasActive => _activeTorrentId != null && _client != null;

  /// Live stats for the active torrent (peers, speed, progress), or null when
  /// nothing is playing or on error. Safe to poll from the player UI.
  Future<TorrentStats?> activeStats() async {
    final id = _activeTorrentId;
    final client = _client;
    if (id == null || client == null) return null;
    try {
      return await client.getStats(id);
    } catch (_) {
      return null;
    }
  }

  /// Stops the active torrent. [deleteFiles] also reclaims disk.
  Future<void> stopActive({bool deleteFiles = false}) async {
    final id = _activeTorrentId;
    final client = _client;
    _activeTorrentId = null;
    if (id != null && client != null) {
      try {
        deleteFiles ? await client.delete(id) : await client.forget(id);
      } catch (_) {}
    }
    unawaited(TorrentForegroundService.instance.stop());
  }

  Future<List<TorrentResult>> _gather(AnimeQuery query) async {
    final lists = await Future.wait(_sources.map((s) async {
      try {
        final r = await s.search(query);
        _log('source ${s.name}: ${r.length} result(s)');
        return r;
      } catch (e) {
        _log('source ${s.name}: ERROR $e');
        return <TorrentResult>[];
      }
    }));
    return [for (final l in lists) ...l];
  }

  /// Fill in seeder counts for entries that lack them (SeaDex/Tosho) by matching
  /// info-hashes against entries that do (Nyaa).
  List<TorrentResult> _enrichSeeders(List<TorrentResult> all) {
    final maxByHash = <String, int>{};
    for (final r in all) {
      final h = r.infoHash?.toLowerCase();
      if (h != null && r.seeders > (maxByHash[h] ?? -1)) {
        maxByHash[h] = r.seeders;
      }
    }
    return all.map((r) {
      final h = r.infoHash?.toLowerCase();
      final best = h != null ? (maxByHash[h] ?? r.seeders) : r.seeders;
      if (best <= r.seeders) return r;
      return TorrentResult(
        title: r.title,
        link: r.link,
        infoHash: r.infoHash,
        seeders: best,
        leechers: r.leechers,
        downloads: r.downloads,
        sizeBytes: r.sizeBytes,
        source: r.source,
        accuracy: r.accuracy,
        type: r.type,
        date: r.date,
      );
    }).toList();
  }

  /// Collapse duplicates by info-hash, keeping the richest entry (curated best
  /// > higher accuracy > more seeders).
  List<TorrentResult> _dedupe(List<TorrentResult> all) {
    final byHash = <String, TorrentResult>{};
    final noHash = <TorrentResult>[];
    for (final r in all) {
      final h = r.infoHash?.toLowerCase();
      if (h == null || h.isEmpty) {
        noHash.add(r);
        continue;
      }
      final existing = byHash[h];
      if (existing == null || _preferable(r, existing)) byHash[h] = r;
    }
    return [...byHash.values, ...noHash];
  }

  bool _preferable(TorrentResult a, TorrentResult b) {
    if (a.isBest != b.isBest) return a.isBest;
    final acc = _accuracyRank(a.accuracy) - _accuracyRank(b.accuracy);
    if (acc != 0) return acc > 0;
    return a.seeders > b.seeders;
  }

  static int _accuracyRank(String a) =>
      switch (a) { 'high' => 2, 'medium' => 1, _ => 0 };
}
