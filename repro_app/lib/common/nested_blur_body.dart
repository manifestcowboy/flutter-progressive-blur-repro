import 'package:flutter/widgets.dart';
import 'package:inspire_blur/inspire_blur.dart';

import 'blur_util.dart';
import 'blur_variant.dart';
import 'constants.dart';

/// A scroll body under a header blur and, optionally, a footer blur, with the
/// footer blur WRAPPING the header blur which wraps [list].
///
/// This is the nesting that multiplies the work: an outer layer is walked once
/// per frame, the inner layer once per walk of the outer one.
class NestedBlurBody extends StatelessWidget {
  const NestedBlurBody({
    super.key,
    required this.variant,
    required this.list,
    this.header = true,
    this.footer = true,
  });

  final BlurVariant variant;
  final Widget list;
  final bool header;
  final bool footer;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints box) {
        final double sigma = deviceSigma(context, kBlurLogicalSigma);
        Widget content = list;
        if (header) {
          content = variant.wrap(
            InspireBlurConfig.topToBottom(
              sigma: sigma,
              extent: zoneExtent(kZoneHeight, box.maxHeight),
            ),
            content,
          );
        }
        if (footer) {
          content = variant.wrap(
            InspireBlurConfig.bottomToTop(
              sigma: sigma,
              extent: zoneExtent(kFooterZoneHeight, box.maxHeight),
            ),
            content,
          );
        }
        return content;
      },
    );
  }
}
