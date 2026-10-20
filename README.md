# Progressive blur with inspire_blur: where it breaks, and what Flutter could do about it

We ship a scroll-driven progressive blur in a production Flutter app (iOS and Android, Impeller) using [`inspire_blur`](https://pub.dev/packages/inspire_blur). Content scrolling under the header blurs progressively, and the same effect sits above the bottom bar. This repo shows the three places where it costs too much, a small music-player demo that reproduces each one, and what we had to patch.

| | |
|---|---|
| [`repro_app`](repro_app) | A plain music-player demo with three test screens. Each has a switch for the stock `inspire_blur` behaviour and for our patched version. |
| [`packages/inspire_blur`](packages/inspire_blur) | `inspire_blur` 0.4.1 with our patches. Branch `upstream-0.4.1` is the untouched pub.dev release. |
| [`FLUTTER_GAPS.md`](FLUTTER_GAPS.md) | What Flutter itself is missing, and why the patches had to exist. |
| [`PATCHES.md`](PATCHES.md) | Technical details of each patch, for the package authors. |

## 1. The whole list is re-drawn every frame just to blur the top of it

**Demo screen 1:** a songs list under a blurred header. Scroll it.

`inspire_blur`'s child blur takes a full-size snapshot of everything under it (`toImageSync`) on every frame and redraws all of it through the shader. That includes the 80% of the list where the blur strength is zero. Flutter has no way to snapshot only part of a widget.

Our patch adds a "band" mode (`Inspire.childBlurBand`, switch on demo screen 2) that snapshots only the strip that is actually blurred. On iPhone: raster mean 2.40 to 1.23 ms, p95 8.80 to 4.05 ms, frames over budget 1.7% to 0%, which equals the cost with no blur at all. It also removed a faint shimmer on text below the blur, caused by the snapshot round trip changing antialiased edges.

## 2. Anything animating under the blur makes it re-blur every frame

**Demo screen 2:** the songs list with a blurred header and a blurred area above the mini player. The now-playing equalizer animates, and nothing else moves.

Flutter only knows that *something* under a layer changed, not *where*. So a tiny animation far from the blurred strip still forces a new snapshot every frame. This is why a screen can feel heavy even when nothing seems to move: a playback progress ring creeping forward by a fraction of a pixel, a small equalizer or a slowly drifting background is enough to keep the blur working at full cost. With a header blur and a footer blur nested, the stock package made 6 large snapshots per frame.

Our patch hashes what's inside the blurred strip and skips the re-blur when it hasn't changed. It also reuses the snapshot within a frame (6 to 4 per frame).

## 3. Memory crash: GPU snapshots pile up faster than they're freed

**Demo screen 3:** a playlist. Swipe a song away: it breaks into particles over 1.25 s. Use "Play 20 in a row" and "Fling list".

On an iPhone 17 Pro (release) this killed the app with `Runner exceeded mem limit: ActiveHard 3376 MB (fatal)`, and there was no crash log. Each frame of the animation made new GPU snapshots, and iOS freed them seconds later, so memory spiked. Dart memory stayed flat, because all of it was GPU memory. A fast fling alone added about 300 MB; the particle animation took the app from 94 to 686 MB. In the worst case (the blur's fallback path) we measured 246 snapshots, 3.1 GB, waiting on the GPU.

Flutter gives no signal for when a `toImageSync` image has actually been drawn and freed, so the package can't hold back. Our fix: the skip from case 2, a per-frame limit on snapshots, and a global cap on snapshots in flight. On the app side, the animation is now drawn with paint only instead of rebuilding widgets.

## Measured on Android with this demo (Nothing Phone (2))

Snapdragon 8+ Gen 1 / Adreno 730, Android 16, 90 Hz screen. Profile build, Flutter 3.47.7, Impeller on Vulkan, "Real-app" load. fps is what Android actually put on screen. Graphics memory is the GPU row from `dumpsys meminfo`.

| Screen | Default inspire_blur | Our band version |
|---|---|---|
| 1. Whole-list blur, scrolling | 88 to 94 fps (blur off: 92) | n/a |
| 2. Header + footer blur, scrolling | **63 to 66 fps**, about 70% of frames late; **killed by Android for low memory** on the first run | 81 to 86 fps |
| 2. Same, at rest (only the equalizer animates) | 63 fps | 81 fps |
| 3. "Play 20 in a row" + flings | **42 to 48 fps**; graphics memory 64 to 161 MB in 42 s, still 185 MB 15 s after the end | 52 to 61 fps; 76 to 134 MB, 144 MB after |

The same screen 2 with "Light" load ran at 84 fps on default inspire_blur, so the cost comes from what animates *under* the blur. On both versions graphics memory keeps growing and isn't given back after the animation stops.

**Native crash.** A default inspire_blur run on screen 3, started with about 211 MB already in graphics memory, ended at 267 MB and crashed seconds later with a SIGSEGV (null pointer) inside the Adreno Vulkan driver's `vkDestroyFramebuffer`, called from the Flutter engine on the platform thread. The trimmed log is in [`reports/android-vkDestroyFramebuffer-crash.txt`](reports/android-vkDestroyFramebuffer-crash.txt).

**So Android is still laggy, even with our patches** (52 to 86 fps on a 90 Hz screen), while iPhone is smooth in our app. A shader progressive blur still costs an offscreen snapshot plus a two-pass shader per blurred strip per frame. A native progressive blur in Flutter, such as a `BackdropFilter` or `ImageFilter` that takes a gradient mask for its strength, would avoid the snapshot entirely. That's the main thing we'd ask for. See [`FLUTTER_GAPS.md`](FLUTTER_GAPS.md).

## Running the demo

Run it on a real phone in profile mode: `cd repro_app && flutter run --profile`. Each test screen shows frame times at the bottom. GPU memory doesn't show up in Dart, so use Xcode's memory gauge on iOS, or `adb shell dumpsys meminfo dev.repro.inspire_blur_repro` on Android. To see the problems with the untouched package, check out `origin/upstream-0.4.1 -- packages/inspire_blur` and run `lib/main_stock.dart`. Details: [`repro_app/README.md`](repro_app/README.md).

## License

`packages/inspire_blur` is MIT, © InspireStack. Our patches and the demo are MIT too.
