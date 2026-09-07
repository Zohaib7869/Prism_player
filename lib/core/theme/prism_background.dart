import 'package:flutter/material.dart';

import 'app_theme.dart';

/// The app-wide premium backdrop: a three-stop vertical gradient with two soft
/// radial glows drifting behind it.
///
/// Installed exactly once, in `MaterialApp.builder`, so every route inherits it.
/// This is why [PrismThemes.buildThemeData] sets `scaffoldBackgroundColor` to
/// transparent — individual Scaffolds must not paint a flat color over this.
/// Screens that intentionally need pure black (the video player) still set
/// their own opaque `backgroundColor` and simply cover the backdrop.
class PrismBackground extends StatefulWidget {
  final Widget child;
  const PrismBackground({super.key, required this.child});

  @override
  State<PrismBackground> createState() => _PrismBackgroundState();
}

class _PrismBackgroundState extends State<PrismBackground>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    // Very slow: the glows breathe rather than animate. Cheap to run (two
    // blurred circles, no layout work) and it makes the app feel alive.
    duration: const Duration(seconds: 18),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = Theme.of(context).extension<PrismPalette>()!;
    final stops = palette.backgroundStops;
    final image = palette.backgroundImage;

    final layers = <Widget>[
      // Wallpaper (image themes only), darkened by a scrim so UI stays legible.
      if (image != null)
        Positioned.fill(
          child: Image.asset(
            image,
            fit: BoxFit.cover,
            // Decoding once at screen size keeps memory flat across routes.
            filterQuality: FilterQuality.medium,
            errorBuilder: (_, __, ___) => const SizedBox.shrink(),
          ),
        ),
      if (image != null)
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(palette.imageDim),
            ),
          ),
        ),
      // The theme gradient. For image themes its stops are semi-transparent,
      // so it tints the wallpaper instead of hiding it.
      Positioned.fill(
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: stops,
            ),
          ),
        ),
      ),
      Positioned.fill(
        child: RepaintBoundary(
          child: AnimatedBuilder(
            animation: _controller,
            builder: (context, _) {
              final t = Curves.easeInOut.transform(_controller.value);
              return CustomPaint(
                painter: _GlowPainter(
                  primary: palette.glowA,
                  secondary: palette.glowB,
                  progress: t,
                ),
              );
            },
          ),
        ),
      ),
      Positioned.fill(child: widget.child),
    ];

    return ColoredBox(
      color: palette.background,
      child: Stack(children: layers),
    );
  }
}

class _GlowPainter extends CustomPainter {
  final Color primary;
  final Color secondary;
  final double progress;

  _GlowPainter({
    required this.primary,
    required this.secondary,
    required this.progress,
  });

  @override
  void paint(Canvas canvas, Size size) {
    void glow(Offset center, double radius, Color color) {
      final rect = Rect.fromCircle(center: center, radius: radius);
      final paint = Paint()
        ..shader = RadialGradient(
          colors: [color, color.withOpacity(0)],
        ).createShader(rect);
      canvas.drawRect(rect, paint);
    }

    // Top-trailing glow drifts down/left, bottom-leading glow drifts up/right.
    glow(
      Offset(size.width * (0.85 - progress * 0.12), size.height * (0.06 + progress * 0.06)),
      size.width * 0.85,
      primary,
    );
    glow(
      Offset(size.width * (0.05 + progress * 0.15), size.height * (0.78 - progress * 0.08)),
      size.width * 0.95,
      secondary,
    );
  }

  @override
  bool shouldRepaint(_GlowPainter old) =>
      old.progress != progress || old.primary != primary || old.secondary != secondary;
}

/// A frosted "glass" panel for premium surfaces (cards, sheets, headers).
class GlassPanel extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final double borderRadius;

  const GlassPanel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.borderRadius = 20,
  });

  @override
  Widget build(BuildContext context) {
    final palette = Theme.of(context).extension<PrismPalette>()!;
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: palette.glass,
        borderRadius: BorderRadius.circular(borderRadius),
        border: Border.all(color: palette.glassBorder),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(palette.isDark ? 0.30 : 0.06),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: child,
    );
  }
}
