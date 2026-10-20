import 'package:flutter/widgets.dart';
import 'package:inspire_blur/src/child_blur/inspire_child_blur_band_sampler.dart';
import 'package:inspire_blur/src/inspire_backdrop_blur.dart';
import 'package:inspire_blur/src/inspire_blur_config.dart';
import 'package:inspire_blur/src/inspire_blur_mode.dart';
import 'package:inspire_blur/src/inspire_child_blur.dart';
import 'package:inspire_blur/src/inspire_shaders.dart';
import 'package:inspire_blur/src/inspire_tint_api.dart';

/// API for the Inspire Blur widgets and utilities.
///
/// Provides convenient factories for child blur and backdrop blur.
class Inspire {
  const Inspire._();

  /// Preloads shaders used by Inspire Blur.
  ///
  /// This can help avoid a minor frame drop the first time a blur is rendered,
  /// especially on lower-end devices.
  ///
  /// Calling this is optional — shaders are loaded lazily on first use
  /// anyway, and in most cases this works perfectly fine.
  ///
  /// Consider using this if you want to ensure perfectly smooth first-time
  /// rendering (e.g. for animations or transitions).
  ///
  /// If used, it is recommended to call this early in the app lifecycle.
  /// For example:
  /// - In `main()` before `runApp()`.
  /// - During a splash screen or initial loading phase.
  ///
  /// This is most useful when blur effect appears immediately on screen.
  static Future<void> warmUp() async {
    try {
      await InspireShaders.backdropBlur;
      await InspireShaders.childBlur;
    } catch (_) {
      // Ignore missing assets in tests / unsupported platforms
    }
  }

  /// Blurs content behind this widget.
  ///
  /// It is a scene-level blur, meaning that the blur effect is applied
  /// to the scene rendered behind it.
  ///
  /// This is typically used for overlays, glass effects, or backgrounds.
  ///
  /// Similarly to [BackdropFilter], the [child] is drawn on top of the
  /// blurred background.
  ///
  /// By default, it blocks gestures from propagating to widgets below it.
  /// To allow gestures to pass-through it, wrap it in [IgnorePointer].
  static Widget backdropBlur({
    required InspireBlurConfig config,
    Clip clipBehavior = Clip.antiAlias,
    bool useRepaintBoundary = true,
    Object? layoutInvalidationKey,
    Widget? child,
  }) {
    return InspireBackdropBlur(
      config: config,
      clipBehavior: clipBehavior,
      useRepaintBoundary: useRepaintBoundary,
      layoutInvalidationKey: layoutInvalidationKey,
      child: child,
    );
  }

  /// Blurs only the given [child].
  ///
  /// It is a component-level blur, meaning that the blur effect is applied
  /// to the widget inside it.
  ///
  /// This is useful for blurring individual UI elements, such as cards,
  /// images, or components, without affecting the background.
  static Widget childBlur({
    required InspireBlurConfig config,
    required Widget child,
    InspireBlurMode mode = InspireBlurMode.auto,
    Clip clipBehavior = Clip.antiAlias,
    bool useRepaintBoundary = true,
    Object? layoutInvalidationKey,
  }) {
    return InspireChildBlur(
      config: config,
      mode: mode,
      clipBehavior: clipBehavior,
      useRepaintBoundary: useRepaintBoundary,
      layoutInvalidationKey: layoutInvalidationKey,
      child: child,
    );
  }

  /// Patch 4 band sampler (see PATCHES.md), not in upstream.
  ///
  /// Same effect as [childBlur] under `InspireBlurMode.animatedSampler`, with
  /// one composition change: everything OUTSIDE the mask's non-zero rows is
  /// composited into the real scene directly instead of through a texture round
  /// trip, and the snapshot the shader reads is clipped to the band plus the
  /// kernel's reach. It falls back to [childBlur] whenever a guard is unmet.
  ///
  /// The band anchors to whichever edge the mask ramps FROM, read off the
  /// gradient map rather than passed in — so this serves a top-anchored header
  /// ramp and a bottom-anchored frosted footer alike, and a mask that blurs
  /// both edges falls back. See `inspire_child_blur_band_sampler.dart` and
  /// PATCHES.md.
  static Widget childBlurBand({
    required InspireBlurConfig config,
    required Widget child,
    Clip clipBehavior = Clip.antiAlias,
    bool useRepaintBoundary = true,
    Object? layoutInvalidationKey,
    double realUnderlap = 0.0,
  }) {
    return InspireChildBlurBandSampler(
      config: config,
      clipBehavior: clipBehavior,
      useRepaintBoundary: useRepaintBoundary,
      layoutInvalidationKey: layoutInvalidationKey,
      realUnderlap: realUnderlap,
      child: child,
    );
  }

  /// API for the Inspire color tint widgets.
  static final tint = const InspireTintApi();
}
