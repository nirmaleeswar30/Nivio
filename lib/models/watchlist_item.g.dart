// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'watchlist_item.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class WatchStatusAdapter extends TypeAdapter<WatchStatus> {
  @override
  final int typeId = 7;

  @override
  WatchStatus read(BinaryReader reader) {
    switch (reader.readByte()) {
      case 0:
        return WatchStatus.planning;
      case 1:
        return WatchStatus.watching;
      case 2:
        return WatchStatus.completed;
      case 3:
        return WatchStatus.paused;
      case 4:
        return WatchStatus.dropped;
      default:
        return WatchStatus.planning;
    }
  }

  @override
  void write(BinaryWriter writer, WatchStatus obj) {
    switch (obj) {
      case WatchStatus.planning:
        writer.writeByte(0);
        break;
      case WatchStatus.watching:
        writer.writeByte(1);
        break;
      case WatchStatus.completed:
        writer.writeByte(2);
        break;
      case WatchStatus.paused:
        writer.writeByte(3);
        break;
      case WatchStatus.dropped:
        writer.writeByte(4);
        break;
    }
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is WatchStatusAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}

class WatchlistItemAdapter extends TypeAdapter<WatchlistItem> {
  @override
  final int typeId = 5;

  @override
  WatchlistItem read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return WatchlistItem(
      id: fields[0] as int,
      title: fields[1] as String,
      posterPath: fields[2] as String?,
      mediaType: fields[3] as String,
      addedAt: fields[4] as DateTime,
      voteAverage: fields[5] as double?,
      releaseDate: fields[6] as String?,
      overview: fields[7] as String?,
      watchStatus: fields[8] is WatchStatus
          ? fields[8] as WatchStatus
          : WatchStatus.planning,
      currentEpisode: fields[9] as int?,
      totalEpisodes: fields[10] as int?,
      anilistId: fields[11] as int?,
      malId: fields[12] as int?,
      updatedAt: fields[13] as DateTime?,
    );
  }

  @override
  void write(BinaryWriter writer, WatchlistItem obj) {
    writer
      ..writeByte(14)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.title)
      ..writeByte(2)
      ..write(obj.posterPath)
      ..writeByte(3)
      ..write(obj.mediaType)
      ..writeByte(4)
      ..write(obj.addedAt)
      ..writeByte(5)
      ..write(obj.voteAverage)
      ..writeByte(6)
      ..write(obj.releaseDate)
      ..writeByte(7)
      ..write(obj.overview)
      ..writeByte(8)
      ..write(obj.watchStatus)
      ..writeByte(9)
      ..write(obj.currentEpisode)
      ..writeByte(10)
      ..write(obj.totalEpisodes)
      ..writeByte(11)
      ..write(obj.anilistId)
      ..writeByte(12)
      ..write(obj.malId)
      ..writeByte(13)
      ..write(obj.updatedAt);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is WatchlistItemAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
