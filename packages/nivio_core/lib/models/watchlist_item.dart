import 'package:hive/hive.dart';

part 'watchlist_item.g.dart';

/// Watch status categories matching streaming and anime tracking platforms.
@HiveType(typeId: 7)
enum WatchStatus {
  @HiveField(0)
  planning('Plan to Watch'),

  @HiveField(1)
  watching('Watching'),

  @HiveField(2)
  completed('Completed'),

  @HiveField(3)
  paused('On Hold'),

  @HiveField(4)
  dropped('Dropped');

  final String label;
  const WatchStatus(this.label);

  static WatchStatus fromString(String? val) {
    if (val == null) return WatchStatus.planning;
    final normalized = val.toLowerCase().trim().replaceAll(' ', '_');
    for (final status in WatchStatus.values) {
      if (status.name.toLowerCase() == normalized ||
          status.label.toLowerCase() == val.toLowerCase()) {
        return status;
      }
    }
    if (normalized == 'current') return WatchStatus.watching;
    if (normalized == 'plan_to_watch' || normalized == 'want_to_watch') {
      return WatchStatus.planning;
    }
    if (normalized == 'on_hold') return WatchStatus.paused;
    return WatchStatus.planning;
  }
}

@HiveType(typeId: 5)
class WatchlistItem extends HiveObject {
  @HiveField(0)
  final int id;

  @HiveField(1)
  final String title;

  @HiveField(2)
  final String? posterPath;

  @HiveField(3)
  final String mediaType; // 'movie', 'tv', or 'anime'

  @HiveField(4)
  final DateTime addedAt;

  @HiveField(5)
  final double? voteAverage;

  @HiveField(6)
  final String? releaseDate;

  @HiveField(7)
  final String? overview;

  @HiveField(8)
  final WatchStatus watchStatus;

  @HiveField(9)
  final int? currentEpisode;

  @HiveField(10)
  final int? totalEpisodes;

  @HiveField(11)
  final int? anilistId;

  @HiveField(12)
  final int? malId;

  @HiveField(13)
  final DateTime? updatedAt;

  WatchlistItem({
    required this.id,
    required this.title,
    this.posterPath,
    required this.mediaType,
    required this.addedAt,
    this.voteAverage,
    this.releaseDate,
    this.overview,
    this.watchStatus = WatchStatus.planning,
    this.currentEpisode,
    this.totalEpisodes,
    this.anilistId,
    this.malId,
    this.updatedAt,
  });

  WatchlistItem copyWith({
    int? id,
    String? title,
    String? posterPath,
    String? mediaType,
    DateTime? addedAt,
    double? voteAverage,
    String? releaseDate,
    String? overview,
    WatchStatus? watchStatus,
    int? currentEpisode,
    int? totalEpisodes,
    int? anilistId,
    int? malId,
    DateTime? updatedAt,
  }) {
    return WatchlistItem(
      id: id ?? this.id,
      title: title ?? this.title,
      posterPath: posterPath ?? this.posterPath,
      mediaType: mediaType ?? this.mediaType,
      addedAt: addedAt ?? this.addedAt,
      voteAverage: voteAverage ?? this.voteAverage,
      releaseDate: releaseDate ?? this.releaseDate,
      overview: overview ?? this.overview,
      watchStatus: watchStatus ?? this.watchStatus,
      currentEpisode: currentEpisode ?? this.currentEpisode,
      totalEpisodes: totalEpisodes ?? this.totalEpisodes,
      anilistId: anilistId ?? this.anilistId,
      malId: malId ?? this.malId,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'posterPath': posterPath,
      'mediaType': mediaType,
      'addedAt': addedAt.toIso8601String(),
      'voteAverage': voteAverage,
      'releaseDate': releaseDate,
      'overview': overview,
      'watchStatus': watchStatus.name,
      'currentEpisode': currentEpisode,
      'totalEpisodes': totalEpisodes,
      'anilistId': anilistId,
      'malId': malId,
      'updatedAt': (updatedAt ?? addedAt).toIso8601String(),
    };
  }

  factory WatchlistItem.fromJson(Map<String, dynamic> json) {
    return WatchlistItem(
      id: json['id'] as int,
      title: json['title'] as String,
      posterPath: json['posterPath'] as String?,
      mediaType: json['mediaType'] as String,
      addedAt: DateTime.tryParse(json['addedAt'] as String? ?? '') ?? DateTime.now(),
      voteAverage: (json['voteAverage'] as num?)?.toDouble(),
      releaseDate: json['releaseDate'] as String?,
      overview: json['overview'] as String?,
      watchStatus: WatchStatus.fromString(json['watchStatus'] as String?),
      currentEpisode: json['currentEpisode'] as int?,
      totalEpisodes: json['totalEpisodes'] as int?,
      anilistId: json['anilistId'] as int?,
      malId: json['malId'] as int?,
      updatedAt: json['updatedAt'] != null
          ? DateTime.tryParse(json['updatedAt'] as String)
          : null,
    );
  }
}
