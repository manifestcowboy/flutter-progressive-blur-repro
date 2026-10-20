# Blur repro

A small Flutter music app (Material 3, follows the system light/dark setting) whose screens recreate, on a real phone, every performance and crash problem met while building a scroll-driven progressive blur with [`inspire_blur`](../packages/inspire_blur), and show the fix beside it.

It depends on the package by path (`inspire_blur: { path: ../packages/inspire_blur }`). No assets, no network, nothing but Flutter and `inspire_blur` (`flutter_shaders` arrives transitively). All content is generated: gradient cover art, round artist avatars, rounded genre chips, text rows.

Built and checked with Flutter 3.47.7 / Dart 3.13.5. Targets iOS and Android; Impeller is on by default.

## Two entrypoints

| Entrypoint | Needs | Shows |
|---|---|---|
| `lib/main_stock.dart` | Pristine **or** patched package | S1 to S8, using only API that exists in pristine `inspire_blur` 0.4.1. This is how to see the original problems with the unmodified package. |
| `lib/main.dart` | The **patched** package (the repo tree) | Everything: S1 to S8 with A/B toggles for `Inspire.childBlurBand`, the package's debug counters on the HUD, and S9 (patched only). |

`main_stock.dart` never imports `lib/patched`. That is enforced by `test/stock_isolation_test.dart`, and it was checked against a real pristine checkout (see "What was verified").

### Run

Always on a **real device** and in **profile** mode. Debug-mode timings are meaningless.

```sh
cd repro_app
flutter pub get
flutter devices

# Patched package (this repo tree), everything:
flutter run --profile -d <device-id> -t lib/main.dart
```

To see the problems with the **unmodified** package, run the stock entrypoint against pristine `inspire_blur` 0.4.1 (tag `upstream-0.4.1`). Safest, without touching your working tree, is a second checkout:

```sh
# from the repo root
git worktree add ../pristine upstream-0.4.1
cp -r repro_app ../pristine/repro_app
cd ../pristine/repro_app
flutter pub get
flutter run --profile -d <device-id> -t lib/main_stock.dart
```

Or switch the package in place (this **overwrites uncommitted changes** in `packages/inspire_blur`, so commit or stash them first):

```sh
# from the repo root
git checkout upstream-0.4.1 -- packages/inspire_blur
git clean -fd packages/inspire_blur          # drops untracked patched-only files, if any
cd repro_app && flutter run --profile -d <device-id> -t lib/main_stock.dart

# afterwards, put the patched package back (from the repo root)
git checkout HEAD -- packages/inspire_blur
```

Run the same screen on both trees to compare. S3 (renderer mismatch, boxy blur), S8 (keyboard) and the "stock" blur of S6 and S7 behave differently under the pristine package and the patched one; the screens do not change, the package does. Note that on the patched tree the "stock" option (`Inspire.childBlur`) still runs through the patched package's bounded fallback sampler. The original numbers only come from `main_stock.dart` on the pristine tree.

Useful flags: `--no-enable-impeller` (Skia: `ImageFilter.isShaderFilterSupported` is false there, so `InspireBlurMode.auto` resolves to the animated sampler everywhere), `-d <id>` to pick a phone.

## Reading a screen

Every screen is an ordinary-looking music screen with a **test panel** above it:

- the **info card** (collapsible, stays collapsed across screens): *With your finger*, *Watch*, *What we saw on device (reported)*;
- the **controls** (A/B toggles, sliders, buttons);
- the **HUD** floating over the screen. Tap its title to collapse it to one line, drag it out of the way, **Reset stats** to start a fresh window.

HUD fields:

- `UI` and `Raster`: mean, p95, and the share of frames slower than 16.7 ms (60 Hz) and 8.3 ms (120 Hz), over the last 600 frames. UI is `FrameTiming.buildDuration`, raster is `rasterDuration`. The engine batches timings (about 100 ms in profile), so the numbers trail the screen.
- `worst UI frame`: the slowest UI-thread frame in the last second, and since reset. A one-frame stall (S4) shows here.
- `RSS`: `ProcessInfo.currentRss`. **Dart-visible RSS, GPU textures are NOT included**; tap the info icon for the long note. Use the tools below for graphics memory.
- Scenario counters (blur mounts, config builds, rebuild counts, and so on).
- On `main.dart`, the patched package's production and texture counters. **They only move in debug builds**: the package increments them behind `if (kDebugMode)`. In `--profile` the HUD prints "n/a (debug build only)". To read them, run the scenario once with `flutter run --debug` (numbers only; take timings from `--profile`).

The HUD itself causes about two trivial frames per second, which are in the stats like any other. Use **Auto-scroll** (where offered) for repeatable runs; touching the list while it runs fights it, so switch it off first.

## Watching GPU memory

The HUD's RSS cannot see graphics memory, and graphics memory is what kills the app in S5 and S7.

**iOS**

- Xcode: run the app from Xcode (profile scheme) and open the Debug navigator, **Memory** gauge. Watch the number, not the shape.
- Instruments (Product > Profile): **Allocations** plus **VM Tracker**; in VM Tracker look at the `IOSurface` and `IOAccelerator` rows (Dirty Size). Add **Metal System Trace** for GPU time.
- After a kill with no crash log: Settings > Privacy & Security > Analytics & Improvements > Analytics Data, `JetsamEvent-*.ips` (look for the footprint and `ActiveHard`).

**Android**

```sh
PKG=dev.repro.inspire_blur_repro

# Graphics memory, once a second: Graphics, GL mtrack, EGL mtrack, TOTAL PSS
while true; do
  adb shell dumpsys meminfo $PKG | grep -E "Graphics|GL mtrack|EGL mtrack|TOTAL PSS|Native Heap"
  echo ---; sleep 1
done

# Frame stats from Android's side. Flutter draws on its own surface, so treat
# gfxinfo as a cross-check; the HUD's FrameTiming is the primary number.
adb shell dumpsys gfxinfo $PKG reset
adb shell dumpsys gfxinfo $PKG framestats

# Which backend is running (look for "Impeller" / "Vulkan")
adb logcat -d | grep -i impeller
```

A phone may hold Flutter to 60 Hz even if its panel does 120 Hz; the `>8.3` column only means something if the device really runs 120 Hz.

## Scenarios

"Stock" scenarios use only API of pristine 0.4.1. "Band" means the patched `Inspire.childBlurBand`, offered as an A/B toggle in `main.dart` only.

Blur sigma note: `inspire_blur` takes sigma in **device** px (the animated-sampler pass divides by the device pixel ratio, the image-filter pass uses it as is), whereas `ImageFilter.blur` takes logical px. The app passes `14.667 * devicePixelRatio` (44 at 3x) wherever it wants the 14.667 logical px of the original app; S1 uses `ImageFilter.blur` directly, so it uses logical px.

| | Music screen | Kind | Finger steps | What to look for |
|---|---|---|---|---|
| **S1** Strip blur (before inspire_blur) | Library > Songs | stock | 1. Scroll the song list up and down, or switch on Auto-scroll. 2. Set Strips to 32, then 64, then 96. 3. Switch Blur on and off. | **Banding**: horizontal stripes in the top 120 pt where sigma steps between strips (worst at 32). **Missed frames**: raster p95 and the `>16.7` column grow with the strip count; compare with Blur off. |
| **S2** Whole-child blur | Library > Songs | stock | 1. With the list at the top, drag it up slowly: the app bar blur ramps in over the first 80 pt. 2. Keep scrolling 5 s (or Auto-scroll). 3. Switch Blur off and repeat. | Raster time on vs off: the **whole list** is re-rasterised every frame, even below the zone where the mask is zero. **Shimmer**: antialiased edges below the zone move slightly versus blur off. Zone ruler marks 120 pt. |
| **S3** Renderer mismatch and boxy blur | Library > Songs (genre chips, artist avatars) | stock | 1. Scroll so the chips and round avatars pass the top 120 pt. 2. Switch Mode: auto, animatedSampler, imageFilter. 3. Drag Sigma towards 30. 4. Switch on "Child paints 250 px above" and compare the fade-out against the dashed zone ruler in each mode. | `auto` resolves to **imageFilter** here (blur is the *parent* of the Scrollable, no Scrollable ancestor); on web or Skia it would be animatedSampler. At dpr 3 imageFilter **truncates the kernel at MAX_RADIUS 64 device px**, so chips and circles square off from about 7 logical sigma; the sampler only does from about 21. imageFilter coverage grows with the overhanging child, so the ramp **shifts**; animatedSampler does not. |
| **S4** First-touch stall | Album | stock | 1. Choose "naive". 2. With the list at rest at the top, put a finger down and drag (or just tap). 3. Lift, scroll back to the very top, wait a second, touch again. 4. Leave and reopen the screen, then repeat with "mounted" and with "fixed". | One long UI frame at the touch: HUD **worst UI frame (last 1 s)** and **last mount frame**. The blur is mounted only while touched or scrolled, and `InspireBlurWrapper` builds its distribution map synchronously on the UI thread on mount. "fixed" (always mounted at sigma 0, cached `customMask` image drawn once into 4x2048) removes the loop. |
| **S5** Reorder drag: new blur config per frame | Playlist edit | stock | 1. Config: "new mask image". 2. Press and hold a song's drag handle (three lines, right) and drag up and down for 10 to 20 s. 3. Release. 4. Repeat with "new directional" and then "memoized". | The screen rebuilds every frame while dragging and hands the blur a config that is not `==` the last one, so the wrapper regenerates its distribution map each frame. Watch **config builds**, UI p95, and **graphics memory** (not RSS). **Can SIGKILL the app** (it did on an iPhone 17 Pro release build, no crash log). "memoized" is the safe comparison. |
| **S6** Header + footer blur nested | Library > Songs with mini player and navigation bar | stock + band A/B | 1. Leave the list at rest for a few seconds and read the HUD. 2. Scroll slowly up and down (or Auto-scroll). 3. Switch "Animated" off and on (equalizer on the playing song, progress bar and equalizer on the mini player). 4. `main.dart`: switch Blur to `Inspire.childBlurBand` and repeat. | The footer blur **wraps** the header blur which wraps the list; the playing song's equalizer repaints every frame inside, so the subtree is dirty even at rest. Stock: each layer re-snapshots its whole child per ancestor walk, 6 render targets per frame (about 13.5 MB/frame at band-sized 1206x467x4, far more for whole-child). Band: counters (debug) show productions, window skips, same-frame reuse. |
| **S7** Long animation under the blur | Playlist (swipe a song to remove it) | stock + band A/B | 1. Swipe a song sideways: it breaks into particles over 1.25 s, then collapses. 2. Or press "Play once" (third song), or "Play 20 in a row". 3. While it plays press "Fling list" (or fling by hand). 4. Compare Animation "rebuild" with "paint only", and (`main.dart`) Blur stock with band. "Restore songs" refills the list. | **Can crash the app** on stock (iPhone: graphics memory into jetsam, `ActiveHard 3376 MB`). Each dirty frame makes two band-sized textures per blur layer and reclamation lags seconds behind. The fix: (a) window-signature gate in the band sampler re-serves the band when nothing in its window changed, (b) paint-only animation, (c) global outstanding-texture cap as backstop. Watch graphics memory; HUD counters (debug) show productions and window skips. |
| **S8** Keyboard | Search | stock (patched differs inside the package) | 1. Press Reset stats. 2. Tap the search field: the keyboard slides up (about 15 frames). 3. Dismiss it (back gesture or tap the list). 4. Repeat a few times. | "Blur-owned element rebuilds" (**debug builds only**): stock reads `MediaQuery.of`, which depends on every field, so each keyboard frame rebuilds the package's subtree; patched reads `sizeOf` / `devicePixelRatioOf` and rebuilds nothing. "App child builds" stays at 1 in both. In profile compare UI and raster p95 during the animation. |
| **S9** Translucent cards under the band | Home | patched only | 1. Scroll so a "recently played" card straddles the bottom of the app bar zone (about 120 pt). 2. Stop there. 3. Switch realUnderlap 0, 12, 24, 48. | With 0 the band sampler cuts the real child at the seam, so the card's backdrop blur reads an unpainted base and goes **dark** in a strip along the seam. With 24 and up the card matches. Only safe over an opaque body (it is opaque here). |

Each info card in the app carries the same steps plus "what we saw on device". Those "saw" lines are the app team's reported observations (and the dev-rig numbers from `PATCHES.md`); this demo does not measure or reproduce those figures by itself.

## Layout

```
lib/
  main.dart            everything (needs the patched package)
  main_stock.dart      S1-S8, pristine-0.4.1 API only
  app/                 MaterialApp shell, home menu, Scenario model
  hud/                 FrameTiming collector, HUD overlay, HudCounter
  common/              music content widgets, test-panel scaffold, controls,
                       particles, mask image, nested blur body (stock-API only)
  stock/               S1-S8 screens + buildStockScenarios()
  patched/             S9, Inspire.childBlurBand variant, debug counters
                       + buildAllScenarios()
test/
  smoke_test.dart          home + every screen under both scenario lists
  stock_smoke_test.dart    same for the stock list only (runs on pristine too)
  stock_isolation_test.dart  main_stock.dart never reaches lib/patched
```

`hud/`, `common/`, `stock/` and `app/` must keep compiling against pristine 0.4.1; anything that needs the patched package goes under `lib/patched/`.

## What was verified

- `flutter analyze`: no issues.
- `flutter test`: 46 tests pass (home and every screen under both scenario lists, plus finger-level interactions on S2 to S9).
- `lib/main_stock.dart` against a real pristine checkout: in a copy of the repo with `git checkout upstream-0.4.1 -- packages/inspire_blur`, `flutter analyze lib/main_stock.dart lib/stock lib/common lib/hud lib/app` is clean, `flutter test test/stock_smoke_test.dart test/stock_isolation_test.dart` passes, and `flutter build bundle --target=lib/main_stock.dart` succeeds.

Not verified: running on a device. The widget tests do not load the blur shader or the distribution map (their async work does not complete under the test binding), so the blur render paths themselves, all timings, and all memory behaviour are unexercised until run on a phone. No Android or iOS build was made here.
