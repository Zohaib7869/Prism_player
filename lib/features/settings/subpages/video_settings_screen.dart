import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../providers/app_providers.dart';
import '../../player/widgets/aspect_ratio_sheet.dart';
import '../widgets/settings_tile.dart';

class VideoSettingsScreen extends ConsumerStatefulWidget {
  const VideoSettingsScreen({super.key});

  @override
  ConsumerState<VideoSettingsScreen> createState() => _VideoSettingsScreenState();
}

class _VideoSettingsScreenState extends ConsumerState<VideoSettingsScreen> {
  @override
  Widget build(BuildContext context) {
    final settings = ref.read(settingsRepositoryProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Video')),
      body: ListView(
        children: [
          SettingsSectionLabel('Playback'),
          ListTile(
            title: const Text('Default aspect ratio'),
            trailing: Text(settings.defaultAspectRatio),
            onTap: () async {
              final mode = await showAspectRatioSheet(context, settings.defaultAspectRatio);
              if (mode != null) setState(() => settings.defaultAspectRatio = mode);
            },
          ),
          SettingsSectionLabel('Subtitles'),
          ListTile(
            title: const Text('Subtitle size'),
            subtitle: Slider(
              value: settings.subtitleSize,
              min: 12,
              max: 32,
              onChanged: (v) => setState(() => settings.subtitleSize = v),
            ),
          ),
          SettingsSwitchTile(
            title: 'Subtitle background',
            value: settings.subtitleBackground,
            onChanged: (v) => setState(() => settings.subtitleBackground = v),
          ),
          SettingsSectionLabel('Performance'),
          const ListTile(
            title: Text('Hardware acceleration'),
            subtitle: Text('Enabled automatically by the Android video decoder'),
            trailing: Icon(Icons.check_circle_rounded, color: Colors.green),
          ),
        ],
      ),
    );
  }
}
