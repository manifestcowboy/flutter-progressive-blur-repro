import '../app/scenario.dart';
import '../common/blur_variant.dart';
import '../hud/hud_counter.dart';
import '../stock/blur_variants.dart';
import '../stock/scenarios.dart';
import 'band_variant.dart';
import 'counters.dart';
import 's9_translucent_cards.dart';

/// Every scenario: S1 to S8 with the band sampler offered as an A/B option
/// where it applies, the package's debug counters on the HUD, and S9.
List<Scenario> buildAllScenarios() {
  final List<HudCounter> counters = patchedHudCounters();
  return <Scenario>[
    ...buildStockScenarios(
      variants: <BlurVariant>[stockChildBlur, bandChildBlur],
      counters: counters,
    ),
    Scenario(
      id: 'S9',
      title: 'Translucent cards under the band (patched)',
      screen: 'Home',
      subtitle: 'BackdropFilter cards at the band seam; realUnderlap 0 vs 24',
      kind: ScenarioKind.patchedOnly,
      builder: (_) => TranslucentCardsScreen(counters: counters),
    ),
  ];
}
