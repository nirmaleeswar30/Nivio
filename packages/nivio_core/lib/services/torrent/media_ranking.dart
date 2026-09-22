import 'media_torrent_models.dart';
import 'torrent_models.dart';

/// Scores and ranks movie and TV show torrent results from Torrentio.
class MediaRanking {
  /// Ranks [results] best-to-worst according to [query].
  static List<TorrentResult> rank(
    List<TorrentResult> results,
    MediaTorrentQuery query,
  ) {
    if (results.isEmpty) return const [];

    final scored = [
      for (final r in results) (result: r, score: _score(r, query)),
    ];

    scored.sort((a, b) {
      if (a.score != b.score) return b.score.compareTo(a.score);
      return b.result.seeders.compareTo(a.result.seeders);
    });

    return scored.map((s) => s.result).toList();
  }

  /// Picks the single best torrent for [query], or null if none.
  static TorrentResult? best(
    List<TorrentResult> results,
    MediaTorrentQuery query,
  ) {
    final ranked = rank(results, query);
    return ranked.isEmpty ? null : ranked.first;
  }

  static double _score(TorrentResult r, MediaTorrentQuery query) {
    double score = 0.0;
    final lowerTitle = r.title.toLowerCase();

    // 1. Heavy penalty for CAM / Telesync / PreDVD (unless user has no other options)
    if (RegExp(r'\b(cam|hdcam|predvd|dvdscr|telesync|ts|tc)\b').hasMatch(lowerTitle)) {
      score -= 500.0;
    }

    // 2. Resolution matching — the user's selected resolution must dominate so
    //    exact matches always surface first, regardless of seeders or format.
    //    Use the same parsed resolution the picker card displays (handles 4K/UHD
    //    via Anitomy) so ranking and the on-screen tag always agree.
    final preferred = query.preferredResolution ?? 1080;
    final itemRes = r.parsed.resolution ?? _extractResolution(lowerTitle);
    if (itemRes != null) {
      if (itemRes == preferred) {
        score += 1000.0; // Exact match with the requested resolution wins outright.
      } else {
        score += _resolutionFallbackScore(itemRes, preferred);
      }
    } else {
      score += 20.0; // Unknown resolution ranks below any known match.
    }

    // 3. High quality release formats
    if (lowerTitle.contains('bluray') || lowerTitle.contains('bdrip') || lowerTitle.contains('remux')) {
      score += 40.0;
    } else if (lowerTitle.contains('web-dl') || lowerTitle.contains('webrip') || lowerTitle.contains('web')) {
      score += 30.0;
    }

    // 4. Premium Audio
    if (lowerTitle.contains('atmos') || lowerTitle.contains('truehd') || lowerTitle.contains('dts')) {
      score += 15.0;
    } else if (lowerTitle.contains('5.1') || lowerTitle.contains('ddp') || lowerTitle.contains('eac3')) {
      score += 10.0;
    }

    // 5. Modern Codecs
    if (lowerTitle.contains('x265') || lowerTitle.contains('hevc') || lowerTitle.contains('10bit') || lowerTitle.contains('av1')) {
      score += 10.0;
    }

    // 6. Seeders (capped contribution)
    if (r.seeders > 0) {
      score += (r.seeders.clamp(0, 100) * 1.5);
    } else {
      score -= 50.0; // Penalize unseeded torrents
    }

    return score;
  }

  /// Scores resolutions that don't exactly match the preferred one, ordered by
  /// closeness. Kept well below the exact-match bonus so matches always lead,
  /// while still allowing seeders/format to order the fallback group sensibly.
  static double _resolutionFallbackScore(int itemRes, int preferred) {
    const tiers = [480, 720, 1080, 2160];
    final itemTier = tiers.indexOf(itemRes);
    final prefTier = tiers.indexOf(preferred);
    if (itemTier == -1 || prefTier == -1) return 30.0;
    final distance = (itemTier - prefTier).abs();
    return (100.0 - distance * 25.0).clamp(0.0, 100.0);
  }

  static int? _extractResolution(String title) {
    final m = RegExp(r'\b(2160|1080|720|480)p?\b').firstMatch(title);
    if (m != null) return int.tryParse(m.group(1)!);
    if (title.contains('4k') || title.contains('uhd')) return 2160;
    return null;
  }
}
