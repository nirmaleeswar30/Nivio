import 'dart:math' as math;

import 'torrent_models.dart';

/// Ranks torrent candidates for a query: prefer curated "best"
/// releases, then the right resolution, then healthy seeders, with accuracy and
/// batch-ness as tie-breakers. Exclusions and specials are filtered out.
class TorrentRanking {
  /// Returns [candidates] filtered + sorted best-first for [query].
  static List<TorrentResult> rank(
    List<TorrentResult> candidates,
    AnimeQuery query, {
    bool requireEpisodeCoverage = true,
  }) {
    final exclusions = query.exclusions.map((e) => e.toLowerCase()).toList();

    final filtered = candidates.where((c) {
      if (query.isManual) return true; // Keep everything for manual search
      
      // Drop OP/ED/PV specials.
      if (c.parsed.isSpecial) return false;
      // Drop excluded keywords.
      final lower = c.title.toLowerCase();
      if (exclusions.any(lower.contains)) return false;
      // Must plausibly contain the target episode: a batch covering it, a
      // single file for it, or an un-numbered release (movie / single-cour).
      // Curated SeaDex/best releases are full-series batches — always keep
      // them; the file resolver picks the right episode inside.
      if (requireEpisodeCoverage && !(c.isBest || c.source == 'seadex')) {
        final p = c.parsed;
        final isMovieOrSingle = p.episodeStart == null && !c.isBatch;
        final covers = p.coversEpisode(query.episode) ||
            p.episodeStart == query.episode ||
            (isMovieOrSingle && query.episode == 1); // movie / single
        
        final absCovers = query.absoluteEpisode != null &&
            (p.coversEpisode(query.absoluteEpisode!) ||
                p.episodeStart == query.absoluteEpisode || 
                (isMovieOrSingle && query.absoluteEpisode == 1));
        
        if (!covers && !absCovers) return false;
      }
      
      // Strict Season Filtering: If the parsed title explicitly specifies a season
      // and it does NOT match our requested season, reject it immediately to
      // avoid playing S2 E2 when S1 E2 is requested (e.g. Kimetsu no Yaiba).
      if (c.parsed.season != null && c.parsed.season != query.season) {
        return false;
      }
      
      // If we request a later season but Anitomy couldn't parse the season from the title,
      // it might be a Season 1 episode (e.g. 'Anime - 21' matching Season 4 Episode 21).
      // We must reject it UNLESS it uses absolute episode numbering or mentions the season.
      if (query.season > 1 && c.parsed.season == null && requireEpisodeCoverage && !(c.isBest || c.source == 'seadex')) {
        final p = c.parsed;
        final absCovers = query.absoluteEpisode != null &&
            (p.coversEpisode(query.absoluteEpisode!) ||
             p.episodeStart == query.absoluteEpisode);
             
        if (!absCovers) {
          final lower = c.title.toLowerCase();
          final s = query.season;
          final mentionsSeason = lower.contains('s$s') || 
                                 lower.contains('season $s') || 
                                 lower.contains('${s}nd season') ||
                                 lower.contains('${s}rd season') ||
                                 lower.contains('${s}th season') ||
                                 lower.contains('season$s');
          if (!mentionsSeason) {
            return false; // Strongly likely to be Season 1 pollution
          }
        }
      }

      return true;
    }).toList();

    filtered.sort((a, b) => _score(b, query).compareTo(_score(a, query)));
    return filtered;
  }

  /// The single best candidate, or null.
  static TorrentResult? best(List<TorrentResult> candidates, AnimeQuery query) {
    final ranked = rank(candidates, query);
    return ranked.isEmpty ? null : ranked.first;
  }

  /// Higher is better. Weighted so curated "best" and correct resolution
  /// dominate, then seeders.
  static double _score(TorrentResult t, AnimeQuery query) {
    double score = 0;

    // Curated best (SeaDex) is strongly preferred.
    if (t.isBest) {
      score += 10000;
    } else {
      // Boost known verified/trusted release groups so they beat random uploads
      final lowerTitle = t.title.toLowerCase();
      const trustedGroups = ['subsplease', 'erai-raws', 'judas', 'ember'];
      for (final group in trustedGroups) {
        if (lowerTitle.contains('[$group]') || lowerTitle.contains('($group)')) {
          score += 5000;
          break;
        }
      }
    }

    // Resolution: reward matching the preferred height; penalize over/under.
    final want = query.preferredResolution ?? 1080;
    final res = t.parsed.resolution;
    if (res != null) {
      if (res == want) {
        score += 3000;
      } else if (res < want) {
        score += 1500 - (want - res); // lower than wanted: worse
      } else {
        score += 2000 - (res - want) ~/ 2; // higher than wanted: mildly penalized
      }
    } else {
      score += 500; // unknown resolution
    }

    // Accuracy of the source match.
    switch (t.accuracy) {
      case 'high':
        score += 800;
        break;
      case 'medium':
        score += 300;
        break;
      default:
        score += 0;
    }

    // Seeders (diminishing returns, capped so a mega-seeded 480p can't beat a
    // correctly-sized 1080p).
    score += _seederScore(t.seeders);

    // Slightly prefer single-episode over batch when both cover the target
    // (faster to first byte), unless it's a curated best.
    if (!t.isBest && t.isBatch) score -= 50;

    return score;
  }

  static double _seederScore(int seeders) {
    if (seeders <= 0) return 0;
    final score = 200 * (1 + math.log(seeders) / math.ln2);
    return score.clamp(0, 1200).toDouble();
  }
}
