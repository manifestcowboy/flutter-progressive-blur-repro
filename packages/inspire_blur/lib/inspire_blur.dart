/// Inspire Blur provides high-performance progressive and variable blur
/// effects for Flutter.
///
/// The package includes:
/// * Child blur and backdrop blur widgets
/// * Directional and shape-based blur distributions
/// * Tint effects
/// * GPU shader-powered rendering optimized for Impeller
///
/// Designed for building modern, visually rich Flutter interfaces.
library;

export 'src/color_adjustment/blur_color_adjustment.dart'
    show BlurColorAdjustment;
export 'src/distribution/blur_distribution.dart';
// Patch 4 band sampler. See src/child_blur/inspire_child_blur_band_sampler.dart
// and PATCHES.md.
export 'src/child_blur/inspire_child_blur_band_sampler.dart'
    show
        InspireBandAnchor,
        InspireBandSpan,
        InspireChildBlurBandSampler,
        InspireBandBackground,
        debugInspireBandSamplerComposites,
        debugInspireBandSamplerDraws,
        debugInspireBandSamplerForcedRefreshes,
        debugInspireBandSamplerGeometry,
        debugInspireBandSamplerPictureReuse,
        debugInspireBandSamplerTextures,
        debugInspireBandSamplerTargetPixels,
        debugInspireBandSamplerPaintAnchor,
        debugInspireBandSamplerPaints,
        debugInspireBandSamplerScenes,
        debugInspireBandSamplerProduceReason,
        debugInspireBandSamplerProductions,
        debugInspireBandSamplerMarks,
        debugInspireBandSamplerReasons,
        debugInspireBandSamplerSceneOrder,
        debugInspireBandSamplerStaleBands,
        debugInspireBandSamplerWindowSkips,
        debugInspireBandTightWindowDisabled,
        debugInspireBandWindowGateDisabled,
        debugInspireBandSamplerWindowUnknown,
        inspireBandSamplerReach,
        inspireBandSamplerTightWindowHeight,
        inspireBandSamplerWindowHeight,
        kInspireBandWindowMaxSkips;
// Patch 4 band sampler (production budget, bounded fallback sampler). The one
// production budget, and the bounded whole-child sampler the FALLBACK
// composition draws through. See PATCHES.md.
export 'src/child_blur/inspire_bounded_sampler.dart'
    show
        InspireBoundedSampler,
        InspireProductionBudget,
        InspireTextureLedger,
        debugInspireBoundedSamplerComposites,
        debugInspireBoundedSamplerPictureReuse,
        debugInspireBoundedSamplerScenes,
        debugInspireBoundedSamplerStalePictures,
        debugInspireBoundedSamplerTargets,
        debugInspireLiveSamplerImages,
        debugInspireOutstandingTextures,
        kInspireBandSamplerMaxOutstanding,
        kInspireMaxOutstandingTextures;
export 'src/inspire_backdrop_blur.dart' show InspireBackdropBlur;
export 'src/inspire_blur.dart' show Inspire;
export 'src/inspire_blur_config.dart'
    show InspireBlurConfig, InspireKernelSampling;
export 'src/inspire_blur_mode.dart' show InspireBlurMode;
export 'src/inspire_child_blur.dart' show InspireChildBlur;
export 'src/inspire_tint_api.dart' show InspireTintApi;
export 'src/model/blur_scale.dart' show BlurScale;
export 'src/transform/blur_transform.dart' show BlurTransform;
