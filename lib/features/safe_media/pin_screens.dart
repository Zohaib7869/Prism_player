import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_theme.dart';
import '../../providers/app_providers.dart';

/// First-run Safe Media setup: choose a 4-6 digit PIN, then confirm it.
/// The PIN itself is never stored — only its salted SHA-256 hash, via
/// SafeMediaRepository -> SecureStorageService.
class SetupPinScreen extends ConsumerStatefulWidget {
  const SetupPinScreen({super.key});

  @override
  ConsumerState<SetupPinScreen> createState() => _SetupPinScreenState();
}

class _SetupPinScreenState extends ConsumerState<SetupPinScreen> {
  String _firstEntry = '';
  String _current = '';
  bool _confirming = false;
  String? _error;

  Future<void> _submit() async {
    if (_current.length < 4) {
      setState(() => _error = 'PIN must be at least 4 digits');
      return;
    }
    if (!_confirming) {
      setState(() {
        _firstEntry = _current;
        _current = '';
        _confirming = true;
      });
      return;
    }
    if (_current != _firstEntry) {
      setState(() {
        _error = 'PINs did not match — try again';
        _current = '';
        _confirming = false;
        _firstEntry = '';
      });
      return;
    }
    await ref.read(safeMediaRepositoryProvider).setPin(_current);
    if (mounted) context.pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final palette = Theme.of(context).extension<PrismPalette>()!;
    return Scaffold(
      appBar: AppBar(title: Text(_confirming ? 'Confirm PIN' : 'Create a PIN')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            Text(
              _confirming ? 'Re-enter your PIN to confirm' : 'This PIN protects your hidden videos and songs',
              style: TextStyle(color: palette.textMuted),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(6, (i) {
                final filled = i < _current.length;
                return Container(
                  margin: const EdgeInsets.symmetric(horizontal: 6),
                  width: 16,
                  height: 16,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: filled ? palette.accent : palette.divider,
                  ),
                );
              }),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: TextStyle(color: palette.error)),
            ],
            const SizedBox(height: 32),
            _NumericKeypad(
              onDigit: (d) => setState(() {
                if (_current.length < 6) _current += d;
                _error = null;
              }),
              onBackspace: () => setState(() {
                if (_current.isNotEmpty) _current = _current.substring(0, _current.length - 1);
              }),
              onSubmit: _submit,
            ),
          ],
        ),
      ),
    );
  }
}

/// PIN entry used to unlock the vault once a PIN already exists.
class UnlockPinScreen extends ConsumerStatefulWidget {
  final VoidCallback onUnlocked;
  const UnlockPinScreen({super.key, required this.onUnlocked});

  @override
  ConsumerState<UnlockPinScreen> createState() => _UnlockPinScreenState();
}

class _UnlockPinScreenState extends ConsumerState<UnlockPinScreen> {
  String _current = '';
  String? _error;
  bool _checkingBiometric = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _tryBiometric());
  }

  Future<void> _tryBiometric({bool silent = true}) async {
    if (_checkingBiometric) return;
    final safeRepo = ref.read(safeMediaRepositoryProvider);
    if (!safeRepo.isBiometricEnabled) return;
    if (!await safeRepo.isBiometricAvailable()) {
      // Silent auto-attempt (screen just opened) stays silent so we don't
      // nag every time; the explicit "Use biometrics" tap tells the user why
      // nothing is happening instead of doing nothing visibly.
      if (!silent && mounted) {
        setState(() => _error = 'Biometric unlock isn\'t available on this device.');
      }
      return;
    }
    setState(() => _checkingBiometric = true);
    final ok = await safeRepo.authenticateWithBiometrics();
    setState(() => _checkingBiometric = false);
    if (ok) {
      widget.onUnlocked();
    } else if (!silent && safeRepo.lastAuthError != null) {
      setState(() => _error = safeRepo.lastAuthError);
    }
  }

  Future<void> _submit() async {
    final safeRepo = ref.read(safeMediaRepositoryProvider);
    final ok = await safeRepo.verifyPin(_current);
    if (ok) {
      widget.onUnlocked();
    } else {
      setState(() {
        _error = 'Incorrect PIN';
        _current = '';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = Theme.of(context).extension<PrismPalette>()!;
    final safeRepo = ref.read(safeMediaRepositoryProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Safe Media')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            Icon(Icons.lock_rounded, size: 40, color: palette.accent),
            const SizedBox(height: 12),
            Text('Enter your PIN to continue', style: TextStyle(color: palette.textMuted)),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(6, (i) {
                final filled = i < _current.length;
                return Container(
                  margin: const EdgeInsets.symmetric(horizontal: 6),
                  width: 16,
                  height: 16,
                  decoration: BoxDecoration(shape: BoxShape.circle, color: filled ? palette.accent : palette.divider),
                );
              }),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: TextStyle(color: palette.error)),
            ],
            if (_checkingBiometric) ...[
              const SizedBox(height: 12),
              Text('Waiting for biometric confirmation…', style: TextStyle(color: palette.textMuted, fontSize: 12)),
            ],
            const SizedBox(height: 32),
            _NumericKeypad(
              onDigit: (d) => setState(() {
                if (_current.length < 6) _current += d;
                _error = null;
              }),
              onBackspace: () => setState(() {
                if (_current.isNotEmpty) _current = _current.substring(0, _current.length - 1);
              }),
              onSubmit: _submit,
            ),
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: () => _tryBiometric(silent: false),
              icon: const Icon(Icons.fingerprint_rounded),
              label: const Text('Use biometrics'),
            ),
          ],
        ),
      ),
    );
  }
}

class _NumericKeypad extends StatelessWidget {
  final ValueChanged<String> onDigit;
  final VoidCallback onBackspace;
  final VoidCallback onSubmit;
  const _NumericKeypad({required this.onDigit, required this.onBackspace, required this.onSubmit});

  @override
  Widget build(BuildContext context) {
    final palette = Theme.of(context).extension<PrismPalette>()!;
    final keys = ['1', '2', '3', '4', '5', '6', '7', '8', '9', '', '0', 'back'];
    return Column(
      children: [
        GridView.count(
          crossAxisCount: 3,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          childAspectRatio: 1.6,
          children: keys.map((k) {
            if (k.isEmpty) return const SizedBox.shrink();
            if (k == 'back') {
              return IconButton(
                icon: Icon(Icons.backspace_outlined, color: palette.textPrimary),
                onPressed: () {
                  HapticFeedback.selectionClick();
                  onBackspace();
                },
              );
            }
            return TextButton(
              onPressed: () {
                HapticFeedback.selectionClick();
                onDigit(k);
              },
              child: Text(k, style: TextStyle(fontSize: 22, color: palette.textPrimary)),
            );
          }).toList(),
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: FilledButton(onPressed: onSubmit, child: const Text('Continue')),
        ),
      ],
    );
  }
}
