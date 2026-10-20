// ─────────────────────────────────────────────────────────────────────────
// Patch 4 band sampler (band backgrounds/filter gate): `InspireBandBackground`:
// the band it is exempt from stops
// re-blurring for its content, every other band still sees it, and anything
// else in the window still forces a production.
//
//   1 · a background animating inside BOTH windows, marked exempt from the
//       BOTTOM anchor: the bottom band skips (valve-bounded), the top band
//       produces every frame;
//   2 · the marker's layer is known to the walk (no unknown layer), so the
//       top band's gate still works around it;
//   3 · content (not the background) changing inside the bottom window
//       produces on every frame — the freeze never hides real content.
//
// RED-ARM (measured): treat the marker as a plain OffsetLayer for every
// anchor -> arm 1's bottom skips stay 0.
//
// One process, one test (see band_window_gate_test.dart for why).
// Plain `flutter test`: under `--enable-impeller` this rig's inner band lands
// on the bounded fallback, as in that file.
// ─────────────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inspire_blur/inspire_blur.dart';
// ignore: implementation_imports
import 'package:inspire_blur/src/inspire_shaders.dart';

const double _kDpr = 3.0;
const Size _kView = Size(402, 874);

final ValueNotifier<int> _sky = ValueNotifier<int>(0);
final ValueNotifier<int> _content = ValueNotifier<int>(0);

class _Painter extends CustomPainter {
  _Painter(this.tick, this.color) : super(repaint: tick);
  final ValueNotifier<int> tick;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final double dx = (tick.value % 20).toDouble();
    // Ink at both ends, so it is inside both band windows.
    canvas.drawCircle(Offset(60 + dx, 40), 20, Paint()..color = color);
    canvas.drawCircle(
        Offset(60 + dx, size.height - 40), 20, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_Painter oldDelegate) => false;
}

Widget _host() => MediaQuery(
      data: const MediaQueryData(size: _kView, devicePixelRatio: _kDpr),
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: SizedBox(
          width: _kView.width,
          height: _kView.height,
          child: InspireChildBlurBandSampler(
            config: InspireBlurConfig.bottomToTop(sigma: 20, extent: 0.2),
            child: InspireChildBlurBandSampler(
              config: InspireBlurConfig.topToBottom(sigma: 20, extent: 0.2),
              child: ColoredBox(
                color: const Color(0xFF101010),
                child: Stack(children: <Widget>[
                  Positioned.fill(
                    child: InspireBandBackground(
                      exemptFrom: InspireBandAnchor.bottom,
                      child: RepaintBoundary(
                        child: CustomPaint(
                            painter: _Painter(_sky, const Color(0xFF3060C0))),
                      ),
                    ),
                  ),
                  Positioned.fill(
                    child: RepaintBoundary(
                      child: CustomPaint(
                          painter:
                              _Painter(_content, const Color(0xFFB03030))),
                    ),
                  ),
                ]),
              ),
            ),
          ),
        ),
      ),
    );

Future<void> _frame(WidgetTester tester) async {
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 1)),
  );
  await tester.pump(const Duration(milliseconds: 16));
}

void main() {
  testWidgets('a band background is exempt from its anchor only',
      (WidgetTester tester) async {
    tester.view.devicePixelRatio = _kDpr;
    tester.view.physicalSize = _kView * _kDpr;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_host());
    await tester.runAsync(() => InspireShaders.childBlur);
    debugInspireBandSamplerWindowUnknown = '';
    final int drawsBefore = debugInspireBandSamplerDraws;
    for (int i = 0; i < 10; i++) {
      _sky.value = i;
      await _frame(tester);
    }
    expect(debugInspireBandSamplerDraws, greaterThan(drawsBefore),
        reason: 'band path never engaged: $debugInspireBandSamplerReasons');

    // 1 + 2 · only the background moves.
    const int kFrames = 25;
    final int skips0 = debugInspireBandSamplerWindowSkips;
    final int prod0 = debugInspireBandSamplerProductions;
    for (int i = 0; i < kFrames; i++) {
      _sky.value = 100 + i;
      await _frame(tester);
    }
    final int produced = debugInspireBandSamplerProductions - prod0;
    expect(debugInspireBandSamplerWindowUnknown, '',
        reason: 'the marker layer is unknown to the walk');
    expect(debugInspireBandSamplerWindowSkips - skips0, greaterThan(0),
        reason: 'the bottom band re-blurred for an exempt background');
    // Top: one per frame. Bottom: the valve's 1 in (max skips + 1).
    expect(
      produced,
      inInclusiveRange(
        kFrames + kFrames ~/ (kInspireBandWindowMaxSkips + 1) - 1,
        kFrames + (kFrames / (kInspireBandWindowMaxSkips + 1)).ceil() + 1,
      ),
      reason: 'expected the top band every frame and the bottom band only '
          'on the valve: $produced over $kFrames frames',
    );

    // 3 · content (not the background) moves inside the bottom window.
    final int prod1 = debugInspireBandSamplerProductions;
    final int skips1 = debugInspireBandSamplerWindowSkips;
    for (int i = 0; i < kFrames; i++) {
      _content.value = 200 + i;
      await _frame(tester);
    }
    expect(debugInspireBandSamplerProductions - prod1, 2 * kFrames,
        reason: 'content under the band changed and a band did not follow');
    expect(debugInspireBandSamplerWindowSkips, skips1);
  }, timeout: const Timeout(Duration(minutes: 10)));
}
