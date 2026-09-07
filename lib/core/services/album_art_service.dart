import 'dart:typed_data';

import 'package:flutter/services.dart';

/// Resolves `content://media/external/audio/albumart/...` URIs to raw JPEG
/// bytes via the native `file_ops` channel (Image.file can't read content://
/// directly). Results are cached in memory for the life of the app so the
/// same album cover isn't re-read from disk on every rebuild.
class AlbumArtService {
  static const _channel = MethodChannel('com.prismplayer.app/file_ops');
  final Map<String, Uint8List?> _cache = {};

  /// Magic-number sniff for the container formats Android's decoder accepts.
  static bool _looksLikeImage(Uint8List b) {
    if (b.length < 12) return false;
    // JPEG
    if (b[0] == 0xFF && b[1] == 0xD8) return true;
    // PNG
    if (b[0] == 0x89 && b[1] == 0x50 && b[2] == 0x4E && b[3] == 0x47) return true;
    // GIF
    if (b[0] == 0x47 && b[1] == 0x49 && b[2] == 0x46) return true;
    // WEBP ("RIFF"...."WEBP")
    if (b[0] == 0x52 && b[1] == 0x49 && b[2] == 0x46 && b[3] == 0x46 &&
        b[8] == 0x57 && b[9] == 0x45 && b[10] == 0x42 && b[11] == 0x50) return true;
    // BMP
    if (b[0] == 0x42 && b[1] == 0x4D) return true;
    // HEIF/AVIF ("ftyp" at offset 4)
    if (b[4] == 0x66 && b[5] == 0x74 && b[6] == 0x79 && b[7] == 0x70) return true;
    return false;
  }

  Future<Uint8List?> load(String contentUri) async {
    if (_cache.containsKey(contentUri)) return _cache[contentUri];
    try {
      final bytes = await _channel.invokeMethod<Uint8List>('getAlbumArtBytes', {'uri': contentUri});
      // Second line of defence behind the native decode check: never hand
      // non-image bytes to Image.memory, which logs
      // "Failed to decode image ... unimplemented" and renders nothing.
      final safe = (bytes != null && _looksLikeImage(bytes)) ? bytes : null;
      _cache[contentUri] = safe;
      return safe;
    } on PlatformException {
      _cache[contentUri] = null;
      return null;
    }
  }

  /// True once [contentUri] has been resolved (successfully or not) and is
  /// sitting in memory. Lets callers skip a FutureBuilder round-trip — even
  /// an already-resolved Future still needs a microtask/frame to report
  /// "done", which is exactly the blank-frame flash that made art flicker
  /// when a screen (or a fresh Hero destination widget) first builds.
  bool has(String contentUri) => _cache.containsKey(contentUri);

  /// Synchronous read of whatever's cached for [contentUri], or null if
  /// nothing has resolved yet. Always check [has] first — a genuine cache
  /// miss and "cached null because the art doesn't exist" both return null
  /// here.
  Uint8List? peek(String contentUri) => _cache[contentUri];
}
