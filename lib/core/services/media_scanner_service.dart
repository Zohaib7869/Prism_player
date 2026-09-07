import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

/// Thin Dart wrapper around the native `media_scanner` and `file_ops` channels.
/// Keeps all platform-channel plumbing in one place so repositories never talk
/// to MethodChannel directly.
class MediaScannerService {
  static const _scannerChannel = MethodChannel('com.prismplayer.app/media_scanner');
  static const _fileOpsChannel = MethodChannel('com.prismplayer.app/file_ops');

  Future<List<Map<dynamic, dynamic>>> scanVideos({int sinceEpochMs = 0}) async {
    final result = await _scannerChannel.invokeMethod<List<dynamic>>(
      'scanVideos',
      {'sinceEpochMs': sinceEpochMs},
    );
    return (result ?? []).cast<Map<dynamic, dynamic>>();
  }

  Future<List<Map<dynamic, dynamic>>> scanAudio({int sinceEpochMs = 0}) async {
    final result = await _scannerChannel.invokeMethod<List<dynamic>>(
      'scanAudio',
      {'sinceEpochMs': sinceEpochMs},
    );
    return (result ?? []).cast<Map<dynamic, dynamic>>();
  }

  /// Generates (or returns the cached) JPEG thumbnail for a video, storing it
  /// under the app's cache directory keyed by the video's stable MediaStore id
  /// so we never regenerate the same thumbnail twice.
  Future<String?> videoThumbnail(String videoPath, String videoId) async {
    final cacheDir = await getTemporaryDirectory();
    final outputPath = '${cacheDir.path}/thumbs/$videoId.jpg';
    try {
      final result = await _fileOpsChannel.invokeMethod<String>(
        'generateVideoThumbnail',
        {'path': videoPath, 'outputPath': outputPath, 'maxWidth': 512},
      );
      return result;
    } on PlatformException {
      return null;
    }
  }

  Future<bool> renameFile(String path, String newName) async {
    final result = await _fileOpsChannel.invokeMethod<String>(
      'renameFile',
      {'path': path, 'newName': newName},
    );
    return result != null;
  }

  Future<bool> deleteFile(String path) async {
    final result = await _fileOpsChannel.invokeMethod<bool>('deleteFile', {'path': path});
    return result ?? false;
  }

  Future<void> rescan(String path) async {
    await _fileOpsChannel.invokeMethod('rescanPath', {'path': path});
  }
}
