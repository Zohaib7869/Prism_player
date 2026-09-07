import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../constants/app_constants.dart';
import '../database/hive_boxes.dart';
import 'app_theme.dart';

class ThemeState {
  final AppThemeType type;
  final Color customAccent;
  final bool customIsDark;

  /// User override for the wallpaper scrim strength (0..1), applied on top
  /// of whichever image theme is selected. Null means "use that theme's own
  /// default dim" (see [PrismPalette.imageDim]).
  final double? wallpaperDim;

  const ThemeState({
    required this.type,
    required this.customAccent,
    required this.customIsDark,
    this.wallpaperDim,
  });

  PrismPalette get palette {
    final base = PrismThemes.paletteFor(type, customAccent: customAccent, customIsDark: customIsDark);
    if (wallpaperDim == null || base.backgroundImage == null) return base;
    return base.copyWith(imageDim: wallpaperDim);
  }

  ThemeData get themeData => PrismThemes.buildThemeData(palette);

  ThemeState copyWith({AppThemeType? type, Color? customAccent, bool? customIsDark, double? wallpaperDim}) {
    return ThemeState(
      type: type ?? this.type,
      customAccent: customAccent ?? this.customAccent,
      customIsDark: customIsDark ?? this.customIsDark,
      wallpaperDim: wallpaperDim ?? this.wallpaperDim,
    );
  }
}

class ThemeNotifier extends StateNotifier<ThemeState> {
  ThemeNotifier() : super(_loadInitial()) {
    // Persist any change immediately so a killed app reopens with the same theme.
  }

  static Box get _box => Hive.box(HiveBoxes.appSettings);

  static ThemeState _loadInitial() {
    final typeIndex = _box.get(AppConstants.keyThemeType, defaultValue: 0) as int;
    final accentValue =
        _box.get(AppConstants.keyCustomAccent, defaultValue: PrismThemes.midnight.accent.value) as int;
    final isDark = _box.get(AppConstants.keyCustomIsDark, defaultValue: true) as bool;
    final storedDim = _box.get(AppConstants.keyWallpaperDim, defaultValue: -1.0) as double;
    return ThemeState(
      type: AppThemeType.values[typeIndex.clamp(0, AppThemeType.values.length - 1)],
      customAccent: Color(accentValue),
      customIsDark: isDark,
      wallpaperDim: storedDim < 0 ? null : storedDim,
    );
  }

  void setThemeType(AppThemeType type) {
    state = state.copyWith(type: type);
    _box.put(AppConstants.keyThemeType, type.index);
  }

  void setCustomAccent(Color color) {
    state = state.copyWith(type: AppThemeType.custom, customAccent: color);
    _box.put(AppConstants.keyThemeType, AppThemeType.custom.index);
    _box.put(AppConstants.keyCustomAccent, color.value);
  }

  void setCustomIsDark(bool isDark) {
    state = state.copyWith(customIsDark: isDark);
    _box.put(AppConstants.keyCustomIsDark, isDark);
  }

  /// Sets the wallpaper scrim strength (0 = fully transparent/wallpaper
  /// fully visible, 1 = fully opaque/wallpaper hidden) for image themes.
  void setWallpaperDim(double dim) {
    final clamped = dim.clamp(0.0, 1.0);
    state = state.copyWith(wallpaperDim: clamped);
    _box.put(AppConstants.keyWallpaperDim, clamped);
  }
}

final themeProvider = StateNotifierProvider<ThemeNotifier, ThemeState>((ref) {
  return ThemeNotifier();
});
