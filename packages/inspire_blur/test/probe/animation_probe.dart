// THE PROBE. A real engine, a real raster thread, a sustained animation.
//
// `flutter test` rasterises inline, so it can count PRODUCTIONS but can never
// show reclamation lagging them. This entrypoint runs the band composition (a
// bottom-anchored `InspireChildBlurBandSampler` around a top-anchored one)
// under a ticker that repaints the child every frame — the same steady-state a
// scroll fling or a long particle animation puts it in — and prints, every 60
// frames:
//
//   frame  bandTex  outstanding  rss(MB)
//
// `bandTex` is the monotone `toImageSync` allocation counter; `rss` is the
// process resident set. Run it from any host app that depends on this package
// (the package itself has no platform runner):
//
//   flutter run -d macos -t <path-to>/inspire_blur/test/probe/animation_probe.dart
//
// It exits by itself after `_kFrames` frames.
//
// Arms are selected with environment variables (`INSPIRE_PROBE_*`).

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:inspire_blur/inspire_blur.dart';

const int _kFrames = 600;
const int _kSampleEvery = 60;

/// Repaint only a boundary BELOW the band (the particle-animation shape)
/// instead of the whole slab (the scroll-fling shape).
final bool _isolated =
    Platform.environment['INSPIRE_PROBE_ISOLATED'] == '1';

/// The arms the window-signature gate is measured on.
///
/// `INSPIRE_PROBE_MIDDLE=1` puts the repainting `RepaintBoundary` in the GAP
/// between the two band windows — a particle animation's real shape, and the
/// arm where the gate must engage on BOTH layers. `INSPIRE_PROBE_ISOLATED=1`
/// puts it at y 400..1000, which is inside the FOOTER's window on an 874 pt
/// viewport, so that arm gates the ramp only (measured: 1.245
/// productions/frame against 1.99 before the gate).
///
/// `INSPIRE_PROBE_INBAND=1` animates content INSIDE the ramp's band window: the
/// no-staleness arm. The ramp must produce at the full rate there, and the
/// forced-refresh valve must never be what makes it.
final bool _middle = Platform.environment['INSPIRE_PROBE_MIDDLE'] == '1';
final bool _inBand = Platform.environment['INSPIRE_PROBE_INBAND'] == '1';

/// `INSPIRE_PROBE_PAINTONLY=1` · the same gap placement as
/// `INSPIRE_PROBE_MIDDLE`, animated through a `CustomPainter`'s `repaint`
/// Listenable instead of a `ValueListenableBuilder`. MEASURED: the builder arm
/// re-BUILDS, which marks layout, and `_layoutWithoutResize` walks
/// `markNeedsPaint` up past the `RepaintBoundary` to the footer sampler — so
/// the footer re-records its own pictures every frame and its window signature
/// legitimately moves. A painter repaint stays inside the boundary, which is
/// what particle motes are.
final bool _paintOnly = Platform.environment['INSPIRE_PROBE_PAINTONLY'] == '1';

/// `INSPIRE_PROBE_SCROLL=1` · the arm that says the gate cannot cost the
/// SCROLL anything: the list is jumped 2 pt per frame, so content moves
/// THROUGH both windows. Every frame's signature must differ from the last,
/// `winSkip` must stay 0, and production must stay at the pre-gate rate.
final bool _scroll = Platform.environment['INSPIRE_PROBE_SCROLL'] == '1';

class _MotePainter extends CustomPainter {
  _MotePainter(Listenable repaint) : _tick = repaint, super(repaint: repaint);
  final Listenable _tick;
  @override
  void paint(Canvas canvas, Size size) {
    final int n = (_tick as ValueNotifier<int>).value;
    canvas.drawCircle(
      Offset(size.width / 2 + (n % 20).toDouble(), size.height / 2),
      12,
      Paint()..color = const Color(0xFFB03030),
    );
  }

  @override
  bool shouldRepaint(_MotePainter oldDelegate) => false;
}

/// Run the ticker but never advance `_tick`, so vsync keeps arriving
/// and NOTHING in the tree repaints. The retention baseline: a layer that
/// participates in Flutter's retained rendering produces zero bands here.
final bool _idle = Platform.environment['INSPIRE_PROBE_IDLE'] == '1';

void main() {
  runApp(const _Probe());
}

class _Probe extends StatefulWidget {
  const _Probe();

  @override
  State<_Probe> createState() => _ProbeState();
}

class _ProbeState extends State<_Probe> with SingleTickerProviderStateMixin {
  final ValueNotifier<int> _tick = ValueNotifier<int>(0);
  final ScrollController _controller = ScrollController();
  late final Ticker _ticker;
  int _frame = 0;
  int _baseRss = 0;

  @override
  void initState() {
    super.initState();
    stdout.writeln('PROBE pid=$pid');
    _ticker = createTicker(_onFrame)..start();
  }

  void _onFrame(Duration _) {
    _frame++;
    if (!_idle) _tick.value = _frame;
    if (_scroll && _controller.hasClients) {
      _controller.jumpTo((_frame * 2).toDouble() % 2000);
    }
    if (_frame == _kSampleEvery) _baseRss = ProcessInfo.currentRss;
    if (_frame % _kSampleEvery == 0) {
      final int rss = ProcessInfo.currentRss;
      stdout.writeln('PROBE frame=$_frame '
          'bandTex=$debugInspireBandSamplerTextures '
          'outstanding=$debugInspireOutstandingTextures '
          'paints=$debugInspireBandSamplerPaints '
          'scenes=$debugInspireBandSamplerScenes '
          'prod=$debugInspireBandSamplerProductions '
          'marks=$debugInspireBandSamplerMarks '
          'stale=$debugInspireBandSamplerStaleBands '
          'reuse=$debugInspireBandSamplerPictureReuse '
          'liveImg=$debugInspireLiveSamplerImages '
          'winSkip=$debugInspireBandSamplerWindowSkips '
          'forced=$debugInspireBandSamplerForcedRefreshes '
          'unknown="$debugInspireBandSamplerWindowUnknown" '
          'why="$debugInspireBandSamplerProduceReason" '
          'paintAnchor="$debugInspireBandSamplerPaintAnchor" '
          'geom="$debugInspireBandSamplerGeometry" '
          'rssMB=${(rss / (1 << 20)).toStringAsFixed(1)} '
          'deltaMB=${((rss - _baseRss) / (1 << 20)).toStringAsFixed(1)}');
    }
    if (_frame >= _kFrames) {
      _ticker.stop();
      stdout.writeln('PROBE done');
      unawaited(Future<void>.delayed(
        const Duration(milliseconds: 200),
        () => exit(0),
      ));
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    _tick.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Directionality(
        textDirection: TextDirection.ltr,
        child: MediaQuery(
          data: MediaQueryData.fromView(View.of(context)),
          child: ColoredBox(
            color: const Color(0xFF000000),
            // A bottom-anchored band (a frosted footer) around a top-anchored
            // one (a scroll ramp).
            child: InspireChildBlurBandSampler(
              config: InspireBlurConfig.bottomToTop(sigma: 20, extent: 0.2),
              child: InspireChildBlurBandSampler(
                config: InspireBlurConfig.topToBottom(sigma: 20, extent: 0.2),
                child: ListView(
                  controller: _scroll ? _controller : null,
                  padding: EdgeInsets.zero,
                  physics: _scroll
                      ? const ClampingScrollPhysics()
                      : const NeverScrollableScrollPhysics(),
                  children: <Widget>[
                    // INSPIRE_PROBE_ISOLATED=1 · the repaint is confined to a
                    // RepaintBoundary that sits BELOW the band window, which
                    // is what a particle animation's stage is. Default: the
                    // whole slab repaints, which is the scroll-fling case.
                    if (_paintOnly) ...<Widget>[
                      const SizedBox(height: 200, child: ColoredBox(
                          color: Color(0xFF202020), child: SizedBox.expand())),
                      RepaintBoundary(
                        child: SizedBox(
                          height: 100,
                          child: CustomPaint(
                            painter: _MotePainter(_tick),
                            child: const SizedBox.expand(),
                          ),
                        ),
                      ),
                      const SizedBox(height: 3500, child: ColoredBox(
                          color: Color(0xFF202020), child: SizedBox.expand())),
                    ] else if (_inBand) ...<Widget>[
                      // INSIDE the ramp's band window (y 0..156), through the
                      // same painter the PAINTONLY arm uses — so the only
                      // difference between the two arms is WHERE the repaint
                      // is, and the gate's own decision is what the numbers
                      // measure.
                      RepaintBoundary(
                        child: SizedBox(
                          height: 80,
                          child: CustomPaint(
                            painter: _MotePainter(_tick),
                            child: const SizedBox.expand(),
                          ),
                        ),
                      ),
                      const SizedBox(height: 4000, child: ColoredBox(
                          color: Color(0xFF202020), child: SizedBox.expand())),
                    ] else if (_middle) ...<Widget>[
                      // BETWEEN the two windows. MEASURED on the probe's own
                      // 800x600 macOS window with a 120 pt ramp zone: the
                      // ramp's window is y 0..156 (`geom` in the sample line)
                      // and the frosted footer's hangs off the bottom edge, so
                      // y 200..300 is clear of both. This is a particle
                      // animation's shape — motes repainting where no band
                      // samples them.
                      const SizedBox(height: 200, child: ColoredBox(
                          color: Color(0xFF202020), child: SizedBox.expand())),
                      RepaintBoundary(
                        child: SizedBox(
                          height: 100,
                          child: ValueListenableBuilder<int>(
                            valueListenable: _tick,
                            builder: (BuildContext _, int n, Widget? __) =>
                                ColoredBox(
                              color: n.isEven
                                  ? const Color(0xFFB03030)
                                  : const Color(0xFF3030B0),
                              child: const SizedBox.expand(),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 3500, child: ColoredBox(
                          color: Color(0xFF202020), child: SizedBox.expand())),
                    ] else if (_isolated) ...<Widget>[
                      const SizedBox(height: 400, child: ColoredBox(
                          color: Color(0xFF202020), child: SizedBox.expand())),
                      RepaintBoundary(
                        child: SizedBox(
                          height: 600,
                          child: ValueListenableBuilder<int>(
                            valueListenable: _tick,
                            builder: (BuildContext _, int n, Widget? __) =>
                                ColoredBox(
                              color: n.isEven
                                  ? const Color(0xFFB03030)
                                  : const Color(0xFF3030B0),
                              child: const SizedBox.expand(),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 3000, child: ColoredBox(
                          color: Color(0xFF202020), child: SizedBox.expand())),
                    ] else
                      SizedBox(
                        height: 4000,
                        child: ValueListenableBuilder<int>(
                          valueListenable: _tick,
                          builder: (BuildContext _, int n, Widget? __) =>
                              ColoredBox(
                            color: n.isEven
                                ? const Color(0xFFB03030)
                                : const Color(0xFF3030B0),
                            child: const SizedBox.expand(),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
}
