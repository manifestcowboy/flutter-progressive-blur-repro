# Progressive blur in Flutter: what broke, what we changed, how to reproduce it

This repo collects what we learned shipping a **scroll-driven progressive blur** in a production Flutter app (iOS and Android, Impeller) on top of [`inspire_blur`](https://pub.dev/packages/inspire_blur). It has three parts:

| Folder | What it is |
|---|---|
| [`packages/inspire_blur`](packages/inspire_blur) | `inspire_blur` 0.4.1 with our patches. The branch `upstream-0.4.1` is the untouched pub.dev release, so `git diff origin/upstream-0.4.1 -- packages/inspire_blur` shows every change. |
| [`repro_app`](repro_app) | A small demo app with one screen per problem. Each screen recreates the problem with the stock package and shows the fix next to it. |
| [`PATCHES.md`](PATCHES.md) | A technical write-up of each patch: the defect, the measurement, the fix, and whether it is a candidate for upstream. |
| [`FLUTTER_GAPS.md`](FLUTTER_GAPS.md) | The things Flutter itself does not offer, which forced most of this work. |

The rest of this page is the plain-language version, screen by screen.

---

## The effect we wanted

The app has scrolling lists (songs, albums, playlists, settings) under a fixed header. When you start scrolling, the content sliding under the header goes progressively blurry: sharp at the bottom of the header, fully frosted at the very top. The same effect, flipped upside down, sits above the bottom navigation bar as a "frosted footer". The effect shows on almost every screen, so whatever it costs, it costs everywhere.

## Timeline of problems, in the order we hit them

Every problem below has a screen in `repro_app` (the **S-number**).

### 1. Stacked blur strips: stripes and dropped frames (S1)

**Screen:** any list under the blurred header.
**What you saw:** while scrolling, the blur showed faint horizontal stripes, and scrolling stuttered.
**Why:** the first version faked a progressive blur by stacking 32 to 96 thin `BackdropFilter` strips, each a bit blurrier than the one below. Each strip is a separate full blur pass, and the steps between strips show as bands, exactly `zone height / strip count` pixels apart.
**Measured:** p95 frame time about 20 to 23 ms on iPhone (Impeller), over the 16.7 ms budget for 60 Hz and far over 8.3 ms for 120 Hz.
**Fix:** switch to `inspire_blur`'s child-blur shader, which is a single pass with no strips. It ran at about 0.5 to 1.0 ms in the same scene.

### 2. The first scroll touch did nothing (S4)

**Screen:** any sheet or list, on the first touch after it opened.
**What you saw:** "When I try to scroll up the first time it's unresponsive. I have to tap a few times to get it moving. Smooth once it moves."
**Why:** when the blur widget first appears, `inspire_blur` builds its blur-intensity map with a plain Dart loop on the UI thread: about 408,000 iterations and 1.6 MB on a normal phone. Our code also removed the blur widget whenever the list was at rest and added it back on the first touch, so every first touch paid for that loop again.
**Measured:** 13.9 ms extra on that one frame.
**Fix (on our side):** keep the blur widget mounted at strength 0 when idle, and give it a ready-made mask image drawn once on the GPU (`InspireBlurConfig.customMask`). Down to 0.9 ms.

### 3. Rounded shapes turned boxy, and the blur looked different on web (S3)

**Screen:** a list with rounded pills, round badges and avatars under the header.
**What you saw:** blurred rounded pills came out as squarish blocks (we called it "the boxy pill"), and the blur's strength and position didn't match between the phone and the web preview.
**Why, three package bugs:**
- In `auto` mode the package chooses its renderer by checking whether the blur sits *inside* a scroll view. Ours wraps the scroll view, so phones got the `imageFilter` renderer while web got the `animatedSampler` renderer, and the two don't look the same.
- The shader caps its blur radius at 64. One renderer counts that in logical pixels and the other in device pixels, so on a 3x phone our blur was silently cut to about half its size and degraded into a box blur.
- The `imageFilter` renderer doesn't clip to its own box. If anything inside paints outside it, the blur's mask stretches and moves (we measured 248 px of drift).

**Fix:** pin the renderer to `animatedSampler`, raise the radius cap to 192, and fix the two `imageFilter` bugs in the package (Patches 1 to 3).

### 4. Text below the blur shimmered while scrolling (S2)

**Screen:** any long list.
**What you saw:** rows well below the header, where nothing should be blurred, had a subtle shimmer on their edges while scrolling.
**Why:** the stock child blur takes a snapshot of the **entire list** every frame and redraws all of it through the shader, even the parts where blur strength is zero. That round trip slightly changes antialiased edges: 4.13% of the pixels below the blur differed from the same screen with the blur off. It is also wasted work, since 80% of the screen is copied for nothing.
**Fix:** a new "band sampler" (Patch 4). It snapshots only the strip that actually gets blurred, plus the few pixels the blur needs around it, and draws the rest of the list directly.
**Measured:** average raster time 2.40 to 1.23 ms, p95 8.80 to 4.05 ms, slow frames 1.7% to 0%. That is the same cost as having no blur at all. The shimmer went from 4.13% of pixels to 0.

### 5. Crash 1: dragging to reorder a playlist (S5, S6)

**Screen:** a playlist screen with the blurred header and the frosted footer, while dragging a row to reorder it.
**What you saw:** on an iPhone 17 Pro (release build) the app vanished mid-drag. There was no crash report, because iOS killed it for using too much memory.
**Why, two causes on top of each other:**
- During a drag the screen rebuilds every frame, and our code created a new blur settings object each time. The package compares those settings by identity, so it rebuilt its blur map every frame (about 6.5 MB, 120 times a second).
- The footer blur wraps the header blur. With the stock package, each blur re-snapshots everything inside it every time the layer tree is walked, so the nesting multiplied the snapshots: 6 large images per frame instead of 2.

**Fix:** reuse one settings object; make each blur layer reuse its snapshot within the same frame (6 to 4 per frame); and put a ceiling on how many snapshots can be waiting for the GPU at once.

### 6. Crash 2: the first swipe after installing the app (S6)

**Screen:** the same playlist screen, on the very first launch after install.
**What you saw:** after crash 1 was fixed, warm launches survived, but the first swipe on a fresh install still got killed.
**Why:** on first launch the GPU hasn't compiled its shaders yet, so it is at its slowest. Until the blur shader loaded, the blur fell back to the whole-list snapshot path, and nothing limited how many of those could pile up. The worst case we measured was 246 full-screen snapshots, about 3.1 GB, waiting on the GPU.
**Fix:** the same limit now covers the fallback path (Patch 4, "bounded sampler"), and the shader is loaded at app start.

### 7. Crash 3: deleting an item with a long animation, and fast flings (S7)

**Screen:** a list where you swipe an item away and it breaks into particles over 1.25 s, and also long, fast flings on any list.
**What you saw:** the app was killed about 2.5 s after a swipe-to-delete. iOS logged `Runner exceeded mem limit: ActiveHard 3376 MB (fatal)`.
**Why:** Flutter can't say *where* something changed, only *that* something changed. So any animation anywhere under the blur, even a tiny one in its own repaint boundary, made the blur re-snapshot its band every frame (2 images per blur per frame). iOS frees those images several seconds later, so a long animation produced them faster than they were freed and memory spiked. The app's own Dart memory stayed flat, because all of it was GPU memory, which is why it was so hard to find.
**Measured:** a plain fast fling added about 300 MB, and the dissolve animation went from 94 to 686 MB.
**Fix, in order of impact:**
1. The band now remembers what was inside its window last frame and **skips re-blurring when nothing there changed** (1194 to 300 snapshots over 600 frames).
2. The particle animation is now drawn by paint alone instead of rebuilding widgets every frame (1.25 to 0.50 snapshots per frame, the same as idle).
3. A global cap of 32 snapshots in flight acts as a safety net. Once 1 and 2 landed, it never had to kick in.

### 8. The keyboard made every blur rebuild (S8)

**Screen:** any screen with a text field (search, sign-in).
**Why:** the package listened to *every* screen property (`MediaQuery.of`) when it only needs the screen size. The keyboard changes the screen insets on every animation frame, so every blur rebuilt about 15 times per keyboard open.
**Fix:** listen to size and pixel ratio only (Patch 7).

### 9. Glass cards went dark under the header (S9)

**Screen:** a home screen with frosted-glass cards scrolling under the header.
**Why:** the band sampler draws the real list only *below* the blurred strip. A glass card crossing that edge blurs what's behind it, and above the edge there was nothing drawn, so the card turned dark.
**Fix:** an option (`realUnderlap`) to let the real content extend under the blurred strip, where it stays hidden but gives the glass something to sample.

---

## Where it stands now

- **iPhone:** smooth. No blur-related crashes since these fixes.
- **Android (Nothing Phone (2), Snapdragon 8+ Gen 1):** the app still **feels laggy** on screens with the blur. All the measurements above were taken on iOS and macOS, and we have not profiled Android to the same depth. This is the main open question: even with every patch here, a shader-based progressive blur still means one offscreen snapshot plus a two-pass shader per blurred strip per frame, and that seems to cost more on Android GPUs. A native progressive or masked blur in Flutter (see [`FLUTTER_GAPS.md`](FLUTTER_GAPS.md)) would likely be the real fix.
- This copy is based on `inspire_blur` 0.4.1, including its OpenGL ES orientation fix for Flutter 3.47.

## How to reproduce

See [`repro_app/README.md`](repro_app/README.md). In short: run on a **real device in profile mode**. Use `lib/main_stock.dart` against the untouched package (branch `upstream-0.4.1`) to see the original problems, and `lib/main.dart` for the patched version with on/off toggles. GPU memory doesn't show up in Dart, so watch it in Xcode's memory gauge or Instruments on iOS, or with `adb shell dumpsys meminfo` on Android.

## License

`packages/inspire_blur` is MIT-licensed, © InspireStack (see its `LICENSE`). Our patches and the demo app are released under the same MIT terms.
