import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';
import 'package:inspire_blur/src/child_blur/inspire_bounded_sampler.dart';
import 'package:inspire_blur/src/color_adjustment/blur_color_adjustment.dart';
import 'package:inspire_blur/src/inspire_blur_config.dart';
import 'package:inspire_blur/src/inspire_shaders.dart';
import 'package:inspire_blur/src/transform/blur_transform.dart';
import 'package:inspire_blur/src/utils/extensions/inspire_geometry_extensions.dart';

class InspireChildBlurAnimatedSamplerPass extends StatefulWidget {
  final ui.Image gradientMap;
  final BlurTransform transform;
  final BlurColorAdjustment colorAdjustment;
  final Axis direction;
  final double sigma;
  final Widget child;

  /// Patch 5 kernel sampling modes (see PATCHES.md) · shader floats 24-25. See
  /// [InspireKernelSampling].
  final InspireKernelSampling sampling;

  const InspireChildBlurAnimatedSamplerPass({
    super.key,
    required this.gradientMap,
    required this.transform,
    required this.colorAdjustment,
    required this.direction,
    required this.sigma,
    this.sampling = InspireKernelSampling.unit,
    required this.child,
  });

  @override
  State<InspireChildBlurAnimatedSamplerPass> createState() =>
      _InspireChildBlurAnimatedSamplerPassState();
}

class _InspireChildBlurAnimatedSamplerPassState
    extends State<InspireChildBlurAnimatedSamplerPass> {
  ui.FragmentShader? _shader;

  @override
  void initState() {
    super.initState();
    _loadShader();
  }

  void _loadShader() {
    InspireShaders.childBlur.then((program) {
      final shader = program?.fragmentShader();
      if (mounted) {
        setState(() => _shader = shader);
      } else {
        _shader = shader;
      }
    });
  }

  @override
  void dispose() {
    _shader?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final shader = _shader;
    if (shader == null) return widget.child;

    // Patch 4 band sampler (production budget, bounded fallback sampler; see
    // PATCHES.md). `AnimatedSampler`'s layer calls `toImageSync` on the WHOLE
    // child once per ancestor walk with no frame stamp and no ceiling — the
    // unbounded producer that the band path already bounds, and that this
    // path never reached, although every band-sampler guard failure lands
    // here. Same draw, same pixels, bounded.
    return InspireBoundedSampler(
      // The pixel-deciding values behind the closure, so the layer's
      // cross-frame stale/re-serve compare survives this widget rebuilding
      // (a fresh closure) every scroll frame.
      pixelKey: (
        shader,
        widget.gradientMap,
        widget.transform,
        widget.colorAdjustment,
        widget.direction,
        widget.sigma,
        widget.sampling,
      ),
      (image, size, canvas) {
        // PATCHED vs upstream (PERF, Patch 7 MediaQuery aspects):
        // `devicePixelRatioOf`, not `of(...)` - the keyboard must not rebuild
        // this pass.
        final dpr = MediaQuery.devicePixelRatioOf(context);

        final normalizedOrigin = widget.transform.origin.toNormalizedOffset();

        shader
          ..setImageSampler(0, image)
          ..setImageSampler(1, widget.gradientMap)
          ..setFloat(0, size.width)
          ..setFloat(1, size.height)
          // To ensure 1:1 effective blur strength with ImageFilter.shader
          // when using same sigma values — divide sigma by dpr.
          ..setFloat(2, widget.sigma / dpr)
          ..setFloat(3, widget.direction == Axis.horizontal ? 1.0 : 0.0)
          ..setFloat(4, widget.direction == Axis.vertical ? 1.0 : 0.0)
          ..setFloat(5, 0.0)
          ..setFloat(6, 0.0)
          ..setFloat(7, 0.0)
          ..setFloat(8, 0.0)
          ..setFloat(9, widget.transform.scale.scaleX)
          ..setFloat(10, widget.transform.scale.scaleY)
          ..setFloat(11, widget.transform.offset.dx)
          ..setFloat(12, widget.transform.offset.dy)
          ..setFloat(13, widget.transform.rotation)
          ..setFloat(14, normalizedOrigin.dx)
          ..setFloat(15, normalizedOrigin.dy)
          ..setFloat(16, widget.transform.inversionFactor)
          ..setFloat(17, widget.colorAdjustment.shaderBrightness)
          ..setFloat(18, widget.colorAdjustment.shaderContrast)
          ..setFloat(19, widget.colorAdjustment.shaderExposure)
          ..setFloat(20, widget.colorAdjustment.shaderSaturation)
          ..setFloat(21, widget.colorAdjustment.shaderVibrance)
          ..setFloat(22, widget.colorAdjustment.blurAdjustmentStrength)
          ..setFloat(23, widget.colorAdjustment.nonBlurAdjustmentStrength)
          // Patch 5 kernel sampling modes · the texel here is LOGICAL, so a
          // device px is 1/dpr.
          ..setFloat(24, widget.sampling.shaderMode)
          ..setFloat(25, 1.0 / dpr);
        final paint = Paint()..shader = shader;
        canvas.drawRect(Offset.zero & size, paint);
      },
      child: widget.child,
    );
  }
}
