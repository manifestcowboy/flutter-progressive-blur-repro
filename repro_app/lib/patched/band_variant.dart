import 'package:flutter/widgets.dart';
import 'package:inspire_blur/inspire_blur.dart';

import '../common/blur_variant.dart';

/// `Inspire.childBlurBand` (patched package only): composites the real child
/// directly outside the blur band and snapshots only the band plus the
/// kernel's reach.
final BlurVariant bandChildBlur = BlurVariant(
  'Inspire.childBlurBand',
  (InspireBlurConfig config, Widget child) => Inspire.childBlurBand(
    config: config,
    child: child,
  ),
);
