import 'package:hive/hive.dart';

/// A user-created playlist. Hive typeId: 2.
/// System smart-playlists (Favorites, Recently Played, Most Played) are NOT
/// stored here — they're computed live from VideoModel/AudioModel/history data
/// by PlaylistRepository so they never fall out of sync.
class PlaylistModel extends HiveObject {
  final String id;
  String name;
  List<String> mediaRefs; // "video:<id>" or "audio:<id>", in playback order
  final int createdAtMs;

  PlaylistModel({
    required this.id,
    required this.name,
    required this.mediaRefs,
    required this.createdAtMs,
  });
}

class PlaylistModelAdapter extends TypeAdapter<PlaylistModel> {
  @override
  final int typeId = 2;

  @override
  PlaylistModel read(BinaryReader reader) {
    final numFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numFields; i++) reader.readByte(): reader.read(),
    };
    return PlaylistModel(
      id: fields[0] as String,
      name: fields[1] as String,
      mediaRefs: (fields[2] as List).cast<String>(),
      createdAtMs: fields[3] as int,
    );
  }

  @override
  void write(BinaryWriter writer, PlaylistModel obj) {
    writer
      ..writeByte(4)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.name)
      ..writeByte(2)
      ..write(obj.mediaRefs)
      ..writeByte(3)
      ..write(obj.createdAtMs);
  }
}
