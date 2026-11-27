// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'download_item.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class DownloadItemAdapter extends TypeAdapter<DownloadItem> {
  @override
  final typeId = 6;

  @override
  DownloadItem read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return DownloadItem(
      id: fields[0] as String,
      mediaId: (fields[1] as num).toInt(),
      title: fields[2] as String,
      posterPath: fields[3] as String?,
      mediaType: fields[4] as String,
      season: (fields[5] as num?)?.toInt(),
      episode: (fields[6] as num?)?.toInt(),
      savePath: fields[7] as String,
      status: fields[8] == null
          ? DownloadStatus.pending
          : fields[8] as DownloadStatus,
      progress: fields[9] == null ? 0.0 : (fields[9] as num).toDouble(),
      totalBytes: fields[10] == null ? 0 : (fields[10] as num).toInt(),
      downloadedBytes: fields[11] == null ? 0 : (fields[11] as num).toInt(),
      createdAt: fields[12] as DateTime,
      streamUrl: fields[13] as String?,
      headers: (fields[14] as Map?)?.cast<String, String>(),
      selectedAudioLanguage: fields[15] as String?,
      selectedSubtitleLanguage: fields[16] as String?,
      subtitleUrl: fields[17] as String?,
      torrentId: (fields[18] as num?)?.toInt(),
      fileIndex: (fields[19] as num?)?.toInt(),
    );
  }

  @override
  void write(BinaryWriter writer, DownloadItem obj) {
    writer
      ..writeByte(20)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.mediaId)
      ..writeByte(2)
      ..write(obj.title)
      ..writeByte(3)
      ..write(obj.posterPath)
      ..writeByte(4)
      ..write(obj.mediaType)
      ..writeByte(5)
      ..write(obj.season)
      ..writeByte(6)
      ..write(obj.episode)
      ..writeByte(7)
      ..write(obj.savePath)
      ..writeByte(8)
      ..write(obj.status)
      ..writeByte(9)
      ..write(obj.progress)
      ..writeByte(10)
      ..write(obj.totalBytes)
      ..writeByte(11)
      ..write(obj.downloadedBytes)
      ..writeByte(12)
      ..write(obj.createdAt)
      ..writeByte(13)
      ..write(obj.streamUrl)
      ..writeByte(14)
      ..write(obj.headers)
      ..writeByte(15)
      ..write(obj.selectedAudioLanguage)
      ..writeByte(16)
      ..write(obj.selectedSubtitleLanguage)
      ..writeByte(17)
      ..write(obj.subtitleUrl)
      ..writeByte(18)
      ..write(obj.torrentId)
      ..writeByte(19)
      ..write(obj.fileIndex);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DownloadItemAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}

class DownloadStatusAdapter extends TypeAdapter<DownloadStatus> {
  @override
  final typeId = 4;

  @override
  DownloadStatus read(BinaryReader reader) {
    switch (reader.readByte()) {
      case 0:
        return DownloadStatus.pending;
      case 1:
        return DownloadStatus.downloading;
      case 2:
        return DownloadStatus.completed;
      case 3:
        return DownloadStatus.failed;
      case 4:
        return DownloadStatus.paused;
      case 5:
        return DownloadStatus.extracting;
      default:
        return DownloadStatus.pending;
    }
  }

  @override
  void write(BinaryWriter writer, DownloadStatus obj) {
    switch (obj) {
      case DownloadStatus.pending:
        writer.writeByte(0);
      case DownloadStatus.downloading:
        writer.writeByte(1);
      case DownloadStatus.completed:
        writer.writeByte(2);
      case DownloadStatus.failed:
        writer.writeByte(3);
      case DownloadStatus.paused:
        writer.writeByte(4);
      case DownloadStatus.extracting:
        writer.writeByte(5);
    }
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DownloadStatusAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
