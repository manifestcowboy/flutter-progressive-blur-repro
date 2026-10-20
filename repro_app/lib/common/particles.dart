import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import 'music_data.dart';

/// One dot of the particle dissolve.
class Particle {
  const Particle({
    required this.x,
    required this.y,
    required this.vx,
    required this.vy,
    required this.radius,
    required this.delay,
    required this.color,
  });

  /// Start position as a fraction of the row.
  final double x;
  final double y;

  /// Drift over the whole animation, in logical px.
  final double vx;
  final double vy;
  final double radius;

  /// When the dot appears, as a fraction of the animation.
  final double delay;
  final Color color;

  /// Opacity at animation time [t] (0..1): hidden until [delay], then fading.
  double alphaAt(double t) {
    if (t <= delay) return 0;
    return (1 - (t - delay) / (1 - delay)).clamp(0.0, 1.0) * 0.9;
  }

  Offset positionAt(double t, Size row) => Offset(
        x * row.width + vx * t,
        y * row.height + vy * t + 36 * t * t,
      );
}

/// A few hundred deterministic dots, the same in every run and both drive
/// modes of S7.
class ParticleField {
  ParticleField({int count = 320, int seed = 7})
      : particles = _generate(count, seed);

  final List<Particle> particles;

  /// The dissolve plays for this long.
  static const Duration duration = Duration(milliseconds: 1250);

  /// The row itself has faded out by this fraction of the animation.
  static const double rowFadeEnd = 0.625;

  static List<Particle> _generate(int count, int seed) {
    final math.Random random = math.Random(seed);
    final List<Color> palette = <Color>[
      for (int i = 0; i < 6; i++) seedColor(i * 2 + 1),
    ];
    return List<Particle>.generate(count, (int i) {
      final double x = random.nextDouble();
      return Particle(
        x: x,
        y: random.nextDouble(),
        vx: 20 + random.nextDouble() * 120,
        vy: -30 - random.nextDouble() * 50,
        radius: 1.2 + random.nextDouble() * 2.8,
        delay: x * 0.4,
        color: palette[i % palette.length],
      );
    });
  }
}

/// Paints [field] at the animation's current value. Repaints on every tick of
/// [animation] without rebuilding anything.
class ParticlePainter extends CustomPainter {
  ParticlePainter(this.animation, this.field) : super(repaint: animation);

  final Animation<double> animation;
  final ParticleField field;

  @override
  void paint(Canvas canvas, Size size) {
    final double t = animation.value;
    if (t <= 0) return;
    final Paint paint = Paint();
    for (final Particle p in field.particles) {
      final double alpha = p.alphaAt(t);
      if (alpha <= 0) continue;
      paint.color = p.color.withValues(alpha: alpha);
      canvas.drawCircle(p.positionAt(t, size), p.radius, paint);
    }
  }

  @override
  bool shouldRepaint(ParticlePainter old) => old.field != field;
}
