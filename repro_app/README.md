# Blur repro

A small Flutter music app (Material 3, follows the system light/dark setting) with three screens that recreate, on a real phone, the performance and crash problems met with a scroll-driven progressive blur from [`inspire_blur`](../packages/inspire_blur), and show the fix beside them.

It depends on the package by path (`inspire_blur: { path: ../packages/inspire_blur }`). No assets, no network, nothing but Flutter and `inspire_blur` (`flutter_shaders` arrives transitively). All content is generated: gradient cover art and text rows.

Built and checked with Flutter 3.47.7 / Dart 3.13.5. Targets iOS and Android; Impeller is on by default.

## Two entrypoints

| Entrypoint | Needs | Shows |
|---|---|---|
| `lib/main_stock.dart` | Pristine **or** patched package | S1 to S3, using only API that exists in pristine `inspire_blur` 0.4.1. This is how to see the original problems with the unmodified package. |
| `lib/main.dart` | The **patched** package (the repo tree) | S1 to S3 with A/B toggles for `Inspire.childBlurBand` and the package's debug counters on the HUD. |

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

To see the problems with the **unmodified** package, run the stock entrypoint against pristine `inspire_blur` 0.4.1 (branch `upstream-0.4.1`). Safest, without touching your working tree, is a second checkout:

```sh
# from the repo root
git worktree add ../pristine origin/upstream-0.4.1
cp -r repro_app ../pristine/repro_app
cd ../pristine/repro_app
flutter pub get
flutter run --profile -d <device-id> -t lib/main_stock.dart
```

Or switch the package in place (this **overwrites uncommitted changes** in `packages/inspire_blur`, so commit or stash them first):

```sh
# from the repo root
git checkout origin/upstream-0.4.1 -- packages/inspire_blur
git clean -fd packages/inspire_blur          # drops untracked patched-only files, if any
cd repro_app && flutter run --profile -d <device-id> -t lib/main_stock.dart

# afterwards, put the patched package back (from the repo root)
git checkout HEAD -- packages/inspire_blur
```

Run the same screen on both trees to compare. The "stock" blur of S2 and S3 behaves differently under the pristine package and the patched one; the screens do not change, the package does. Note that on the patched tree the "stock" option (`Inspire.childBlur`) still runs through the patched package's bounded fallback sampler. The original numbers only come from `main_stock.dart` on the pristine tree.

Useful flags: `--no-enable-impeller` (Skia: `ImageFilter.isShaderFilterSupported` is false there, so `InspireBlurMode.auto` resolves to the animated sampler everywhere), `-d <id>` to pick a phone.

## Reading a screen

Every screen is an ordinary-looking music screen with a **test panel** above it:

- the **info card** (collapsible, stays collapsed across screens): *With your finger*, *Watch*, *What we saw on device (reported)*;
- the **controls** (**Load**, A/B toggles, sliders, buttons);
- the **HUD** floating over the screen. Tap its title to collapse it to one line, drag it out of the way, **Reset stats** to start a fresh window.

HUD fields:

- `UI` and `Raster`: mean, p95, and the share of frames slower than 16.7 ms (60 Hz) and 8.3 ms (120 Hz), over the last 600 frames. UI is `FrameTiming.buildDuration`, raster is `rasterDuration`. The engine batches timings (about 100 ms in profile), so the numbers trail the screen.
- `worst UI frame`: the slowest UI-thread frame in the last second, and since reset.
- `RSS`: `ProcessInfo.currentRss`. **Dart-visible RSS, GPU textures are NOT included**; tap the info icon for the long note. Use the tools below for graphics memory.
- Scenario counters (blur mounts, config builds, rebuild counts, and so on).
- On `main.dart`, the patched package's production and texture counters. **They only move in debug builds**: the package increments them behind `if (kDebugMode)`. In `--profile` the HUD prints "n/a (debug build only)". To read them, run the scenario once with `flutter run --debug` (numbers only; take timings from `--profile`).

The HUD itself causes about two trivial frames per second, which are in the stats like any other. Use **Auto-scroll** (where offered) for repeatable runs; touching the list while it runs fights it, so switch it off first.

## Load

Every screen's controls start with **Load** (Light / Real-app, default **Real-app**), one global setting shared by all three screens.

- **Light**: the bare demo, rows on a flat surface. On a Nothing Phone (2) in profile mode this alone reproduced nothing (reported: S1 raster p95 about 2 ms, S2 stock and band both under 9 ms, S3 memory flat).
- **Real-app**: what the production screens put under their blurs, all **inside the blurred child**:
  - `AmbientBackground`: large soft colour blobs (six full-area `RadialGradient` fills) drifting forever, repainted every frame by a `CustomPainter`, so the blurred subtree is dirty every frame, even at rest;
  - glass cards (`BackdropFilter`, sigma 20, in a rounded `ClipRRect`): a "Recently played" row at the top and one after every 5th song;
  - large cover tiles: 2-column "Made for you" grids after every 5th song (same `CoverArt`, only bigger);
  - long lists: 400 items in S1 and S2, 160 songs plus the cards in S3.

Both loads keep sigma 14.667 logical px (44 device px at 3x), the 120 pt header zone and, on S2 and S3, the footer zone above the mini player; S1 stays header-only. Code: `common/load.dart`, `ambient_background.dart`, `real_app_content.dart` (stock-API only). Refresh rate: `CADisableMinimumFrameDurationOnPhone` is set in `ios/Runner/Info.plist` so ProMotion iPhones can run 120 Hz; Android is left at its default.

## Watching GPU memory

The HUD's RSS cannot see graphics memory, and graphics memory is what kills the app in S3.

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

"Stock" screens use only API of pristine 0.4.1. "Band" means the patched `Inspire.childBlurBand`, offered as an A/B toggle in `main.dart` only.

Blur sigma note: `inspire_blur` takes sigma in **device** px (the animated-sampler pass divides by the device pixel ratio, the image-filter pass uses it as is), whereas `ImageFilter.blur` takes logical px. The app passes `14.667 * devicePixelRatio` (44 at 3x).

| | Music screen | Kind | Finger steps | What to look for |
|---|---|---|---|---|
| **S1** Whole-child blur | Library > Songs | stock | 1. With the list at the top, drag it up slowly: the app bar blur ramps in over the first 80 pt. 2. Keep scrolling 5 s (or Auto-scroll). 3. Switch Blur off and repeat. | Raster time on vs off: the **whole list** is re-rasterised every frame, even below the zone where the mask is zero. Zone ruler marks 120 pt. On a Nothing Phone (2) (Android) it still feels laggy. |
| **S2** Header + footer blur nested | Library > Songs with mini player and navigation bar | stock + band A/B | 1. Leave the list at rest for a few seconds and read the HUD. 2. Scroll slowly up and down (or Auto-scroll). 3. Switch "Animated" off and on (equalizer on the playing song, progress bar and equalizer on the mini player). 4. `main.dart`: switch Blur to `Inspire.childBlurBand` and repeat. | The footer blur **wraps** the header blur which wraps the list; the playing song's equalizer repaints every frame inside, so the subtree is dirty even at rest. Stock: each layer re-snapshots its whole child per ancestor walk, 6 render targets per frame. Band: counters (debug) show productions, window skips, same-frame reuse. On a Nothing Phone (2) (Android) it still feels laggy with the band variant. |
| **S3** Long animation under the blur | Playlist (swipe a song to remove it) | stock + band A/B | 1. Swipe a song sideways: it breaks into particles over 1.25 s, then collapses. 2. Or press "Play once" (the third song from the top of what is on screen), or "Play 20 in a row". 3. While it plays press "Fling list" (or fling by hand); the run carries on at wherever the list is. 4. Compare Animation "rebuild" with "paint only", and (`main.dart`) Blur stock with band. "Restore songs" refills the list. | **Can crash the app** on stock (iPhone: graphics memory into jetsam). Each dirty frame makes band-sized textures per blur layer and reclamation lags seconds behind. The fix: (a) window-signature gate in the band sampler re-serves the band when nothing in its window changed, (b) paint-only animation, (c) global outstanding-texture cap as backstop. Watch graphics memory; HUD counters (debug) show productions and window skips. On a Nothing Phone (2) (Android) it still feels laggy with the band variant. |

Each info card in the app carries the same steps plus "what we saw on device". Those "saw" lines are the app team's reported observations (and the dev-rig numbers from `PATCHES.md`); this demo does not measure or reproduce those figures by itself.

## Layout

```
lib/
  main.dart            everything (needs the patched package)
  main_stock.dart      S1-S3, pristine-0.4.1 API only
  app/                 MaterialApp shell, home menu, Scenario model
  hud/                 FrameTiming collector, HUD overlay, HudCounter
  common/              music content widgets, test-panel scaffold, controls,
                       particles, nested blur body, Load setting, ambient
                       background, glass cards and cover grids (stock-API only)
  stock/               S1-S3 screens + buildStockScenarios()
  patched/             Inspire.childBlurBand variant, debug counters
                       + buildAllScenarios()
test/
  smoke_test.dart          home + every screen (both loads) under both scenario lists
  stock_smoke_test.dart    same for the stock list only (runs on pristine too)
  stock_isolation_test.dart  main_stock.dart never reaches lib/patched
  real_app_slots_test.dart   slot pattern of the Real-app lists
```

`hud/`, `common/`, `stock/` and `app/` must keep compiling against pristine 0.4.1; anything that needs the patched package goes under `lib/patched/`.

## What was verified

- `flutter analyze`: no issues.
- `flutter test`: 42 tests pass (home and every screen, under both loads and both scenario lists, plus finger-level interactions, among them "Play 20 in a row" with "Fling list" under both loads).
- `lib/main_stock.dart` against a real pristine package: in a copy of the tree with `packages/inspire_blur` replaced by `git archive upstream-0.4.1`, `flutter analyze lib/main_stock.dart lib/stock lib/common lib/hud lib/app` and the stock tests are clean, `flutter test test/stock_smoke_test.dart test/stock_isolation_test.dart test/real_app_slots_test.dart` passes (18 tests), and `flutter build bundle --target=lib/main_stock.dart` succeeds.

Fixed: in S3, "Fling list" while "Play 20 in a row" was running froze the run after a couple of songs and it never finished. The list builds rows lazily, so the flung list disposed the row that was mid-dissolve, and a disposed `AnimationController` leaves its `forward()` future unresolved; the run awaited it forever. A dissolving row now keeps itself alive until it has been removed (and never leaves a waiter hanging if it is disposed anyway), and the run targets the third song of what is on screen instead of a fixed list index that scrolling had made unbuilt. `test/support/smoke_cases.dart` covers it.

Not verified: running on a device, and that Real-app is heavy enough to show the production cost (it was built to the brief, not measured). The widget tests do not load the blur shader or the distribution map (their async work does not complete under the test binding), so the blur render paths themselves, all timings, and all memory behaviour are unexercised until run on a phone. No Android or iOS build was made here.
