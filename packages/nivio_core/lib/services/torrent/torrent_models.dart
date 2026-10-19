import 'anitomy.dart';

/// A torrent candidate returned by a source (Nyaa / AnimeTosho / SeaDex),
/// containing the parsed release info.
class TorrentResult {
  TorrentResult({
    required this.title,
    required this.link,
    required this.seeders,
    required this.leechers,
    required this.sizeBytes,
    required this.source,
    this.infoHash,
    this.downloads = 0,
    this.date,
    this.accuracy = 'medium',
    this.type,
    this.fileIndex,
  }) : parsed = Anitomy.parse(title);

  /// Release title (what gets parsed for resolution/group/episode).
  final String title;

  /// Magnet link, `.torrent` URL, or bare info-hash — passed straight to rqbit.
  final String link;

  final String? infoHash;
  final int seeders;
  final int leechers;
  final int downloads;
  final int sizeBytes;
  final DateTime? date;

  /// Optional specific file index inside the torrent (e.g. from Stremio fileIdx).
  final int? fileIndex;

  /// 'high' | 'medium' | 'low' — how confidently this matches the query.
  final String accuracy;

  /// 'batch' | 'best' | 'alt' | null.
  final String? type;

  /// Which source produced this ('nyaa', 'animetosho', 'seadex', 'torrentio').
  final String source;

  final AnitomyResult parsed;

  bool get isBest => type == 'best';
  bool get isBatch => type == 'batch' || parsed.isBatch;
}

/// The search context built from a Nivio media selection.
class AnimeQuery {
  AnimeQuery({
    required this.titles,
    required this.episode,
    required this.season,
    this.anilistId,
    this.episodeCount,
    this.absoluteEpisode,
    this.resolution = '1080',
    this.exclusions = const [],
    this.isManual = false,
  });

  /// Candidate titles (romaji / english / native / synonyms), most-preferred
  /// first — used to build source search queries.
  final List<String> titles;

  final int episode;
  final int season;
  final int? anilistId;
  final int? episodeCount;

  /// Absolute episode number across seasons (for absolute-numbered releases).
  final int? absoluteEpisode;

  /// Preferred vertical resolution as a string: '2160' | '1080' | '720' | ...
  final String resolution;

  /// Keywords to strictly reject (e.g., 'dub' if sub is strongly preferred).
  final List<String> exclusions;

  /// True if this query was manually entered by the user.
  final bool isManual;

  int? get preferredResolution => int.tryParse(resolution);
  String get primaryTitle => titles.isEmpty ? '' : titles.first;
}
