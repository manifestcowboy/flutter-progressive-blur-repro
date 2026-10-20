import 'package:flutter/widgets.dart';
import 'package:inspire_blur/inspire_blur.dart';

/// Wraps [child] in a blur described by [config].
typedef BlurWrap = Widget Function(InspireBlurConfig config, Widget child);

/// One way of applying the same blur, so a scenario can offer an A/B toggle.
///
/// The stock variant uses `Inspire.childBlur`; the patched entrypoint adds one
/// for `Inspire.childBlurBand`. Keeping the choice behind this class is what
/// lets the scenario screens compile against the pristine 0.4.1 package.
class BlurVariant {
  const BlurVariant(this.label, this.wrap);

  final String label;
  final BlurWrap wrap;
}
