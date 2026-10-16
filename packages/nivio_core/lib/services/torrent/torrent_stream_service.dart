import 'dart:async';

import 'package:rqbit_ffi/rqbit_ffi.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/debug_log.dart';
import '../../models/search_result.dart';
import '../tmdb_service.dart';
import 'anime_query_builder.dart';
import 'media_ranking.dart';
import 'media_torrent_models.dart';
import 'ranking.dart';
import 'resolver.dart';
import 'sources/nyaa_source.dart';
import 'sources/piratebay_source.dart';
import 'sources/torrent_source.dart';
import 'sources/torrentio_source.dart';
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

/// A next episode pre-added to rqbit for binge mode. [fromPack] means it's a
/// file inside the already-active season-pack torrent (no new torrent added).
class _PrefetchEntry {
  final int episode;
  final int torrentId;
  final int fileIndex;
  final String url;
  final bool fromPack;
  final int? resolution;

  _PrefetchEntry({
    required this.episode,
    required this.torrentId,
    required this.fileIndex,
    required this.url,
    required this.fromPack,
    this.resolution,
  });
}

/// Orchestrates the torrent streaming pipeline:
/// - Anime: NyaaSource via AnimeQuery and TorrentRanking
/// - Movies & Shows: TorrentioSource via MediaTorrentQuery and MediaRanking
/// build query → search sources → merge/rank → add to rqbit → resolve file →
/// return a seekable localhost stream URL for media_kit.
class TorrentStreamService {
  TorrentStreamService({
    List<TorrentSource>? animeSources,
    List<TorrentSource>? sources,
    List<MediaTorrentSource>? mediaSources,
    AnimeQueryBuilder? queryBuilder,
    TmdbService? tmdbService,
  })  : _animeSources = animeSources ?? sources ?? [NyaaSource()],
        _mediaSources = mediaSources ?? [TorrentioSource(), PirateBaySource()],
        _queryBuilder = queryBuilder ?? AnimeQueryBuilder(),
        _tmdbService = tmdbService;

  final List<TorrentSource> _animeSources;
  final List<MediaTorrentSource> _mediaSources;
  final AnimeQueryBuilder _queryBuilder;
  final TmdbService? _tmdbService;

  List<TorrentSource> get animeSources => _animeSources;
  List<TorrentSource> get sources => _animeSources;
  List<MediaTorrentSource> get mediaSources => _mediaSources;
  AnimeQueryBuilder get queryBuilder => _queryBuilder;
  TmdbService? get tmdbService => _tmdbService;

  int? _activeTorrentId;
  // True when _activeTorrentId points at a torrent owned by DownloadService
  // (adopted only so stats can be shown). We must NOT forget/delete it on
  // stopActive — that would kill the user's ongoing download.
  bool _activeIsAdopted = false;
  RqbitClient? _client;

  // Binge prefetch: the next episode pre-added to rqbit (metadata + first
  // pieces) so switching to it is near-instant.
  _PrefetchEntry? _prefetch;

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
    String? preferredGroup,
    void Function(String status)? onStatus,
  }) async {
    final isAnime = media.mediaType == 'anime';

    if (isAnime) {
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

      // Binge mode: prefer the same release group the user picked before,
      // falling back to the best-ranked release when it isn't available.
      final best =
          _pickByGroup(results, preferredGroup) ?? TorrentRanking.best(results, query);
      if (best == null) {
        _log('=> ${results.length} candidates but none passed ranking/episode filter');
        onStatus?.call('No suitable release found');
        return null;
      }

      return startTorrent(best, query, episode, onStatus);
    } else {
      // Movies and TV series
      final isMovie = media.mediaType == 'movie';
      onStatus?.call('Resolving IMDb ID…');

      String? imdbId;
      if (_tmdbService != null) {
        imdbId = await _tmdbService.getImdbId(
          tmdbId: media.id,
          isMovie: isMovie,
        );
      }

      if (imdbId == null || imdbId.isEmpty) {
        _log('=> could not resolve IMDb ID for media TMDB ${media.id}');
        onStatus?.call('IMDb ID not found for torrent lookup');
        return null;
      }

      final query = MediaTorrentQuery(
        imdbId: imdbId,
        tmdbId: media.id,
        title: media.title ?? media.name ?? '',
        isMovie: isMovie,
        season: isMovie ? null : season,
        episode: isMovie ? null : episode,
        resolution: resolution,
      );

      final results = await searchMediaTorrents(query: query, onStatus: onStatus);
      if (results.isEmpty) return null;

      final best =
          _pickByGroup(results, preferredGroup) ?? MediaRanking.best(results, query);
      if (best == null) {
        _log('=> ${results.length} media candidates but none passed ranking');
        onStatus?.call('No suitable release found');
        return null;
      }

      return startTorrent(best, query, episode, onStatus);
    }
  }

  /// Returns the highest-ranked candidate whose release group matches [group]
  /// (case-insensitive), or null if none match. Candidates are already ranked
  /// best-first, so the first match is the best same-group release.
  TorrentResult? _pickByGroup(List<TorrentResult> ranked, String? group) {
    if (group == null || group.trim().isEmpty) return null;
    final g = group.trim().toLowerCase();
    for (final r in ranked) {
      final rg = r.parsed.releaseGroup?.trim().toLowerCase();
      if (rg != null && rg.isNotEmpty && rg == g) return r;
    }
    return null;
  }

  /// Persists the release group of [chosen] as the binge preference for the
  /// series [mediaId], so future episodes prefer the same group.
  Future<void> rememberReleaseGroup(int mediaId, TorrentResult chosen) async {
    final group = chosen.parsed.releaseGroup;
    if (group == null || group.trim().isEmpty) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('binge_group_$mediaId', group.trim());
    } catch (_) {}
  }

  /// The remembered binge release group for series [mediaId], if any.
  Future<String?> recallReleaseGroup(int mediaId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final g = prefs.getString('binge_group_$mediaId');
      return (g != null && g.trim().isNotEmpty) ? g.trim() : null;
    } catch (_) {
      return null;
    }
  }

  /// Season-pack fast path: if the currently-streaming torrent is a multi-file
  /// pack that also contains [episode], returns a handle streaming that file
  /// directly — no new search, no re-add. Returns null if it isn't in the pack.
  Future<TorrentStreamHandle?> nextEpisodeInActiveTorrent({
    required int episode,
    int? season,
    int? absoluteEpisode,
  }) async {
    final id = _activeTorrentId;
    final client = _client;
    if (id == null || client == null) return null;
    try {
      final details = await client.getDetails(id);
      if (details.files.length <= 1) return null; // single-file, not a pack
      final file = TorrentFileResolver.resolve(
        details.files,
        episode: episode,
        season: season,
        absoluteEpisode: absoluteEpisode,
      );
      if (file == null) return null;
      try {
        await client.updateOnlyFiles(id, [file.index]);
      } catch (_) {}
      _log('season-pack fast path: episode $episode -> file[${file.index}] "${file.name}"');
      return TorrentStreamHandle(
        url: client.streamUrl(id, file.index),
        torrentId: id,
        fileIndex: file.index,
        fileName: file.name,
        client: client,
        title: file.name,
        resolution: null,
      );
    } catch (_) {
      return null;
    }
  }

  /// Binge medium-prefetch: while the current episode is still playing, search
  /// for [episode], pick the same-group (or best) release, and pre-add it to
  /// rqbit so its metadata + first pieces are ready. Does NOT touch the active
  /// stream — the swap only happens later in [consumePrefetch].
  Future<void> prefetchEpisode({
    required SearchResult media,
    required int episode,
    required int season,
    String resolution = '1080',
    int? absoluteEpisode,
    String? preferredGroup,
  }) async {
    try {
      if (_prefetch?.episode == episode) return; // already prefetched

      // If the active torrent is a pack that already has this episode, we don't
      // need to add anything — just note the file to switch to.
      final pack = await nextEpisodeInActiveTorrent(
        episode: episode,
        season: season,
        absoluteEpisode: absoluteEpisode,
      );
      if (pack != null) {
        _prefetch = _PrefetchEntry(
          episode: episode,
          torrentId: pack.torrentId,
          fileIndex: pack.fileIndex,
          url: pack.url,
          fromPack: true,
          resolution: pack.resolution,
        );
        return;
      }

      final isAnime = media.mediaType == 'anime';
      TorrentResult? best;
      if (isAnime) {
        final query = await _queryBuilder.build(
          media,
          episode,
          season: season,
          resolution: resolution,
          absoluteEpisode: absoluteEpisode,
        );
        final results = await searchTorrents(query: query);
        if (results.isEmpty) return;
        best = _pickByGroup(results, preferredGroup) ?? TorrentRanking.best(results, query);
      } else {
        final isMovie = media.mediaType == 'movie';
        final imdbId = _tmdbService != null
            ? await _tmdbService.getImdbId(tmdbId: media.id, isMovie: isMovie)
            : null;
        if (imdbId == null || imdbId.isEmpty) return;
        final query = MediaTorrentQuery(
          imdbId: imdbId,
          tmdbId: media.id,
          title: media.title ?? media.name ?? '',
          isMovie: isMovie,
          season: isMovie ? null : season,
          episode: isMovie ? null : episode,
          resolution: resolution,
        );
        final results = await searchMediaTorrents(query: query);
        if (results.isEmpty) return;
        best = _pickByGroup(results, preferredGroup) ?? MediaRanking.best(results, query);
      }
      if (best == null) return;

      final client = await RqbitEngine.instance.ensureStarted();
      _client ??= client;
      final add = await client.addTorrent(
        best.link,
        isUrl: best.link.startsWith('http') ? true : null,
      );
      final id = add.id;
      if (id == null) return;

      var details = await client.getDetails(id);
      for (var i = 0; details.files.isEmpty && i < 30; i++) {
        await Future.delayed(const Duration(seconds: 1));
        details = await client.getDetails(id);
      }
      if (details.files.isEmpty) {
        await _releaseTorrent(id);
        return;
      }

      TorrentFileInfo? file = best.fileIndex != null
          ? details.files.where((f) => f.index == best!.fileIndex).firstOrNull
          : null;
      file ??= TorrentFileResolver.resolve(
        details.files,
        episode: episode,
        absoluteEpisode: absoluteEpisode,
        season: season,
      );
      if (file == null) return;
      try {
        await client.updateOnlyFiles(id, [file.index]);
      } catch (_) {}

      _prefetch = _PrefetchEntry(
        episode: episode,
        torrentId: id,
        fileIndex: file.index,
        url: client.streamUrl(id, file.index),
        fromPack: false,
        resolution: best.parsed.resolution,
      );
      _log('prefetched episode $episode -> torrent $id file[${file.index}]');
    } catch (e) {
      _log('prefetch error: $e');
    }
  }

  /// Returns the prefetched handle for [episode] (if any) and promotes it to the
  /// active stream, releasing the previously-active torrent. Null if nothing was
  /// prefetched for that episode.
  TorrentStreamHandle? consumePrefetch(int episode) {
    final p = _prefetch;
    if (p == null || p.episode != episode) return null;
    _prefetch = null;
    final client = _client;
    if (client == null) return null;

    if (!p.fromPack) {
      final old = _activeTorrentId;
      final oldAdopted = _activeIsAdopted;
      _activeTorrentId = p.torrentId;
      _activeIsAdopted = false;
      // Never release an adopted download torrent — it belongs to DownloadService.
      if (old != null && old != p.torrentId && !oldAdopted) {
        unawaited(_releaseTorrent(old));
      }
    }
    _log('consuming prefetch for episode $episode (torrent ${p.torrentId})');
    return TorrentStreamHandle(
      url: p.url,
      torrentId: p.torrentId,
      fileIndex: p.fileIndex,
      fileName: '',
      client: client,
      title: '',
      resolution: p.resolution,
    );
  }

  /// Releases a torrent from rqbit, honouring the persist-files setting.
  Future<void> _releaseTorrent(int id) async {
    final client = _client;
    if (client == null) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final persist = prefs.getBool('torrent_persist_files') ?? false;
      persist ? await client.forget(id) : await client.delete(id);
    } catch (_) {}
  }

  /// Searches and ranks torrents for a given anime query, returning all candidates.
  Future<List<TorrentResult>> searchTorrents({
    required AnimeQuery query,
    void Function(String status)? onStatus,
  }) async {
    onStatus?.call('Searching sources…');
    _log('query anilistId=${query.anilistId} titles=${query.titles} episodeCount=${query.episodeCount}');

    final all = await _gather(query);
    _log('gathered ${all.length} total results from anime sources');
    if (all.isEmpty) {
      _log('=> NO torrents found from any anime source; giving up (engine not started)');
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

  /// Searches and ranks torrents for movies and TV shows via Torrentio.
  /// When [rank] is false (e.g. a manual free-text search), the results are
  /// returned raw — deduped and sorted by seeders only, with no resolution/
  /// quality weighting — so the user sees exactly what the source returned.
  Future<List<TorrentResult>> searchMediaTorrents({
    required MediaTorrentQuery query,
    void Function(String status)? onStatus,
    bool rank = true,
  }) async {
    onStatus?.call('Searching sources…');
    _log('media query imdbId=${query.imdbId} title=${query.title} isMovie=${query.isMovie} S${query.season}E${query.episode}');

    final all = await _gatherMedia(query);
    _log('gathered ${all.length} total results from media sources');
    if (all.isEmpty) {
      _log('=> NO torrents found from any media source; giving up');
      onStatus?.call('No torrents found');
      return [];
    }

    final merged = _dedupe(_enrichSeeders(all));
    if (!rank) {
      // Raw manual search: no quality/resolution ranking, just most-seeded first.
      final list = [...merged]..sort((a, b) => b.seeders.compareTo(a.seeders));
      return list;
    }
    final ranked = MediaRanking.rank(merged, query);
    return ranked;
  }

  /// Starts downloading the [best] torrent and resolves the file to stream.
  Future<TorrentStreamHandle?> startTorrent(
    TorrentResult best,
    dynamic query,
    int episode,
    void Function(String status)? onStatus,
  ) async {
    _log('best="${best.title}" src=${best.source} seeders=${best.seeders} '
        'res=${best.parsed.resolution} type=${best.type} link=${best.link.substring(0, best.link.length.clamp(0, 60))}…');

    final prefs = await SharedPreferences.getInstance();
    final persistFiles = prefs.getBool('torrent_persist_files') ?? false;

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

    // Stop any previously-playing torrent — unless it was an adopted download
    // torrent (owned by DownloadService), which must keep running.
    final prev = _activeTorrentId;
    final prevAdopted = _activeIsAdopted;
    if (prev != null && prev != id && !prevAdopted) {
      try {
        if (persistFiles) {
          await client.forget(prev);
        } else {
          await client.delete(prev);
        }
      } catch (_) {}
    }
    _activeTorrentId = id;
    _activeIsAdopted = false;

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

    TorrentFileInfo? file;
    if (best.fileIndex != null) {
      file = details.files.where((f) => f.index == best.fileIndex).firstOrNull;
    }
    file ??= TorrentFileResolver.resolve(
      details.files,
      episode: episode,
      absoluteEpisode: query is AnimeQuery ? query.absoluteEpisode : null,
      season: query is MediaTorrentQuery
          ? query.season
          : (query is AnimeQuery ? query.season : null),
    );
    if (file == null) {
      _log('=> resolver found no playable file');
      onStatus?.call('No playable file in torrent');
      return null;
    }
    _log('resolved file[${file.index}]="${file.name}" -> streaming');

    // Wait out the initializing/checking state (up to ~20s) so the stream
    // endpoint can actually serve the file header when mpv opens it. When replaying
    // a torrent that was partially streamed previously, rqbit enters 'initializing'
    // while hash-checking on-disk pieces. If mpv connects while rqbit is initializing,
    // the stream endpoint serves nothing and mpv gets stuck at 0:00 forever.
    for (int i = 0; i < 40; i++) {
      try {
        final stats = await client.getStats(id);
        final state = stats.state.toLowerCase();
        if (state == 'live' || stats.finished || state == 'error') break;
        onStatus?.call(
            'Verifying cached data… (${(stats.progressBytes / 1024 / 1024).toStringAsFixed(1)} MB)');
      } catch (_) {}
      await Future.delayed(const Duration(milliseconds: 500));
    }

    // Restrict download to just the target file (faster, less disk).
    for (int retry = 0; retry < 5; retry++) {
      try {
        await client.updateOnlyFiles(id, [file.index]);
        break;
      } catch (_) {
        await Future.delayed(const Duration(milliseconds: 200));
      }
    }

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

  /// Adopts a torrent that was started elsewhere (e.g. a DownloadService
  /// "watch while downloading" torrent running on the same shared rqbit engine)
  /// so the player's live P2P stats overlay can report it. The engine client is
  /// shared, so getStats(id) works once we point [_activeTorrentId] at it.
  Future<void> adoptActiveTorrent(int torrentId) async {
    try {
      _client ??= await RqbitEngine.instance.ensureStarted();
      _activeTorrentId = torrentId;
      _activeIsAdopted = true;
    } catch (_) {}
  }

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

  /// Stops the active torrent and halts network/seeding activity.
  /// Keeps downloaded chunks in cache so re-opening the same video resumes instantly.
  /// Old video cache is automatically deleted when a different video is played.
  Future<void> stopActive({bool deleteFiles = false}) async {
    final id = _activeTorrentId;
    final client = _client;
    final wasAdopted = _activeIsAdopted;
    _activeTorrentId = null;
    _activeIsAdopted = false;
    // An adopted torrent is owned by DownloadService's ongoing download — just
    // stop reporting it; forgetting/deleting it would abort that download.
    if (wasAdopted) {
      unawaited(TorrentForegroundService.instance.stop());
      return;
    }
    if (id != null && client != null) {
      try {
        deleteFiles ? await client.delete(id) : await client.forget(id);
      } catch (_) {}
    }
    unawaited(TorrentForegroundService.instance.stop());
  }

  Future<List<TorrentResult>> _gather(AnimeQuery query) async {
    final prefs = await SharedPreferences.getInstance();
    final nyaaEnabled = prefs.getBool('torrent_source_nyaa') ?? true;

    final activeSources = _animeSources.where((s) {
      if (s is NyaaSource) return nyaaEnabled;
      return true;
    }).toList();

    if (activeSources.isEmpty) {
      _log('all anime torrent sources are disabled in settings');
      return [];
    }

    final lists = await Future.wait(activeSources.map((s) async {
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

  Future<List<TorrentResult>> _gatherMedia(MediaTorrentQuery query) async {
    final prefs = await SharedPreferences.getInstance();
    final torrentioEnabled = prefs.getBool('torrent_source_torrentio') ?? true;
    final pirateBayEnabled = prefs.getBool('torrent_source_piratebay') ?? true;

    final activeSources = _mediaSources.where((s) {
      if (s is TorrentioSource) return torrentioEnabled;
      if (s is PirateBaySource) return pirateBayEnabled;
      return true;
    }).toList();

    if (activeSources.isEmpty) {
      _log('all media torrent sources are disabled in settings');
      return [];
    }

    final lists = await Future.wait(activeSources.map((s) async {
      try {
        final r = await s.searchMedia(query);
        _log('media source ${s.name}: ${r.length} result(s)');
        return r;
      } catch (e) {
        _log('media source ${s.name}: ERROR $e');
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
