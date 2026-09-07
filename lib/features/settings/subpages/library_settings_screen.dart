import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../providers/app_providers.dart';
import '../widgets/settings_tile.dart';

class LibrarySettingsScreen extends ConsumerStatefulWidget {
  const LibrarySettingsScreen({super.key});

  @override
  ConsumerState<LibrarySettingsScreen> createState() => _LibrarySettingsScreenState();
}

class _LibrarySettingsScreenState extends ConsumerState<LibrarySettingsScreen> {
  bool _scanning = false;

  @override
  Widget build(BuildContext context) {
    final settings = ref.read(settingsRepositoryProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Library')),
      body: ListView(
        children: [
          SettingsActionTile(
            icon: Icons.refresh_rounded,
            title: 'Scan media',
            subtitle: _scanning ? 'Scanning…' : 'Rescan device storage for new videos and songs',
            onTap: () async {
              setState(() => _scanning = true);
              await ref.read(mediaRepositoryProvider).scan(fullRescan: true);
              if (mounted) setState(() => _scanning = false);
            },
          ),
          SettingsSwitchTile(
            title: 'Grid view by default',
            subtitle: 'Use a grid instead of a list on Videos',
            value: settings.gridViewDefault,
            onChanged: (v) => setState(() => settings.gridViewDefault = v),
          ),
          const ListTile(
            title: Text('Excluded folders'),
            subtitle: Text('Manage which folders are hidden from Videos/Music (use "Hide folder" from the Folders tab)'),
          ),
        ],
      ),
    );
  }
}
