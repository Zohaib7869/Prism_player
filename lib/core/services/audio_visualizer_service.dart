import 'package:flutter/services.dart';

import '../permissions/permission_service.dart';

/// Dart-side bridge to the native `Visualizer` audio effect (see
/// AudioVisualizerPlugin.kt). Streams real, live magnitude bars for whatever
/// is actually playing through the attached Android audio session — this is
/// genuine FFT data reacting to the audio in real time, not a simulated
/// animation.
///
/// Same platform limitation as [EqualizerService]: this only has data during
/// Music/Audio playback (just_audio), since video_player doesn't expose an
/// Android audio session id. It is a singleton — like the audio session
/// itself, there is only ever one to attach to — so every visualizer widget
/// in the app (mini-player bars, Now Playing spectrum/disk/wave) shares the
/// same live stream instead of each opening its own native capture.
class AudioVisualizerService {
  AudioVisualizerService._internal();
  static final AudioVisualizerService instance = AudioVisualizerService._internal();

  static const _methodChannel = MethodChannel('com.prismplayer.app/audio_visualizer');
  static const _eventChannel = EventChannel('com.prismplayer.app/audio_visualizer/events');

  final _permissionService = PermissionService();

  Stream<List<double>>? _levelStream;
  int? _attachedSessionId;
  bool _permissionChecked = false;
  bool _permissionGranted = false;

  /// Broadcast stream of normalized (0..1) magnitude bars, refreshed roughly
  /// 20 times a second while attached. Emits nothing (stays silent, never
  /// errors) whenever there's no live session to read from — callers should
  /// treat "no recent event" as "fall back to a simulated look", not as an
  /// error state.
  Stream<List<double>> get levelStream {
    return _levelStream ??= _eventChannel.receiveBroadcastStream().map<List<double>>(
          (event) => (event as List).cast<num>().map((n) => n.toDouble()).toList(),
        );
  }

  bool get isAttached => _attachedSessionId != null;

  /// Attaches the native visualizer to [sessionId]. Requests microphone
  /// permission on first use (required by Android's Visualizer effect) —
  /// if denied, this becomes a no-op and callers simply never see level
  /// data, which is exactly the "fall back to simulated" case widgets
  /// already handle.
  Future<void> attach(int sessionId) async {
    if (_attachedSessionId == sessionId) return;
    if (!_permissionChecked) {
      _permissionChecked = true;
      _permissionGranted = await _permissionService.hasAudioCapturePermission();
      if (!_permissionGranted) {
        _permissionGranted = await _permissionService.requestAudioCapturePermission();
      }
    }
    if (!_permissionGranted) return;
    await _methodChannel.invokeMethod('attach', {'sessionId': sessionId});
    _attachedSessionId = sessionId;
  }

  Future<void> detach() async {
    if (_attachedSessionId == null) return;
    await _methodChannel.invokeMethod('detach');
    _attachedSessionId = null;
  }
}
