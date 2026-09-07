import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:path_provider/path_provider.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/media_bottom_sheet.dart';
import '../../../providers/app_providers.dart';
import '../../../routes/app_router.dart';
import '../widgets/settings_tile.dart';

class StorageSettingsScreen extends ConsumerStatefulWidget {
  const StorageSettingsScreen({super.key});

  @override
  ConsumerState<StorageSettingsScreen> createState() => _StorageSettingsScreenState();
}

class _StorageSettingsScreenState extends ConsumerState<StorageSettingsScreen> {
  int _cacheBytes = 0;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadCacheSize();
  }

  Future<void> _loadCacheSize() async {
    final dir = await getTemporaryDirectory();
    int total = 0;
    if (await dir.exists()) {
      await for (final entity in dir.list(recursive: true, followLinks: false)) {
        if (entity is File) {
          try {
            total += await entity.length();
          } catch (_) {}
        }
      }
    }
    if (mounted) setState(() {
      _cacheBytes = total;
      _loading = false;
    });
  }

  Future<void> _clearCache() async {
    final dir = await getTemporaryDirectory();
    if (await dir.exists()) {
      try {
        await dir.delete(recursive: true);
        await dir.create();
      } catch (_) {}
    }
    await _loadCacheSize();
  }

  @override
  Widget build(BuildContext context) {
    final repo = ref.read(mediaRepositoryProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Storage')),
      body: ListView(
        children: [
          SettingsSectionLabel('Library'),
          ListTile(
            title: const Text('Videos'),
            trailing: Text('${repo.allVideos.length} files · ${Formatters.fileSize(repo.allVideos.fold<int>(0, (a, v) => a + v.sizeBytes))}'),
          ),
          ListTile(
            title: const Text('Songs'),
            trailing: Text('${repo.allAudio.length} files · ${Formatters.fileSize(repo.allAudio.fold<int>(0, (a, v) => a + v.sizeBytes))}'),
          ),
          SettingsSectionLabel('Cache'),
          ListTile(
            title: const Text('Thumbnail & temp cache'),
            subtitle: Text(_loading ? 'Calculating…' : Formatters.fileSize(_cacheBytes)),
            trailing: TextButton(
              onPressed: () async {
                final confirmed = await showConfirmDialog(
                    context: context, title: 'Clear cache', message: 'This clears cached video thumbnails. They will be regenerated as needed.',
                    confirmLabel: 'Clear', destructive: false);
                if (confirmed == true) await _clearCache();
              },
              child: const Text('Clear'),
            ),
          ),
          SettingsActionTile(
            icon: Icons.refresh_rounded,
            title: 'Rescan media',
            subtitle: 'Full rescan with live progress',
            onTap: () => context.push(AppRoutes.scanStorage),
          ),
        ],
      ),
    );
  }
}
