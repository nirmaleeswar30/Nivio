// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'new_episode.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class NewEpisodeAdapter extends TypeAdapter<NewEpisode> {
  @override
  final int typeId = 3;

  @override
  NewEpisode read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return NewEpisode(
      showId: fields[0] as int,
      showName: fields[1] as String,
      seasonNumber: fields[2] as int,
      episodeNumber: fields[3] as int,
      episodeName: fields[4] as String,
      posterPath: fields[5] as String?,
      airDate: fields[6] as DateTime,
      detectedAt: fields[7] as DateTime,
      isRead: fields[8] as bool,
    );
  }

  @override
  void write(BinaryWriter writer, NewEpisode obj) {
    writer
      ..writeByte(9)
      ..writeByte(0)
      ..write(obj.showId)
      ..writeByte(1)
      ..write(obj.showName)
      ..writeByte(2)
      ..write(obj.seasonNumber)
      ..writeByte(3)
      ..write(obj.episodeNumber)
      ..writeByte(4)
      ..write(obj.episodeName)
      ..writeByte(5)
      ..write(obj.posterPath)
      ..writeByte(6)
      ..write(obj.airDate)
      ..writeByte(7)
      ..write(obj.detectedAt)
      ..writeByte(8)
      ..write(obj.isRead);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is NewEpisodeAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
