import 'package:flutter/widgets.dart';
import 'package:inspire_blur/inspire_blur.dart';

import '../common/blur_variant.dart';

/// `Inspire.childBlur`, pinned to the animated-sampler renderer.
///
/// Every scenario here wraps a scroll view (the blur is the PARENT of the
/// Scrollable), where `InspireBlurMode.auto` would pick the image-filter
/// renderer on a phone. Pinning keeps the renderer fixed, except in S3 which
/// is about exactly that choice.
final BlurVariant stockChildBlur = BlurVariant(
  'Inspire.childBlur',
  (InspireBlurConfig config, Widget child) => Inspire.childBlur(
    config: config,
    mode: InspireBlurMode.animatedSampler,
    child: child,
  ),
);
