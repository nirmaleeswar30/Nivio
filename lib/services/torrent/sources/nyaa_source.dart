import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart' as http_io;

import '../torrent_models.dart';
import 'torrent_source.dart';

/// Nyaa.si RSS source. Provides live seeder/leecher counts (important for
/// ranking) via the site's RSS feed. Category 1_2 = Anime (English-translated).
class NyaaSource implements TorrentSource {
  NyaaSource({http.Client? client, this.category = '1_2'})
      : _http = client ?? _createInsecureClient();

  final http.Client _http;

  static http.Client _createInsecureClient() {
    final ioClient = HttpClient()..badCertificateCallback = (cert, host, port) => true;
    return http_io.IOClient(ioClient);
  }

  /// Nyaa category: '1_2' Eng-subbed, '1_3' non-Eng, '1_4' raw, '1_0' all anime.
  final String category;

  @override
  String get name => 'nyaa';

  @override
  Future<List<TorrentResult>> search(AnimeQuery query) async {
    final futures = query.titles.map((title) => _searchOnce(title));
    final lists = await Future.wait(futures);
    return lists.expand((l) => l).toList();
  }

  Future<List<TorrentResult>> _searchOnce(String title) async {
    final uri = Uri.https('nyaa.si', '/', {
      'page': 'rss',
      'c': category,
      'f': '0',
      'q': title,
    });
    try {
      final resp = await _http.get(uri, headers: {
        'User-Agent': 'Nivio/1.0 (+torrent-source)',
        'Accept': 'application/rss+xml, application/xml, text/xml',
      }).timeout(const Duration(seconds: 12));
      if (resp.statusCode != 200) return const [];
      return _parseRss(resp.body);
    } catch (_) {
      return const [];
    }
  }

  List<TorrentResult> _parseRss(String xml) {
    final items = RegExp(r'<item>(.*?)</item>', dotAll: true).allMatches(xml);
    final out = <TorrentResult>[];
    for (final item in items) {
      final block = item.group(1)!;
      final title = _tag(block, 'title');
      final infoHash = _tag(block, 'nyaa:infoHash');
      final link = _tag(block, 'link');
      if (title == null) continue;
      final seeders = int.tryParse(_tag(block, 'nyaa:seeders') ?? '') ?? 0;
      final leechers = int.tryParse(_tag(block, 'nyaa:leechers') ?? '') ?? 0;
      final downloads = int.tryParse(_tag(block, 'nyaa:downloads') ?? '') ?? 0;
      final sizeBytes = parseSizeToBytes(_tag(block, 'nyaa:size'));
      final pubDate = _tag(block, 'pubDate');

      // Prefer a magnet built from the info-hash (DHT + trackers); fall back to
      // the .torrent link if the hash is missing.
      final magnet = (infoHash != null && infoHash.isNotEmpty)
          ? buildMagnet(infoHash, displayName: title)
          : link;
      if (magnet == null) continue;

      out.add(TorrentResult(
        title: _unescape(title),
        link: magnet,
        infoHash: infoHash,
        seeders: seeders,
        leechers: leechers,
        downloads: downloads,
        sizeBytes: sizeBytes,
        source: name,
        accuracy: 'medium',
        date: _parseDate(pubDate),
      ));
    }
    return out;
  }

  static String? _tag(String block, String tag) {
    final m = RegExp('<$tag>(?:<!\\[CDATA\\[)?(.*?)(?:\\]\\]>)?</$tag>', dotAll: true)
        .firstMatch(block);
    return m?.group(1)?.trim();
  }

  static String _unescape(String s) => s
      .replaceAll('&amp;', '&')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&#39;', "'");

  static DateTime? _parseDate(String? s) {
    if (s == null) return null;
    try {
      return DateTime.parse(s);
    } catch (_) {
      return null;
    }
  }
}
