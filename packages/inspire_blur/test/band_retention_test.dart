// ─────────────────────────────────────────────────────────────────────────
// Patch 4 band sampler (same-frame reuse): THE BAND SAMPLER PARTICIPATES IN
// RETAINED RENDERING.
//
// THE DEFECT. `_InspireBandSamplerLayer.addToScene` ended with a third
// `_forceReAdd(firstChild)`, marking its whole child subtree dirty AFTER both
// walks were done. `ContainerLayer.updateSubtreeNeedsAddToScene` ORs a child's
// flag into its parent's on the next frame, so a subtree left dirty at the end
// of frame N makes this layer dirty at the start of frame N+1 — and a dirty
// layer never takes `addRetained`. Its `addToScene` ran, and this one
// rasterises two window-sized `toImageSync` targets when it does. Nothing had
// to repaint to keep that going: it fed itself.
//
// MEASURED on a real macOS engine (`test/probe/animation_probe.dart`, idle
// arm — vsync arriving, nothing in the tree repainting, 600 frames, a
// bottom-anchored band around a top-anchored one):
//
//   with the trailing force    1194 productions   2388 render targets
//   without it                    2 productions      4 render targets
//
// WHAT THIS FILE ASSERTS, and each assertion fails on a different regression:
//   1 · A QUIET SCENE COSTS NOTHING. Build scenes with no repaint anywhere and
//       the layer must be retained, not re-added. This is the one this
//       test exists for; restore the trailing `_forceReAdd` and it goes non-zero.
//       It is driven through `Layer.buildScene` rather than `pump` because
//       `flutter test` does not composite a frame with nothing dirty — MEASURED
//       here, and it is why a pump loop passes with the bug in place.
//   2 · A REPAINT STILL PRODUCES. The gate must be retention, not a cache: a
//       child that actually changed has to re-rasterise or the band freezes,
//       which is the failure mode worth more than the memory.
//   3 · THE BAND PATH ENGAGED AT ALL. Without it 1 and 2 both pass vacuously
//       on the upstream fallback composition.
//
// The composition is a bottom-anchored band wrapping a top-anchored one (a
// frosted footer around a scroll ramp), built out of two of this package's own
// samplers.
//
// ONE PROCESS, ONE `testWidgets`, three phases — the same shape the other band
// tests are forced into and for the same measured reason: only the FIRST test
// in a process ever engages the band composition, because the shader warm-up's
// bare `await` inside `runAsync` never completes in a later one.
// ─────────────────────────────────────────────────────────────────────────

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

/// Bumped only when a phase wants a real pixel change in the child.
final ValueNotifier<int> _tick = ValueNotifier<int>(0);

Widget _host() => MediaQuery(
      data: const MediaQueryData(size: _kView, devicePixelRatio: _kDpr),
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: SizedBox(
          width: _kView.width,
          height: _kView.height,
          child: InspireChildBlurBandSampler(
            // A bottom-anchored band (a frosted footer) wrapping a
            // top-anchored one (a scroll ramp), so the outer sampler walks the
            // inner one into its own snapshot scene as well as into the real
            // scene. One sampler is not the nested composition and it is not
            // the one that measured 1194 productions.
            config: InspireBlurConfig.bottomToTop(sigma: 20, extent: 0.2),
            child: InspireChildBlurBandSampler(
            config: InspireBlurConfig.topToBottom(sigma: 20, extent: 0.2),
            child: ColoredBox(
              color: const Color(0xFF000000),
              child: ListView(
                padding: EdgeInsets.zero,
                physics: const NeverScrollableScrollPhysics(),
                children: <Widget>[
                  SizedBox(
                    height: 4000,
                    child: ValueListenableBuilder<int>(
                      valueListenable: _tick,
                      builder: (BuildContext _, int n, Widget? __) => ColoredBox(
                        color: Color(0xFFC0C0C0 - (n % 3)),
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
      ),
    );

/// One frame with the real async machinery running — the mask generation and
/// the band-extent readback are both real `Future`s that `pump`'s fake-async
/// zone will never complete on its own.
Future<void> _frame(WidgetTester tester, {bool repaint = false}) async {
  if (repaint) _tick.value++;
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 1)),
  );
  await tester.pump(const Duration(milliseconds: 16));
}

void main() {
  testWidgets(
    'a quiet frame produces no band, a repaint still does',
    (WidgetTester tester) async {
      tester.view.devicePixelRatio = _kDpr;
      tester.view.physicalSize = _kView * _kDpr;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(_host());
      await tester.runAsync(() => InspireShaders.childBlur);

      // Settle: the mask has to generate and its band extent has to read back
      // before the band composition engages at all. Repaint while settling so
      // nothing is retained across the warm-up.
      final int drawsBefore = debugInspireBandSamplerDraws;
      for (int i = 0; i < 10; i++) {
        await _frame(tester, repaint: true);
      }
      expect(
        debugInspireBandSamplerDraws,
        greaterThan(drawsBefore),
        reason: 'PHASE 3 · the band composition never engaged, so phases 1 and '
            '2 measure the upstream fallback and prove nothing: '
            '$debugInspireBandSamplerReasons',
      );

      // ── PHASE 1 · A QUIET SCENE COSTS NOTHING. ────────────────────────
      //
      // Compositing is what has to be measured, and `flutter test` will not
      // hand it over through `pump`: MEASURED here, a pump with nothing dirty
      // never reaches `Layer.addToScene` at all (the counters sit still for 20
      // frames even with the trailing `_forceReAdd` restored), so a pump loop
      // passes whether the bug is present or not. So drive the same call the
      // engine drives — `buildScene` on the render view's root layer, which is
      // `updateSubtreeNeedsAddToScene` followed by the retained walk — and ask
      // the second one to cost nothing.
      await _frame(tester);
      // ignore: invalid_use_of_protected_member
      final ContainerLayer root = tester.binding.renderViews.first.layer!;
      root.buildScene(ui.SceneBuilder()).dispose();
      final int quietBefore = debugInspireBandSamplerProductions;
      for (int i = 0; i < 20; i++) {
        root.buildScene(ui.SceneBuilder()).dispose();
      }
      final int quiet = debugInspireBandSamplerProductions - quietBefore;
      expect(
        quiet,
        0,
        reason: 'THE ONE THIS FILE EXISTS FOR. 20 scenes were built with '
            'nothing repainting and the band samplers produced $quiet band '
            'pictures — two window-sized toImageSync render targets each. A '
            'layer that ends its addToScene with its own subtree marked dirty '
            'can never be retained: the framework ORs that flag back into it '
            'on the next frame, so it re-rasterises forever on a static '
            'screen. That is what the trailing _forceReAdd did, and on a real '
            'engine it cost 1194 productions over 600 idle frames. (Restored, '
            'this reads 6 rather than 40 — MEASURED: no frame '
            'stamp advances between these scenes, so each of the two sampler '
            'layers produces its per-stamp production allowance of '
            '$kInspireBandSamplerMaxOutstanding and then serves the stale '
            'band. Non-zero is the failure.)',
      );

      // ── PHASE 2 · A REPAINT STILL PRODUCES. ────────────────────────────
      final int liveBefore = debugInspireBandSamplerProductions;
      await _frame(tester, repaint: true);
      expect(
        debugInspireBandSamplerProductions,
        greaterThan(liveBefore),
        reason: 'the child repainted and the band did NOT re-rasterise — the '
            'band is frozen at an old picture, which is worse than the memory '
            'this patch is bounding',
      );
    },
  );
}
