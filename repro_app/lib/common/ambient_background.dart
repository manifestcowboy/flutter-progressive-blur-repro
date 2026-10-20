import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'music_data.dart';

/// A "now playing" ambient background: large soft colour blobs drifting slowly
/// across the whole area, forever.
///
/// It repaints every frame (a `CustomPainter` repainted by the animation, no
/// rebuilds), so whatever blur it sits under has a dirty child on every frame.
/// Each blob is a `RadialGradient` covering most of the area, so the fill rate
/// is a few screens of overdraw per frame.
class AmbientBackground extends StatefulWidget {
  const AmbientBackground({super.key});

  /// One full drift cycle.
  static const Duration cycle = Duration(seconds: 90);

  @override
  State<AmbientBackground> createState() => _AmbientBackgroundState();
}

class _AmbientBackgroundState extends State<AmbientBackground>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: AmbientBackground.cycle,
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool dark = theme.brightness == Brightness.dark;
    return IgnorePointer(
      child: RepaintBoundary(
        child: CustomPaint(
          painter: _AmbientPainter(
            _controller,
            base: theme.colorScheme.surface,
            blobAlpha: dark ? 0.42 : 0.5,
          ),
          size: Size.infinite,
        ),
      ),
    );
  }
}

class _Blob {
  const _Blob(this.seed, this.kx, this.ky, this.phase, this.radius);

  /// Picks the colour.
  final int seed;

  /// Whole number of orbits per cycle on each axis, so the loop is seamless.
  final int kx;
  final int ky;
  final double phase;

  /// As a fraction of the longer side.
  final double radius;
}

const List<_Blob> _blobs = <_Blob>[
  _Blob(3, 1, 2, 0.00, 0.70),
  _Blob(8, 2, 1, 0.17, 0.62),
  _Blob(14, 1, 1, 0.41, 0.78),
  _Blob(21, 3, 2, 0.58, 0.55),
  _Blob(27, 2, 3, 0.73, 0.66),
  _Blob(33, 1, 3, 0.90, 0.60),
];

class _AmbientPainter extends CustomPainter {
  _AmbientPainter(this.animation, {required this.base, required this.blobAlpha})
      : super(repaint: animation);

  final Animation<double> animation;
  final Color base;
  final double blobAlpha;

  @override
  void paint(Canvas canvas, Size size) {
    final Rect area = Offset.zero & size;
    canvas.drawRect(area, Paint()..color = base);
    final double t = animation.value;
    final double reach = size.longestSide;
    for (final _Blob b in _blobs) {
      final Offset center = Offset(
        size.width * (0.5 + 0.45 * math.sin(2 * math.pi * (b.kx * t + b.phase))),
        size.height *
            (0.5 + 0.45 * math.cos(2 * math.pi * (b.ky * t + b.phase * 1.7))),
      );
      final double radius = reach * b.radius;
      final Color color = seedColor(b.seed, saturation: 0.65, value: 0.95);
      canvas.drawRect(
        area,
        Paint()
          ..shader = RadialGradient(
            colors: <Color>[
              color.withValues(alpha: blobAlpha),
              color.withValues(alpha: blobAlpha * 0.45),
              color.withValues(alpha: 0),
            ],
            stops: const <double>[0, 0.45, 1],
          ).createShader(Rect.fromCircle(center: center, radius: radius)),
      );
    }
  }

  @override
  bool shouldRepaint(_AmbientPainter old) =>
      old.animation != animation ||
      old.base != base ||
      old.blobAlpha != blobAlpha;
}
