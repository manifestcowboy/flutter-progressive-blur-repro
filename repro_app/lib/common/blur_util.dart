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
