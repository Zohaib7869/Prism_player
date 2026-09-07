import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_constants.dart';
import '../../../providers/app_providers.dart';
import '../../../repositories/settings_repository.dart';
import '../widgets/settings_tile.dart';

class PlaybackSettingsScreen extends ConsumerStatefulWidget {
  const PlaybackSettingsScreen({super.key});

  @override
  ConsumerState<PlaybackSettingsScreen> createState() => _PlaybackSettingsScreenState();
}

class _PlaybackSettingsScreenState extends ConsumerState<PlaybackSettingsScreen> {
  late SettingsRepository settings;

  @override
  void initState() {
    super.initState();
    settings = ref.read(settingsRepositoryProvider);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Playback')),
      body: ListView(
        children: [
          SettingsDropdownTile<double>(
            title: 'Default playback speed',
            value: settings.defaultPlaybackSpeed,
            options: {for (final s in AppConstants.playbackSpeeds) s: '${s}x'},
            onChanged: (v) => setState(() => settings.defaultPlaybackSpeed = v),
          ),
          SettingsSwitchTile(
            title: 'Auto play next',
            subtitle: 'Automatically play the next item in the queue',
            value: settings.autoPlayNext,
            onChanged: (v) => setState(() => settings.autoPlayNext = v),
          ),
          SettingsSwitchTile(
            title: 'Resume playback',
            subtitle: 'Continue from where you left off',
            value: settings.resumePlayback,
            onChanged: (v) => setState(() => settings.resumePlayback = v),
          ),
          SettingsSwitchTile(
            title: 'Gesture controls',
            subtitle: 'Swipe to seek, adjust brightness and volume',
            value: settings.gestureControlsEnabled,
            onChanged: (v) => setState(() => settings.gestureControlsEnabled = v),
          ),
          SettingsDropdownTile<int>(
            title: 'Double-tap seek duration',
            value: settings.doubleTapSeekSeconds,
            options: const {5: '5 seconds', 10: '10 seconds', 15: '15 seconds', 20: '20 seconds'},
            onChanged: (v) => setState(() => settings.doubleTapSeekSeconds = v),
          ),
          SettingsDropdownTile<DefaultOrientation>(
            title: 'Default orientation',
            value: settings.defaultOrientation,
            options: const {
              DefaultOrientation.portrait: 'Portrait',
              DefaultOrientation.landscape: 'Landscape',
              DefaultOrientation.auto: 'Auto',
            },
            onChanged: (v) => setState(() => settings.defaultOrientation = v),
          ),
        ],
      ),
    );
  }
}
