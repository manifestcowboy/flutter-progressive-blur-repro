import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

/// inspire_blur's `sigma` is in DEVICE px, not logical px.
///
/// Both child-blur passes agree on that: the image-filter pass hands sigma to
/// the shader as is (device px), the animated-sampler pass divides it by the
/// device pixel ratio first because its texture is logical. So a sigma of
/// 14.667 logical px, which is what `ImageFilter.blur` would want, has to be
/// passed as `14.667 * devicePixelRatio` (44 at 3x).
double deviceSigma(BuildContext context, double logicalSigma) =>
    logicalSigma * MediaQuery.devicePixelRatioOf(context);

/// A blur zone as a fraction of the blurred box's height, which is what the
/// `extent` of `InspireBlurConfig.topToBottom` / `bottomToTop` means.
double zoneExtent(double zone, double boxHeight) =>
    (zone / boxHeight).clamp(0.01, 0.99);

/// A 4 x 2048 grayscale ramp for `InspireBlurConfig.customMask`.
///
/// Red is the blur strength, 1 at the anchored edge easing to 0 at [extent]
/// (a fraction of the height) and staying 0 beyond. It is the same shape as
/// the package's own `easeInSine` directional ramp, but drawn once on the GPU
/// instead of by the package's synchronous Dart loop.
///
/// The caller owns the returned image and must dispose it.
ui.Image buildRampMaskImage({
  required double extent,
  bool fromBottom = false,
  Curve fadeCurve = Curves.easeInSine,
  int width = 4,
  int height = 2048,
}) {
  const int stops = 16;
  final List<Color> colors = <Color>[];
  final List<double> positions = <double>[];
  for (int i = 0; i < stops; i++) {
    final double t = i / (stops - 1);
    final int gray = (fadeCurve.transform(1 - t).clamp(0.0, 1.0) * 255).round();
    colors.add(Color.fromARGB(255, gray, gray, gray));
    positions.add(t);
  }
  final double h = height.toDouble();
  final ui.Gradient gradient = ui.Gradient.linear(
    Offset(0, fromBottom ? h : 0),
    Offset(0, fromBottom ? h * (1 - extent) : h * extent),
    colors,
    positions,
  );
  final ui.PictureRecorder recorder = ui.PictureRecorder();
  Canvas(recorder).drawRect(
    Rect.fromLTWH(0, 0, width.toDouble(), h),
    Paint()..shader = gradient,
  );
  final ui.Picture picture = recorder.endRecording();
  final ui.Image image = picture.toImageSync(width, height);
  picture.dispose();
  return image;
}
