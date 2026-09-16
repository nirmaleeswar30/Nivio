import 'dart:convert';

import 'package:http/http.dart' as http;

import '../torrent_models.dart';
import 'torrent_source.dart';

/// SeaDex (releases.moe) source — a curated database of the *best* anime
/// releases, keyed by AniList id. Results are marked high-accuracy and, when
/// flagged, `type: 'best'`, so ranking prefers them strongly. Requires
/// [AnimeQuery.anilistId]; returns empty without it.
class SeaDexSource implements TorrentSource {
  SeaDexSource({http.Client? client}) : _http = client ?? http.Client();

  final http.Client _http;

  @override
  String get name => 'seadex';

  @override
  Future<List<TorrentResult>> search(AnimeQuery query) async {
    final alId = query.anilistId;
    if (alId == null) return const [];

    final uri = Uri.https('releases.moe', '/api/collections/entries/records', {
      'filter': 'alID=$alId',
      'expand': 'trs',
      'perPage': '50',
    });
    try {
      final resp = await _http.get(uri, headers: {
        'User-Agent': 'Nivio/1.0 (+torrent-source)',
        'Accept': 'application/json',
      }).timeout(const Duration(seconds: 4));
      if (resp.statusCode != 200) return const [];
      final data = jsonDecode(resp.body);
      final items = (data is Map ? data['items'] : null);
      if (items is! List) return const [];

      final out = <TorrentResult>[];
      for (final entry in items) {
        final trs = (entry is Map ? entry['expand'] : null);
        final list = (trs is Map ? trs['trs'] : null);
        if (list is! List) continue;
        for (final tr in list) {
          if (tr is! Map) continue;
          final infoHash = tr['infoHash']?.toString();
          if (infoHash == null || infoHash.isEmpty || infoHash == '<redacted>') {
            continue; // non-torrent tracker entries have no usable hash
          }
          final files = (tr['files'] as List?) ?? const [];
          final repName = _representativeName(files, tr['releaseGroup'], query);
          final isBest = tr['isBest'] == true;
          out.add(TorrentResult(
            title: repName,
            link: buildMagnet(infoHash, displayName: repName),
            infoHash: infoHash,
            seeders: 0, // SeaDex doesn't report seeders; Nyaa fills that in
            leechers: 0,
            sizeBytes: _totalSize(files),
            source: name,
            accuracy: 'high',
            type: isBest ? 'best' : 'alt',
          ));
        }
      }
      return out;
    } catch (_) {
      return const [];
    }
  }

  /// A name that anitomy can parse for resolution/group. SeaDex provides full
  /// series batches, so using the largest file's name (e.g. "Episode 09.mkv")
  /// is highly misleading in the UI when the user requested Episode 05.
  static String _representativeName(
      List files, dynamic releaseGroup, AnimeQuery query) {
    final grp = releaseGroup?.toString() ?? '';
    final title = query.primaryTitle;
    
    // We append the resolution of the largest file if possible, so the UI shows it.
    String res = '';
    int bestLen = -1;
    for (final f in files) {
      if (f is Map) {
        final len = (f['length'] as num?)?.toInt() ?? 0;
        final nm = f['name']?.toString() ?? '';
        if (len > bestLen) {
          bestLen = len;
          if (nm.contains('1080p')) res = '1080p';
          else if (nm.contains('720p')) res = '720p';
          else if (nm.contains('2160p')) res = '2160p';
          else if (nm.contains('480p')) res = '480p';
        }
      }
    }
    
    final resStr = res.isNotEmpty ? ' [$res]' : '';
    return '[$grp] $title (SeaDex Batch)$resStr'.trim();
  }

  static int _totalSize(List files) {
    var total = 0;
    for (final f in files) {
      if (f is Map) total += (f['length'] as num?)?.toInt() ?? 0;
    }
    return total;
  }
}
