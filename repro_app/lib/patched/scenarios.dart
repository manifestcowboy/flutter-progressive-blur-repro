import '../app/scenario.dart';
import '../common/blur_variant.dart';
import '../hud/hud_counter.dart';
import '../stock/blur_variants.dart';
import '../stock/scenarios.dart';
import 'band_variant.dart';
import 'counters.dart';

/// Every scenario, with the band sampler offered as an A/B option where it
/// applies and the package's debug counters on the HUD.
List<Scenario> buildAllScenarios() {
  final List<HudCounter> counters = patchedHudCounters();
  return buildStockScenarios(
    variants: <BlurVariant>[stockChildBlur, bandChildBlur],
    counters: counters,
  );
}
