import 'package:inspire_blur/inspire_blur.dart';

import '../hud/hud_counter.dart';

/// The patched package's production and texture counters, for the HUD.
///
/// The package only moves them in debug builds (`if (kDebugMode)`), so in a
/// profile run they stay at zero and the HUD says so. Run one pass in
/// `--debug` just to read these; take timings from `--profile`.
List<HudCounter> patchedHudCounters() => <HudCounter>[
      HudCounter.count(
        'band productions (2 textures each)',
        () => debugInspireBandSamplerProductions,
        debugOnly: true,
      ),
      HudCounter.count(
        'band textures (toImageSync)',
        () => debugInspireBandSamplerTextures,
        debugOnly: true,
      ),
      HudCounter.count(
        'band target MB (pixels x 4)',
        () => debugInspireBandSamplerTargetPixels * 4 / 1e6,
        debugOnly: true,
      ),
      HudCounter.count(
        'window-gate skips',
        () => debugInspireBandSamplerWindowSkips,
        debugOnly: true,
      ),
      HudCounter.count(
        'forced refreshes (valve)',
        () => debugInspireBandSamplerForcedRefreshes,
        debugOnly: true,
      ),
      HudCounter.count(
        'same-frame picture reuse',
        () => debugInspireBandSamplerPictureReuse,
        debugOnly: true,
      ),
      HudCounter.count(
        'stale bands (backstop)',
        () => debugInspireBandSamplerStaleBands,
        debugOnly: true,
      ),
      HudCounter.count(
        'band scenes walked',
        () => debugInspireBandSamplerScenes,
        debugOnly: true,
      ),
      HudCounter.count(
        'fallback sampler targets',
        () => debugInspireBoundedSamplerTargets,
        debugOnly: true,
      ),
      HudCounter.text(
        'outstanding textures / cap',
        () => '$debugInspireOutstandingTextures / $kInspireMaxOutstandingTextures',
        debugOnly: true,
      ),
      HudCounter.text(
        'last produce reason',
        () => debugInspireBandSamplerProduceReason.isEmpty
            ? '-'
            : debugInspireBandSamplerProduceReason,
        debugOnly: true,
      ),
      HudCounter.text(
        'unrecognised layer in window',
        () => debugInspireBandSamplerWindowUnknown.isEmpty
            ? '-'
            : debugInspireBandSamplerWindowUnknown,
        debugOnly: true,
      ),
    ];
