import 'package:hive/hive.dart';

part 'new_episode.g.dart';

/// Model for tracking new episode notifications
@HiveType(typeId: 3)
class NewEpisode extends HiveObject {
  @HiveField(0)
  final int showId;

  @HiveField(1)
  final String showName;

  @HiveField(2)
  final int seasonNumber;

  @HiveField(3)
  final int episodeNumber;

  @HiveField(4)
  final String episodeName;

  @HiveField(5)
  final String? posterPath;

  @HiveField(6)
  final DateTime airDate;

  @HiveField(7)
  final DateTime detectedAt;

  @HiveField(8)
  bool isRead;

  NewEpisode({
    required this.showId,
    required this.showName,
    required this.seasonNumber,
    required this.episodeNumber,
    required this.episodeName,
    this.posterPath,
    required this.airDate,
    required this.detectedAt,
    this.isRead = false,
  });

  /// Unique key for this episode
  String get key => '${showId}_${seasonNumber}_$episodeNumber';

  /// Copy with modifications
  NewEpisode copyWith({
    int? showId,
    String? showName,
    int? seasonNumber,
    int? episodeNumber,
    String? episodeName,
    String? posterPath,
    DateTime? airDate,
    DateTime? detectedAt,
    bool? isRead,
  }) {
    return NewEpisode(
      showId: showId ?? this.showId,
      showName: showName ?? this.showName,
      seasonNumber: seasonNumber ?? this.seasonNumber,
      episodeNumber: episodeNumber ?? this.episodeNumber,
      episodeName: episodeName ?? this.episodeName,
      posterPath: posterPath ?? this.posterPath,
      airDate: airDate ?? this.airDate,
      detectedAt: detectedAt ?? this.detectedAt,
      isRead: isRead ?? this.isRead,
    );
  }

  Map<String, dynamic> toJson() => {
    'showId': showId,
    'showName': showName,
    'seasonNumber': seasonNumber,
    'episodeNumber': episodeNumber,
    'episodeName': episodeName,
    'posterPath': posterPath,
    'airDate': airDate.toIso8601String(),
    'detectedAt': detectedAt.toIso8601String(),
    'isRead': isRead,
  };

  factory NewEpisode.fromJson(Map<String, dynamic> json) => NewEpisode(
    showId: json['showId'] as int,
    showName: json['showName'] as String,
    seasonNumber: json['seasonNumber'] as int,
    episodeNumber: json['episodeNumber'] as int,
    episodeName: json['episodeName'] as String,
    posterPath: json['posterPath'] as String?,
    airDate: DateTime.parse(json['airDate'] as String),
    detectedAt: DateTime.parse(json['detectedAt'] as String),
    isRead: json['isRead'] as bool? ?? false,
  );
}
