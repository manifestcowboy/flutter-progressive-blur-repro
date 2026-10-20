// ─────────────────────────────────────────────────────────────────────────
// Patch 4 band sampler (window-signature gate): A REPAINT THAT MISSES THE BAND
// WINDOW MUST NOT COST A BAND.
//
// WHAT THE RETENTION WORK LEFT OPEN. It made a QUIET frame free. It did nothing
// for a frame that is dirty SOMEWHERE ELSE, and that is the shape of a long
// particle animation under the band: a 1250 ms mote animation inside a
// `RepaintBoundary` that lies between the two band windows. Flutter's dirty bit
// carries no region, so `addToScene` ran and rasterised two window-sized render
// targets for content the repaint never touched. MEASURED on a real macOS
// engine (`test/probe/animation_probe.dart`, paint-only arm, 600 frames, two
// nested band samplers):
//
//   gate off   prod=1194   bandTex=2388     (1.99 productions/frame)
//   gate on    prod=300    bandTex=600      (0.50 — 2 layers x 1 in 4)
//
// WHAT THIS FILE ASSERTS, each arm failing on a different regression:
//   1 · THE BAND PATH ENGAGED AT ALL. Without it everything below is about the
//       upstream fallback and proves nothing.
//   2 · A REPAINT OUTSIDE BOTH WINDOWS IS GATED. Productions over N repainting
//       frames stay at or under the valve's ceiling, and the gate — not the
//       production-budget / texture-cap backstops — is what did it (`windowSkips` moved, `staleBands`
//       did not).
//   3 · THE VALVE FIRES. `PictureLayer.canvasBounds` is the recorder's cull
//       rect, an ESTIMATE; a bound that lied small would freeze the band. So
//       the gate may skip at most [kInspireBandWindowMaxSkips] CONSECUTIVE
//       productions and every 4th dirty frame produces regardless. This arm
//       reads the forced-refresh counter and the per-layer floor.
//   4 · A REPAINT INSIDE A WINDOW IS NOT GATED, AND THE PIXELS PROVE IT. The
//       same frames are rendered twice — gate on, then gate off through
//       [debugInspireBandWindowGateDisabled] — and captured. Byte-identical
//       both ways, with content moving INSIDE the band window, is the "no
//       visible staleness path" claim; the production count rising by one per
//       frame is the mechanism behind it.
//
// RED-ARM (measured, in this order):
//   · `kInspireBandWindowMaxSkips = 0` disables the gate: arm 2's count goes to
//     one production per layer per frame and `windowSkips` stays 0.
//   · Hashing nothing (make `_BandWindowSignature.run` return a constant): arm
//     4's production count collapses to the valve floor and its captures
//     diverge — a frozen band under moving content.
//
// ONE PROCESS, ONE TEST, FOUR PHASES — the shape every band-composition test in
// this package is forced into: only the FIRST test in a process ever engages the
// band composition, because the shader warm-up's bare `await` inside `runAsync`
// never completes in a later one.
// ─────────────────────────────────────────────────────────────────────────

import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inspire_blur/inspire_blur.dart';
// The shader cache is not exported and the warm-up below needs it.
// ignore: implementation_imports
import 'package:inspire_blur/src/inspire_shaders.dart';

const double _kDpr = 3.0;
const Size _kView = Size(402, 874);

/// Two layers: a bottom-anchored band (a frosted footer's shape) around a
/// top-anchored one (a scroll ramp's).
const int _kLayers = 2;

final ValueNotifier<int> _tick = ValueNotifier<int>(0);
final GlobalKey _boundary = GlobalKey();

/// Repaints on every `_tick`, inside its own `RepaintBoundary`, and moves ink
/// while it does — the motes' shape. A `ValueListenableBuilder` would REBUILD
/// instead, which marks layout, and `_layoutWithoutResize` walks
/// `markNeedsPaint` up past the boundary into the ancestor sampler; that
/// sampler then re-records its own pictures and its window signature moves for
/// real. MEASURED on the probe: 1.99 productions/frame with a builder, 0.50
/// with this painter.
class _MotePainter extends CustomPainter {
  _MotePainter(this.tick) : super(repaint: tick);

  final ValueNotifier<int> tick;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawCircle(
      Offset(size.width / 2 + (tick.value % 20).toDouble(), size.height / 2),
      12,
      Paint()..color = const Color(0xFFB03030),
    );
  }

  @override
  bool shouldRepaint(_MotePainter oldDelegate) => false;
}

/// [gapTop] is the offset of the animated boundary inside the scroll body. At
/// 874 pt with 0.2 extents the top window ends around y 250 and the bottom one
/// begins around y 620, so 300 is between them and 0 is inside the top one.
Widget _host({required double gapTop}) => MediaQuery(
      data: const MediaQueryData(size: _kView, devicePixelRatio: _kDpr),
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: RepaintBoundary(
          key: _boundary,
          child: SizedBox(
            width: _kView.width,
            height: _kView.height,
            child: InspireChildBlurBandSampler(
              config: InspireBlurConfig.bottomToTop(sigma: 20, extent: 0.2),
              child: InspireChildBlurBandSampler(
                config: InspireBlurConfig.topToBottom(sigma: 20, extent: 0.2),
                child: ColoredBox(
                  color: const Color(0xFF101010),
                  child: ListView(
                    padding: EdgeInsets.zero,
                    physics: const NeverScrollableScrollPhysics(),
                    children: <Widget>[
                      SizedBox(
                        height: gapTop,
                        child: const ColoredBox(
                          color: Color(0xFF808080),
                          child: SizedBox.expand(),
                        ),
                      ),
                      RepaintBoundary(
                        child: SizedBox(
                          height: 120,
                          child: CustomPaint(
                            painter: _MotePainter(_tick),
                            child: const SizedBox.expand(),
                          ),
                        ),
                      ),
                      const SizedBox(
                        height: 3000,
                        child: ColoredBox(
                          color: Color(0xFF404040),
                          child: SizedBox.expand(),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );

/// One frame with the real async machinery running — the mask generation and
/// the band-extent readback are both real `Future`s that `pump`'s fake-async
/// zone will never complete on its own.
Future<void> _frame(WidgetTester tester, {int? tick}) async {
  if (tick != null) _tick.value = tick;
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 1)),
  );
  await tester.pump(const Duration(milliseconds: 16));
}

/// The composited result, at 1 device pixel per logical pixel — enough to see
/// a band that stopped following its content, and 1.4 MB a frame instead of
/// 12.6.
Future<Uint8List> _capture(WidgetTester tester) async {
  final RenderRepaintBoundary box =
      _boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  late Uint8List bytes;
  await tester.runAsync(() async {
    final ui.Image image = await box.toImage();
    final ByteData? data =
        await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    bytes = Uint8List.fromList(data!.buffer.asUint8List());
    image.dispose();
  });
  return bytes;
}

void main() {
  testWidgets(
    'a repaint outside the band window costs no band, one inside still does',
    (WidgetTester tester) async {
      tester.view.devicePixelRatio = _kDpr;
      tester.view.physicalSize = _kView * _kDpr;
      addTearDown(tester.view.reset);
      addTearDown(() => debugInspireBandWindowGateDisabled = false);

      await tester.pumpWidget(_host(gapTop: 300));
      await tester.runAsync(() => InspireShaders.childBlur);

      // ── PHASE 1 · THE BAND PATH ENGAGED. ────────────────────────────────
      final int drawsBefore = debugInspireBandSamplerDraws;
      for (int i = 0; i < 10; i++) {
        await _frame(tester, tick: i);
      }
      expect(
        debugInspireBandSamplerDraws,
        greaterThan(drawsBefore),
        reason: 'the band composition never engaged, so every number below is '
            'about the upstream fallback: $debugInspireBandSamplerReasons',
      );
      expect(
        debugInspireBandSamplerWindowUnknown,
        '',
        reason: 'the signature walk met a layer type it does not recognise '
            '($debugInspireBandSamplerWindowUnknown) and disengaged the gate '
            'on this tree. That is SAFE — it produces exactly as it did before '
            'the gate — but nothing below is then measuring the gate. Teach the '
            'walk that type, or move the arm.',
      );

      // ── PHASE 2 · A REPAINT BETWEEN THE WINDOWS IS GATED. ───────────────
      const int kFrames = 24;
      final int prodBefore = debugInspireBandSamplerProductions;
      final int skipsBefore = debugInspireBandSamplerWindowSkips;
      final int staleBefore = debugInspireBandSamplerStaleBands;
      for (int i = 0; i < kFrames; i++) {
        await _frame(tester, tick: 100 + i);
      }
      final int produced = debugInspireBandSamplerProductions - prodBefore;
      expect(
        debugInspireBandSamplerWindowSkips,
        greaterThan(skipsBefore),
        reason: 'THE GATE NEVER ENGAGED. $kFrames frames repainted a boundary '
            'that lies between the two band windows and every one of them still '
            'rasterised two window-sized render targets per layer — which is '
            'the 1250 ms particle animation, and the watchdog RAM kill it '
            'caused.',
      );
      expect(
        produced,
        lessThanOrEqualTo(
          _kLayers * ((kFrames / (kInspireBandWindowMaxSkips + 1)).ceil() + 1),
        ),
        reason: 'the gate engaged but did not bound: $produced productions over '
            '$kFrames frames, against a ceiling of one per layer per '
            '${kInspireBandWindowMaxSkips + 1} frames',
      );
      expect(
        debugInspireBandSamplerStaleBands,
        staleBefore,
        reason: 'the production-budget / texture-cap backstop engaged on '
            'healthy frames — these '
            'numbers are then about an allocator ceiling, not about the gate',
      );

      // ── PHASE 3 · AND THE VALVE FIRES, SO NOTHING CAN FREEZE. ───────────
      expect(
        debugInspireBandSamplerForcedRefreshes,
        greaterThan(0),
        reason: 'no production was FORCED over $kFrames gated frames, so the '
            'freeze-proofing never ran. `PictureLayer.canvasBounds` is an '
            'estimate: without the valve a bound that lies small pins the band '
            'forever.',
      );
      expect(
        produced,
        greaterThanOrEqualTo(
          _kLayers * (kFrames ~/ (kInspireBandWindowMaxSkips + 1) - 1),
        ),
        reason: 'a layer went more than $kInspireBandWindowMaxSkips frames '
            'without producing: $produced productions over $kFrames frames is '
            'below the valve floor',
      );

      // ── PHASE 4 · A REPAINT INSIDE THE WINDOW, AND THE PIXELS. ──────────
      // The motes move INSIDE the top band's window now. The band must follow
      // them, and "follow" is asserted as pixels: the same tick sequence
      // rendered with the gate on and with it off, byte for byte.
      await tester.pumpWidget(_host(gapTop: 0));
      for (int i = 0; i < 4; i++) {
        await _frame(tester, tick: 200 + i);
      }

      const int kPixelFrames = 6;
      final int inWindowBefore = debugInspireBandSamplerProductions;
      final List<Uint8List> gated = <Uint8List>[];
      for (int i = 0; i < kPixelFrames; i++) {
        await _frame(tester, tick: 300 + i);
        gated.add(await _capture(tester));
      }
      final int inWindow =
          debugInspireBandSamplerProductions - inWindowBefore;
      expect(
        inWindow,
        greaterThanOrEqualTo(kPixelFrames),
        reason: 'content moved INSIDE the band window and the layer over it '
            'produced only $inWindow bands in $kPixelFrames frames — the '
            'signature is not seeing the window, which is a band lagging its '
            'own content',
      );

      debugInspireBandWindowGateDisabled = true;
      final List<Uint8List> ungated = <Uint8List>[];
      for (int i = 0; i < kPixelFrames; i++) {
        await _frame(tester, tick: 300 + i);
        ungated.add(await _capture(tester));
      }
      debugInspireBandWindowGateDisabled = false;

      final List<int> divergent = <int>[];
      for (int i = 0; i < kPixelFrames; i++) {
        bool same = gated[i].length == ungated[i].length;
        if (same) {
          for (int b = 0; b < gated[i].length; b++) {
            if (gated[i][b] != ungated[i][b]) {
              same = false;
              break;
            }
          }
        }
        if (!same) divergent.add(300 + i);
      }
      expect(
        divergent,
        isEmpty,
        reason: 'THE GATE CHANGED THE PIXELS. Ticks $divergent render '
            'differently with the gate on than with it off, over content '
            'animating inside the band window — that is a stale band, the one '
            'outcome this patch may not ship.',
      );
    },
    timeout: const Timeout(Duration(minutes: 10)),
  );
}
