import 'dart:async';

import 'dart:io';

import 'package:hive/hive.dart';
import 'package:rqbit_ffi/rqbit_ffi.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/debug_log.dart';
import '../../models/search_result.dart';
import '../download_service.dart';
import '../tmdb_service.dart';
import 'anitomy.dart';
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

class TorrentFileSizeException implements Exception {
  const TorrentFileSizeException(this.message);

  final String message;

  @override
  String toString() => message;
}

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
    this.releaseGroup,
    this.fromPack = false,
  });

  final String url;
  final int torrentId;
  final int fileIndex;
  final String fileName;
  final RqbitClient client;
  final String title;
  final int? resolution;
  final String? releaseGroup;
  final bool fromPack;

  Future<TorrentStats> stats() => client.getStats(torrentId);
}

/// A next episode pre-added to rqbit for binge mode. [fromPack] means it's a
/// file inside the already-active season-pack torrent (no new torrent added).
typedef _BingeEpisode = ({String mediaType, int mediaId, int season, int episode, String? group});

class _PrefetchEntry {
  final _BingeEpisode target;
  final int torrentId;
  final int fileIndex;
  final String url;
  final String title;
  final String fileName;
  final bool fromPack;
  final int? resolution;
  final String? releaseGroup;

  _PrefetchEntry({
    required this.target,
    required this.torrentId,
    required this.fileIndex,
    required this.url,
    required this.title,
    required this.fileName,
    required this.fromPack,
    this.resolution,
    this.releaseGroup,
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
  String? _activeReleaseGroup;
  ({String mediaType, int mediaId})? _activeMedia;
  int? _lastStreamedTorrentId;
  // True when _activeTorrentId points at a torrent owned by DownloadService
  // (adopted only so stats can be shown). We must NOT forget/delete it on
  // stopActive — that would kill the user's ongoing download.
  bool _activeIsAdopted = false;
  RqbitClient? _client;

  // Binge prefetch: the next episode pre-added to rqbit (metadata + first
  // pieces) so switching to it is near-instant.
  _PrefetchEntry? _prefetch;
  Object? _prefetching;

  _BingeEpisode _bingeEpisode(SearchResult media, int season, int episode, String? group) => (
    mediaType: media.mediaType,
    mediaId: media.id,
    season: season,
    episode: episode,
    group: group?.trim().toLowerCase(),
  );

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
    bool binge = false,
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

      if (binge && (query.season != season || query.absoluteEpisode != absoluteEpisode)) {
        final pack = await nextEpisodeInActiveTorrent(
          media: media,
          episode: episode,
          season: query.season,
          absoluteEpisode: query.absoluteEpisode,
          preferredGroup: preferredGroup,
        );
        if (pack != null) return pack;
      }

      final results = await searchTorrents(query: query, onStatus: onStatus);
      if (results.isEmpty) return null;

      return _startRanked(results, TorrentRanking.best(results, query), query,
          media, episode, preferredGroup, binge, onStatus);
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

      return _startRanked(results, results.first, query, media, episode,
          preferredGroup, binge, onStatus);
    }
  }

  Future<TorrentStreamHandle?> _startRanked(
    List<TorrentResult> ranked,
    TorrentResult? best,
    Object query,
    SearchResult media,
    int episode,
    String? preferredGroup,
    bool binge,
    void Function(String)? onStatus,
  ) async {
    final preferred = _pickByGroup(ranked, preferredGroup);
    if (preferred != null) {
      try {
        final handle = await startTorrent(preferred, query, episode, onStatus,
            media: media, requireEpisodeMatch: binge);
        if (handle != null) return handle;
      } catch (error) {
        _log('Preferred release could not start: $error');
      }
    }
    final fallback = preferred != null && preferred == best
        ? ranked.where((item) => item != preferred).firstOrNull
        : best;
    if (fallback == null) {
      onStatus?.call('No suitable release found');
      return null;
    }
    return startTorrent(fallback, query, episode, onStatus,
        media: media, requireEpisodeMatch: binge);
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
  /// series, so future episodes prefer the same group.
  Future<void> rememberReleaseGroup(SearchResult media, TorrentResult chosen,
      {required String fileName}) async {
    final group = chosen.parsed.releaseGroup ?? Anitomy.parse(fileName).releaseGroup;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('binge_group_${media.mediaType}_${media.id}', group?.trim() ?? '');
    } catch (_) {}
  }

  /// The remembered binge release group for this series, if any.
  Future<String?> recallReleaseGroup(SearchResult media) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final g = prefs.getString('binge_group_${media.mediaType}_${media.id}') ??
          prefs.getString('binge_group_${media.id}');
      return (g != null && g.trim().isNotEmpty) ? g.trim() : null;
    } catch (_) {
      return null;
    }
  }

  /// Season-pack fast path: if the currently-streaming torrent is a multi-file
  /// pack that also contains [episode], returns a handle streaming that file
  /// directly — no new search, no re-add. Returns null if it isn't in the pack.
  Future<TorrentStreamHandle?> nextEpisodeInActiveTorrent({
    required SearchResult media,
    required int episode,
    int? season,
    int? absoluteEpisode,
    String? preferredGroup,
    bool prepareOnly = false,
  }) async {
    final id = _activeTorrentId;
    final client = _client;
    if (id == null || client == null ||
        _activeMedia != (mediaType: media.mediaType, mediaId: media.id) ||
        (preferredGroup != null && _activeReleaseGroup?.toLowerCase() != preferredGroup.toLowerCase())) return null;
    try {
      final details = await client.getDetails(id);
      if (details.files.length <= 1) return null; // single-file, not a pack
      final file = TorrentFileResolver.resolve(
        details.files,
        episode: episode,
        season: season,
        absoluteEpisode: absoluteEpisode,
        requireEpisodeMatch: true,
      );
      if (file == null) return null;
      if (!prepareOnly && !_activeIsAdopted) {
        try {
          await client.updateOnlyFiles(id, [file.index]);
        } catch (_) {}
      }
      _log('season-pack fast path: episode $episode -> file[${file.index}] "${file.name}"');
      return TorrentStreamHandle(
        url: client.streamUrl(id, file.index),
        torrentId: id,
        fileIndex: file.index,
        fileName: file.name,
        client: client,
        title: details.name?.trim().isNotEmpty == true ? details.name! : file.name,
        releaseGroup: _activeReleaseGroup,
        fromPack: true,
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
  }) async {
    final activeId = _activeTorrentId;
    if (activeId == null) return;
    final preferredGroup = await recallReleaseGroup(media);
    final target = _bingeEpisode(media, season, episode, preferredGroup);
    if (_activeTorrentId != activeId || _prefetching != null || _prefetch?.target == target) return;
    final request = Object();
    _prefetching = request;
    int? addedId;
    try {
      // If the active torrent is a pack that already has this episode, we don't
      // need to add anything — just note the file to switch to.
      var pack = await nextEpisodeInActiveTorrent(
        media: media,
        episode: episode,
        season: season,
        absoluteEpisode: absoluteEpisode,
        preferredGroup: preferredGroup,
        prepareOnly: true,
      );
      if (_prefetching != request || _activeTorrentId != activeId) return;
      if (pack != null) {
        _cachePack(target, pack);
        return;
      }

      final isAnime = media.mediaType == 'anime';
      TorrentResult? best;
      var fileSeason = season;
      var fileAbsoluteEpisode = absoluteEpisode;
      if (isAnime) {
        final query = await _queryBuilder.build(
          media,
          episode,
          season: season,
          resolution: resolution,
          absoluteEpisode: absoluteEpisode,
        );
        fileSeason = query.season;
        fileAbsoluteEpisode = query.absoluteEpisode;
        if (fileSeason != season || fileAbsoluteEpisode != absoluteEpisode) {
          pack = await nextEpisodeInActiveTorrent(
            media: media,
            episode: episode,
            season: fileSeason,
            absoluteEpisode: fileAbsoluteEpisode,
            preferredGroup: preferredGroup,
            prepareOnly: true,
          );
          if (_prefetching != request || _activeTorrentId != activeId) return;
          if (pack != null) {
            _cachePack(target, pack);
            return;
          }
        }
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
      if (best == null || _prefetching != request || _activeTorrentId != activeId) return;

      final client = await RqbitEngine.instance.ensureStarted();
      _client ??= client;
      final add = await client.addTorrent(
        best.link,
        isUrl: best.link.startsWith('http') ? true : null,
      );
      final id = add.id;
      if (id == null) return;
      addedId = id;

      var details = await client.getDetails(id);
      for (var i = 0; details.files.isEmpty && i < 30; i++) {
        await Future.delayed(const Duration(seconds: 1));
        details = await client.getDetails(id);
      }
      if (details.files.isEmpty || _prefetching != request || _activeTorrentId != activeId) return;

      TorrentFileInfo? file = best.fileIndex != null
          ? details.files.where((f) => f.index == best!.fileIndex).firstOrNull
          : null;
      file ??= TorrentFileResolver.resolve(
        details.files,
        episode: episode,
        absoluteEpisode: fileAbsoluteEpisode,
        season: fileSeason,
        requireEpisodeMatch: true,
        allowUnnumberedSingle: !best.isBatch,
      );
      if (file == null) return;
      if (id != activeId) {
        try {
          await client.updateOnlyFiles(id, [file.index]);
        } catch (_) {}
      }
      if (_prefetching != request || _activeTorrentId != activeId) return;

      _cachePrefetch(_PrefetchEntry(
        target: target,
        torrentId: id,
        fileIndex: file.index,
        url: client.streamUrl(id, file.index),
        title: best.title,
        fileName: file.name,
        fromPack: false,
        resolution: best.parsed.resolution,
        releaseGroup: best.parsed.releaseGroup ?? Anitomy.parse(file.name).releaseGroup,
      ));
      _log('prefetched episode $episode -> torrent $id file[${file.index}]');
    } catch (e) {
      _log('prefetch error: $e');
    } finally {
      if (_prefetching == request) _prefetching = null;
      if (addedId != null && addedId != _activeTorrentId && addedId != _prefetch?.torrentId) {
        await _releaseTorrent(addedId);
      }
    }
  }

  void _cachePack(_BingeEpisode target, TorrentStreamHandle pack) {
    _cachePrefetch(_PrefetchEntry(
      target: target,
      torrentId: pack.torrentId,
      fileIndex: pack.fileIndex,
      url: pack.url,
      title: pack.title,
      fileName: pack.fileName,
      fromPack: true,
      resolution: pack.resolution,
      releaseGroup: pack.releaseGroup,
    ));
  }

  void _cachePrefetch(_PrefetchEntry entry) {
    final old = _prefetch;
    _prefetch = entry;
    if (old != null && !old.fromPack && old.torrentId != entry.torrentId &&
        old.torrentId != _activeTorrentId) {
      unawaited(_releaseTorrent(old.torrentId));
    }
  }

  /// Returns the prefetched handle for [episode] (if any) and promotes it to the
  /// active stream, releasing the previously-active torrent. Null if nothing was
  /// prefetched for that episode.
  Future<TorrentStreamHandle?> consumePrefetch({
    required SearchResult media,
    required int episode,
    required int season,
    required String? preferredGroup,
  }) async {
    final p = _prefetch;
    final target = _bingeEpisode(media, season, episode, preferredGroup);
    if (p == null || p.target != target || (p.fromPack && p.torrentId != _activeTorrentId)) return null;
    _prefetch = null;
    final client = _client;
    if (client == null) return null;

    if (!p.fromPack) {
      final old = _activeTorrentId ?? _lastStreamedTorrentId;
      final oldAdopted = _activeIsAdopted;
      _activeTorrentId = p.torrentId;
      _lastStreamedTorrentId = p.torrentId;
      _activeIsAdopted = false;
      _activeMedia = (mediaType: media.mediaType, mediaId: media.id);
      _activeReleaseGroup = p.releaseGroup?.trim();
      // Never release an adopted download torrent — it belongs to DownloadService.
      if (old != null && old != p.torrentId && !oldAdopted) {
        unawaited(_releaseTorrent(old));
      }
    }
    if (!_activeIsAdopted) {
      try {
        await client.updateOnlyFiles(p.torrentId, [p.fileIndex]);
      } catch (_) {}
    }
    _log('consuming prefetch for episode $episode (torrent ${p.torrentId})');
    return TorrentStreamHandle(
      url: p.url,
      torrentId: p.torrentId,
      fileIndex: p.fileIndex,
      fileName: p.fileName,
      client: client,
      title: p.title,
      resolution: p.resolution,
      releaseGroup: p.releaseGroup,
      fromPack: p.fromPack,
    );
  }

  /// Releases a torrent from rqbit, honouring the persist-files setting.
  Future<void> _releaseTorrent(int id) async {
    final client = _client;
    if (client == null) return;
    try {
      if (Hive.isBoxOpen('downloads') && DownloadService.box.values.any((item) => item.torrentId == id)) return;
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
    void Function(String status)? onStatus, {
    required SearchResult media,
    bool requireEpisodeMatch = false,
    Duration? metadataTimeout,
    bool Function()? cancelled,
    int? maxFileBytes,
  }) async {
    _log('best="${best.title}" src=${best.source} seeders=${best.seeders} '
        'res=${best.parsed.resolution} type=${best.type} link=${best.link.substring(0, best.link.length.clamp(0, 60))}…');

    final prefs = await SharedPreferences.getInstance();
    final persistFiles = prefs.getBool('torrent_persist_files') ?? false;

    onStatus?.call('Starting: ${best.title}');
    _log('starting rqbit engine…');
    final client = await RqbitEngine.instance.ensureStarted();
    _log('engine ready at ${RqbitEngine.instance.baseUrl}; adding torrent…');
    _client = client;

    if (cancelled?.call() == true) return null;
    final add = await client.addTorrent(
      best.link,
      isUrl: best.link.startsWith('http') ? true : null,
    );
    final id = add.id;
    if (id == null) return null;
    _log('torrent added id=$id; waiting for metadata/files…');

    // Magnets resolve metadata from peers — wait for the file list.
    final metadataWait = Stopwatch()..start();
    final maxWait = metadataTimeout ?? const Duration(seconds: 60);
    var details = await client.getDetails(id);
    for (var i = 0; details.files.isEmpty && metadataWait.elapsed < maxWait &&
        cancelled?.call() != true; i++) {
      onStatus?.call('Fetching metadata from peers… (${i}s)');
      await Future.delayed(const Duration(seconds: 1));
      details = await client.getDetails(id);
    }
    if (details.files.isEmpty || cancelled?.call() == true) {
      _log('=> torrent metadata wait ended after ${metadataWait.elapsed.inSeconds}s for id=$id');
      if (cancelled?.call() != true) onStatus?.call('Could not fetch metadata (no peers?)');
      if (id != _activeTorrentId) await _releaseTorrent(id);
      return null;
    }
    _log('metadata ready: ${details.files.length} file(s) in torrent');
    final season = query is MediaTorrentQuery
        ? query.season
        : (query is AnimeQuery ? query.season : null);
    final absoluteEpisode = query is AnimeQuery ? query.absoluteEpisode : null;
    TorrentFileInfo? file;
    if (best.fileIndex != null) {
      file = details.files.where((f) => f.index == best.fileIndex).firstOrNull;
      if (file != null && requireEpisodeMatch) {
        file = TorrentFileResolver.resolve(
          [file], episode: episode, season: season, absoluteEpisode: absoluteEpisode,
          requireEpisodeMatch: true,
        );
      }
    }
    file ??= TorrentFileResolver.resolve(
      details.files,
      episode: episode,
      absoluteEpisode: absoluteEpisode,
      season: season,
      requireEpisodeMatch: requireEpisodeMatch,
      allowUnnumberedSingle: !best.isBatch,
    );
    if (file == null) {
      _log('=> resolver found no playable file');
      onStatus?.call('No playable file in torrent');
      if (id != _activeTorrentId) await _releaseTorrent(id);
      return null;
    }
    if (maxFileBytes != null && (file.length <= 0 || file.length > maxFileBytes)) {
      if (id != _activeTorrentId && id != _prefetch?.torrentId) {
        await _releaseTorrent(id);
      }
      throw TorrentFileSizeException(
        file.length <= 0
            ? 'Could not verify the torrent video’s file size.'
            : 'The torrent video exceeds your maximum file size.',
      );
    }
    _log('resolved file[${file.index}]="${file.name}" -> streaming');

    // Keep the prior stream until the chosen release has a playable file.
    final prev = _activeTorrentId ?? _lastStreamedTorrentId;
    final prevAdopted = _activeIsAdopted;
    _activeTorrentId = id;
    _lastStreamedTorrentId = id;
    _activeIsAdopted = false;
    _activeMedia = (mediaType: media.mediaType, mediaId: media.id);
    final releaseGroup = (best.parsed.releaseGroup ?? Anitomy.parse(file.name).releaseGroup)?.trim();
    _activeReleaseGroup = releaseGroup;
    if (prev != null && prev != id && !prevAdopted) await _releaseTorrent(prev);
    if (!persistFiles) {
      unawaited(_cleanupOldStreamingCache(client, currentTorrentId: id, details: details));
    }

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
      releaseGroup: releaseGroup,
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
      _activeMedia = null;
      _activeReleaseGroup = null;
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
    _activeMedia = null;
    _activeReleaseGroup = null;
    _prefetching = null;
    final prefetched = _prefetch;
    _prefetch = null;
    if (prefetched != null && !prefetched.fromPack && prefetched.torrentId != id) {
      unawaited(_releaseTorrent(prefetched.torrentId));
    }
    // An adopted torrent is owned by DownloadService's ongoing download — just
    // stop reporting it; forgetting/deleting it would abort that download.
    if (wasAdopted) {
      unawaited(TorrentForegroundService.instance.stop());
      return;
    }
    if (id != null && client != null) {
      try {
        if (deleteFiles) {
          await client.delete(id);
          _lastStreamedTorrentId = null;
        } else {
          _lastStreamedTorrentId = id;
          await client.pause(id);
        }
      } catch (_) {}
    }
    unawaited(TorrentForegroundService.instance.stop());
  }

  /// Cleans up previous streaming torrents and disk cache when a new torrent is played.
  Future<void> _cleanupOldStreamingCache(
    RqbitClient client, {
    required int currentTorrentId,
    required TorrentDetails details,
  }) async {
    try {
      final activeDownloadTorrentIds = <int>{};
      final activeDownloadPaths = <String>{};
      if (Hive.isBoxOpen('downloads')) {
        for (final item in DownloadService.box.values) {
          if (item.torrentId != null) activeDownloadTorrentIds.add(item.torrentId!);
          if (item.savePath.isNotEmpty) activeDownloadPaths.add(item.savePath);
        }
      }

      // 1. Delete any other torrents in rqbit session not belonging to DownloadService
      final allTorrents = await client.listTorrents();
      for (final t in allTorrents) {
        final tId = t.id;
        if (tId != null && tId != currentTorrentId && !activeDownloadTorrentIds.contains(tId)) {
          _log('🗑️ Purging previous streaming torrent $tId (${t.name}) from rqbit');
          try {
            await client.delete(tId);
          } catch (_) {}
        }
      }

      // 2. Clear prefetch if it was for a different torrent
      if (_prefetch != null && _prefetch!.torrentId != currentTorrentId) {
        final pId = _prefetch!.torrentId;
        _prefetch = null;
        if (!activeDownloadTorrentIds.contains(pId)) {
          try {
            await client.delete(pId);
          } catch (_) {}
        }
      }

      // 3. Clean up any leftover folders/files in the torrents cache directory
      final downloadDir = RqbitEngine.instance.downloadDir;
      if (downloadDir != null) {
        final dir = Directory(downloadDir);
        if (await dir.exists()) {
          final keepNames = <String>{};
          if (details.name != null && details.name!.isNotEmpty) {
            keepNames.add(details.name!);
          }
          for (final f in details.files) {
            if (f.name.isNotEmpty) {
              keepNames.add(f.name.split(Platform.pathSeparator).first);
              keepNames.add(f.name.split('/').first);
            }
          }

          final entities = await dir.list().toList();
          for (final entity in entities) {
            final baseName = entity.uri.pathSegments.where((s) => s.isNotEmpty).lastOrNull ?? '';
            if (baseName.isEmpty) continue;
            if (keepNames.contains(baseName)) continue;
            if (activeDownloadPaths.any((p) => p.contains(baseName))) continue;

            try {
              _log('🧹 Purging old torrent streaming cache from disk: ${entity.path}');
              await entity.delete(recursive: true);
            } catch (e) {
              _log('Failed to delete old torrent cache ${entity.path}: $e');
            }
          }
        }
      }
    } catch (e) {
      _log('Warning: cleanupOldStreamingCache error: $e');
    }
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
