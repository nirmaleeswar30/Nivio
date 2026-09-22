import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart' as http_io;

import '../media_torrent_models.dart';
import '../torrent_models.dart';
import 'torrent_source.dart';

/// Base class for Stremio Stream Protocol addons (Torrentio).
abstract class StremioBaseSource implements MediaTorrentSource {
  StremioBaseSource({http.Client? client})
      : _http = client ?? _createInsecureClient();

  final http.Client _http;

  static http.Client _createInsecureClient() {
    final ioClient = HttpClient()
      ..badCertificateCallback = (cert, host, port) => true;
    return http_io.IOClient(ioClient);
  }

  /// Base URL of the addon instance.
  String get baseUrl;

  @override
  Future<List<TorrentResult>> searchMedia(MediaTorrentQuery query) async {
    final pathSegment = query.stremioPathSegment;
    if (pathSegment == null) return const [];

    final cleanBase = baseUrl.endsWith('/') ? baseUrl.substring(0, baseUrl.length - 1) : baseUrl;
    final url = Uri.parse('$cleanBase/stream/$pathSegment');

    try {
      final resp = await _http.get(url, headers: {
        'User-Agent': 'Nivio/1.0 (+stremio-source)',
        'Accept': 'application/json',
      }).timeout(const Duration(seconds: 12));

      if (resp.statusCode != 200) return const [];

      final data = jsonDecode(utf8.decode(resp.bodyBytes)) as Map<String, dynamic>;
      final streams = data['streams'] as List?;
      if (streams == null || streams.isEmpty) return const [];

      final results = <TorrentResult>[];
      for (final s in streams) {
        if (s is! Map) continue;
        final map = Map<String, dynamic>.from(s);

        final infoHash = map['infoHash'] as String?;
        if (infoHash == null || infoHash.trim().isEmpty) continue;

        final rawTitle = map['title'] as String? ?? map['name'] as String? ?? 'Untitled';
        final behaviorHints = map['behaviorHints'] as Map<String, dynamic>?;
        final filename = behaviorHints?['filename'] as String?;
        final fileIdx = map['fileIdx'] as int?;

        // Extract seeders: "👤 101" or "S: 101"
        final seederMatch = RegExp(r'[👤S:]\s*(\d+)').firstMatch(rawTitle);
        final seeders = seederMatch != null ? int.tryParse(seederMatch.group(1)!) ?? 0 : 0;

        // Extract size: "💾 2.1 GB"
        final sizeMatch = RegExp(r'💾\s*([\d.]+\s*[KMGT]i?B)', caseSensitive: false).firstMatch(rawTitle);
        final sizeBytes = parseSizeToBytes(sizeMatch?.group(1));

        final displayName = filename ?? rawTitle.split('\n').first.trim();
        final magnet = buildMagnet(infoHash.trim(), displayName: displayName);

        results.add(TorrentResult(
          title: displayName,
          link: magnet,
          infoHash: infoHash.trim(),
          seeders: seeders,
          leechers: 0,
          sizeBytes: sizeBytes,
          source: name,
          fileIndex: fileIdx,
          accuracy: 'high',
        ));
      }
      return results;
    } catch (_) {
      return const [];
    }
  }
}
