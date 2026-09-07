import 'package:flutter/material.dart';

import '../../../core/utils/formatters.dart';

/// Transient on-screen-display shown while dragging: a brightness or volume
/// gauge on vertical drags, or a "current -> target" time readout while
/// scrubbing horizontally. Purely visual, driven by VideoPlayerScreen's state.
class GestureOsd extends StatelessWidget {
  final double? brightness;
  final double? volume;
  final Duration? seekPosition;
  final Duration totalDuration;

  const GestureOsd({super.key, this.brightness, this.volume, this.seekPosition, required this.totalDuration});

  @override
  Widget build(BuildContext context) {
    if (brightness != null) {
      return _GaugeOsd(icon: Icons.brightness_6_rounded, value: brightness!, alignment: Alignment.center);
    }
    if (volume != null) {
      return _GaugeOsd(icon: Icons.volume_up_rounded, value: volume!, alignment: Alignment.center);
    }
    if (seekPosition != null) {
      return Center(
        child: IgnorePointer(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(color: Colors.black.withOpacity(0.7), borderRadius: BorderRadius.circular(10)),
            child: Text(
              '${Formatters.duration(seekPosition!.inMilliseconds)} / ${Formatters.duration(totalDuration.inMilliseconds)}',
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
            ),
          ),
        ),
      );
    }
    return const SizedBox.shrink();
  }
}

class _GaugeOsd extends StatelessWidget {
  final IconData icon;
  final double value;
  final Alignment alignment;
  const _GaugeOsd({required this.icon, required this.value, required this.alignment});

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: alignment,
      child: IgnorePointer(
        child: Container(
          width: 96,
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
          decoration: BoxDecoration(color: Colors.black.withOpacity(0.7), borderRadius: BorderRadius.circular(14)),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: Colors.white, size: 22),
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: LinearProgressIndicator(value: value, minHeight: 5, backgroundColor: Colors.white24, valueColor: const AlwaysStoppedAnimation(Colors.white)),
              ),
              const SizedBox(height: 6),
              Text('${(value * 100).round()}%', style: const TextStyle(color: Colors.white, fontSize: 11)),
            ],
          ),
        ),
      ),
    );
  }
}
