import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/permissions/permission_service.dart';
import '../../core/services/storage_scan_service.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../providers/app_providers.dart';

/// Full-storage scan with a live progress readout: how many files have been
/// scanned so far, how many turned out to be media, and what percentage of
/// the device's used storage that represents.
class StorageScanScreen extends ConsumerStatefulWidget {
  const StorageScanScreen({super.key});

  @override
  ConsumerState<StorageScanScreen> createState() => _StorageScanScreenState();
}

class _StorageScanScreenState extends ConsumerState<StorageScanScreen> {
  StreamSubscription<StorageScanProgress>? _sub;
  StorageScanProgress? _progress;
  bool _done = false;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _start());
  }

  Future<void> _start() async {
    setState(() {
      _error = null;
      _done = false;
      _progress = null;
    });

    final hasPermission = await PermissionService().hasMediaPermissions();
    if (!hasPermission) {
      final granted = await PermissionService().requestMediaPermissions();
      if (!granted) {
        setState(() => _error = 'Media permission is required to scan your storage.');
        return;
      }
    }

    _sub?.cancel();
    _sub = ref.read(storageScanServiceProvider).scan().listen(
      (event) async {
        if (!mounted) return;
        setState(() => _progress = event);
        if (event.isComplete) {
          setState(() => _saving = true);
          await ref.read(mediaRepositoryProvider).applyScanResult(event.videos, event.audio);
          if (!mounted) return;
          setState(() {
            _saving = false;
            _done = true;
          });
        }
      },
      onError: (e) {
        if (!mounted) return;
        setState(() => _error = 'Scan failed: $e');
      },
    );
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = Theme.of(context).extension<PrismPalette>()!;
    final p = _progress;

    return Scaffold(
      appBar: AppBar(title: const Text('Scan Storage')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (_error != null) ...[
                  Icon(Icons.error_outline_rounded, size: 56, color: palette.error),
                  const SizedBox(height: 16),
                  Text(_error!, textAlign: TextAlign.center, style: TextStyle(color: palette.textPrimary)),
                  const SizedBox(height: 20),
                  ElevatedButton(onPressed: _start, child: const Text('Try again')),
                ] else ...[
                  SizedBox(
                    width: 140,
                    height: 140,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        SizedBox(
                          width: 140,
                          height: 140,
                          child: CircularProgressIndicator(
                            value: _done ? 1.0 : (p?.percentFiles ?? 0) / 100,
                            strokeWidth: 8,
                            backgroundColor: palette.surface,
                            valueColor: AlwaysStoppedAnimation(palette.accent),
                          ),
                        ),
                        Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              '${(_done ? 100 : (p?.percentFiles ?? 0)).toStringAsFixed(0)}%',
                              style: TextStyle(
                                color: palette.textPrimary,
                                fontSize: 28,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            Text(
                              _done ? 'Done' : 'Scanning',
                              style: TextStyle(color: palette.textMuted, fontSize: 12),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 28),
                  Text(
                    _done
                        ? 'Scan complete'
                        : (_saving ? 'Saving to library…' : 'Scanning device storage…'),
                    style: TextStyle(
                      color: palette.textPrimary,
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 20),
                  _StatRow(
                    label: 'Files scanned',
                    value: p == null
                        ? '—'
                        : '${p.filesScanned} / ${p.totalFiles}',
                    palette: palette,
                  ),
                  const SizedBox(height: 10),
                  _StatRow(
                    label: 'Media found',
                    value: p == null ? '—' : '${p.mediaFound}',
                    palette: palette,
                  ),
                  const SizedBox(height: 10),
                  _StatRow(
                    label: 'Storage scanned',
                    value: p == null
                        ? '—'
                        : '${Formatters.fileSize(p.bytesScanned)} of ${Formatters.fileSize(p.totalStorageBytes)}'
                            ' (${p.percentStorage.toStringAsFixed(1)}%)',
                    palette: palette,
                  ),
                  if (p != null && p.currentName.isNotEmpty && !_done) ...[
                    const SizedBox(height: 16),
                    Text(
                      p.currentName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: palette.textMuted, fontSize: 12),
                    ),
                  ],
                  const SizedBox(height: 32),
                  if (_done)
                    ElevatedButton(
                      onPressed: () => context.pop(),
                      child: const Text('Done'),
                    ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _StatRow extends StatelessWidget {
  final String label;
  final String value;
  final PrismPalette palette;
  const _StatRow({required this.label, required this.value, required this.palette});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: TextStyle(color: palette.textMuted, fontSize: 14)),
        Text(value, style: TextStyle(color: palette.textPrimary, fontSize: 14, fontWeight: FontWeight.w600)),
      ],
    );
  }
}
