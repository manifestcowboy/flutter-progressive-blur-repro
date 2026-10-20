import '../app/scenario.dart';
import '../common/blur_variant.dart';
import '../hud/hud_counter.dart';
import 'blur_variants.dart';
import 's1_whole_child.dart';
import 's2_nested.dart';
import 's3_long_animation.dart';

/// Scenarios 1 to 3, using only API that exists in pristine inspire_blur 0.4.1.
///
/// The patched entrypoint calls this too, passing the extra [variants] (the
/// band sampler) and [counters] (the package's debug counters) that
/// scenarios 2 and 3 can show.
List<Scenario> buildStockScenarios({
  List<BlurVariant>? variants,
  List<HudCounter> counters = const <HudCounter>[],
}) {
  final List<BlurVariant> blurs = variants ?? <BlurVariant>[stockChildBlur];
  final bool ab = blurs.length > 1;
  return <Scenario>[
    Scenario(
      id: 'S1',
      title: 'Whole-child blur',
      screen: 'Library > Songs',
      subtitle: 'app bar blur ramps in with scroll; whole list re-rasterised',
      kind: ScenarioKind.stock,
      builder: (_) => const WholeChildBlurScreen(),
    ),
    Scenario(
      id: 'S2',
      title: 'Header + footer blur nested',
      screen: 'Library > Songs with mini player',
      subtitle: 'footer wraps header, playing row animates every frame',
      kind: ab ? ScenarioKind.stockWithBand : ScenarioKind.stock,
      builder: (_) => NestedBlurScreen(variants: blurs, counters: counters),
    ),
    Scenario(
      id: 'S3',
      title: 'Long animation under the blur',
      screen: 'Playlist',
      subtitle: 'swipe a song: 1.25 s particle dissolve; fling the list',
      kind: ab ? ScenarioKind.stockWithBand : ScenarioKind.stock,
      builder: (_) => LongAnimationScreen(variants: blurs, counters: counters),
    ),
  ];
}
