# What Flutter is missing for a good progressive blur

1. **A native progressive blur.** `ImageFilter.blur` and `BackdropFilter` take a single sigma. A blur whose strength follows a gradient mask, done in Impeller, would remove the offscreen snapshot that every shader-based approach (including `inspire_blur`) has to make. This is the biggest win, especially on Android, where the shader approach still feels laggy on a Nothing Phone (2) (Adreno 730) while iPhone is smooth.

2. **Snapshot only part of a widget.** `AnimatedSampler`, `SnapshotWidget`, `ImageFilterLayer` and `BackdropFilter` all rasterise the whole child. A blur that covers the top 20% of a list pays for 100% of it every frame. We had to write a custom layer (band sampler) to snapshot a sub-rectangle.

3. **Know when a `toImageSync` image is really done.** The image is rasterised asynchronously and out of band from the frame pipeline. `Image.dispose()` frees only the Dart handle, and `FrameTiming` arrives in batches (about 1 s in release). A layer can't tell how many of its images are still waiting on the GPU, so under load they pile up into gigabytes of graphics memory and iOS kills the app, while Dart memory looks flat. We built backpressure from the frame counter plus a 1x1 `Picture.toImage` "echo" on the raster thread.

4. **Know *where* something changed.** Repainting anything under a layer, even inside its own `RepaintBoundary` far from the blur, forces the blur to snapshot again. We hash the layers inside the blurred strip to skip unchanged frames, which relies on `PictureLayer.canvasBounds`, an estimate.

5. Small: `flutter_shaders`' `AnimatedSampler` never disposes the `Scene` it builds in `addToScene`.
