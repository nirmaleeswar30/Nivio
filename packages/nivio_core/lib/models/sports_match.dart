/// A live/upcoming sports event surfaced in the TV/Sports tab.
class SportsMatch {
  final String id;
  final String title;
  final String category;
  final int dateMs;
  final String poster;
  final bool popular;
  final String homeTeam;
  final String homeBadge;
  final String awayTeam;
  final String awayBadge;

  /// Backend source descriptors to resolve the stream: [{source, id}].
  final List<SportsSourceRef> sources;

  SportsMatch({
    required this.id,
    required this.title,
    this.category = '',
    this.dateMs = 0,
    this.poster = '',
    this.popular = false,
    this.homeTeam = '',
    this.homeBadge = '',
    this.awayTeam = '',
    this.awayBadge = '',
    this.sources = const [],
  });

  DateTime? get startTime =>
      dateMs > 0 ? DateTime.fromMillisecondsSinceEpoch(dateMs) : null;

  /// Roughly "live" if it started within the last 4 hours.
  bool get isLikelyLive {
    final start = startTime;
    if (start == null) return false;
    final now = DateTime.now();
    return now.isAfter(start) &&
        now.difference(start) < const Duration(hours: 4);
  }

  bool get hasTeams => homeTeam.isNotEmpty && awayTeam.isNotEmpty;

  factory SportsMatch.fromJson(Map<String, dynamic> json) {
    final teams = json['teams'];
    Map<String, dynamic> home = {};
    Map<String, dynamic> away = {};
    if (teams is Map) {
      if (teams['home'] is Map) home = Map<String, dynamic>.from(teams['home']);
      if (teams['away'] is Map) away = Map<String, dynamic>.from(teams['away']);
    }
    final rawSources = json['sources'];
    final sources = <SportsSourceRef>[];
    if (rawSources is List) {
      for (final s in rawSources) {
        if (s is Map) {
          final ref = SportsSourceRef.fromJson(Map<String, dynamic>.from(s));
          if (ref != null) sources.add(ref);
        }
      }
    }
    return SportsMatch(
      id: json['id']?.toString() ?? '',
      title: json['title']?.toString() ?? '',
      category: json['category']?.toString() ?? '',
      dateMs: int.tryParse(json['date']?.toString() ?? '') ?? 0,
      poster: json['poster']?.toString() ?? '',
      popular: json['popular'] == true,
      homeTeam: home['name']?.toString() ?? '',
      homeBadge: home['badge']?.toString() ?? '',
      awayTeam: away['name']?.toString() ?? '',
      awayBadge: away['badge']?.toString() ?? '',
      sources: sources,
    );
  }
}

class SportsSourceRef {
  final String source;
  final String id;

  SportsSourceRef({required this.source, required this.id});

  static SportsSourceRef? fromJson(Map<String, dynamic> json) {
    final source = json['source']?.toString();
    final id = json['id']?.toString();
    if (source == null || source.isEmpty || id == null || id.isEmpty) {
      return null;
    }
    return SportsSourceRef(source: source, id: id);
  }
}

/// A resolved, playable stream option for a match.
class SportsStream {
  final String id;
  final int streamNo;
  final String language;
  final bool hd;
  final String url; // direct HLS (.m3u8)
  final String label;

  SportsStream({
    required this.id,
    required this.url,
    this.streamNo = 1,
    this.language = '',
    this.hd = false,
    this.label = '',
  });

  bool get isDirectHls =>
      url.contains('.m3u8') || url.contains('/proxy/m3u8');
}
