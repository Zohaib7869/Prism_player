/// File-extension allow-lists used when the scanner and file pickers decide
/// whether something is playable media. MediaStore already filters most of
/// this for us, but these are used for local folder browsing / "open with".
class MediaConstants {
  MediaConstants._();

  static const Set<String> videoExtensions = {
    'mp4', 'mkv', 'avi', 'mov', 'webm', '3gp', 'ts', 'm4v', 'flv',
  };

  static const Set<String> audioExtensions = {
    'mp3', 'aac', 'm4a', 'wav', 'flac', 'ogg', 'opus', 'wma',
  };

  static const Set<String> subtitleExtensions = {'srt', 'vtt', 'ass', 'ssa'};

  static bool isVideo(String path) => videoExtensions.contains(_ext(path));
  static bool isAudio(String path) => audioExtensions.contains(_ext(path));
  static bool isSubtitle(String path) => subtitleExtensions.contains(_ext(path));

  static String _ext(String path) {
    final dot = path.lastIndexOf('.');
    if (dot == -1 || dot == path.length - 1) return '';
    return path.substring(dot + 1).toLowerCase();
  }
}

/// Long-form default preset band curves (in millibels, relative to flat) for a
/// 10-band 60Hz–16kHz layout. Used as a software fallback when the device's
/// native Equalizer doesn't expose enough presets, and to seed the "Custom" tab.
class EqPresets {
  EqPresets._();

  static const Map<String, List<int>> curves = {
    'Normal':     [0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
    'Flat':       [0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
    'Classical':  [0, 0, 0, 0, 0, 0, -200, -200, -200, -300],
    'Dance':      [500, 300, 0, 0, 200, 400, 400, 0, 0, 0],
    'Folk':       [300, 200, 100, 0, 0, 0, 100, 100, 200, 200],
    'HeavyMetal': [400, 200, 0, -300, -100, 200, 500, 500, 500, 500],
    'HipHop':     [500, 400, 100, 300, -200, -200, 100, 100, 300, 400],
    'Jazz':       [300, 200, 100, 200, -200, -200, 0, 200, 300, 400],
    'Pop':        [-200, 200, 400, 400, 200, -100, -200, -200, -100, -100],
    'Rock':       [400, 200, -400, -600, -200, 300, 500, 500, 500, 500],
  };

  static const List<int> centerFrequenciesHz = [
    60, 120, 250, 500, 1000, 2000, 4000, 8000, 12000, 16000,
  ];
}
