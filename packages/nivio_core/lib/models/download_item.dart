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

  /// rqbit torrent id for an in-progress torrent download (session-scoped).
  /// Used to stream the file while it downloads. Null for direct downloads.
  @HiveField(18)
  int? torrentId;

  /// Index of the target file inside the torrent (for streaming while downloading).
  @HiveField(19)
  int? fileIndex;

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
    this.torrentId,
    this.fileIndex,
  });

  /// Returns the clean series or movie title without the internal '|||' delimiter.
  String get seriesOrMovieTitle {
    final parts = title.split('|||');
    return parts.first.trim();
  }

  /// Returns the episode or secondary subtitle name if stored after '|||'.
  String? get episodeSubtitle {
    final parts = title.split('|||');
    if (parts.length > 1) {
      final sub = parts.last.trim();
      return sub.isNotEmpty ? sub : null;
    }
    return null;
  }

  /// Returns a clean, human-readable display title for notifications and UI.
  String get formattedDisplayTitle {
    final main = seriesOrMovieTitle;
    final sub = episodeSubtitle;

    if (season != null && episode != null) {
      final epTag = 'S${season} E${episode}';
      if (sub != null &&
          sub.toLowerCase() != 'episode $episode' &&
          sub.toLowerCase() != 'season batch') {
        return '$main - $epTag: $sub';
      } else if (sub == 'Season Batch') {
        return '$main - Season $season Batch';
      }
      return '$main - $epTag';
    }

    if (sub != null && sub.isNotEmpty) {
      return '$main - $sub';
    }

    return main;
  }

  /// Returns the series/movie main poster without '|||'.
  String? get mainPosterPath {
    if (posterPath == null) return null;
    final parts = posterPath!.split('|||');
    return parts.isNotEmpty ? parts.first : null;
  }

  /// Returns the episode still image if available after '|||'.
  String? get episodeStillPath {
    if (posterPath == null) return null;
    final parts = posterPath!.split('|||');
    return parts.length > 1 ? parts.last : (parts.isNotEmpty ? parts.first : null);
  }
}
