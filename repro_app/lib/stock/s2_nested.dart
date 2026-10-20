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
          'Leave the list at rest and read the HUD, then scroll slowly (or '
          'use Auto-scroll). Switch "Animated" off and on: it controls the '
          'equalizer on the playing song and the mini player.'
          '${hasBand ? ' Then switch the blur to Inspire.childBlurBand and repeat.' : ''}',
      watch:
          'The footer blur wraps the header blur, which wraps the list. The '
          'playing song repaints every frame inside, so the blurred subtree '
          'is dirty even at rest. Compare raster time and graphics memory '
          '(not RSS) with Animated on vs off.'
          '${hasBand ? '\nIn debug builds the HUD counters show band productions and outstanding textures.' : ''}',
      saw: 'With stock Inspire.childBlur every nested layer re-rasterised its '
          'whole child: 6 render targets per frame. On a Nothing Phone (2) '
          '(Android) it still feels laggy even with the band variant.',
    );

/// S2: a songs list with a header blur and a footer blur behind the mini
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
      title: 'S2 · Header + footer blur nested',
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
