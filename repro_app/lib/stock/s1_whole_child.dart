import 'package:flutter/material.dart';
import 'package:inspire_blur/inspire_blur.dart';

import '../common/auto_scroller.dart';
import '../common/blur_util.dart';
import '../common/constants.dart';
import '../common/controls.dart';
import '../common/load.dart';
import '../common/music_chrome.dart';
import '../common/scenario_scaffold.dart';
import '../common/songs_list.dart';
import '../common/zone_ruler.dart';

const ScenarioInfo _info = ScenarioInfo(
  finger:
      'Drag the list up slowly from the top: the app bar blur ramps in over '
      'the first 80 pt. Keep scrolling for a few seconds (or use '
      'Auto-scroll), then switch Blur off and scroll the same way.',
  watch:
      'HUD raster time with Blur on vs off. Inspire.childBlur snapshots the '
      'whole list and runs the shader over all of it every frame, even below '
      'the 120 pt zone where the mask is zero. Load "Real-app" (default) puts '
      'an ambient background that repaints every frame, glass cards and large '
      'covers inside the blurred child; "Light" is the bare list.',
  saw: 'On a Nothing Phone (2) (Android, Impeller) this still felt laggy; '
      'an iPhone was smooth.',
);

/// S1: `Inspire.childBlur` over a scroll view, sigma driven by scroll offset.
class WholeChildBlurScreen extends StatefulWidget {
  const WholeChildBlurScreen({super.key});

  @override
  State<WholeChildBlurScreen> createState() => _WholeChildBlurScreenState();
}

class _WholeChildBlurScreenState extends State<WholeChildBlurScreen> {
  final ScrollController _scroll = ScrollController();
  late final AutoScroller _auto = AutoScroller(_scroll);
  final ValueNotifier<double> _offset = ValueNotifier<double>(0);

  /// Keep the list's State (and the ambient background's) alive when the blur
  /// wrapper above them appears, disappears or switches between sigma 0 (bare
  /// child) and sigma > 0.
  final GlobalKey _listKey = GlobalKey();
  final GlobalKey _stageKey = GlobalKey();

  bool _blurOn = true;
  bool _ruler = false;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(
      () => _offset.value = _scroll.hasClients ? _scroll.offset : 0,
    );
  }

  @override
  void dispose() {
    _auto.dispose();
    _scroll.dispose();
    _offset.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // What goes inside the blur: the scroll view, plus under Load "Real-app"
    // the animated ambient background behind it.
    final Widget list = LoadStage(
      key: _stageKey,
      child: SongsListView(key: _listKey, controller: _scroll),
    );
    return ScenarioScaffold(
      title: 'S1 · Whole-child blur',
      info: _info,
      controls: ControlsRow(
        children: <Widget>[
          const LoadChoice(),
          ToggleChip(
            label: 'Blur on',
            value: _blurOn,
            onChanged: (bool v) => setState(() => _blurOn = v),
          ),
          ListenableBuilder(
            listenable: _auto,
            builder: (BuildContext context, Widget? _) => ToggleChip(
              label: 'Auto-scroll',
              value: _auto.running,
              onChanged: (_) => _auto.toggle(),
            ),
          ),
          ToggleChip(
            label: 'Zone ruler',
            value: _ruler,
            onChanged: (bool v) => setState(() => _ruler = v),
          ),
        ],
      ),
      body: MusicFrame(
        title: 'Songs',
        bottom: const LibraryChips(),
        body: Stack(
          children: <Widget>[
            Positioned.fill(
              child: !_blurOn
                  ? list
                  : LayoutBuilder(
                      builder: (BuildContext context, BoxConstraints box) {
                        final double full =
                            deviceSigma(context, kBlurLogicalSigma);
                        final double extent =
                            zoneExtent(kZoneHeight, box.maxHeight);
                        return ValueListenableBuilder<double>(
                          valueListenable: _offset,
                          child: list,
                          builder: (BuildContext context, double offset,
                              Widget? child) {
                            final double ramp =
                                (offset / kScrollRampDistance).clamp(0.0, 1.0);
                            return Inspire.childBlur(
                              config: InspireBlurConfig.topToBottom(
                                sigma: full * ramp,
                                extent: extent,
                              ),
                              mode: InspireBlurMode.animatedSampler,
                              child: child!,
                            );
                          },
                        );
                      },
                    ),
            ),
            if (_ruler) const ZoneRuler(),
          ],
        ),
      ),
    );
  }
}
