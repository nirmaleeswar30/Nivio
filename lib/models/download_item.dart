import 'package:hive/hive.dart';

part 'download_item.g.dart';

@HiveType(typeId: 4)
enum DownloadStatus {
  @HiveField(0)
  pending,
  @HiveField(1)
  downloading,
  @HiveField(2)
  completed,
  @HiveField(3)
  failed,
  @HiveField(4)
  paused,
  @HiveField(5)
  extracting,
}

@HiveType(typeId: 6)
class DownloadItem extends HiveObject {
  @HiveField(0)
  String id;

  @HiveField(1)
  int mediaId;

  @HiveField(2)
  String title;

  @HiveField(3)
  String? posterPath;

  @HiveField(4)
  String mediaType;

  @HiveField(5)
  int? season;

  @HiveField(6)
  int? episode;

  @HiveField(7)
  String savePath;

  @HiveField(8)
  DownloadStatus status;

  @HiveField(9)
  double progress;

  @HiveField(10)
  int totalBytes;

  @HiveField(11)
  int downloadedBytes;

  @HiveField(12)
  DateTime createdAt;

  @HiveField(13)
  String? streamUrl;
  
  @HiveField(14)
  Map<String, String>? headers;

  @HiveField(15)
  String? selectedAudioLanguage;

  @HiveField(16)
  String? selectedSubtitleLanguage;

  @HiveField(17)
  String? subtitleUrl;

  DownloadItem({
    required this.id,
    required this.mediaId,
    required this.title,
    this.posterPath,
    required this.mediaType,
    this.season,
    this.episode,
    required this.savePath,
    this.status = DownloadStatus.pending,
    this.progress = 0.0,
    this.totalBytes = 0,
    this.downloadedBytes = 0,
    required this.createdAt,
    this.streamUrl,
    this.headers,
    this.selectedAudioLanguage,
    this.selectedSubtitleLanguage,
    this.subtitleUrl,
  });
}
