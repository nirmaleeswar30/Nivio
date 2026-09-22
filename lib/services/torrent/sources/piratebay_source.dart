import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart' as http_io;

import '../media_torrent_models.dart';
import '../torrent_models.dart';
import 'torrent_source.dart';

/// The Pirate Bay text-search source (via the public apibay JSON API).
///
/// Unlike Torrentio (which resolves by IMDb id + season/episode), this is a
/// free-text search: it sends exactly what the user typed. That makes it the
/// source that powers manual searches, and it also complements Torrentio on
/// normal loads by finding season packs / alternate releases.
class PirateBaySource implements MediaTorrentSource {
  PirateBaySource({http.Client? client, String? baseUrl})
      : _http = client ?? _createInsecureClient(),
        _baseUrl = baseUrl ?? 'https://apibay.org';

  final http.Client _http;
  final String _baseUrl;

  static http.Client _createInsecureClient() {
    final ioClient = HttpClient()
      ..badCertificateCallback = (cert, host, port) => true;
    return http_io.IOClient(ioClient);
  }

  @override
  String get name => 'piratebay';

  @override
  String get displayName => 'PirateBay';

  @override
  Future<List<TorrentResult>> searchMedia(MediaTorrentQuery query) async {
    final q = _buildQuery(query);
    if (q.trim().isEmpty) return const [];

    final url = Uri.parse(
      '$_baseUrl/q.php?q=${Uri.encodeQueryComponent(q)}&cat=',
    );

    try {
      final resp = await _http.get(url, headers: {
        'User-Agent': 'Nivio/1.0',
        'Accept': 'application/json',
      }).timeout(const Duration(seconds: 12));

      if (resp.statusCode != 200) return const [];

      final decoded = jsonDecode(resp.body);
      if (decoded is! List) return const [];

      final results = <TorrentResult>[];
      for (final e in decoded) {
        if (e is! Map) continue;
        final map = Map<String, dynamic>.from(e);

        final infoHash = (map['info_hash'] ?? '').toString().trim();
        final title = (map['name'] ?? '').toString().trim();
        // apibay returns a single sentinel row when there are no matches.
        if (infoHash.isEmpty ||
            infoHash.replaceAll('0', '').isEmpty ||
            title.isEmpty ||
            title.toLowerCase() == 'no results returned') {
          continue;
        }

        // On automatic (non-manual) loads, drop obviously-unrelated hits so a
        // text search doesn't pollute the ranked results with wrong titles.
        if (!query.isManual && !_looksRelevant(title, query.title)) continue;

        results.add(
          TorrentResult(
            title: title,
            link: buildMagnet(infoHash, displayName: title),
            infoHash: infoHash,
            seeders: int.tryParse('${map['seeders']}') ?? 0,
            leechers: int.tryParse('${map['leechers']}') ?? 0,
            sizeBytes: int.tryParse('${map['size']}') ?? 0,
            source: name,
            accuracy: query.isManual ? 'high' : 'medium',
          ),
        );
      }
      return results;
    } catch (_) {
      return const [];
    }
  }

  /// Builds the text query. A manual search is sent verbatim; an automatic load
  /// uses the title (plus SxxExx for a specific episode) — never resolution.
  String _buildQuery(MediaTorrentQuery query) {
    final raw = query.rawQuery?.trim();
    if (raw != null && raw.isNotEmpty) return raw;

    final title = query.title.trim();
    if (title.isEmpty) return '';
    if (query.isMovie) {
      return query.year != null ? '$title ${query.year}' : title;
    }
    if (query.season != null && query.episode != null) {
      final s = query.season!.toString().padLeft(2, '0');
      final ep = query.episode!.toString().padLeft(2, '0');
      return '$title S${s}E$ep';
    }
    return title;
  }

  /// Loose relevance check: every significant word of the title should appear
  /// somewhere in the result name.
  bool _looksRelevant(String resultName, String title) {
    final name = resultName.toLowerCase();
    final words = title
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9\s]'), ' ')
        .split(RegExp(r'\s+'))
        .where((w) => w.length > 2)
        .toList();
    if (words.isEmpty) return true;
    return words.every((w) => name.contains(w));
  }
}
