// Portions of this file are derived from `flutter_shaders` 0.1.3
// (`lib/src/animated_sampler.dart`):
//   Copyright 2013 The Flutter Authors. All rights reserved.
//   Use of this source code is governed by a BSD-style license.
//
// ── Patch 4 band sampler (production budget, bounded fallback sampler) · NEW
// FILE, not in upstream. See PATCHES.md. ────────────────────────────────────
//
// THE INVARIANT THIS FILE EXISTS TO MAKE TRUE: **no code path in the child-blur
// layer may outrun the raster thread unboundedly.** The band sampler's per-frame
// and per-frame-STAMP bounds cover the BAND path, and neither reached
// `InspireChildBlurBandSampler._fallback()`, the upstream
// `InspireChildBlur(animatedSampler)` composition that EVERY guard failure lands
// on (and which a caller selects wholesale by not using the band sampler).
//
// NOT the pre-shader window, which costs nothing and used to be claimed here:
// while `InspireShaders.childBlur` is unresolved the fallback's own pass returns
// the BARE CHILD (`inspire_child_blur_animated_sampler_pass.dart` — `if (shader
// == null) return widget.child`), and it is the same cached future both sides
// await, so those frames allocate ZERO. The window is real; its cost is not.
//
// That path samples through `flutter_shaders`' `AnimatedSampler`, whose layer
// (`_ShaderSamplerBuilderLayer.addToScene`) calls `toImageSync` once per
// ANCESTOR WALK, unconditionally: no frame stamp, no ceiling, and — unlike the
// band — the target is the WHOLE CHILD, not the band's ~21% window. MEASURED on
// a 402x874 dpr-3 rig with a real guard failure driving the fallback: 120
// out-of-band walks between two frames allocated **246** targets of
// 1206x2622x4 = 12.65 MB each, i.e. **3.11 GB** outstanding, posted to the
// raster thread out of band of the frame pipeline
// (`dart:ui.Picture.toImageSync` — "created and returned synchronously, but
// rasterized asynchronously").
//
// WHAT THAT NUMBER IS AND IS NOT. It is the worst case of a real unbounded
// producer, and its magnitude MATCHES a device memory kill that was captured
// (iPhone 17 Pro, release: `memorystatus: Runner exceeded mem limit:
// ActiveHard 3376 MB (fatal)`, 2.5 s after a swipe-remove animation settled on
// a list screen). It is NOT that kill explained: a test of that screen showed
// it stays on the BAND path at every list length, and no code in the app
// drove the out-of-band burst this file measures. **The device's driver is
// still unidentified.** This closes a producer that could have done it; the
// next device capture (a memory trace) is what will say whether it did.
//
// SO THE FALLBACK GETS THE BAND SAMPLER'S OWN MECHANISM — SHARED, NOT COPIED.
// [InspireProductionBudget] is the drain-and-cap the band sampler uses, lifted
// out of `_InspireBandSamplerLayer` verbatim so there is ONE of it: the drain is
// the frame stamp advancing (the engine's pipeline is two deep and the animator
// does not begin a frame while it is full, so a new stamp is proof the raster
// thread consumed one — zero reporting latency, in release and in tests), a run
// of null stamps counts as ONE stamp (that is exactly the out-of-band burst),
// and past [kInspireBandSamplerMaxOutstanding] productions the layer re-serves
// the last picture it made on the same geometry.
//
// WHAT THE BOUND COSTS WHEN IT ENGAGES, and it is the same trade as the band's:
// one picture as old as this layer's last production for this geometry, instead
// of an allocator kill. GEOMETRY IS NOT STALE-ABLE — a changed size, dpr or
// pixel key (the shader inputs behind the callback; the callback object itself
// when no key is given) always produces, because a picture for a different box
// is not one frame out of date, it is the wrong picture in the wrong place.
// Nothing drawing at frame rate can reach the bound, because a frame resets
// the count.

import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

/// How many productions a layer may make against ONE frame stamp before it
/// serves the last thing it made instead of making a new one.
///
/// The band sampler's number, and deliberately the same one for both paths: it is a
/// property of the engine's pipeline depth, not of what is being rasterised.
const int kInspireBandSamplerMaxOutstanding = 3;

// ── Patch 4 band sampler (texture ledger) · THE CROSS-FRAME CEILING, WITH A
// REAL COMPLETION SIGNAL ────────────────────────────────────────────────────
//
// The per-stamp drain — the frame stamp advancing — bounds production per frame,
// and its premise ("a new stamp is proof raster consumed one") is true of FRAMES
// and false of TEXTURES: the pipeline being two deep throttles scene raster,
// but `toImageSync` targets are posted to the raster task runner OUT OF BAND
// and their GPU memory is reclaimed whenever raster (and the allocator behind
// it) gets there. Under any SUSTAINED animation the samplers therefore produce
// two band-sized textures per frame while reclamation lags, and nothing above
// bounds the OUTSTANDING set. MEASURED on macOS with a real raster thread
// (`test/probe/animation_probe.dart`): a plain scroll fling grew phys_footprint
// by ~300 MB (bandTex 2 -> 180); a long particle animation under the band
// 94 -> 686 MB; on device the same curve ends at jetsam
// (`ActiveHard 3376 MB (fatal)`).
//
// THE SIGNAL. Dart still has no per-image raster callback, but the raster
// task runner is a FIFO queue and `ui.Picture.toImage` completes on the UI
// thread after ITS rasterisation ran there — so a 1x1 "echo" posted after N
// `toImageSync` productions completes only once those N rasterisations have
// been consumed. That is a real, low-latency completion signal, unlike the
// two that were rejected (`ui.Image.dispose` frees the Dart handle only;
// `FrameTiming` is batched up to ~1s in release).
//
// THE LEDGER. Every `toImageSync` in this package increments a single global
// outstanding count; at most one echo is in flight, covering everything
// produced before it was posted; completion retires that cohort. Past
// [kInspireMaxOutstandingTextures] outstanding, layers with a same-geometry
// picture re-serve it (the stale path — a band refresh frame dropped, which
// is invisible) instead of producing; a geometry change still always
// produces, because a picture for a different box is the wrong picture, not
// an old one. Retirement is production-driven (the echo pending at cap was
// posted by the last production), so the cap can never latch shut.
//
// FAIL OPEN, ARM ON PROOF. The cap only engages once one echo has ever
// completed in this process: an environment whose engine futures never
// deliver (a fake-async test zone) gives no signal, and a ceiling with no
// drain would freeze the blur at the first cap-full of pictures — worse
// there than the leak it bounds, where no real GPU is filling up anyway. An
// echo that ERRORS retires its cohort for the same reason.

/// The ceiling on `toImageSync` render targets this package may have
/// outstanding (produced, not yet proven consumed by the raster thread)
/// across ALL its layers and frames.
///
/// Sized against the band composition: two layers, two window-sized
/// targets each per frame, echo round-trip of a frame or two on a healthy
/// device — steady state well under 16. 32 leaves headroom for a nested
/// third sampler and a slow first echo; at the measured 2.25 MB per
/// target it caps the package's worst-case outstanding at ~72 MB, against
/// the unbounded climb that ended at 3.3 GB.
const int kInspireMaxOutstandingTextures = 32;

/// The outstanding-textures GAUGE (not a monotone counter): mirrors
/// [InspireTextureLedger]'s live count in debug builds. The cross-frame
/// sibling of `debugInspireBandSamplerTextures`, which only ever goes up.
int debugInspireOutstandingTextures = 0;

/// The one global ledger of outstanding `toImageSync` textures — see
/// the block comment above for the mechanism.
class InspireTextureLedger {
  InspireTextureLedger._();

  static int _outstanding = 0;
  static int _sinceEcho = 0;
  static bool _echoPending = false;
  static bool _armed = false;

  /// Whether the ceiling is engaged: armed (one echo has completed, so the
  /// signal is live in this environment) AND at or past the cap.
  ///
  /// IT HAS NEVER FIRED, AND IT DOES NOT MEASURE WHAT ITS NAME SAYS.
  /// MEASURED on a real macOS engine over 3000 frames of sustained animation
  /// (`test/probe/animation_probe.dart`): `_outstanding` read 0 and the stale path
  /// read 0 at EVERY sample, while `phys_footprint` sawtoothed 350 -> 950 MB
  /// and ~600 MB sat unreclaimed. The echo completes when the raster thread
  /// has RASTERISED the cohort — not when the GPU has RECLAIMED its textures,
  /// which is the thing that actually fills memory and which Dart cannot
  /// observe. So this cap is a rasterisation-backlog bound, it is a correct
  /// one, and it is not a memory bound. Do not read a passing `atCap` as
  /// evidence that texture memory is under control.
  static bool get atCap =>
      _armed && _outstanding >= kInspireMaxOutstandingTextures;

  /// One `toImageSync` target was allocated. Called at every production site
  /// in this package, in release builds too — the ledger IS the mechanism,
  /// not telemetry.
  static void produced() {
    _outstanding++;
    _sinceEcho++;
    if (kDebugMode) debugInspireOutstandingTextures = _outstanding;
    _ensureEcho();
  }

  static void _ensureEcho() {
    if (_echoPending || _sinceEcho == 0) return;
    _echoPending = true;
    final int covered = _sinceEcho;
    _sinceEcho = 0;
    // A [debugReset] while this echo is in flight zeroes the
    // ledger; letting the echo land afterwards would retire a cohort the
    // reset already forgot and drive `_outstanding` negative. The epoch makes
    // a reset orphan every echo it outlives.
    final int epoch = _epoch;
    final ui.PictureRecorder recorder = ui.PictureRecorder();
    ui.Canvas(recorder);
    final ui.Picture picture = recorder.endRecording();
    picture.toImage(1, 1).then((ui.Image image) {
      image.dispose();
      if (epoch != _epoch) return;
      _armed = true;
      _completed(covered);
    }).catchError((Object _) {
      // Fail open: an environment that cannot rasterise an echo cannot be
      // filling a GPU either, and must not freeze the blur.
      if (epoch != _epoch) return;
      _completed(covered);
    });
    picture.dispose();
  }

  /// Bumped by [debugReset] so an echo posted before a reset cannot retire
  /// (or arm) against the state after it.
  static int _epoch = 0;

  static void _completed(int covered) {
    _echoPending = false;
    if (debugHoldEchoes) {
      // Test-only stall: the raster thread has "answered" but retirement is
      // withheld, which is what a raster thread that has stopped reclaiming
      // looks like to the ledger. Keep echoing so arming still happens.
      _held += covered;
      _ensureEcho();
      return;
    }
    _retire(covered);
  }

  static void _retire(int covered) {
    _outstanding -= covered;
    if (kDebugMode) debugInspireOutstandingTextures = _outstanding;
    _ensureEcho();
  }

  /// Test-only: while true, completed echoes do NOT retire their cohort —
  /// the deterministic stand-in for a raster thread whose reclamation lags
  /// production, which no test environment exhibits for real (the automated
  /// test binding rasterises inline). [debugReleaseEchoes] retires the
  /// withheld cohorts.
  @visibleForTesting
  static bool debugHoldEchoes = false;
  static int _held = 0;

  /// Test-only: end a [debugHoldEchoes] stall and retire everything held.
  @visibleForTesting
  static void debugReleaseEchoes() {
    debugHoldEchoes = false;
    final int held = _held;
    _held = 0;
    if (held > 0) _retire(held);
  }

  /// Test-only: whether one echo has ever completed (the cap is live).
  @visibleForTesting
  static bool get debugArmed => _armed;

  /// Test-only: forget everything, including armed state. An echo in flight
  /// is orphaned (see `_epoch`), never applied to the reset state.
  @visibleForTesting
  static void debugReset() {
    _epoch++;
    _outstanding = 0;
    _sinceEcho = 0;
    _echoPending = false;
    _armed = false;
    _held = 0;
    debugHoldEchoes = false;
    debugInspireOutstandingTextures = 0;
  }
}

/// `toImageSync` targets allocated by [InspireBoundedSampler] — the FALLBACK
/// composition's counter, the whole-child sibling of
/// `debugInspireBandSamplerTextures`.
int debugInspireBoundedSamplerTargets = 0;

/// Pictures served STALE by the backstop (production ran past the bound against
/// one frame stamp). Zero on every normally-draining frame.
int debugInspireBoundedSamplerStalePictures = 0;

/// `ui.Image` handles CREATED BY THIS PACKAGE AND NOT YET DISPOSED,
/// across both samplers. Bumped after every `toImageSync`, dropped at every
/// `dispose()` of one.
///
/// It answers ONE question, the first one to rule out: is the ~7 s
/// between a production and the footprint coming back down THIS PACKAGE'S
/// hold — a Dart handle kept, an echo queue, a cached last image — or the engine's? Every
/// production site in this package disposes its handle inside the same
/// `addToScene` (`source` and `intermediate` in `finally` blocks on the band
/// path, `image` in one on the fallback path), so this reads a small constant
/// while the process footprint sawtooths by hundreds of megabytes (see
/// `test/probe/animation_probe.dart`).
int debugInspireLiveSamplerImages = 0;

/// `addToScene` entries on the fallback composition's LAYER, and the
/// pictures those entries ADDED to a scene. The band path's
/// `debugInspireBandSamplerScenes` / `debugInspireBandSamplerComposites` pair,
/// one composition over, and asserted the same way: every `addToScene` must end
/// with a picture composited, so a bound that engaged by NOT DRAWING breaks
/// `composites == scenes`. A walk that never re-adds the layer (retained
/// rendering) moves neither.
int debugInspireBoundedSamplerScenes = 0;

/// See [debugInspireBoundedSamplerScenes].
int debugInspireBoundedSamplerComposites = 0;

/// Pictures served from the per-frame cache instead of re-rasterised — the band
/// sampler's nesting fix, applied to the fallback path as well. Non-zero on any
/// composition where an ancestor walks this layer more than once in a frame.
int debugInspireBoundedSamplerPictureReuse = 0;

/// The band sampler's drain-and-cap, owned in one place and used by every layer in this
/// package that allocates render targets.
///
/// Not a `Timer`, not `FrameTiming`, not a live-handle count — see the note at
/// the top of `inspire_child_blur_band_sampler.dart` for why each of those is
/// the wrong completion signal. The drain is the frame stamp advancing.
class InspireProductionBudget {
  int _outstanding = 0;
  Duration? _drainStamp;

  /// The current frame's identity, or null when we are not inside one.
  ///
  /// Compositing runs under `persistentCallbacks` (`drawFrame` ->
  /// `compositeFrame`), the ONLY phase where `currentFrameTimeStamp` is both
  /// set and meaningful — and where the render tree is frozen, which is what
  /// makes "same frame => same pixels" true. Every other caller
  /// (`RenderRepaintBoundary.toImage` from a post-frame callback or from idle)
  /// gets null and rasterises for itself.
  static Duration? frameStamp() {
    final SchedulerBinding binding = SchedulerBinding.instance;
    if (binding.schedulerPhase != SchedulerPhase.persistentCallbacks) {
      return null;
    }
    return binding.currentFrameTimeStamp;
  }

  /// Drain against [stamp], then answer whether this layer has already produced
  /// its allowance against it. A stamp this budget has not counted against yet
  /// means the pipeline moved, so everything produced against the previous one
  /// is through; A RUN OF NULL STAMPS IS ONE STAMP, which is exactly the
  /// out-of-band burst the bound exists for.
  bool backlogged(Duration? stamp) {
    if (stamp != _drainStamp) {
      _drainStamp = stamp;
      _outstanding = 0;
    }
    return _outstanding >= kInspireBandSamplerMaxOutstanding;
  }

  void produced() => _outstanding++;
}

/// A callback for [InspireBoundedSampler] — `flutter_shaders`'
/// `AnimatedSamplerBuilder`, same signature.
typedef InspireBoundedSamplerBuilder = void Function(
  ui.Image image,
  Size size,
  ui.Canvas canvas,
);

/// `AnimatedSampler` with a production budget: a drop-in for it at this
/// package's own call sites, identical in what it draws and bounded in how many
/// render targets it can have outstanding.
///
/// The `enabled` parameter is not carried over — nothing in this package ever
/// passed anything but `true`.
class InspireBoundedSampler extends StatelessWidget {
  const InspireBoundedSampler(
    this.builder, {
    required this.child,
    this.pixelKey,
    super.key,
  });

  final InspireBoundedSamplerBuilder builder;

  /// The values [builder] closes over that decide the drawn
  /// pixels, as an equatable object (a record). The layer's cross-frame
  /// stale/re-serve decision compares this INSTEAD of the callback's closure
  /// identity — a caller that rebuilds per frame (a scroll header that
  /// `setState`s per scroll notification) hands the layer a fresh closure
  /// every frame, and an identity compare made `sameGeometry` false forever,
  /// so the per-stamp bound and the texture cap never engaged. Null keeps the callback
  /// identity compare (the drop-in `AnimatedSampler` behaviour).
  final Object? pixelKey;

  final Widget child;

  @override
  Widget build(BuildContext context) => _BoundedSamplerBuilder(
        builder,
        pixelKey: pixelKey,
        devicePixelRatio: MediaQuery.devicePixelRatioOf(context),
        child: child,
      );
}

class _BoundedSamplerBuilder extends SingleChildRenderObjectWidget {
  const _BoundedSamplerBuilder(
    this.builder, {
    required this.pixelKey,
    required this.devicePixelRatio,
    required Widget super.child,
  });

  final InspireBoundedSamplerBuilder builder;
  final Object? pixelKey;
  final double devicePixelRatio;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderBoundedSampler(
        devicePixelRatio: devicePixelRatio,
        builder: builder,
        pixelKey: pixelKey,
      );

  @override
  void updateRenderObject(BuildContext context, RenderObject renderObject) {
    (renderObject as _RenderBoundedSampler)
      ..devicePixelRatio = devicePixelRatio
      ..builder = builder
      ..pixelKey = pixelKey;
  }
}

class _RenderBoundedSampler extends RenderProxyBox {
  _RenderBoundedSampler({
    required double devicePixelRatio,
    required InspireBoundedSamplerBuilder builder,
    required Object? pixelKey,
  })  : _devicePixelRatio = devicePixelRatio,
        _builder = builder,
        _pixelKey = pixelKey;

  Object? get pixelKey => _pixelKey;
  Object? _pixelKey;
  set pixelKey(Object? value) {
    if (value == _pixelKey) return;
    _pixelKey = value;
    markNeedsCompositedLayerUpdate();
  }

  double get devicePixelRatio => _devicePixelRatio;
  double _devicePixelRatio;
  set devicePixelRatio(double value) {
    if (value == _devicePixelRatio) return;
    _devicePixelRatio = value;
    markNeedsCompositedLayerUpdate();
  }

  InspireBoundedSamplerBuilder get builder => _builder;
  InspireBoundedSamplerBuilder _builder;
  set builder(InspireBoundedSamplerBuilder value) {
    if (value == _builder) return;
    _builder = value;
    markNeedsCompositedLayerUpdate();
  }

  @override
  OffsetLayer updateCompositedLayer({
    required covariant _BoundedSamplerLayer? oldLayer,
  }) {
    final _BoundedSamplerLayer layer =
        oldLayer ?? _BoundedSamplerLayer(_builder);
    layer
      ..callback = _builder
      ..pixelKey = _pixelKey
      ..size = size
      ..devicePixelRatio = _devicePixelRatio;
    return layer;
  }

  @override
  bool get isRepaintBoundary => true;

  @override
  bool get alwaysNeedsCompositing => true;

  @override
  void paint(PaintingContext context, Offset offset) {
    if (size.isEmpty) return;
    assert(offset == Offset.zero);
    return super.paint(context, offset);
  }
}

/// Everything that decides the picture's pixels EXCEPT the child's content,
/// which cannot change inside one frame. Compared with the frame stamp, never
/// on its own.
///
/// The third element is the caller's [InspireBoundedSampler
/// .pixelKey] — the VALUES the callback feeds the shader — falling back to
/// the callback object only when no pixel key was given. Closure identity is
/// fresh on every caller rebuild (scroll headers rebuild per scroll
/// notification), which made the cross-frame stale/re-serve path unreachable.
typedef _PictureKey = (Size, double, Object);

class _BoundedSamplerLayer extends OffsetLayer {
  _BoundedSamplerLayer(this._callback);

  ui.Picture? _lastPicture;
  Duration? _pictureFrame;
  _PictureKey? _pictureKey;
  final InspireProductionBudget _budget = InspireProductionBudget();

  Object? get pixelKey => _pixelKey;
  Object? _pixelKey;
  set pixelKey(Object? value) {
    if (value == _pixelKey) return;
    _pixelKey = value;
    markNeedsAddToScene();
  }

  Size get size => _size;
  Size _size = Size.zero;
  set size(Size value) {
    if (value == _size) return;
    _size = value;
    markNeedsAddToScene();
  }

  double get devicePixelRatio => _devicePixelRatio;
  double _devicePixelRatio = 1.0;
  set devicePixelRatio(double value) {
    if (value == _devicePixelRatio) return;
    _devicePixelRatio = value;
    markNeedsAddToScene();
  }

  InspireBoundedSamplerBuilder get callback => _callback;
  InspireBoundedSamplerBuilder _callback;
  set callback(InspireBoundedSamplerBuilder value) {
    if (value == _callback) return;
    _callback = value;
    markNeedsAddToScene();
  }

  ui.Image _snapshotChild() {
    final ui.SceneBuilder builder = ui.SceneBuilder();
    builder.pushTransform(
      Matrix4.diagonal3Values(devicePixelRatio, devicePixelRatio, 1).storage,
    );
    addChildrenToScene(builder);
    builder.pop();
    final ui.Scene scene = builder.build();
    if (kDebugMode) debugInspireBoundedSamplerTargets++;
    final ui.Image image = scene.toImageSync(
      (devicePixelRatio * size.width).ceil(),
      (devicePixelRatio * size.height).ceil(),
    );
    // AFTER `toImageSync`, so the echo `produced` may post is queued on the
    // raster runner BEHIND this production and its completion covers it.
    InspireTextureLedger.produced();
    if (kDebugMode) debugInspireLiveSamplerImages++;
    scene.dispose();
    return image;
  }

  @override
  void dispose() {
    _lastPicture?.dispose();
    super.dispose();
  }

  @override
  void addToScene(ui.SceneBuilder builder) {
    if (size.isEmpty) return;
    if (kDebugMode) debugInspireBoundedSamplerScenes++;

    final Duration? frame = InspireProductionBudget.frameStamp();
    final _PictureKey key = (size, devicePixelRatio, _pixelKey ?? callback);
    final ui.Picture? cached = _lastPicture;

    // Drain first — see [InspireProductionBudget.backlogged]. The
    // global outstanding-texture ceiling backstops the per-stamp budget.
    final bool backlogged =
        _budget.backlogged(frame) || InspireTextureLedger.atCap;
    final bool sameGeometry = cached != null && key == _pictureKey;
    // NEVER REUSE ON A NULL STAMP for the in-frame cache: `null == null` would
    // make every out-of-frame walk a hit and freeze the sampler at the first
    // picture it ever made. The BOUND is what handles those, and only past it.
    final bool sameFrame =
        sameGeometry && frame != null && frame == _pictureFrame;

    final ui.Picture picture;
    if (sameFrame || (backlogged && sameGeometry)) {
      picture = cached!;
      if (kDebugMode) {
        if (sameFrame) {
          debugInspireBoundedSamplerPictureReuse++;
        } else {
          debugInspireBoundedSamplerStalePictures++;
        }
      }
    } else {
      final ui.Image image = _snapshotChild();
      final ui.PictureRecorder recorder = ui.PictureRecorder();
      final Canvas canvas = Canvas(recorder);
      try {
        callback(image, size, canvas);
      } finally {
        image.dispose();
        if (kDebugMode) debugInspireLiveSamplerImages--;
      }
      picture = recorder.endRecording();
      _lastPicture?.dispose();
      _lastPicture = picture;
      _pictureFrame = frame;
      _pictureKey = key;
      _budget.produced();
    }

    builder.addPicture(offset, picture);
    if (kDebugMode) debugInspireBoundedSamplerComposites++;
  }
}
