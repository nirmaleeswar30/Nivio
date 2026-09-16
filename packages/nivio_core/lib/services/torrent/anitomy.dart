/// A focused, pure-Dart anime release-name parser (a pragmatic subset of
/// anitomy / anitomyscript). Extracts the fields Nivio needs to rank torrents
/// and resolve the right episode file: release group, resolution, episode
/// number(s), season, batch-ness, and special-type (OP/ED/PV) detection.
///
/// It is deliberately regex-based and tolerant — it does not aim for full
/// anitomy parity, only the fields that drive ranking and file selection.
library;

/// Non-episode special types that should be excluded when resolving the
/// episode to play (mirrors Hayase's TYPE_EXCLUSIONS).
const Set<String> kSpecialTypes = {
  'ED', 'ENDING', 'NCED', 'NCOP', 'OP', 'OPENING', 'PREVIEW', 'PV', 'NCE',
};

final RegExp kVideoExtRx =
    RegExp(r'\.(mkv|mp4|avi|webm|mov|flv|ogv|wmv|m4v|ts|m2ts)$', caseSensitive: false);

class AnitomyResult {
  AnitomyResult({
    required this.filename,
    this.title,
    this.releaseGroup,
    this.resolution,
    this.episodeStart,
    this.episodeEnd,
    this.season,
    this.isBatch = false,
    this.specialType,
    this.videoCodec,
    this.source,
  });

  final String filename;
  final String? title;
  final String? releaseGroup;

  /// Vertical resolution in pixels: 480, 540, 720, 1080, 1440, 2160.
  final int? resolution;

  /// Parsed episode number (or first of a range).
  final int? episodeStart;

  /// Last episode of a range (for batches like `01-12`), else null.
  final int? episodeEnd;

  final int? season;

  /// True when the release covers multiple episodes / a whole season.
  final bool isBatch;

  /// OP/ED/PV/... when this is a special, else null.
  final String? specialType;

  final String? videoCodec; // x264/x265/HEVC/AV1
  final String? source; // BD/BluRay/WEB-DL/WEBRip/TV

  bool get isSpecial => specialType != null;

  /// True when [episode] falls within this result's episode coverage.
  bool coversEpisode(int episode) {
    if (episodeStart == null) return false;
    final end = episodeEnd ?? episodeStart!;
    return episode >= episodeStart! && episode <= end;
  }
}

class Anitomy {
  static final _groupBracketRx = RegExp(r'^\s*[\[(]([^\])]+)[\])]');
  static final _groupTrailingRx = RegExp(r'-\s*([A-Za-z0-9]+)\s*$');
  static final _resolutionRx =
      RegExp(r'(?:(\d{3,4})\s*[pP])|(?:\b(?:4k|4K|2160|1440|1080|720|540|480)\b)');
  static final _seasonRx = RegExp(
      r'(?:\bS(?:eason)?\s*0*(\d{1,2})\b)|(?:\b0*(\d{1,2})(?:st|nd|rd|th)\s+Season\b)',
      caseSensitive: false);
  static final _sxxexxRx = RegExp(r'\bS0*(\d{1,2})[\s._-]*E0*(\d{1,3})\b', caseSensitive: false);
  static final _rangeRx = RegExp(r'\b0*(\d{1,3})\s*[-~]\s*0*(\d{1,3})\b');
  static final _dashEpisodeRx = RegExp(r'(?:^|[\s_])-\s*0*(\d{1,4})(?:v\d)?(?=[\s_.\[(]|$)');
  static final _epKeywordRx =
      RegExp(r'\b(?:E|EP|Episode)\s*0*(\d{1,4})\b', caseSensitive: false);
  static final _batchKeywordRx = RegExp(
      r'\b(?:batch|complete|season|seasons|vol\.?|volume|collection|bd[- ]?box|\d+\s*~\s*\d+)\b',
      caseSensitive: false);
  static final _codecRx = RegExp(r'\b(x265|h\.?265|hevc|x264|h\.?264|av1)\b', caseSensitive: false);
  static final _sourceRx =
      RegExp(r'\b(bluray|blu-ray|bdrip|bd|web-?dl|web-?rip|webrip|hdtv|dvd)\b', caseSensitive: false);
  // Allow a trailing number (OP1, ED2, NCOP3) — the base token is captured.
  static final _specialRx = RegExp(
      r'\b(NCED|NCOP|OPENING|ENDING|PREVIEW|PV|OP|ED)\d*\b',
      caseSensitive: false);

  /// Parse a single release name / filename.
  static AnitomyResult parse(String name) {
    // Strip the extension for parsing; keep original for the result.
    final base = name.replaceAll(kVideoExtRx, '');

    String? group;
    final gb = _groupBracketRx.firstMatch(base);
    if (gb != null) {
      group = gb.group(1)?.trim();
    } else {
      final gt = _groupTrailingRx.firstMatch(base);
      // Only treat trailing -TOKEN as a group when it looks like a scene group
      // (letters present), to avoid catching episode numbers.
      final t = gt?.group(1);
      if (t != null && RegExp(r'[A-Za-z]').hasMatch(t)) group = t;
    }

    final resolution = _parseResolution(base);
    final season = _parseSeason(base);

    int? epStart, epEnd;
    bool batch = false;

    final sxe = _sxxexxRx.firstMatch(base);
    final range = _rangeRx.firstMatch(base);
    if (sxe != null) {
      epStart = int.tryParse(sxe.group(2)!);
    } else if (range != null) {
      epStart = int.tryParse(range.group(1)!);
      epEnd = int.tryParse(range.group(2)!);
      if (epStart != null && epEnd != null && epEnd > epStart) batch = true;
    } else {
      final dash = _dashEpisodeRx.firstMatch(base);
      final kw = _epKeywordRx.firstMatch(base);
      final n = dash?.group(1) ?? kw?.group(1);
      if (n != null) epStart = int.tryParse(n);
    }

    if (!batch && _batchKeywordRx.hasMatch(base)) batch = true;

    String? special;
    final sp = _specialRx.firstMatch(base);
    if (sp != null) {
      final tok = sp.group(1)!.toUpperCase();
      // "OP"/"ED" only count as specials when standalone tokens, not part of a
      // word; the \b boundaries above already enforce that.
      if (kSpecialTypes.contains(tok)) special = tok;
    }

    return AnitomyResult(
      filename: name,
      title: _parseTitle(base, group),
      releaseGroup: group,
      resolution: resolution,
      episodeStart: epStart,
      episodeEnd: epEnd,
      season: season,
      isBatch: batch,
      specialType: special,
      videoCodec: _codecRx.firstMatch(base)?.group(1),
      source: _sourceRx.firstMatch(base)?.group(1),
    );
  }

  static int? _parseResolution(String s) {
    final m = _resolutionRx.firstMatch(s);
    if (m == null) return null;
    final matched = m.group(0)!.toLowerCase();
    if (matched.contains('4k')) return 2160;
    final digits = RegExp(r'\d{3,4}').firstMatch(matched)?.group(0);
    return digits == null ? null : int.tryParse(digits);
  }

  static int? _parseSeason(String s) {
    final sxe = _sxxexxRx.firstMatch(s);
    if (sxe != null) return int.tryParse(sxe.group(1)!);
    final m = _seasonRx.firstMatch(s);
    if (m == null) return null;
    return int.tryParse(m.group(1) ?? m.group(2) ?? '');
  }

  /// Best-effort title: the text before the episode/quality markers, minus the
  /// leading group bracket.
  static String? _parseTitle(String base, String? group) {
    var s = base;
    if (group != null) {
      s = s.replaceFirst(RegExp(r'^\s*[\[(][^\])]+[\])]\s*'), '');
    }
    // Cut at the first strong marker (episode dash, SxxExx, bracketed tag).
    final cut = RegExp(r'(\s-\s*\d)|(\bS\d{1,2}E\d)|(\[)|(\()', caseSensitive: false)
        .firstMatch(s);
    if (cut != null) s = s.substring(0, cut.start);
    s = s.replaceAll(RegExp(r'[._]+'), ' ').trim();
    return s.isEmpty ? null : s;
  }
}
