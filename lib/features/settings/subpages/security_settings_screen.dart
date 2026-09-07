import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/media_bottom_sheet.dart';
import '../../../providers/app_providers.dart';
import '../../../routes/app_router.dart';
import '../widgets/settings_tile.dart';

class SecuritySettingsScreen extends ConsumerStatefulWidget {
  const SecuritySettingsScreen({super.key});

  @override
  ConsumerState<SecuritySettingsScreen> createState() => _SecuritySettingsScreenState();
}

class _SecuritySettingsScreenState extends ConsumerState<SecuritySettingsScreen> {
  bool _hasPin = false;
  bool _biometricAvailable = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final repo = ref.read(safeMediaRepositoryProvider);
    final hasPin = await repo.hasPinSet();
    final bioAvailable = await repo.isBiometricAvailable();
    if (mounted) setState(() {
      _hasPin = hasPin;
      _biometricAvailable = bioAvailable;
    });
  }

  @override
  Widget build(BuildContext context) {
    final palette = Theme.of(context).extension<PrismPalette>()!;
    final safeRepo = ref.read(safeMediaRepositoryProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Security')),
      body: ListView(
        children: [
          SettingsSectionLabel('Safe Media'),
          ListTile(
            leading: Icon(Icons.lock_rounded, color: palette.accent),
            title: Text(_hasPin ? 'Change PIN' : 'Set up PIN'),
            subtitle: Text(_hasPin ? 'A PIN is currently set' : 'No PIN set yet — Safe Media is disabled'),
            onTap: () async {
              if (!_hasPin) {
                final result = await context.push<bool>('${AppRoutes.safeMedia}/setup-pin');
                if (result == true) _load();
                return;
              }
              final currentPin = await showTextInputDialog(context: context, title: 'Current PIN', initialValue: '', hint: 'Enter current PIN');
              if (currentPin == null || currentPin.isEmpty) return;
              final newPin = await showTextInputDialog(context: context, title: 'New PIN', initialValue: '', hint: 'Enter new PIN');
              if (newPin == null || newPin.isEmpty) return;
              try {
                await safeRepo.changePin(currentPin, newPin);
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('PIN updated')));
                }
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
                }
              }
            },
          ),
          SettingsSwitchTile(
            title: 'Biometric unlock',
            subtitle: _biometricAvailable ? 'Use fingerprint/face unlock for Safe Media' : 'Not available on this device',
            value: safeRepo.isBiometricEnabled,
            onChanged: _biometricAvailable && _hasPin
                ? (v) => setState(() => safeRepo.isBiometricEnabled = v)
                : null,
          ),
          if (_hasPin)
            SettingsActionTile(
              icon: Icons.lock_open_rounded,
              title: 'Disable Safe Media',
              subtitle: 'Removes the PIN and unhides all Safe Media items',
              destructive: true,
              onTap: () async {
                final currentPin = await showTextInputDialog(context: context, title: 'Confirm PIN', initialValue: '', hint: 'Enter current PIN');
                if (currentPin == null || currentPin.isEmpty) return;
                try {
                  await safeRepo.disableSafeMedia(currentPin);
                  if (mounted) setState(() => _hasPin = false);
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
                  }
                }
              },
            ),
        ],
      ),
    );
  }
}
