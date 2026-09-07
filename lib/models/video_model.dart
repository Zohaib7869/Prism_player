import 'package:hive/hive.dart';

/// A scanned video file and everything the app tracks about it locally.
/// Hive typeId: 0
class VideoModel extends HiveObject {
  final String id; // MediaStore _id, stable across scans
  final String path;
  String title;
  final int durationMs;
  final int sizeBytes;
  final int width;
  final int height;
  final int dateModifiedMs;
  final String folderName;
  final String folderPath;
  final String mimeType;
  String? thumbnailPath;

  int lastPositionMs;
  double watchedFraction; // 0.0 - 1.0, used for "Continue Watching" progress
  int playCount;
  bool isFavorite;
  bool isHidden;
  int lastPlayedAtMs;

  VideoModel({
    required this.id,
    required this.path,
    required this.title,
    required this.durationMs,
    required this.sizeBytes,
    required this.width,
    required this.height,
    required this.dateModifiedMs,
    required this.folderName,
    required this.folderPath,
    required this.mimeType,
    this.thumbnailPath,
    this.lastPositionMs = 0,
    this.watchedFraction = 0,
    this.playCount = 0,
    this.isFavorite = false,
    this.isHidden = false,
    this.lastPlayedAtMs = 0,
  });

  String get mediaRef => 'video:$id';

  factory VideoModel.fromScanMap(Map<dynamic, dynamic> map) {
    final path = map['path'] as String;
    return VideoModel(
      id: map['id'] as String,
      path: path,
      title: map['title'] as String,
      durationMs: (map['durationMs'] as num).toInt(),
      sizeBytes: (map['sizeBytes'] as num).toInt(),
      width: (map['width'] as num).toInt(),
      height: (map['height'] as num).toInt(),
      dateModifiedMs: (map['dateModifiedMs'] as num).toInt(),
      folderName: map['folderName'] as String? ?? 'Unknown',
      folderPath: _parentDir(path),
      mimeType: map['mimeType'] as String? ?? 'video/*',
    );
  }

  static String _parentDir(String path) {
    final idx = path.lastIndexOf('/');
    return idx == -1 ? path : path.substring(0, idx);
  }
}

class VideoModelAdapter extends TypeAdapter<VideoModel> {
  @override
  final int typeId = 0;

  @override
  VideoModel read(BinaryReader reader) {
    final numFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numFields; i++) reader.readByte(): reader.read(),
    };
    return VideoModel(
      id: fields[0] as String,
      path: fields[1] as String,
      title: fields[2] as String,
      durationMs: fields[3] as int,
      sizeBytes: fields[4] as int,
      width: fields[5] as int,
      height: fields[6] as int,
      dateModifiedMs: fields[7] as int,
      folderName: fields[8] as String,
      folderPath: fields[9] as String,
      mimeType: fields[10] as String,
      thumbnailPath: fields[11] as String?,
      lastPositionMs: fields[12] as int? ?? 0,
      watchedFraction: fields[13] as double? ?? 0,
      playCount: fields[14] as int? ?? 0,
      isFavorite: fields[15] as bool? ?? false,
      isHidden: fields[16] as bool? ?? false,
      lastPlayedAtMs: fields[17] as int? ?? 0,
    );
  }

  @override
  void write(BinaryWriter writer, VideoModel obj) {
    writer
      ..writeByte(18)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.path)
      ..writeByte(2)
      ..write(obj.title)
      ..writeByte(3)
      ..write(obj.durationMs)
      ..writeByte(4)
      ..write(obj.sizeBytes)
      ..writeByte(5)
      ..write(obj.width)
      ..writeByte(6)
      ..write(obj.height)
      ..writeByte(7)
      ..write(obj.dateModifiedMs)
      ..writeByte(8)
      ..write(obj.folderName)
      ..writeByte(9)
      ..write(obj.folderPath)
      ..writeByte(10)
      ..write(obj.mimeType)
      ..writeByte(11)
      ..write(obj.thumbnailPath)
      ..writeByte(12)
      ..write(obj.lastPositionMs)
      ..writeByte(13)
      ..write(obj.watchedFraction)
      ..writeByte(14)
      ..write(obj.playCount)
      ..writeByte(15)
      ..write(obj.isFavorite)
      ..writeByte(16)
      ..write(obj.isHidden)
      ..writeByte(17)
      ..write(obj.lastPlayedAtMs);
  }
}
