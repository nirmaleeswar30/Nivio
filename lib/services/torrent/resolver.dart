import 'package:rqbit_ffi/rqbit_ffi.dart';

import 'anitomy.dart';

/// Picks which file inside a torrent to stream for a target episode:
/// keep video files, parse each, drop OP/ED/PV
/// specials, match the episode (season/absolute aware), with sensible fallbacks.
class TorrentFileResolver {
  /// Returns the [TorrentFileInfo] to stream, or null if none.
  static TorrentFileInfo? resolve(
    List<TorrentFileInfo> files, {
    required int episode,
    int? absoluteEpisode,
    int? season,
    bool requireEpisodeMatch = false,
    bool allowUnnumberedSingle = false,
  }) {
    if (files.isEmpty) return null;

    final videos = files.where((f) => kVideoExtRx.hasMatch(f.name)).toList();
    if (videos.isEmpty) {
      if (requireEpisodeMatch) return null;
      // No recognizable video files — stream the largest file.
      final sorted = [...files]..sort((a, b) => b.length.compareTo(a.length));
      return sorted.first;
    }
    if (videos.length == 1 && !requireEpisodeMatch) return videos.first;

    final parsed = [
      for (final f in videos)
        (file: f, info: Anitomy.parse(requireEpisodeMatch ? _episodeFileName(f.name) : f.name)),
    ];

    // Drop specials (OP/ED/PV) unless that would leave nothing.
    final nonSpecial = parsed.where((p) => !p.info.isSpecial).toList();
    final pool = nonSpecial.isEmpty && !requireEpisodeMatch ? parsed : nonSpecial;

    // Exact episode match, season-aware.
    ({TorrentFileInfo file, AnitomyResult info})? match;
    for (final p in pool) {
      if (p.info.episodeStart == episode || p.info.coversEpisode(episode)) {
        if (season == null || p.info.season == null || p.info.season == season) {
          match = p;
          break;
        }
        if (!requireEpisodeMatch) match ??= p;
      }
    }

    // Absolute-numbering fallback.
    if (match == null && absoluteEpisode != null) {
      for (final p in pool) {
        if (requireEpisodeMatch && season != null && p.info.season != null &&
            p.info.season != season) continue;
        if (p.info.episodeStart == absoluteEpisode ||
            p.info.coversEpisode(absoluteEpisode)) {
          match = p;
          break;
        }
      }
    }

    if (requireEpisodeMatch) {
      if (match != null) return match.file;
      if (allowUnnumberedSingle && videos.length == 1 && pool.length == 1) {
        final single = pool.single;
        if (single.info.episodeStart == null &&
            (season == null || single.info.season == null || single.info.season == season)) {
          return single.file;
        }
      }
      return null;
    }

    // Fallbacks: episode 1, else lowest-numbered, else largest file.
    if (match == null) {
      final byEpisode = [...pool]..sort((a, b) =>
          (a.info.episodeStart ?? 1 << 30).compareTo(b.info.episodeStart ?? 1 << 30));
      match = byEpisode.cast<({TorrentFileInfo file, AnitomyResult info})?>().firstWhere(
            (p) => p!.info.episodeStart == 1,
            orElse: () => byEpisode.isNotEmpty ? byEpisode.first : null,
          );
    }

    if (match == null) {
      final sorted = [...videos]..sort((a, b) => b.length.compareTo(a.length));
      return sorted.first;
    }
    return match.file;
  }

  static String _episodeFileName(String path) {
    final fileName = path.split(RegExp(r'[/\\]')).last;
    final stem = fileName.replaceFirst(kVideoExtRx, '');
    final episode = int.tryParse(stem);
    return episode != null && episode > 0 && episode <= 999
        ? 'Episode $episode'
        : fileName;
  }
}
