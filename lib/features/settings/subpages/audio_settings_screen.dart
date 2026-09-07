import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../providers/app_providers.dart';
import '../../../routes/app_router.dart';
import '../widgets/settings_tile.dart';

class AudioSettingsScreen extends ConsumerStatefulWidget {
  const AudioSettingsScreen({super.key});

  @override
  ConsumerState<AudioSettingsScreen> createState() => _AudioSettingsScreenState();
}

class _AudioSettingsScreenState extends ConsumerState<AudioSettingsScreen> {
  @override
  Widget build(BuildContext context) {
    final settings = ref.read(settingsRepositoryProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Audio')),
      body: ListView(
        children: [
          SettingsActionTile(
            icon: Icons.equalizer_rounded,
            title: 'Equalizer',
            subtitle: 'Presets, 10-band EQ, bass boost, virtualizer',
            onTap: () => context.push(AppRoutes.equalizer),
          ),
          SettingsSwitchTile(
            title: 'Gapless playback',
            subtitle: 'Minimize silence between tracks in a queue',
            value: settings.gaplessPlayback,
            onChanged: (v) => setState(() => settings.gaplessPlayback = v),
          ),
          const ListTile(
            leading: Icon(Icons.info_outline_rounded),
            title: Text('Audio normalization'),
            subtitle: Text('Not included in this build — see README for details.'),
          ),
        ],
      ),
    );
  }
}
