import 'package:hive/hive.dart';

/// A scanned audio file. Hive typeId: 1
class AudioModel extends HiveObject {
  final String id;
  final String path;
  String title;
  final String artist;
  final String album;
  final String? genre;
  final String? albumArtUri;
  final int durationMs;
  final int sizeBytes;
  final int dateModifiedMs;
  final String folderName;
  final String folderPath;
  final String mimeType;

  int lastPositionMs;
  int playCount;
  bool isFavorite;
  bool isHidden;
  int lastPlayedAtMs;
  bool isExtracted; // true if this file was produced by "Save as Audio"

  AudioModel({
    required this.id,
    required this.path,
    required this.title,
    required this.artist,
    required this.album,
    this.genre,
    this.albumArtUri,
    required this.durationMs,
    required this.sizeBytes,
    required this.dateModifiedMs,
    required this.folderName,
    required this.folderPath,
    required this.mimeType,
    this.lastPositionMs = 0,
    this.playCount = 0,
    this.isFavorite = false,
    this.isHidden = false,
    this.lastPlayedAtMs = 0,
    this.isExtracted = false,
  });

  String get mediaRef => 'audio:$id';

  factory AudioModel.fromScanMap(Map<dynamic, dynamic> map) {
    final path = map['path'] as String;
    return AudioModel(
      id: map['id'] as String,
      path: path,
      title: map['title'] as String,
      artist: map['artist'] as String? ?? 'Unknown Artist',
      album: map['album'] as String? ?? 'Unknown Album',
      genre: map['genre'] as String?,
      albumArtUri: map['albumArtUri'] as String?,
      durationMs: (map['durationMs'] as num).toInt(),
      sizeBytes: (map['sizeBytes'] as num).toInt(),
      dateModifiedMs: (map['dateModifiedMs'] as num).toInt(),
      folderName: map['folderName'] as String? ?? 'Unknown',
      folderPath: _parentDir(path),
      mimeType: map['mimeType'] as String? ?? 'audio/*',
    );
  }

  static String _parentDir(String path) {
    final idx = path.lastIndexOf('/');
    return idx == -1 ? path : path.substring(0, idx);
  }
}

class AudioModelAdapter extends TypeAdapter<AudioModel> {
  @override
  final int typeId = 1;

  @override
  AudioModel read(BinaryReader reader) {
    final numFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numFields; i++) reader.readByte(): reader.read(),
    };
    return AudioModel(
      id: fields[0] as String,
      path: fields[1] as String,
      title: fields[2] as String,
      artist: fields[3] as String,
      album: fields[4] as String,
      genre: fields[5] as String?,
      albumArtUri: fields[6] as String?,
      durationMs: fields[7] as int,
      sizeBytes: fields[8] as int,
      dateModifiedMs: fields[9] as int,
      folderName: fields[10] as String,
      folderPath: fields[11] as String,
      mimeType: fields[12] as String,
      lastPositionMs: fields[13] as int? ?? 0,
      playCount: fields[14] as int? ?? 0,
      isFavorite: fields[15] as bool? ?? false,
      isHidden: fields[16] as bool? ?? false,
      lastPlayedAtMs: fields[17] as int? ?? 0,
      isExtracted: fields[18] as bool? ?? false,
    );
  }

  @override
  void write(BinaryWriter writer, AudioModel obj) {
    writer
      ..writeByte(19)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.path)
      ..writeByte(2)
      ..write(obj.title)
      ..writeByte(3)
      ..write(obj.artist)
      ..writeByte(4)
      ..write(obj.album)
      ..writeByte(5)
      ..write(obj.genre)
      ..writeByte(6)
      ..write(obj.albumArtUri)
      ..writeByte(7)
      ..write(obj.durationMs)
      ..writeByte(8)
      ..write(obj.sizeBytes)
      ..writeByte(9)
      ..write(obj.dateModifiedMs)
      ..writeByte(10)
      ..write(obj.folderName)
      ..writeByte(11)
      ..write(obj.folderPath)
      ..writeByte(12)
      ..write(obj.mimeType)
      ..writeByte(13)
      ..write(obj.lastPositionMs)
      ..writeByte(14)
      ..write(obj.playCount)
      ..writeByte(15)
      ..write(obj.isFavorite)
      ..writeByte(16)
      ..write(obj.isHidden)
      ..writeByte(17)
      ..write(obj.lastPlayedAtMs)
      ..writeByte(18)
      ..write(obj.isExtracted);
  }
}
