import 'package:flutter/material.dart';

import '../../../core/utils/formatters.dart';

class PlayerControlsOverlay extends StatelessWidget {
  final String title;
  final bool isPlaying;
  final bool isBuffering;
  final bool locked;
  final Duration position;
  final Duration duration;
  final VoidCallback onBack;
  final VoidCallback onPlayPause;
  final VoidCallback onSkipNext;
  final VoidCallback onSkipPrevious;
  final bool hasNext;
  final bool hasPrevious;
  final ValueChanged<Duration> onSeek;
  final VoidCallback onLockToggle;
  final VoidCallback onMore;
  final VoidCallback onPlayAsAudio;
  final VoidCallback onFullscreenToggle;
  final bool isFullscreen;

  const PlayerControlsOverlay({
    super.key,
    required this.title,
    required this.isPlaying,
    required this.isBuffering,
    required this.locked,
    required this.position,
    required this.duration,
    required this.onBack,
    required this.onPlayPause,
    required this.onSkipNext,
    required this.onSkipPrevious,
    required this.hasNext,
    required this.hasPrevious,
    required this.onSeek,
    required this.onLockToggle,
    required this.onMore,
    required this.onPlayAsAudio,
    required this.onFullscreenToggle,
    required this.isFullscreen,
  });

  @override
  Widget build(BuildContext context) {
    if (locked) {
      return Align(
        alignment: Alignment.centerLeft,
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: _RoundIconButton(icon: Icons.lock_rounded, onTap: onLockToggle),
          ),
        ),
      );
    }

    // IMPORTANT: the scrim gradient is painted by a Container with a
    // `decoration`, and Flutter's DecoratedBox intercepts hit-testing across
    // its *entire* area even where it paints fully transparent pixels — a
    // single Container wrapping both the gradient and the real controls used
    // to swallow every tap/drag over its empty middle section (between the
    // top bar and bottom bar), which is exactly where VideoGestureLayer's
    // brightness/volume/seek gestures need to land. That's why gestures only
    // ever worked once this overlay was hidden entirely (IgnorePointer'd)
    // instead of just tapping through its empty space while visible.
    //
    // Fix: paint the gradient in its own IgnorePointer'd layer (purely
    // visual, never hit-tested) and keep the actual interactive controls in
    // a separate, undecorated Column on top of it. A plain Column/Spacer has
    // no hit-testable area of its own, so taps over the empty middle now
    // correctly fall through to whatever is beneath this overlay in the
    // Stack, while the top bar / center transport / bottom bar buttons still
    // receive their taps normally.
    return Stack(
      children: [
        Positioned.fill(
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withOpacity(0.65),
                    Colors.transparent,
                    Colors.transparent,
                    Colors.black.withOpacity(0.75),
                  ],
                  stops: const [0, 0.25, 0.7, 1],
                ),
              ),
            ),
          ),
        ),
        SafeArea(
          child: Column(
            children: [
            // Top bar
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Row(
                children: [
                  IconButton(icon: const Icon(Icons.arrow_back_rounded, color: Colors.white), onPressed: onBack),
                  Expanded(
                    child: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 15)),
                  ),
                  IconButton(icon: const Icon(Icons.headphones_rounded, color: Colors.white), onPressed: onPlayAsAudio, tooltip: 'Play as Audio'),
                  IconButton(icon: const Icon(Icons.lock_open_rounded, color: Colors.white), onPressed: onLockToggle),
                  IconButton(icon: const Icon(Icons.more_vert_rounded, color: Colors.white), onPressed: onMore),
                ],
              ),
            ),
            const Spacer(),
            // Center transport controls
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _RoundIconButton(icon: Icons.skip_previous_rounded, onTap: hasPrevious ? onSkipPrevious : null, size: 40),
                const SizedBox(width: 28),
                _RoundIconButton(
                  icon: isBuffering ? null : (isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded),
                  loading: isBuffering,
                  onTap: onPlayPause,
                  size: 64,
                  filled: true,
                ),
                const SizedBox(width: 28),
                _RoundIconButton(icon: Icons.skip_next_rounded, onTap: hasNext ? onSkipNext : null, size: 40),
              ],
            ),
            const Spacer(),
            // Bottom bar: scrubber + time + fullscreen
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              child: Row(
                children: [
                  Text(Formatters.duration(position.inMilliseconds), style: const TextStyle(color: Colors.white, fontSize: 12)),
                  Expanded(
                    child: SliderTheme(
                      data: SliderTheme.of(context).copyWith(
                        trackHeight: 2.5,
                        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                        overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
                      ),
                      child: Slider(
                        value: position.inMilliseconds.clamp(0, duration.inMilliseconds == 0 ? 1 : duration.inMilliseconds).toDouble(),
                        min: 0,
                        max: duration.inMilliseconds == 0 ? 1 : duration.inMilliseconds.toDouble(),
                        activeColor: Colors.white,
                        inactiveColor: Colors.white24,
                        onChanged: (v) => onSeek(Duration(milliseconds: v.round())),
                      ),
                    ),
                  ),
                  Text(Formatters.duration(duration.inMilliseconds), style: const TextStyle(color: Colors.white, fontSize: 12)),
                  IconButton(
                    icon: Icon(isFullscreen ? Icons.fullscreen_exit_rounded : Icons.fullscreen_rounded, color: Colors.white),
                    onPressed: onFullscreenToggle,
                  ),
                ],
              ),
            ),
          ],
          ),
        ),
      ],
    );
  }
}

class _RoundIconButton extends StatelessWidget {
  final IconData? icon;
  final VoidCallback? onTap;
  final double size;
  final bool filled;
  final bool loading;
  const _RoundIconButton({required this.icon, required this.onTap, this.size = 44, this.filled = false, this.loading = false});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: filled ? Colors.white.withOpacity(0.15) : Colors.transparent,
      shape: const CircleBorder(),
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: SizedBox(
          width: size,
          height: size,
          child: loading
              ? const Padding(
                  padding: EdgeInsets.all(16),
                  child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5),
                )
              : Icon(icon, color: onTap == null ? Colors.white38 : Colors.white, size: size * 0.55),
        ),
      ),
    );
  }
}
