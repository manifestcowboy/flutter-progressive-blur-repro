import 'dart:async';

import 'package:flutter/material.dart';

import 'music_data.dart';
import 'music_widgets.dart';
import 'particles.dart';

/// How the dissolve is driven.
enum DissolveDrive {
  /// `AnimatedBuilder` rebuilds the row subtree (a Stack of a few hundred
  /// positioned dots) on every tick: build, layout and paint, every frame.
  rebuild,

  /// `CustomPainter(repaint: controller)` and a `FadeTransition`: the widget
  /// tree is built once and only paint runs per frame.
  paintOnly,
}

final ParticleField _sharedField = ParticleField();

/// A song row that breaks into particles over 1.25 s when it is swiped
/// sideways, then collapses and calls [onRemoved].
///
/// Keep a `GlobalKey<DissolveSongRowState>` to start it from code.
class DissolveSongRow extends StatefulWidget {
  const DissolveSongRow({
    super.key,
    required this.song,
    required this.drive,
    required this.onRemoved,
  });

  final Song song;
  final DissolveDrive drive;
  final VoidCallback onRemoved;

  @override
  State<DissolveSongRow> createState() => DissolveSongRowState();
}

class DissolveSongRowState extends State<DissolveSongRow>
    with TickerProviderStateMixin {
  late final AnimationController _dissolve = AnimationController(
    vsync: this,
    duration: ParticleField.duration,
  );
  late final AnimationController _collapse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 180),
    value: 1,
  );
  late final Animation<double> _rowFade = Tween<double>(begin: 1, end: 0)
      .animate(
    CurvedAnimation(
      parent: _dissolve,
      curve: const Interval(0, ParticleField.rowFadeEnd),
    ),
  );

  Completer<void>? _running;
  double _swipe = 0;

  @override
  void dispose() {
    _dissolve.dispose();
    _collapse.dispose();
    super.dispose();
  }

  /// Plays the dissolve, collapses the row, calls `onRemoved`. Completes when
  /// that is done; calling it again while it runs returns the same future.
  Future<void> startDissolve() {
    final Completer<void>? running = _running;
    if (running != null) return running.future;
    final Completer<void> done = _running = Completer<void>();
    unawaited(_play(done));
    return done.future;
  }

  Future<void> _play(Completer<void> done) async {
    await _dissolve.forward(from: 0);
    if (!mounted) return;
    await _collapse.reverse();
    if (!mounted) return;
    widget.onRemoved();
    done.complete();
  }

  @override
  Widget build(BuildContext context) {
    final Widget row = SongTile(song: widget.song);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onHorizontalDragStart: (_) => _swipe = 0,
      onHorizontalDragUpdate: (DragUpdateDetails d) => _swipe += d.delta.dx,
      onHorizontalDragEnd: (DragEndDetails d) {
        if (_swipe.abs() > 72 || (d.primaryVelocity ?? 0).abs() > 700) {
          startDissolve();
        }
      },
      // Collapses the row's height once it has dissolved. The clip also keeps
      // the particles inside the row.
      child: AnimatedBuilder(
        animation: _collapse,
        builder: (BuildContext context, Widget? child) => ClipRect(
          child: Align(
            alignment: Alignment.topCenter,
            heightFactor: _collapse.value,
            child: child,
          ),
        ),
        child: RepaintBoundary(
          child: widget.drive == DissolveDrive.rebuild
              ? _rebuildDriven(row)
              : _paintDriven(row),
        ),
      ),
    );
  }

  Widget _rebuildDriven(Widget row) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints box) {
        final Size size = Size(box.maxWidth, SongTile.height);
        return AnimatedBuilder(
          animation: _dissolve,
          builder: (BuildContext context, Widget? _) {
            final double t = _dissolve.value;
            return Stack(
              children: <Widget>[
                Opacity(
                  opacity: (1 - t / ParticleField.rowFadeEnd).clamp(0.0, 1.0),
                  child: row,
                ),
                if (t > 0)
                  for (final Particle p in _sharedField.particles)
                    if (p.alphaAt(t) > 0)
                      Positioned(
                        left: p.positionAt(t, size).dx - p.radius,
                        top: p.positionAt(t, size).dy - p.radius,
                        width: p.radius * 2,
                        height: p.radius * 2,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: p.color.withValues(alpha: p.alphaAt(t)),
                          ),
                        ),
                      ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _paintDriven(Widget row) {
    return Stack(
      children: <Widget>[
        FadeTransition(opacity: _rowFade, child: row),
        Positioned.fill(
          child: CustomPaint(painter: ParticlePainter(_dissolve, _sharedField)),
        ),
      ],
    );
  }
}
