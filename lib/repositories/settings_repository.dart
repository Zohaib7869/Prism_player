import 'package:hive_flutter/hive_flutter.dart';

import '../core/constants/app_constants.dart';
import '../core/database/hive_boxes.dart';

enum DefaultOrientation { portrait, landscape, auto }

/// Typed read/write access over the generic app_settings Hive box, so no
/// screen ever touches a raw Hive key string.
class SettingsRepository {
  Box get _box => Hive.box(HiveBoxes.appSettings);

  double get defaultPlaybackSpeed =>
      (_box.get(AppConstants.keyDefaultPlaybackSpeed, defaultValue: 1.0) as num).toDouble();
  set defaultPlaybackSpeed(double v) => _box.put(AppConstants.keyDefaultPlaybackSpeed, v);

  bool get autoPlayNext => _box.get(AppConstants.keyAutoPlayNext, defaultValue: true) as bool;
  set autoPlayNext(bool v) => _box.put(AppConstants.keyAutoPlayNext, v);

  bool get resumePlayback => _box.get(AppConstants.keyResumePlayback, defaultValue: true) as bool;
  set resumePlayback(bool v) => _box.put(AppConstants.keyResumePlayback, v);

  bool get gestureControlsEnabled =>
      _box.get(AppConstants.keyGestureControlsEnabled, defaultValue: true) as bool;
  set gestureControlsEnabled(bool v) => _box.put(AppConstants.keyGestureControlsEnabled, v);

  int get doubleTapSeekSeconds =>
      (_box.get(AppConstants.keyDoubleTapSeekSeconds, defaultValue: 10) as num).toInt();
  set doubleTapSeekSeconds(int v) => _box.put(AppConstants.keyDoubleTapSeekSeconds, v);

  DefaultOrientation get defaultOrientation {
    final index = _box.get(AppConstants.keyDefaultOrientation, defaultValue: 2) as int;
    return DefaultOrientation.values[index.clamp(0, DefaultOrientation.values.length - 1)];
  }

  set defaultOrientation(DefaultOrientation v) =>
      _box.put(AppConstants.keyDefaultOrientation, v.index);

  String get defaultAspectRatio =>
      _box.get(AppConstants.keyDefaultAspectRatio, defaultValue: 'Fit') as String;
  set defaultAspectRatio(String v) => _box.put(AppConstants.keyDefaultAspectRatio, v);

  double get subtitleSize =>
      (_box.get(AppConstants.keySubtitleSize, defaultValue: 18.0) as num).toDouble();
  set subtitleSize(double v) => _box.put(AppConstants.keySubtitleSize, v);

  int get subtitleColor => _box.get(AppConstants.keySubtitleColor, defaultValue: 0xFFFFFFFF) as int;
  set subtitleColor(int v) => _box.put(AppConstants.keySubtitleColor, v);

  bool get subtitleBackground =>
      _box.get(AppConstants.keySubtitleBackground, defaultValue: true) as bool;
  set subtitleBackground(bool v) => _box.put(AppConstants.keySubtitleBackground, v);

  int get subtitleDelayMs =>
      (_box.get(AppConstants.keySubtitleDelayMs, defaultValue: 0) as num).toInt();
  set subtitleDelayMs(int v) => _box.put(AppConstants.keySubtitleDelayMs, v);

  bool get gridViewDefault => _box.get(AppConstants.keyGridViewDefault, defaultValue: true) as bool;
  set gridViewDefault(bool v) => _box.put(AppConstants.keyGridViewDefault, v);

  String get sortOrder => _box.get(AppConstants.keySortOrder, defaultValue: 'date') as String;
  set sortOrder(String v) => _box.put(AppConstants.keySortOrder, v);

  bool get gaplessPlayback => _box.get(AppConstants.keyGaplessPlayback, defaultValue: false) as bool;
  set gaplessPlayback(bool v) => _box.put(AppConstants.keyGaplessPlayback, v);

  bool get biometricEnabled => _box.get(AppConstants.keyBiometricEnabled, defaultValue: false) as bool;
  set biometricEnabled(bool v) => _box.put(AppConstants.keyBiometricEnabled, v);

  /// Index into [VisualizerStyle.values] (see core/widgets/audio_spectrum.dart).
  int get visualizerStyleIndex => (_box.get(AppConstants.keyVisualizerStyle, defaultValue: 1) as num).toInt();
  set visualizerStyleIndex(int v) => _box.put(AppConstants.keyVisualizerStyle, v);

  List<String> get excludedFolders =>
      (_box.get(AppConstants.keyExcludedFolders, defaultValue: <String>[]) as List).cast<String>();
  set excludedFolders(List<String> v) => _box.put(AppConstants.keyExcludedFolders, v);
}
