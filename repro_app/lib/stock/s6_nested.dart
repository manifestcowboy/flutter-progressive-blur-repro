import 'package:flutter/material.dart';

import '../common/auto_scroller.dart';
import '../common/blur_variant.dart';
import '../common/constants.dart';
import '../common/controls.dart';
import '../common/music_chrome.dart';
import '../common/music_data.dart';
import '../common/music_widgets.dart';
import '../common/nested_blur_body.dart';
import '../common/scenario_scaffold.dart';
import '../hud/hud_counter.dart';

/// Where the playing song sits in the list: below both blur zones at rest.
const int _playingIndex = 2;

ScenarioInfo _info(bool hasBand) => ScenarioInfo(
      finger:
          'Leave the list at rest first and read the HUD for a few seconds, '
          'then scroll slowly up and down (or use Auto-scroll). Switch '
          '"Animated" off and on: it controls the equalizer on the playing '
          'song and the mini player\'s progress bar and equalizer.'
          '${hasBand ? ' Then switch the blur to Inspire.childBlurBand and repeat.' : ' (The band option only exists in main.dart; the original numbers come from running main_stock.dart against pristine 0.4.1.)'}',
      watch:
          'The footer blur (above the mini player and navigation bar) WRAPS '
          'the header blur, which wraps the list. The playing song\'s '
          'equalizer repaints every frame inside that subtree, so it is dirty '
          'every frame even with your finger off the screen. With stock '
          'Inspire.childBlur every layer snapshots its whole child once per '
          'ancestor walk, and the inner layer is walked twice: 6 render '
          'targets per frame. Compare raster mean and p95 with Animated on vs '
          'off, and graphics memory (not RSS).'
          '${hasBand ? '\nWith the band variant the HUD counters (debug builds) show band productions, picture reuse and the outstanding-texture gauge.' : ''}',
      saw: 'With stock, each nested layer re-rasterised its whole child per '
          'ancestor walk: 6 targets per frame, about 13.5 MB per frame at '
          '1206x467x4 per band-sized target (2.25 MB each); whole-child '
          'targets are far bigger (1206x2622x4 = 12.65 MB each). Memory peaked '
          'on device. Same-frame reuse in the band sampler took 6 to 4.',
    );

/// S6: a songs list with a header blur and a footer blur behind the mini
/// player, the footer wrapping the header.
class NestedBlurScreen extends StatefulWidget {
  const NestedBlurScreen({
    super.key,
    required this.variants,
    this.counters = const <HudCounter>[],
  });

  /// The blur implementations on offer; one entry hides the toggle.
  final List<BlurVariant> variants;
  final List<HudCounter> counters;

  @override
  State<NestedBlurScreen> createState() => _NestedBlurScreenState();
}

class _NestedBlurScreenState extends State<NestedBlurScreen> {
  final ScrollController _scroll = ScrollController();
  late final AutoScroller _auto = AutoScroller(_scroll);
  final GlobalKey _listKey = GlobalKey();
  int _variant = 0;
  bool _animated = true;

  @override
  void dispose() {
    _auto.dispose();
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ScenarioScaffold(
      title: 'S6 · Header + footer blur nested',
      info: _info(widget.variants.length > 1),
      counters: widget.counters,
      controls: ControlsRow(
        children: <Widget>[
          if (widget.variants.length > 1)
            SegmentChoice<int>(
              label: 'Blur',
              value: _variant,
              options: <int, String>{
                for (int i = 0; i < widget.variants.length; i++)
                  i: widget.variants[i].label,
              },
              onChanged: (int v) => setState(() => _variant = v),
            ),
          ToggleChip(
            label: 'Animated',
            value: _animated,
            onChanged: (bool v) => setState(() => _animated = v),
          ),
          ListenableBuilder(
            listenable: _auto,
            builder: (BuildContext context, Widget? _) => ToggleChip(
              label: 'Auto-scroll',
              value: _auto.running,
              onChanged: (_) => _auto.toggle(),
            ),
          ),
        ],
      ),
      body: MusicFrame(
        title: 'Songs',
        bottom: const LibraryChips(),
        bottomBars: true,
        nowPlayingAnimated: _animated,
        body: NestedBlurBody(
          variant: widget.variants[_variant],
          list: SongsListView(
            key: _listKey,
            controller: _scroll,
            bottomPadding: kBottomBarsHeight + 16,
            overrides: <int, WidgetBuilder>{
              _playingIndex: (_) =>
                  PlayingSongTile(song: songAt(_playingIndex), animate: _animated),
            },
          ),
        ),
      ),
    );
  }
}
