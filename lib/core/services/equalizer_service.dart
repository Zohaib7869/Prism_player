import 'package:flutter/services.dart';

class EqualizerBandInfo {
  final int numberOfBands;
  final int minLevelMb;
  final int maxLevelMb;
  final List<int> centerFrequenciesHz;
  const EqualizerBandInfo({
    required this.numberOfBands,
    required this.minLevelMb,
    required this.maxLevelMb,
    required this.centerFrequenciesHz,
  });

  factory EqualizerBandInfo.empty() =>
      const EqualizerBandInfo(numberOfBands: 0, minLevelMb: 0, maxLevelMb: 0, centerFrequenciesHz: []);
}

/// Dart-side wrapper around the native `audio_effects` channel (Equalizer,
/// BassBoost, Virtualizer, LoudnessEnhancer-based volume boost). Must be
/// [attach]ed to a live Android audio session id before any control call has
/// an effect — see GlobalPlayerController, which attaches it to just_audio's
/// `androidAudioSessionId` whenever audio playback starts.
///
/// Native audio effects only attach to an Android audio session id, and
/// video_player does not expose one through its public API — so equalizer,
/// bass boost, virtualizer and volume boost apply during Music/Audio playback
/// and "Play as Audio" mode, not during native video playback. This is a
/// platform limitation, not an oversight; see README.
class EqualizerService {
  static const _channel = MethodChannel('com.prismplayer.app/audio_effects');

  int? _attachedSessionId;

  Future<void> attach(int sessionId) async {
    if (_attachedSessionId == sessionId) return;
    await _channel.invokeMethod('attach', {'sessionId': sessionId});
    _attachedSessionId = sessionId;
  }

  Future<void> detach() async {
    if (_attachedSessionId == null) return;
    await _channel.invokeMethod('detach');
    _attachedSessionId = null;
  }

  bool get isAttached => _attachedSessionId != null;

  Future<EqualizerBandInfo> getEqualizerInfo() async {
    final result = await _channel.invokeMapMethod<String, dynamic>('getEqualizerInfo');
    if (result == null) return EqualizerBandInfo.empty();
    return EqualizerBandInfo(
      numberOfBands: result['numberOfBands'] as int,
      minLevelMb: result['minLevelMb'] as int,
      maxLevelMb: result['maxLevelMb'] as int,
      centerFrequenciesHz: (result['centerFrequenciesHz'] as List).cast<int>(),
    );
  }

  Future<void> setEqualizerEnabled(bool enabled) =>
      _channel.invokeMethod('setEqualizerEnabled', {'enabled': enabled});

  Future<void> setBandLevel(int band, int levelMb) =>
      _channel.invokeMethod('setBandLevel', {'band': band, 'levelMb': levelMb});

  Future<List<String>> getPresetNames() async {
    final result = await _channel.invokeListMethod<String>('getPresetNames');
    return result ?? [];
  }

  Future<void> usePreset(int index) => _channel.invokeMethod('usePreset', {'index': index});

  Future<void> setBassBoostEnabled(bool enabled) =>
      _channel.invokeMethod('setBassBoostEnabled', {'enabled': enabled});

  Future<void> setBassBoostStrength(int strength) =>
      _channel.invokeMethod('setBassBoostStrength', {'strength': strength});

  Future<void> setVirtualizerEnabled(bool enabled) =>
      _channel.invokeMethod('setVirtualizerEnabled', {'enabled': enabled});

  Future<void> setVirtualizerStrength(int strength) =>
      _channel.invokeMethod('setVirtualizerStrength', {'strength': strength});

  /// percent: 100 (unmodified) .. 200 (double amplitude, ~+20dB ceiling).
  Future<void> setVolumeBoostPercent(int percent) =>
      _channel.invokeMethod('setVolumeBoostPercent', {'percent': percent});
}
