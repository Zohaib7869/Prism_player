import 'package:device_info_plus/device_info_plus.dart';
import 'package:permission_handler/permission_handler.dart';

/// Requests only the permissions the app actually needs, and only the ones
/// relevant to the Android version running on the device (READ_MEDIA_* on 13+,
/// legacy storage permission below that).
class PermissionService {
  Future<bool> requestMediaPermissions() async {
    final sdkInt = await _sdkInt();
    if (sdkInt >= 33) {
      final statuses = await [
        Permission.videos,
        Permission.audio,
      ].request();
      return statuses.values.every((s) => s.isGranted);
    } else {
      final status = await Permission.storage.request();
      return status.isGranted;
    }
  }

  Future<bool> requestNotificationPermission() async {
    final sdkInt = await _sdkInt();
    if (sdkInt < 33) return true; // not required below Android 13
    final status = await Permission.notification.request();
    return status.isGranted;
  }

  Future<bool> hasMediaPermissions() async {
    final sdkInt = await _sdkInt();
    if (sdkInt >= 33) {
      return await Permission.videos.isGranted && await Permission.audio.isGranted;
    }
    return await Permission.storage.isGranted;
  }

  Future<bool> isPermanentlyDenied() async {
    final sdkInt = await _sdkInt();
    if (sdkInt >= 33) {
      return await Permission.videos.isPermanentlyDenied ||
          await Permission.audio.isPermanentlyDenied;
    }
    return await Permission.storage.isPermanentlyDenied;
  }

  /// Needed by the native `Visualizer` audio effect that powers the
  /// real-time Now Playing audio visualizer. No audio is recorded — this
  /// only unlocks the OS handing the effect live FFT data for in-app
  /// playback. Requested lazily (first time the visualizer is shown), not
  /// at startup, since it's not essential to using the app. If denied, the
  /// visualizer widgets fall back to their simulated animation.
  Future<bool> requestAudioCapturePermission() async {
    final status = await Permission.microphone.request();
    return status.isGranted;
  }

  Future<bool> hasAudioCapturePermission() => Permission.microphone.isGranted;

  Future<void> openSettings() => openAppSettings();

  Future<int> _sdkInt() async {
    final info = await DeviceInfoPlugin().androidInfo;
    return info.version.sdkInt;
  }
}
