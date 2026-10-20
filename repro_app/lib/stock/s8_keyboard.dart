import 'package:flutter/material.dart';
import 'package:inspire_blur/inspire_blur.dart';

import '../common/blur_util.dart';
import '../common/build_counter.dart';
import '../common/constants.dart';
import '../common/music_chrome.dart';
import '../common/music_widgets.dart';
import '../common/rebuild_tracker.dart';
import '../common/scenario_scaffold.dart';
import '../hud/hud_counter.dart';

const ScenarioInfo _info = ScenarioInfo(
  finger:
      'Press "Reset stats". Tap the search field: the keyboard slides up '
      '(roughly 15 frames). Dismiss it with the back gesture or by tapping '
      'the list, and repeat a few times. Read the counters after each open.',
  watch:
      '"Blur-owned element rebuilds" (debug builds only, it uses the '
      'framework\'s debugOnRebuildDirtyWidget hook): stock 0.4.1 reads '
      'MediaQuery.of(context) in the blur wrapper and in both blur passes, '
      'which depends on EVERY MediaQuery field, so each frame of the '
      'keyboard animation rebuilds the package-owned subtree under '
      'Inspire.childBlur (and, since the sampler callback is a new closure '
      'each time, repaints it). The patched package reads MediaQuery.sizeOf '
      'and devicePixelRatioOf, which the keyboard does not change, so the '
      'count stays at zero.\n'
      '"App child builds" is a probe inside the blurred child: it stays at 1 '
      'in both, because the child widget instance is identical; only '
      'package-owned elements rebuild.\n'
      'In profile builds, compare UI and raster p95 while the keyboard '
      'animates. The Scaffold does not resize for the keyboard '
      '(resizeToAvoidBottomInset: false) and the search field is outside the '
      'blur, so nothing but the MediaQuery dependency differs.',
  saw: 'Stock: every keyboard animation frame (about 15 per open) rebuilt '
      'every blur subtree. Patched: MediaQuery.sizeOf / devicePixelRatioOf, so '
      'none do.',
);

/// S8: a search screen. The text field is a sibling of the blur, so only the
/// package's own MediaQuery dependency can rebuild the blurred subtree.
class KeyboardScreen extends StatefulWidget {
  const KeyboardScreen({super.key});

  @override
  State<KeyboardScreen> createState() => _KeyboardScreenState();
}

class _KeyboardScreenState extends State<KeyboardScreen> {
  final ScrollController _scroll = ScrollController();
  final RebuildTracker _tracker = RebuildTracker();
  final Counter _probe = Counter();

  /// Built once so that this State's rebuilds never rebuild the blur.
  late final Widget _results = _BlurredResults(
    controller: _scroll,
    probe: _probe,
  );

  @override
  void initState() {
    super.initState();
    _tracker.attach();
  }

  @override
  void dispose() {
    _tracker.detach();
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ScenarioScaffold(
      title: 'S8 · Keyboard',
      info: _info,
      counters: <HudCounter>[
        HudCounter.count(
          'blur-owned element rebuilds',
          () => _tracker.blurOwned,
          debugOnly: true,
        ),
        HudCounter.count('app child builds (probe)', () => _probe.value),
      ],
      onReset: () {
        _tracker.reset();
        _probe.reset();
      },
      body: MusicFrame(
        title: 'Search',
        bottom: const _SearchField(),
        body: _results,
      ),
    );
  }
}

class _SearchField extends StatelessWidget {
  const _SearchField();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
      child: TextField(
        decoration: InputDecoration(
          hintText: 'Songs, artists, albums',
          prefixIcon: const Icon(Icons.search),
          filled: true,
          isDense: true,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(28),
            borderSide: BorderSide.none,
          ),
        ),
      ),
    );
  }
}

/// The search results under a header blur. Built once, so it is only ever
/// rebuilt by something the package itself depends on.
class _BlurredResults extends StatelessWidget {
  const _BlurredResults({required this.controller, required this.probe});

  final ScrollController controller;
  final Counter probe;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints box) {
        return KeyedSubtree(
          key: RebuildTracker.blurKey,
          child: Inspire.childBlur(
            config: InspireBlurConfig.topToBottom(
              sigma: deviceSigma(context, kBlurLogicalSigma),
              extent: zoneExtent(kZoneHeight, box.maxHeight),
            ),
            mode: InspireBlurMode.animatedSampler,
            child: KeyedSubtree(
              key: RebuildTracker.appKey,
              child: BuildCounter(
                counter: probe,
                child: SongsListView(controller: controller),
              ),
            ),
          ),
        );
      },
    );
  }
}
