import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../../core/database/hive_boxes.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/audio_card.dart';
import '../../core/widgets/empty_state.dart';
import '../../core/widgets/video_card.dart';
import '../../models/audio_model.dart';
import '../../models/video_model.dart';
import '../../providers/app_providers.dart';
import '../../routes/app_router.dart';
import 'pin_screens.dart';

/// Entry point for the Safe Media tab. Shows first-run setup if no PIN
/// exists yet, otherwise requires PIN/biometric unlock before revealing the
/// vault content — hidden items never render anywhere in this flow until
/// the user authenticates.
class SafeMediaGate extends ConsumerStatefulWidget {
  const SafeMediaGate({super.key});

  @override
  ConsumerState<SafeMediaGate> createState() => _SafeMediaGateState();
}

class _SafeMediaGateState extends ConsumerState<SafeMediaGate> {
  bool? _hasPin;
  bool _unlocked = false;

  @override
  void initState() {
    super.initState();
    _checkPin();
  }

  Future<void> _checkPin() async {
    final has = await ref.read(safeMediaRepositoryProvider).hasPinSet();
    if (mounted) setState(() => _hasPin = has);
  }

  @override
  Widget build(BuildContext context) {
    if (_hasPin == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (!_hasPin!) {
      final palette = Theme.of(context).extension<PrismPalette>()!;
      return Scaffold(
        appBar: AppBar(title: const Text('Safe Media')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.shield_rounded, size: 56, color: palette.accent),
                const SizedBox(height: 16),
                Text('Protect your private videos and songs', style: TextStyle(color: palette.textPrimary, fontWeight: FontWeight.w700, fontSize: 17), textAlign: TextAlign.center),
                const SizedBox(height: 8),
                Text('Set a PIN to hide media from Home, Videos, Music and Search.', style: TextStyle(color: palette.textMuted), textAlign: TextAlign.center),
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: () async {
                    final result = await context.push('${AppRoutes.safeMedia}/setup-pin');
                    if (result == true) _checkPin();
                  },
                  child: const Text('Set up Safe Media'),
                ),
              ],
            ),
          ),
        ),
      );
    }
    if (!_unlocked) {
      return UnlockPinScreen(onUnlocked: () => setState(() => _unlocked = true));
    }
    return const _SafeMediaVault();
  }
}

class _SafeMediaVault extends ConsumerWidget {
  const _SafeMediaVault();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.watch(mediaRepositoryProvider);

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Safe Media'),
          bottom: const TabBar(tabs: [Tab(text: 'Videos'), Tab(text: 'Songs')]),
        ),
        body: AnimatedBuilder(
          animation: Listenable.merge([
            Hive.box<VideoModel>(HiveBoxes.videos).listenable(),
            Hive.box<AudioModel>(HiveBoxes.audio).listenable(),
          ]),
          builder: (context, _) {
            final hiddenVideos = repo.hiddenVideos;
            final hiddenAudio = repo.hiddenAudio;
            return TabBarView(
              children: [
                hiddenVideos.isEmpty
                    ? const EmptyState(icon: Icons.visibility_off_outlined, title: 'No hidden videos')
                    : GridView.builder(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 120),
                        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2, mainAxisSpacing: 14, crossAxisSpacing: 14, childAspectRatio: 0.82,
                        ),
                        itemCount: hiddenVideos.length,
                        itemBuilder: (context, i) => VideoCard(
                          video: hiddenVideos[i],
                          onTap: () async {
                            await ref.read(globalPlayerControllerProvider.notifier).playVideo(hiddenVideos[i]);
                            if (context.mounted) context.push(AppRoutes.videoPlayer);
                          },
                          onMore: () => repo.setVideoHidden(hiddenVideos[i].id, false),
                        ),
                      ),
                hiddenAudio.isEmpty
                    ? const EmptyState(icon: Icons.visibility_off_outlined, title: 'No hidden songs')
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 120),
                        itemCount: hiddenAudio.length,
                        itemBuilder: (context, i) => AudioCard(
                          audio: hiddenAudio[i],
                          onTap: () async {
                            await ref.read(globalPlayerControllerProvider.notifier).playAudio(hiddenAudio[i]);
                            if (context.mounted) context.push(AppRoutes.audioPlayer);
                          },
                          trailing: IconButton(
                            icon: const Icon(Icons.visibility_rounded),
                            tooltip: 'Unhide',
                            onPressed: () => repo.setAudioHidden(hiddenAudio[i].id, false),
                          ),
                        ),
                      ),
              ],
            );
          },
        ),
      ),
    );
  }
}
