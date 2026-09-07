class AppConstants {
  AppConstants._();

  static const String appName = 'Prism Player';

  // Settings keys (app_settings_box)
  static const String keyThemeType = 'theme_type';
  static const String keyCustomAccent = 'custom_accent_color';
  static const String keyCustomIsDark = 'custom_is_dark';
  static const String keyDefaultPlaybackSpeed = 'default_playback_speed';
  static const String keyAutoPlayNext = 'auto_play_next';
  static const String keyResumePlayback = 'resume_playback';
  static const String keyGestureControlsEnabled = 'gesture_controls_enabled';
  static const String keyDoubleTapSeekSeconds = 'double_tap_seek_seconds';
  static const String keyDefaultOrientation = 'default_orientation';
  static const String keyDefaultAspectRatio = 'default_aspect_ratio';
  static const String keySubtitleSize = 'subtitle_size';
  static const String keySubtitleColor = 'subtitle_color';
  static const String keySubtitleBackground = 'subtitle_background';
  static const String keySubtitleDelayMs = 'subtitle_delay_ms';
  static const String keyGridViewDefault = 'grid_view_default';
  static const String keySortOrder = 'sort_order';
  static const String keyGaplessPlayback = 'gapless_playback';
  static const String keySafePinHash = 'safe_pin_hash'; // stored in secure storage, not here
  static const String keyBiometricEnabled = 'biometric_enabled';
  static const String keyExcludedFolders = 'excluded_folders';
  // -1 sentinel means "not set" — falls back to each wallpaper theme's own default.
  static const String keyWallpaperDim = 'wallpaper_dim';
  static const String keyVisualizerStyle = 'visualizer_style';
  // Name of the last YouTube API client profile that successfully resolved a
  // stream. Tried first on the next resolve so we stop paying for the
  // profiles YouTube is currently blocking.
  static const String keyYtLastGoodProfile = 'yt_last_good_profile';

  static const Duration seekStep = Duration(seconds: 10);
  static const List<double> playbackSpeeds = [0.25, 0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0];
}
