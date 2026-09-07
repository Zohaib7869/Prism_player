import 'package:hive/hive.dart';

/// Persisted equalizer + bass boost + virtualizer + volume booster state.
/// Single instance stored under key 'current' in the eqSettings box. Hive typeId: 4.
class EqSettingsModel extends HiveObject {
  bool equalizerEnabled;
  int presetIndex; // -1 == "Custom"
  List<int> bandLevelsMb; // one entry per native band, in millibels
  bool bassBoostEnabled;
  int bassBoostStrength; // 0-1000
  bool virtualizerEnabled;
  int virtualizerStrength; // 0-1000
  int volumeBoostPercent; // 100-200

  EqSettingsModel({
    this.equalizerEnabled = false,
    this.presetIndex = 0,
    this.bandLevelsMb = const [],
    this.bassBoostEnabled = false,
    this.bassBoostStrength = 0,
    this.virtualizerEnabled = false,
    this.virtualizerStrength = 0,
    this.volumeBoostPercent = 100,
  });
}

class EqSettingsModelAdapter extends TypeAdapter<EqSettingsModel> {
  @override
  final int typeId = 4;

  @override
  EqSettingsModel read(BinaryReader reader) {
    final numFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numFields; i++) reader.readByte(): reader.read(),
    };
    return EqSettingsModel(
      equalizerEnabled: fields[0] as bool? ?? false,
      presetIndex: fields[1] as int? ?? 0,
      bandLevelsMb: (fields[2] as List?)?.cast<int>() ?? const [],
      bassBoostEnabled: fields[3] as bool? ?? false,
      bassBoostStrength: fields[4] as int? ?? 0,
      virtualizerEnabled: fields[5] as bool? ?? false,
      virtualizerStrength: fields[6] as int? ?? 0,
      volumeBoostPercent: fields[7] as int? ?? 100,
    );
  }

  @override
  void write(BinaryWriter writer, EqSettingsModel obj) {
    writer
      ..writeByte(8)
      ..writeByte(0)
      ..write(obj.equalizerEnabled)
      ..writeByte(1)
      ..write(obj.presetIndex)
      ..writeByte(2)
      ..write(obj.bandLevelsMb)
      ..writeByte(3)
      ..write(obj.bassBoostEnabled)
      ..writeByte(4)
      ..write(obj.bassBoostStrength)
      ..writeByte(5)
      ..write(obj.virtualizerEnabled)
      ..writeByte(6)
      ..write(obj.virtualizerStrength)
      ..writeByte(7)
      ..write(obj.volumeBoostPercent);
  }
}
