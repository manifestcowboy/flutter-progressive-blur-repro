// ─────────────────────────────────────────────────────────────────────────
// Patch 4 band sampler (band backgrounds/filter gate): GLASS IN THE BAND
// WINDOW NO LONGER DISENGAGES THE WINDOW-SIGNATURE GATE.
//
// Before: a `BackdropFilterLayer` (every glass card, tile or pill) was
// an unknown layer to `_BandWindowSignature`, so any repaint ANYWHERE under a
// band that had glass in its window produced a band. Now blur/matrix/dilate/
// erode/colour filters are hashed by value.
//
//   1 · the band engaged and the walk recognised every layer (glass included);
//   2 · a repaint OUTSIDE the windows, with glass INSIDE one, is gated;
//   3 · a change to the glass ITSELF (its sigma) inside the window still
//       produces, and the pixels match the gate-off render byte for byte;
//   4 · a filter whose value cannot be hashed (a compose) is still unknown.
//
// RED-ARM (measured): drop the BackdropFilterLayer branch -> arm 1 reads
// `BackdropFilterLayer`. NOT a red arm: dropping `_mix(l.filter)` alone stays
// green, because a filter change goes through `RenderBackdropFilter.filter`'s
// `markNeedsPaint`, which re-records the pictures around it and moves the
// signature anyway. Mixing the filter is defence in depth for a layer whose
// filter is swapped without a repaint.
//
// Plain `flutter test` only: under `--enable-impeller` this rig's inner band
// lands on the bounded fallback (`_BoundedSamplerLayer`, still unknown to the
// walk), as in band_window_gate_test.dart.
//
// One process, one test (see band_window_gate_test.dart for why).
// ─────────────────────────────────────────────────────────────────────────

import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inspire_blur/inspire_blur.dart';
// ignore: implementation_imports
import 'package:inspire_blur/src/inspire_shaders.dart';

const double _kDpr = 3.0;
const Size _kView = Size(402, 874);

final ValueNotifier<int> _tick = ValueNotifier<int>(0);
final ValueNotifier<double> _sigma = ValueNotifier<double>(8);
final GlobalKey _boundary = GlobalKey();

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

Widget _host({bool compose = false}) {
  final Widget glass = ValueListenableBuilder<double>(
    valueListenable: _sigma,
    builder: (_, double s, __) => ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: s, sigmaY: s),
        child: const ColoredBox(
          color: Color(0x33FFFFFF),
          child: SizedBox(height: 150, width: 300),
        ),
      ),
    ),
  );
  return MediaQuery(
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
                child: Column(
                  children: <Widget>[
                    // Stripes for the glass to blur: inside the top window.
                    SizedBox(
                      height: 160,
                      child: Stack(children: <Widget>[
                        for (int i = 0; i < 8; i++)
                          Positioned(
                            left: i * 50.0,
                            top: 0,
                            bottom: 0,
                            width: 20,
                            child: const ColoredBox(color: Color(0xFF3060C0)),
                          ),
                        Positioned(left: 40, top: 5, child: glass),
                      ]),
                    ),
                    const SizedBox(height: 140),
                    // Between the two windows (top ends ~y250, bottom ~y620).
                    RepaintBoundary(
                      child: SizedBox(
                        height: 120,
                        child: CustomPaint(
                          painter: _MotePainter(_tick),
                          child: const SizedBox.expand(),
                        ),
                      ),
                    ),
                    if (compose)
                      ImageFiltered(
                        imageFilter: ui.ImageFilter.compose(
                          outer: ui.ImageFilter.blur(sigmaX: 1, sigmaY: 1),
                          inner: ui.ImageFilter.blur(sigmaX: 2, sigmaY: 2),
                        ),
                        child: const SizedBox(height: 400, width: 400),
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
}

Future<void> _frame(WidgetTester tester) async {
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 1)),
  );
  await tester.pump(const Duration(milliseconds: 16));
}

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
  testWidgets('glass in the band window is hashed, not unknown',
      (WidgetTester tester) async {
    tester.view.devicePixelRatio = _kDpr;
    tester.view.physicalSize = _kView * _kDpr;
    addTearDown(tester.view.reset);
    addTearDown(() => debugInspireBandWindowGateDisabled = false);

    await tester.pumpWidget(_host());
    await tester.runAsync(() => InspireShaders.childBlur);

    // 1 · engaged, and every layer recognised.
    debugInspireBandSamplerWindowUnknown = '';
    final int drawsBefore = debugInspireBandSamplerDraws;
    for (int i = 0; i < 10; i++) {
      _tick.value = i;
      await _frame(tester);
    }
    expect(debugInspireBandSamplerDraws, greaterThan(drawsBefore),
        reason: 'band path never engaged: $debugInspireBandSamplerReasons');
    expect(debugInspireBandSamplerWindowUnknown, '',
        reason: 'the walk still rejects a layer with glass in the window');

    // 2 · a repaint between the windows is gated despite the glass.
    const int kFrames = 24;
    final int skipsBefore = debugInspireBandSamplerWindowSkips;
    final int prodBefore = debugInspireBandSamplerProductions;
    for (int i = 0; i < kFrames; i++) {
      _tick.value = 100 + i;
      await _frame(tester);
    }
    expect(debugInspireBandSamplerWindowSkips, greaterThan(skipsBefore),
        reason: 'glass in the window still disengages the gate');
    expect(
      debugInspireBandSamplerProductions - prodBefore,
      lessThanOrEqualTo(
          2 * ((kFrames / (kInspireBandWindowMaxSkips + 1)).ceil() + 1)),
    );

    // 3 · the glass itself changing inside the window still produces, and
    //     the pixels equal the gate-off render.
    const int kPixelFrames = 6;
    final List<Uint8List> gated = <Uint8List>[];
    final int inBefore = debugInspireBandSamplerProductions;
    for (int i = 0; i < kPixelFrames; i++) {
      _sigma.value = 4.0 + i;
      await _frame(tester);
      gated.add(await _capture(tester));
    }
    expect(debugInspireBandSamplerProductions - inBefore,
        greaterThanOrEqualTo(kPixelFrames),
        reason: 'a sigma change on glass inside the window did not produce');
    debugInspireBandWindowGateDisabled = true;
    final List<Uint8List> ungated = <Uint8List>[];
    for (int i = 0; i < kPixelFrames; i++) {
      _sigma.value = 4.0 + i;
      await _frame(tester);
      ungated.add(await _capture(tester));
    }
    debugInspireBandWindowGateDisabled = false;
    for (int i = 0; i < kPixelFrames; i++) {
      expect(gated[i], orderedEquals(ungated[i]),
          reason: 'frame $i differs gate on vs off');
    }

    // 4 · an unhashable filter (compose) is still unknown => produce.
    await tester.pumpWidget(_host(compose: true));
    for (int i = 0; i < 6; i++) {
      _tick.value = 400 + i;
      await _frame(tester);
    }
    expect(debugInspireBandSamplerWindowUnknown, 'ImageFilterLayer');
  }, timeout: const Timeout(Duration(minutes: 10)));
}
