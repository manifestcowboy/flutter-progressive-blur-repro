# What Flutter does not offer (and why that made this hard)

These are engine and framework gaps we had to work around in package code. Each one maps to a patch in [`PATCHES.md`](PATCHES.md).

1. **No built-in progressive (mask-driven, variable-sigma) blur.** `ImageFilter.blur` and `BackdropFilter` take one sigma. Approximating a ramp with stacked `BackdropFilter`s bands at `zone / strip count` and misses the frame budget. A shader child blur works, but every app has to rebuild the composition below.

2. **No region-of-interest snapshot for child-sampling shaders.** `AnimatedSampler` (flutter_shaders), `SnapshotWidget`, `ImageFilterLayer` and `BackdropFilter` all rasterise the **whole** child offscreen. A blur that only affects the top 20% of a list still pays to snapshot 100% of it every frame. That round trip also re-quantises antialiased edges where the blur strength is zero (4.13% of pixels changed). Our band sampler (Patch 4) is a custom layer that snapshots only a sub-rect, which means reimplementing `addToScene`.

3. **No raster-side completion signal for `Picture.toImageSync`.** The image is "created and returned synchronously, but rasterized asynchronously", out of band from the frame pipeline. `Image.dispose()` frees only the Dart handle. `FrameTiming` is batched (about 1 s in release). So a layer has no way to know how many of its render targets are still waiting on the GPU, and under a lagging raster thread they pile up into multi-GB graphics footprint (iOS jetsam at `ActiveHard 3376 MB`) while Dart RSS stays flat. We built backpressure out of the frame stamp plus a 1x1 `Picture.toImage` echo on the FIFO raster runner (Patch 4, production budget and texture ledger).

4. **Dirty bits have no region.** A repaint anywhere under a layer, even inside its own `RepaintBoundary` far from the blurred strip, forces the blur to re-snapshot. We hash the layer subtree that falls inside the band's window and skip unchanged frames (Patch 4, window-signature gate), which relies on `PictureLayer.canvasBounds`, an estimate.

5. **Shader image filters don't run on web (CanvasKit).** `ImageFilter.isShaderFilterSupported` is false, so a shader backdrop blur renders nothing there.

6. **`flutter_shaders` `AnimatedSampler` never disposes its private `Scene`** (`animated_sampler.dart`, `addToScene`). This is minor, and fixed in our bounded sampler.

7. **Android cost.** Even with all of the above bounded, an offscreen snapshot plus a two-pass Gaussian per blurred strip per frame still feels laggy on a Nothing Phone (2) (Adreno 730, Impeller), while iPhone is smooth. A native implementation (a masked or variable-radius blur filter in Impeller, or a `BackdropFilter` that takes a gradient mask) would avoid the extra offscreen snapshot entirely.
