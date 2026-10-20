import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:inspire_blur/src/color_adjustment/blur_color_adjustment.dart';
import 'package:inspire_blur/src/inspire_shaders.dart';
import 'package:inspire_blur/src/transform/blur_transform.dart';
// Patch 1 imageFilter mask deltas (see PATCHES.md): `inspire_double_extensions.dart`
// was imported here for takeNegativeOrZero/takePositiveOrZero, used only by the
// screen-relative deltas this patch zeroes out (see paint()). Dropped with them.
import 'package:inspire_blur/src/utils/extensions/inspire_geometry_extensions.dart';

class InspireChildBlurImageFilterPass extends StatefulWidget {
  final ui.Image gradientMap;
  final BlurTransform transform;
  final BlurColorAdjustment colorAdjustment;
  final Axis direction;
  final double sigma;
  final Widget child;

  const InspireChildBlurImageFilterPass({
    super.key,
    required this.gradientMap,
    required this.transform,
    required this.colorAdjustment,
    required this.direction,
    required this.sigma,
    required this.child,
  });

  @override
  State<InspireChildBlurImageFilterPass> createState() =>
      _InspireChildBlurImageFilterPassState();
}

class _InspireChildBlurImageFilterPassState
    extends State<InspireChildBlurImageFilterPass> {
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
        setState(() {
          _shader = shader;
        });
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

    return _BlurFiltered(
      shader: shader,
      gradientMap: widget.gradientMap,
      transform: widget.transform,
      colorAdjustment: widget.colorAdjustment,
      direction: widget.direction,
      sigma: widget.sigma,
      child: widget.child,
    );
  }
}

class _BlurFiltered extends SingleChildRenderObjectWidget {
  final ui.FragmentShader shader;
  final ui.Image gradientMap;
  final BlurTransform transform;
  final BlurColorAdjustment colorAdjustment;
  final Axis direction;
  final double sigma;

  const _BlurFiltered({
    super.child,
    required this.shader,
    required this.gradientMap,
    required this.transform,
    required this.colorAdjustment,
    required this.direction,
    required this.sigma,
  });

  @override
  RenderObject createRenderObject(BuildContext context) {
    final scrollPosition = Scrollable.maybeOf(context)?.position;
    final view = View.of(context);

    return _BlurFilterRenderObject(
      shader,
      gradientMap,
      transform,
      colorAdjustment,
      direction,
      sigma,
      scrollPosition,
      _getScreenSize(view),
      _getDpr(context),
    );
  }

  @override
  void updateRenderObject(
    BuildContext context,
    _BlurFilterRenderObject renderObject,
  ) {
    final scrollPosition = Scrollable.maybeOf(context)?.position;
    final view = View.of(context);

    renderObject
      ..shader = shader
      ..gradientMap = gradientMap
      ..transform = transform
      ..colorAdjustment = colorAdjustment
      ..direction = direction
      ..sigma = sigma
      ..scrollPosition = scrollPosition
      ..screenSize = _getScreenSize(view)
      ..dpr = _getDpr(context);
  }

  Size _getScreenSize(ui.FlutterView view) =>
      view.physicalSize / view.devicePixelRatio;

  // PATCHED vs upstream (PERF, Patch 7 MediaQuery aspects):
  // `devicePixelRatioOf`, not `of(...)` - the keyboard must not rebuild this
  // pass.
  double _getDpr(BuildContext context) =>
      MediaQuery.devicePixelRatioOf(context);
}

class _BlurFilterRenderObject extends RenderProxyBox {
  ui.ImageFilter? _imageFilter;

  ui.FragmentShader _shader;
  set shader(ui.FragmentShader value) {
    if (identical(_shader, value)) return;
    _shader = value;
    _updateShader();
  }

  ui.Image _gradientMap;
  set gradientMap(ui.Image value) {
    if (_gradientMap == value) return;
    _gradientMap = value;
    _updateShader();
  }

  BlurTransform _transform;
  set transform(BlurTransform value) {
    if (_transform == value) return;
    _transform = value;
    _updateShader();
  }

  BlurColorAdjustment _colorAdjustment;
  set colorAdjustment(BlurColorAdjustment value) {
    if (_colorAdjustment == value) return;
    _colorAdjustment = value;
    _updateShader();
  }

  Axis _direction;
  set direction(Axis value) {
    if (_direction == value) return;
    _direction = value;
    _updateShader();
  }

  double _sigma;
  set sigma(double value) {
    if (_sigma == value) return;
    _sigma = value;
    _updateShader();
  }

  Size _screenSize;
  set screenSize(Size value) {
    if (_screenSize == value) return;
    _screenSize = value;
    markNeedsPaint();
  }

  double _dpr;
  set dpr(double value) {
    if (_dpr == value) return;
    _dpr = value;
    markNeedsPaint();
  }

  ScrollPosition? _scrollPosition;
  set scrollPosition(ScrollPosition? value) {
    if (_scrollPosition == value) return;
    _detachListener();
    _scrollPosition = value;
    _attachListener();
  }

  _BlurFilterRenderObject(
    this._shader,
    this._gradientMap,
    this._transform,
    this._colorAdjustment,
    this._direction,
    this._sigma,
    this._scrollPosition,
    this._screenSize,
    this._dpr,
  ) {
    _updateShader();
  }

  Rect? _lastPaintedBounds;
  bool? _wasFullyVisible;

  void _attachListener() {
    if (!attached) return;
    _scrollPosition?.addListener(_onPositionChanged);
  }

  void _detachListener() => _scrollPosition?.removeListener(_onPositionChanged);

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _attachListener();
  }

  @override
  void detach() {
    _detachListener();
    super.detach();
  }

  void _onPositionChanged() {
    if (!attached) return;

    final bounds = localToGlobal(Offset.zero) & size;
    final isFullyVisible = _isFullyVisible(bounds, _screenSize);

    if (!_shouldRepaint(bounds, isFullyVisible)) return;

    _wasFullyVisible = isFullyVisible;
    markNeedsPaint();
  }

  bool _isFullyVisible(Rect bounds, Size screenSize) {
    return bounds.top >= 0 &&
        bounds.bottom <= screenSize.height &&
        bounds.left >= 0 &&
        bounds.right <= screenSize.width;
  }

  bool _shouldRepaint(Rect bounds, bool isFullyVisible) {
    // If widget is still fully visible, no repaint is needed.
    // Flutter will simply offset the existing layer (when in RepaintBoundary).
    if (isFullyVisible && _wasFullyVisible == true) {
      return false;
    }

    if (bounds == _lastPaintedBounds) {
      return false;
    }

    return true;
  }

  void _updateShader() {
    final normalizedOrigin = _transform.origin.toNormalizedOffset();

    _shader.setImageSampler(1, _gradientMap);
    _shader.setFloat(2, _sigma);
    _shader.setFloat(3, _direction == Axis.horizontal ? 1.0 : 0.0);
    _shader.setFloat(4, _direction == Axis.vertical ? 1.0 : 0.0);
    _shader.setFloat(9, _transform.scale.scaleX);
    _shader.setFloat(10, _transform.scale.scaleY);
    _shader.setFloat(11, _transform.offset.dx);
    _shader.setFloat(12, _transform.offset.dy);
    _shader.setFloat(13, _transform.rotation);
    _shader.setFloat(14, normalizedOrigin.dx);
    _shader.setFloat(15, normalizedOrigin.dy);
    _shader.setFloat(16, _transform.inversionFactor);
    _shader.setFloat(17, _colorAdjustment.shaderBrightness);
    _shader.setFloat(18, _colorAdjustment.shaderContrast);
    _shader.setFloat(19, _colorAdjustment.shaderExposure);
    _shader.setFloat(20, _colorAdjustment.shaderSaturation);
    _shader.setFloat(21, _colorAdjustment.shaderVibrance);
    _shader.setFloat(22, _colorAdjustment.blurAdjustmentStrength);
    _shader.setFloat(23, _colorAdjustment.nonBlurAdjustmentStrength);

    _recreateImageFilter();
    markNeedsPaint();
  }

  void _recreateImageFilter() {
    _imageFilter = ui.ImageFilter.shader(_shader);
  }

  @override
  void paint(PaintingContext context, ui.Offset offset) {
    final childValue = child;
    if (childValue == null) return;

    final newBounds = localToGlobal(Offset.zero) & size;

    if (_lastPaintedBounds?.isNotClose(newBounds) ?? true) {
      _lastPaintedBounds = newBounds;

      // ── Patch 1 imageFilter mask deltas · PATCHED vs upstream. ───────────
      // Upstream wrote screen-relative deltas here:
      //     deltaLeft   = bounds.left.takeNegativeOrZero().abs()
      //     deltaTop    = bounds.top .takeNegativeOrZero().abs()
      //     deltaRight  = (bounds.right  - _screenSize.width ).takePositiveOrZero()
      //     deltaBottom = (bounds.bottom - _screenSize.height).takePositiveOrZero()
      //     setFloat(5..8, delta * _dpr)
      // — i.e. how far the child spills off each screen edge, in device px.
      // The shader folds uniforms 5-8 straight into the gradient-map lookup
      // (`shaders/inspire_blur_child.frag`):
      //     uv_blur = (xy + u_delta_left_top)
      //             / (u_size + u_delta_left_top + u_delta_right_bottom)
      // i.e. they shift AND rescale the mask — they are the mask's denominator.
      // The animatedSampler pass writes 0.0 into all four
      // (`inspire_child_blur_animated_sampler_pass.dart`), unconditionally.
      // So the two passes ramp over different denominators and CANNOT render
      // the same blur, which is half of the imageFilter-vs-animatedSampler
      // mismatch that was measured (the other half is the MAX_RADIUS unit
      // mismatch, Patch 2, patched in the .frag).
      // Zeroed to match the sampler exactly. The intended topology is a ramp
      // that is the scroll view's PARENT and is on-screen by construction, so
      // there these deltas were only ever a correction for a case that does
      // not occur.
      _shader.setFloat(5, 0.0);
      _shader.setFloat(6, 0.0);
      _shader.setFloat(7, 0.0);
      _shader.setFloat(8, 0.0);

      _imageFilter = ui.ImageFilter.shader(_shader);
    }

    final ImageFilterLayer filterLayer = ImageFilterLayer(
      imageFilter: _imageFilter,
    );

    context.pushLayer(filterLayer,
        (PaintingContext childContext, Offset childOffset) {
      // ── Patch 3 imageFilter coverage clip · PATCHED vs upstream. ─────────
      // MEASURED (dpr-3 1:1 preview rig, debug shader that renders `uv.y` and
      // the mask lookup instead of the blur):
      //
      //   surface                      u_size.y (dev px)  texture top vs screen row 0
      //   list screen, at rest         2553.5             -1.4    → mask starts at 1.00
      //   screen with scrolling sky    2738.3             -248.5  → mask starts at 0.37
      //
      // `ui.ImageFilter.shader` sets the shader's first vec2 (`u_size`) to
      // "the size of the bound texture" (`dart:ui` painting.dart), and
      // `FlutterFragCoord()` is relative to that texture's origin — NOT to
      // this render object's box. The bound texture is the ImageFilterLayer's
      // COVERAGE, i.e. whatever the child subtree actually painted. The shader
      // divides by `u_size` and looks the gradient map up in that space
      // (`inspire_blur_child.frag`: `uv_blur = xy / u_size`), so any subtree
      // that paints outside the box stretches AND shifts the whole ramp.
      //
      // The second surface does exactly that, and the reason is ONE unclipped
      // translate — not anything inside the background widget. The shell puts
      // the sky INSIDE the ramp subtree and scrolls it with
      //     Stack(fit: StackFit.expand, children: [
      //       ValueListenableBuilder(... builder: (_, y, sky) =>
      //           Transform.translate(offset: Offset(0, -y), child: sky)),
      //       ...])
      // The sky is a NON-POSITIONED stack child, so it is laid out at the
      // viewport size and then painted `y` logical px ABOVE the box.
      // `RenderStack.performLayout` sets `_hasVisualOverflow` only in the
      // `childParentData.isPositioned` branch (`rendering/stack.dart`), so a
      // non-positioned child that overflows never trips the stack's clip and
      // nothing else on the path clips it either. The overhang is therefore
      // exactly scroll-offset x dpr: 248.5 device px (82.8 pt) at the ~85 pt
      // offset the capture was taken at — 45.4% of the ramp's whole length
      // spent off-screen, and the visible band then ends ~71 pt early.
      //
      // That also explains every other measured fact: the overhang tracks the
      // scroll offset (hence the scroll-state dependence), it stops growing at
      // the bottom stop, and the list screen — same shell, same sky, but at
      // rest — overhangs ~0 (-1.4 device px). The sky widget itself is NOT the
      // culprit: the sky is wrapped in `IgnorePointer(ClipRect(...))`, and the
      // parameter-driven variant — the only thing that owns the
      // `ImageFiltered` glow circles at a negative `top` — is itself inside a
      // `ClipRect`, so those circles cannot escape their own box, let alone
      // the ramp's.
      //
      // `animatedSampler` is immune by construction: it sets `u_size` itself
      // from the widget's own `size` and draws `Offset.zero & size`
      // (`inspire_child_blur_animated_sampler_pass.dart`). Clipping the
      // filtered child to that same box is what makes the two passes agree.
      //
      // Visually this clip is a no-op: `InspireChildBlur` already wraps the
      // whole pass in a `ClipRect` of the same box (`inspire_child_blur.dart`
      // `_wrapWithClipRect`), so the overhang was never visible — it only ever
      // corrupted `u_size`.
      childContext.pushClipRect(
        true,
        childOffset,
        Offset.zero & size,
        (PaintingContext clipContext, Offset clipOffset) {
          clipContext.paintChild(childValue, clipOffset);
        },
        clipBehavior: Clip.hardEdge,
      );
    }, offset);
  }
}
