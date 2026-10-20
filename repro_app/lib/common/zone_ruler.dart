import 'package:flutter/material.dart';

import 'constants.dart';

/// A dashed line at the end of the blur zone, for judging where a ramp
/// actually fades out. Ignores touches.
class ZoneRuler extends StatelessWidget {
  const ZoneRuler({super.key, this.y = kZoneHeight});

  /// Distance from the top of the area, in logical px.
  final double y;

  @override
  Widget build(BuildContext context) {
    final Color color = Theme.of(context).colorScheme.error;
    return IgnorePointer(
      child: Stack(
        children: <Widget>[
          Positioned(
            top: y,
            left: 0,
            right: 0,
            child: CustomPaint(
              size: const Size(double.infinity, 1),
              painter: _DashPainter(color),
            ),
          ),
          Positioned(
            top: y + 2,
            right: 8,
            child: Text(
              'zone end ${y.round()} pt',
              style: TextStyle(color: color, fontSize: 10),
            ),
          ),
        ],
      ),
    );
  }
}

class _DashPainter extends CustomPainter {
  _DashPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint()
      ..color = color
      ..strokeWidth = 1.5;
    for (double x = 0; x < size.width; x += 12) {
      canvas.drawLine(Offset(x, 0), Offset(x + 6, 0), paint);
    }
  }

  @override
  bool shouldRepaint(_DashPainter old) => old.color != color;
}
