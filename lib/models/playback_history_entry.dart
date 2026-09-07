import 'package:hive/hive.dart';

/// One row per media item tracking when it was last played and how often.
/// Keyed in the box by mediaRef ("video:<id>" / "audio:<id>"). Hive typeId: 3.
class PlaybackHistoryEntry extends HiveObject {
  final String mediaRef;
  int lastPlayedAtMs;
  int playCount;

  PlaybackHistoryEntry({
    required this.mediaRef,
    required this.lastPlayedAtMs,
    required this.playCount,
  });
}

class PlaybackHistoryEntryAdapter extends TypeAdapter<PlaybackHistoryEntry> {
  @override
  final int typeId = 3;

  @override
  PlaybackHistoryEntry read(BinaryReader reader) {
    final numFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numFields; i++) reader.readByte(): reader.read(),
    };
    return PlaybackHistoryEntry(
      mediaRef: fields[0] as String,
      lastPlayedAtMs: fields[1] as int,
      playCount: fields[2] as int,
    );
  }

  @override
  void write(BinaryWriter writer, PlaybackHistoryEntry obj) {
    writer
      ..writeByte(3)
      ..writeByte(0)
      ..write(obj.mediaRef)
      ..writeByte(1)
      ..write(obj.lastPlayedAtMs)
      ..writeByte(2)
      ..write(obj.playCount);
  }
}
