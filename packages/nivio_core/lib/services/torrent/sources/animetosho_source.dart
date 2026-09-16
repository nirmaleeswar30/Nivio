import 'dart:convert';

import 'package:http/http.dart' as http;

import '../torrent_models.dart';
import 'torrent_source.dart';

/// AnimeTosho source via its JSON feed. Aggregates Nyaa/AniDB and always
/// provides a magnet URI + info-hash. Seeder counts are often absent (Tosho
/// doesn't track them live), so ranking leans on Nyaa for seeders and uses
/// Tosho mainly for coverage and reliable magnets.
class AnimeToshoSource implements TorrentSource {
  AnimeToshoSource({http.Client? client}) : _http = client ?? http.Client();

  final http.Client _http;

  @override
  String get name => 'animetosho';

  @override
  Future<List<TorrentResult>> search(AnimeQuery query) async {
    for (final title in query.titles.take(4)) {
      final results = await _searchOnce(title);
      if (results.isNotEmpty) return results;
    }
    return const [];
  }

  Future<List<TorrentResult>> _searchOnce(String title) async {
    final uri = Uri.https('feed.animetosho.org', '/json', {
      'q': title,
      'only_tor': '1',
    });
    try {
      final resp = await _http.get(uri, headers: {
        'User-Agent': 'Nivio/1.0 (+torrent-source)',
        'Accept': 'application/json',
      }).timeout(const Duration(seconds: 12));
      if (resp.statusCode != 200) return const [];
      final data = jsonDecode(resp.body);
      if (data is! List) return const [];
      final out = <TorrentResult>[];
      for (final e in data) {
        if (e is! Map) continue;
        final title = (e['title'] ?? e['torrent_name'])?.toString();
        if (title == null) continue;
        final infoHash = e['info_hash']?.toString();
        final magnet = e['magnet_uri']?.toString() ??
            (infoHash != null ? buildMagnet(infoHash, displayName: title) : null);
        if (magnet == null) continue;
        out.add(TorrentResult(
          title: title,
          link: magnet,
          infoHash: infoHash,
          seeders: _int(e['seeders']),
          leechers: _int(e['leechers']),
          downloads: _int(e['torrent_downloaded_count']),
          sizeBytes: _int(e['total_size']),
          source: name,
          accuracy: 'medium',
          date: _dateFromTimestamp(e['timestamp']),
        ));
      }
      return out;
    } catch (_) {
      return const [];
    }
  }

  static int _int(dynamic v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v) ?? 0;
    return 0;
  }

  static DateTime? _dateFromTimestamp(dynamic ts) {
    final seconds = _int(ts);
    if (seconds <= 0) return null;
    return DateTime.fromMillisecondsSinceEpoch(seconds * 1000, isUtc: true);
  }
}
