import '../app/scenario.dart';
import '../common/blur_variant.dart';
import '../hud/hud_counter.dart';
import 'blur_variants.dart';
import 's1_strip_blur.dart';
import 's2_whole_child.dart';
import 's3_renderer_mismatch.dart';
import 's4_first_touch.dart';
import 's5_config_churn.dart';
import 's6_nested.dart';
import 's7_long_animation.dart';
import 's8_keyboard.dart';

/// S1 to S8, using only API that exists in pristine inspire_blur 0.4.1.
///
/// The patched entrypoint calls this too, passing the extra [variants] (the
/// band sampler) and [counters] (the package's debug counters) that S6 and S7
/// can show.
List<Scenario> buildStockScenarios({
  List<BlurVariant>? variants,
  List<HudCounter> counters = const <HudCounter>[],
}) {
  final List<BlurVariant> blurs = variants ?? <BlurVariant>[stockChildBlur];
  final bool ab = blurs.length > 1;
  return <Scenario>[
    Scenario(
      id: 'S1',
      title: 'Strip blur (before inspire_blur)',
      screen: 'Library > Songs',
      subtitle: '32 / 64 / 96 stacked BackdropFilter strips: banding, jank',
      kind: ScenarioKind.stock,
      builder: (_) => const StripBlurScreen(),
    ),
    Scenario(
      id: 'S2',
      title: 'Whole-child blur (stock)',
      screen: 'Library > Songs',
      subtitle: 'app bar blur ramps in with scroll; whole list re-rasterised',
      kind: ScenarioKind.stock,
      builder: (_) => const WholeChildBlurScreen(),
    ),
    Scenario(
      id: 'S3',
      title: 'Renderer mismatch & boxy blur (stock)',
      screen: 'Library > Songs (genres, artists)',
      subtitle: 'auto vs sampler vs filter, sigma to 30, coverage overhang',
      kind: ScenarioKind.stock,
      builder: (_) => const RendererMismatchScreen(),
    ),
    Scenario(
      id: 'S4',
      title: 'First-touch stall (stock)',
      screen: 'Album',
      subtitle: 'blur mounted only while touched: sync map build on touch',
      kind: ScenarioKind.stock,
      builder: (_) => const FirstTouchScreen(),
    ),
    Scenario(
      id: 'S5',
      title: 'Reorder drag: new blur config per frame (stock)',
      screen: 'Playlist edit',
      subtitle: 'config rebuilt every frame while dragging; may SIGKILL',
      kind: ScenarioKind.stock,
      builder: (_) => const ConfigChurnScreen(),
    ),
    Scenario(
      id: 'S6',
      title: 'Header + footer blur nested',
      screen: 'Library > Songs with mini player',
      subtitle: 'footer wraps header, playing row animates every frame',
      kind: ab ? ScenarioKind.stockWithBand : ScenarioKind.stock,
      builder: (_) => NestedBlurScreen(variants: blurs, counters: counters),
    ),
    Scenario(
      id: 'S7',
      title: 'Long animation under the blur',
      screen: 'Playlist',
      subtitle: 'swipe a song: 1.25 s particle dissolve; fling the list',
      kind: ab ? ScenarioKind.stockWithBand : ScenarioKind.stock,
      builder: (_) => LongAnimationScreen(variants: blurs, counters: counters),
    ),
    Scenario(
      id: 'S8',
      title: 'Keyboard (stock vs patched package)',
      screen: 'Search',
      subtitle: 'keyboard frames rebuild the blur subtree via MediaQuery.of',
      kind: ScenarioKind.stock,
      builder: (_) => const KeyboardScreen(),
    ),
  ];
}
