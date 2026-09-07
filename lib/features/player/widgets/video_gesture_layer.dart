import 'package:flutter/material.dart';

/// Full-screen gesture surface layered over the video, implementing the
/// standard modern-player gesture set:
///  - vertical drag, left half  -> screen brightness
///  - vertical drag, right half -> playback volume
///  - horizontal drag           -> seek scrubbing (shows a delta overlay,
///                                  actual seek happens on release)
///  - double tap left / right   -> rewind / forward by [doubleTapSeekSeconds]
///  - double tap center         -> play/pause
///  - single tap                -> toggle the controls overlay
///
/// All gestures can be disabled via [enabled] (Settings > Gesture controls).
class VideoGestureLayer extends StatefulWidget {
  final Widget child;
  final bool enabled;
  final bool locked;
  final int doubleTapSeekSeconds;
  final ValueChanged<double> onBrightnessDelta; // -1..1 fraction of screen height dragged
  final ValueChanged<double> onVolumeDelta;
  final void Function(double deltaFraction) onSeekPreview; // called continuously during drag
  final VoidCallback onSeekEnd;
  final VoidCallback onDoubleTapRewind;
  final VoidCallback onDoubleTapForward;
  final VoidCallback onDoubleTapPlayPause;
  final VoidCallback onSingleTap;

  const VideoGestureLayer({
    super.key,
    required this.child,
    required this.enabled,
    required this.locked,
    required this.doubleTapSeekSeconds,
    required this.onBrightnessDelta,
    required this.onVolumeDelta,
    required this.onSeekPreview,
    required this.onSeekEnd,
    required this.onDoubleTapRewind,
    required this.onDoubleTapForward,
    required this.onDoubleTapPlayPause,
    required this.onSingleTap,
  });

  @override
  State<VideoGestureLayer> createState() => _VideoGestureLayerState();
}

class _VideoGestureLayerState extends State<VideoGestureLayer> {
  Offset? _dragStart;
  bool _isHorizontalDrag = false;

  @override
  Widget build(BuildContext context) {
    if (widget.locked) {
      // Only a single tap (to reveal the unlock button) is allowed while locked.
      return GestureDetector(onTap: widget.onSingleTap, child: widget.child);
    }
    if (!widget.enabled) {
      return GestureDetector(onTap: widget.onSingleTap, child: widget.child);
    }

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: widget.onSingleTap,
      onDoubleTapDown: (details) => _dragStart = details.localPosition,
      onDoubleTap: () {
        final width = context.size?.width ?? 0;
        final x = _dragStart?.dx ?? width / 2;
        if (x < width / 3) {
          widget.onDoubleTapRewind();
        } else if (x > width * 2 / 3) {
          widget.onDoubleTapForward();
        } else {
          widget.onDoubleTapPlayPause();
        }
      },
      onVerticalDragStart: (details) {
        _dragStart = details.localPosition;
      },
      onVerticalDragUpdate: (details) {
        final size = context.size;
        if (size == null || _dragStart == null) return;
        final isLeftHalf = _dragStart!.dx < size.width / 2;
        final fraction = -details.delta.dy / size.height;
        if (isLeftHalf) {
          widget.onBrightnessDelta(fraction);
        } else {
          widget.onVolumeDelta(fraction);
        }
      },
      onHorizontalDragStart: (details) {
        _dragStart = details.localPosition;
        _isHorizontalDrag = true;
      },
      onHorizontalDragUpdate: (details) {
        final size = context.size;
        if (size == null || !_isHorizontalDrag) return;
        widget.onSeekPreview(details.delta.dx / size.width);
      },
      onHorizontalDragEnd: (_) {
        _isHorizontalDrag = false;
        widget.onSeekEnd();
      },
      child: widget.child,
    );
  }
}
