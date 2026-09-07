import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../services/audio_visualizer_service.dart';
import '../theme/app_theme.dart';
import 'media_thumbnail.dart';

/// Resamples [source] (any length) into exactly [count] values by linear
/// interpolation, so a single 32-bar native capture can drive bar rows of
/// any width (4 mini bars, 28 wide bars, 48 ring bars) without the native
/// side needing to know how any particular widget will draw it.
List<double> _resample(List<double> source, int count) {
  if (source.isEmpty) return List.filled(count, 0);
  if (source.length == count) return source;
  return List.generate(count, (i) {
    final pos = (i / count) * (source.length - 1);
    final lo = pos.floor().clamp(0, source.length - 1);
    final hi = pos.ceil().clamp(0, source.length - 1);
    final frac = pos - lo;
    return source[lo] + (source[hi] - source[lo]) * frac;
  });
}

/// Like [_resample], but mirrors the result around the center instead of
/// sweeping linearly low-frequency-to-high-frequency across the whole
/// width. Native FFT data is naturally bass-heavy at bar 0 and treble-thin
/// at the last bar, so a plain linear resample always makes one edge look
/// tall and the other look short. Mirroring means both outer edges are
/// driven by the *same* underlying bins, so they always read the same
/// height — the symmetric "butterfly" look most spectrum visualizers
/// (PlayIt included) use.
List<double> _mirrorResample(List<double> source, int count) {
  if (count <= 1) return _resample(source, count);
  final half = (count / 2).ceil();
  final halfValues = _resample(source, half);
  return List.generate(count, (i) {
    final mirrored = i < half ? i : count - 1 - i;
    return halfValues[mirrored.clamp(0, half - 1)];
  });
}

/// Subscribes to the native real-time audio visualizer stream (see
/// [AudioVisualizerService]) and rebuilds [builder] with the latest bars.
/// Passes `null` to [builder] whenever there's no live data to show — either
/// nothing has arrived yet, or it's gone stale (session detached, paused,
/// or currently on video/iOS where no native session is attached) — so
/// callers can fall back to a simulated look instead of freezing on old data.
class _LiveLevels extends StatefulWidget {
  final Widget Function(BuildContext context, List<double>? bars) builder;
  const _LiveLevels({required this.builder});

  @override
  State<_LiveLevels> createState() => _LiveLevelsState();
}

class _LiveLevelsState extends State<_LiveLevels> {
  StreamSubscription<List<double>>? _sub;
  List<double>? _bars;
  Timer? _staleTimer;

  @override
  void initState() {
    super.initState();
    _sub = AudioVisualizerService.instance.levelStream.listen((bars) {
      if (!mounted) return;
      setState(() => _bars = bars);
      _armStaleTimer();
    });
  }

  // Native capture stops emitting the moment it's detached (track paused,
  // switched to video, app backgrounded off audio session, etc.) — without
  // this, the very last frame of real data would stay on screen forever
  // looking like a frozen visualizer instead of falling back to the
  // simulated animation.
  void _armStaleTimer() {
    _staleTimer?.cancel();
    _staleTimer = Timer(const Duration(milliseconds: 400), () {
      if (mounted) setState(() => _bars = null);
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    _staleTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, _bars);
}

/// Visualizer styles selectable on the Now Playing screen.
enum VisualizerStyle { spectrum, rotatingDisk, wave }

extension VisualizerStyleX on VisualizerStyle {
  String get label => switch (this) {
        VisualizerStyle.spectrum => 'Spectrum',
        VisualizerStyle.rotatingDisk => 'Rotating disk',
        VisualizerStyle.wave => 'Wave',
      };

  IconData get icon => switch (this) {
        VisualizerStyle.spectrum => Icons.equalizer_rounded,
        VisualizerStyle.rotatingDisk => Icons.album_rounded,
        VisualizerStyle.wave => Icons.graphic_eq_rounded,
      };
}

/// Drives a single looping clock shared by every bar/wave's *fallback*
/// animation (used when there's no live audio data — video playback, no
/// permission, or nothing has arrived from the native side yet). Real
/// playback is driven by [_LiveLevels] instead; this clock only produces the
/// simulated, organic-looking pattern many players fall back to when true
/// spectrum data isn't available. It still only moves while [playing] is
/// true, and eases to a flat baseline when paused so it doesn't look broken.
class _SpectrumClock extends StatefulWidget {
  final bool playing;
  final Widget Function(BuildContext context, double t) builder;
  const _SpectrumClock({required this.playing, required this.builder});

  @override
  State<_SpectrumClock> createState() => _SpectrumClockState();
}

class _SpectrumClockState extends State<_SpectrumClock> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 2),
  );

  @override
  void initState() {
    super.initState();
    if (widget.playing) _controller.repeat();
  }

  @override
  void didUpdateWidget(covariant _SpectrumClock old) {
    super.didUpdateWidget(old);
    if (widget.playing && !_controller.isAnimating) {
      _controller.repeat();
    } else if (!widget.playing && _controller.isAnimating) {
      _controller.stop();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) => widget.builder(context, _controller.value),
    );
  }
}

/// Compact animated bar spectrum for the mini-player / bottom audio tab.
class MiniSpectrumBars extends StatelessWidget {
  final bool playing;
  final Color color;
  final int barCount;
  final double height;

  const MiniSpectrumBars({
    super.key,
    required this.playing,
    required this.color,
    this.barCount = 4,
    this.height = 16,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: barCount * 5.0,
      height: height,
      child: _LiveLevels(
        builder: (context, liveBars) => _SpectrumClock(
          playing: playing,
          builder: (context, t) {
            return CustomPaint(
              painter: _BarsPainter(
                t: t,
                playing: playing,
                color: color,
                barCount: barCount,
                liveBars: (playing && liveBars != null) ? _mirrorResample(liveBars, barCount) : null,
              ),
            );
          },
        ),
      ),
    );
  }
}

class _BarsPainter extends CustomPainter {
  final double t;
  final bool playing;
  final Color color;
  final int barCount;
  final List<double>? liveBars;
  _BarsPainter({required this.t, required this.playing, required this.color, required this.barCount, this.liveBars});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    final barWidth = size.width / (barCount * 1.8);
    final gap = barWidth * 0.8;
    final live = liveBars;
    for (var i = 0; i < barCount; i++) {
      double wave;
      if (live != null) {
        // Real FFT magnitude for this bar, floored a little so a near-silent
        // bar still reads as a small visible nub rather than vanishing.
        // Auto-gain + envelope is already applied natively, so this can use
        // the value almost directly — just a tiny floor so a fully silent
        // bar still reads as a visible sliver instead of vanishing to 0.
        wave = 0.03 + live[i] * 0.97;
      } else {
        // Distance-from-center (not raw index) drives the fallback wave so
        // it's symmetric too — matching the mirrored live-data look instead
        // of reverting to a lopsided animation whenever there's no live
        // audio to show (paused, video, no permission).
        final center = (barCount - 1) / 2.0;
        final dist = (i - center).abs();
        final seed = dist * 1.7;
        wave = playing
            ? (0.35 +
                0.65 *
                    (0.5 +
                        0.5 *
                            math.sin(2 * math.pi * (t * (1.2 + dist * 0.35)) + seed) *
                            math.cos(2 * math.pi * (t * 0.6) + seed)))
            : 0.12;
      }
      final h = (size.height * wave).clamp(size.height * 0.1, size.height);
      final x = i * (barWidth + gap);
      final rect = Rect.fromLTWH(x, size.height - h, barWidth, h);
      canvas.drawRRect(RRect.fromRectAndRadius(rect, Radius.circular(barWidth / 2)), paint);
    }
  }

  @override
  bool shouldRepaint(_BarsPainter old) =>
      old.t != t || old.playing != playing || old.color != color || old.liveBars != liveBars;
}

/// A wider bar-spectrum strip (bigger sibling of [MiniSpectrumBars]) used as
/// an overlay along the bottom edge of the "Spectrum" Now Playing style.
class SpectrumBarsOverlay extends StatelessWidget {
  final bool playing;
  final Color color;
  final Color secondary;
  final double height;

  const SpectrumBarsOverlay({
    super.key,
    required this.playing,
    required this.color,
    required this.secondary,
    this.height = 56,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      child: _LiveLevels(
        builder: (context, liveBars) => _SpectrumClock(
          playing: playing,
          builder: (context, t) => CustomPaint(
            size: Size.infinite,
            painter: _WideBarsPainter(
              t: t,
              playing: playing,
              color: color,
              secondary: secondary,
              liveBars: (playing && liveBars != null) ? _mirrorResample(liveBars, _WideBarsPainter._barCount) : null,
            ),
          ),
        ),
      ),
    );
  }
}

class _WideBarsPainter extends CustomPainter {
  final double t;
  final bool playing;
  final Color color;
  final Color secondary;
  final List<double>? liveBars;
  static const int _barCount = 28;
  _WideBarsPainter({required this.t, required this.playing, required this.color, required this.secondary, this.liveBars});

  @override
  void paint(Canvas canvas, Size size) {
    final barWidth = size.width / (_barCount * 1.6);
    final gap = (size.width - barWidth * _barCount) / (_barCount - 1);
    final live = liveBars;
    for (var i = 0; i < _barCount; i++) {
      double wave;
      if (live != null) {
        wave = 0.02 + live[i] * 0.98;
      } else {
        // Same mirrored-symmetry fix as the mini bars fallback: seed off
        // distance from center, not raw index, so the two edges match.
        final center = (_barCount - 1) / 2.0;
        final dist = (i - center).abs();
        final seed = dist * 0.9;
        wave = playing
            ? (0.2 +
                0.8 *
                    (0.5 +
                        0.5 *
                            math.sin(2 * math.pi * (t * (1.4 + (dist % 5) * 0.22)) + seed) *
                            math.cos(2 * math.pi * (t * 0.7) + seed * 0.4)))
            : 0.08;
      }
      final h = (size.height * wave).clamp(size.height * 0.06, size.height);
      final x = i * (barWidth + gap);
      final rect = Rect.fromLTWH(x, size.height - h, barWidth, h);
      final paint = Paint()
        ..shader = ui.Gradient.linear(
          Offset(x, size.height),
          Offset(x, size.height - h),
          [color.withOpacity(0.9), secondary.withOpacity(0.6)],
        );
      canvas.drawRRect(RRect.fromRectAndRadius(rect, Radius.circular(barWidth / 2)), paint);
    }
  }

  @override
  bool shouldRepaint(_WideBarsPainter old) => old.t != t || old.playing != playing || old.liveBars != liveBars;
}

/// A single animated sine waveform line, used by the "Wave" Now Playing style.
class WaveformOverlay extends StatelessWidget {
  final bool playing;
  final Color color;
  final double height;

  const WaveformOverlay({super.key, required this.playing, required this.color, this.height = 56});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      child: _LiveLevels(
        builder: (context, liveBars) => _SpectrumClock(
          playing: playing,
          builder: (context, t) => CustomPaint(
            size: Size.infinite,
            painter: _WavePainter(
              t: t,
              playing: playing,
              color: color,
              liveBars: (playing && liveBars != null) ? _mirrorResample(liveBars, 64) : null,
            ),
          ),
        ),
      ),
    );
  }
}

class _WavePainter extends CustomPainter {
  final double t;
  final bool playing;
  final Color color;
  final List<double>? liveBars;
  _WavePainter({required this.t, required this.playing, required this.color, this.liveBars});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round;
    final path = Path();
    const steps = 64;
    final live = liveBars;
    for (var i = 0; i <= steps; i++) {
      final x = size.width * i / steps;
      double y;
      if (live != null) {
        // Real per-band magnitude, alternated above/below the centerline so
        // it reads as a waveform rather than a one-sided bar chart, and
        // eased with neighbors so it's a smooth line, not a jagged spike
        // train.
        final idx = i.clamp(0, live.length - 1);
        final prev = live[(idx - 1).clamp(0, live.length - 1)];
        final next = live[(idx + 1).clamp(0, live.length - 1)];
        final smoothed = (prev + live[idx] * 2 + next) / 4;
        final sign = idx.isEven ? 1 : -1;
        y = size.height / 2 + sign * smoothed * size.height * 0.42;
      } else {
        final amplitude = playing ? size.height * 0.35 : size.height * 0.04;
        final phase = 2 * math.pi * (t * 1.4);
        y = size.height / 2 +
            amplitude *
                math.sin((i / steps) * 4 * math.pi + phase) *
                (0.6 + 0.4 * math.sin((i / steps) * math.pi));
      }
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_WavePainter old) =>
      old.t != t || old.playing != playing || old.color != color || old.liveBars != liveBars;
}

/// Full-size Now Playing visualizer: a slowly rotating "vinyl" disk with the
/// track's art centered in it, ringed by a radiating spectrum of bars.
class RotatingDiskVisualizer extends StatefulWidget {
  final bool playing;
  final String? artPath;
  final bool isVideo;
  final PrismPalette palette;

  const RotatingDiskVisualizer({
    super.key,
    required this.playing,
    required this.artPath,
    required this.isVideo,
    required this.palette,
  });

  @override
  State<RotatingDiskVisualizer> createState() => _RotatingDiskVisualizerState();
}

class _RotatingDiskVisualizerState extends State<RotatingDiskVisualizer> with SingleTickerProviderStateMixin {
  late final AnimationController _spin = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 16),
  );

  @override
  void initState() {
    super.initState();
    if (widget.playing) _spin.repeat();
  }

  @override
  void didUpdateWidget(covariant RotatingDiskVisualizer old) {
    super.didUpdateWidget(old);
    if (widget.playing && !_spin.isAnimating) {
      _spin.repeat();
    } else if (!widget.playing && _spin.isAnimating) {
      _spin.stop();
    }
  }

  @override
  void dispose() {
    _spin.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = widget.palette;
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = math.min(constraints.maxWidth, constraints.maxHeight);
        return SizedBox(
          width: size,
          height: size,
          child: _LiveLevels(
            builder: (context, liveBars) => _SpectrumClock(
            playing: widget.playing,
            builder: (context, t) {
              return Stack(
                alignment: Alignment.center,
                children: [
                  // Spectrum ring, behind the disk.
                  CustomPaint(
                    size: Size.square(size),
                    painter: _RingSpectrumPainter(
                      t: t,
                      playing: widget.playing,
                      color: palette.accent,
                      secondary: palette.accentSecondary,
                      liveBars: (widget.playing && liveBars != null)
                          ? _mirrorResample(liveBars, _RingSpectrumPainter._barCount)
                          : null,
                    ),
                  ),
                  // The rotating disk itself.
                  AnimatedBuilder(
                    animation: _spin,
                    builder: (context, child) => Transform.rotate(
                      angle: _spin.value * 2 * math.pi,
                      child: child,
                    ),
                    child: Container(
                      width: size * 0.68,
                      height: size * 0.68,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: RadialGradient(
                          colors: [palette.surfaceElevated, Colors.black.withOpacity(0.85)],
                          stops: const [0.72, 1.0],
                        ),
                        boxShadow: [
                          BoxShadow(color: Colors.black.withOpacity(0.35), blurRadius: 24, offset: const Offset(0, 10)),
                        ],
                      ),
                      padding: EdgeInsets.all(size * 0.09),
                      child: ClipOval(
                        child: Container(
                          color: Colors.black,
                          child: MediaThumbnail(
                            path: widget.artPath,
                            isVideo: widget.isVideo,
                            borderRadius: size,
                          ),
                        ),
                      ),
                    ),
                  ),
                  // Center spindle dot, like a record.
                  Container(
                    width: size * 0.045,
                    height: size * 0.045,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: palette.background,
                      border: Border.all(color: Colors.white.withOpacity(0.6), width: 1.5),
                    ),
                  ),
                ],
              );
            },
            ),
          ),
        );
      },
    );
  }
}

class _RingSpectrumPainter extends CustomPainter {
  final double t;
  final bool playing;
  final Color color;
  final Color secondary;
  final List<double>? liveBars;
  static const int _barCount = 48;

  _RingSpectrumPainter({
    required this.t,
    required this.playing,
    required this.color,
    required this.secondary,
    this.liveBars,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final innerRadius = size.width * 0.36;
    final maxBarLen = size.width * 0.14;
    final live = liveBars;

    for (var i = 0; i < _barCount; i++) {
      final angle = (i / _barCount) * 2 * math.pi;
      double wave;
      if (live != null) {
        // Real per-direction FFT magnitude — this is the ring actually
        // reacting to the track playing, instead of a fixed rotating sine
        // loop that looked the same on every single song.
        wave = (0.04 + live[i] * 0.96).clamp(0.04, 1.0);
      } else {
        // Distance from the seam (where index 0 meets the last index, both
        // sitting at the same angle) instead of raw index — otherwise the
        // fallback ring has the same jump-at-the-seam look the live data
        // used to have.
        final dist = math.min(i, _barCount - i).toDouble();
        final seed = dist * 0.618;
        wave = playing
            ? (0.25 +
                0.75 *
                    (0.5 +
                        0.5 *
                            math.sin(2 * math.pi * (t * (1.0 + (dist % 7) * 0.18)) + seed) *
                            math.cos(2 * math.pi * (t * 0.5) + seed * 0.5)))
            : 0.15;
      }
      final len = maxBarLen * wave.clamp(0.12, 1.0);

      final from = Offset(center.dx + innerRadius * math.cos(angle), center.dy + innerRadius * math.sin(angle));
      final to = Offset(center.dx + (innerRadius + len) * math.cos(angle), center.dy + (innerRadius + len) * math.sin(angle));

      final paint = Paint()
        ..strokeWidth = math.max(2.0, size.width * 0.010)
        ..strokeCap = StrokeCap.round
        ..shader = ui.Gradient.linear(from, to, [color.withOpacity(0.85), secondary.withOpacity(0.55)]);
      canvas.drawLine(from, to, paint);
    }
  }

  @override
  bool shouldRepaint(_RingSpectrumPainter old) =>
      old.t != t || old.playing != playing || old.color != color || old.secondary != secondary || old.liveBars != liveBars;
}
