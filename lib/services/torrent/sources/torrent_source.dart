import '../torrent_models.dart';

/// Common interface for anime torrent sources (Nyaa / AnimeTosho / SeaDex).
abstract class TorrentSource {
  /// Short id, e.g. 'nyaa', 'animetosho', 'seadex'.
  String get name;

  /// Returns candidate torrents for [query]. Implementations should be
  /// defensive: network errors return an empty list, never throw.
  Future<List<TorrentResult>> search(AnimeQuery query);
}

/// Well-seeded public trackers appended to constructed magnets so rqbit can
/// find peers via trackers in addition to DHT (Nyaa's own tracker first).
const List<String> kDefaultTrackers = [
  'http://nyaa.tracker.wf:7777/announce',
  'udp://tracker.opentrackr.org:1337/announce',
  'udp://open.demonii.com:1337/announce',
  'udp://tracker.torrent.eu.org:451/announce',
  'udp://exodus.desync.com:6969/announce',
  'udp://open.stealth.si:80/announce',
  'udp://tracker.openbittorrent.com:6969/announce',
];

/// Builds a magnet URI from an info-hash (+ optional display name), embedding
/// the default tracker list. rqbit also accepts a bare info-hash, but including
/// trackers improves peer discovery.
String buildMagnet(String infoHash, {String? displayName}) {
  final buf = StringBuffer('magnet:?xt=urn:btih:$infoHash');
  if (displayName != null && displayName.isNotEmpty) {
    buf.write('&dn=${Uri.encodeQueryComponent(displayName)}');
  }
  for (final tr in kDefaultTrackers) {
    buf.write('&tr=${Uri.encodeQueryComponent(tr)}');
  }
  return buf.toString();
}

/// Parses human-readable sizes like "1.3 GiB", "700 MB", "512 KiB" into bytes.
int parseSizeToBytes(String? size) {
  if (size == null) return 0;
  final m = RegExp(r'([\d.]+)\s*([KMGT]i?B)', caseSensitive: false)
      .firstMatch(size.trim());
  if (m == null) return 0;
  final value = double.tryParse(m.group(1)!) ?? 0;
  final unit = m.group(2)!.toUpperCase();
  const factors = {
    'KB': 1000, 'KIB': 1024,
    'MB': 1000000, 'MIB': 1048576,
    'GB': 1000000000, 'GIB': 1073741824,
    'TB': 1000000000000, 'TIB': 1099511627776,
  };
  final f = factors[unit] ?? 1;
  return (value * f).round();
}
