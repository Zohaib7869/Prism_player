import 'package:flutter/material.dart';

import '../../../core/utils/subtitle_parser.dart';

class SubtitleOverlay extends StatelessWidget {
  final List<SubtitleCue> cues;
  final Duration position;
  final int delayMs;
  final double fontSize;
  final Color color;
  final bool background;

  const SubtitleOverlay({
    super.key,
    required this.cues,
    required this.position,
    this.delayMs = 0,
    this.fontSize = 18,
    this.color = Colors.white,
    this.background = true,
  });

  @override
  Widget build(BuildContext context) {
    if (cues.isEmpty) return const SizedBox.shrink();
    final adjusted = position + Duration(milliseconds: delayMs);
    final cue = cues.cast<SubtitleCue?>().firstWhere(
          (c) => adjusted >= c!.start && adjusted <= c.end,
          orElse: () => null,
        );
    if (cue == null) return const SizedBox.shrink();

    return Positioned(
      left: 24,
      right: 24,
      bottom: 90,
      child: IgnorePointer(
        child: Center(
          child: Container(
            padding: background ? const EdgeInsets.symmetric(horizontal: 10, vertical: 4) : EdgeInsets.zero,
            decoration: background
                ? BoxDecoration(color: Colors.black.withOpacity(0.6), borderRadius: BorderRadius.circular(6))
                : null,
            child: Text(
              cue.text,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: color,
                fontSize: fontSize,
                fontWeight: FontWeight.w600,
                shadows: background ? null : const [Shadow(color: Colors.black, blurRadius: 6)],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
