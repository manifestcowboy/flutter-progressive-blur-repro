import 'package:flutter/material.dart';
import 'package:inspire_blur/inspire_blur.dart';

import '../common/auto_scroller.dart';
import '../common/blur_util.dart';
import '../common/constants.dart';
import '../common/controls.dart';
import '../common/music_chrome.dart';
import '../common/music_widgets.dart';
import '../common/scenario_scaffold.dart';
import '../common/zone_ruler.dart';

const ScenarioInfo _info = ScenarioInfo(
  finger:
      'Start with the list at the top and drag it up slowly. The app bar blur '
      'ramps in from 0 over the first 80 pt of scroll and then holds. Keep '
      'scrolling for a few seconds (or use Auto-scroll), then switch Blur off '
      'and scroll the same way to compare.',
  watch:
      '1. Cost: HUD raster time with Blur on vs off. Inspire.childBlur '
      '(animatedSampler) snapshots the WHOLE list into a texture and runs the '
      'shader over all of it every frame, even below the 120 pt zone where '
      'the mask is zero.\n'
      '2. Shimmer: with blur on, antialiased edges below the zone (cover art '
      'rims, glyph edges) shimmer slightly while the list moves, compared '
      'with blur off, because every pixel takes a texture round trip.\n'
      '3. Sigma units: inspire_blur takes sigma in DEVICE px. This screen '
      'passes 14.667 * devicePixelRatio (44 at 3x), which is the same blur as '
      '14.667 logical px with ImageFilter.blur.',
  saw: 'The whole list is re-rasterised every frame even where the mask is '
      'zero, and antialiased edges below the blur zone shimmer slightly '
      'compared with blur off. On a Nothing Phone (2) (Adreno 730, Impeller) a '
      'snapshot plus a two-pass Gaussian per frame still felt laggy; an '
      'iPhone was smooth.',
);

/// S2: `Inspire.childBlur` over a scroll view, sigma driven by scroll offset.
class WholeChildBlurScreen extends StatefulWidget {
  const WholeChildBlurScreen({super.key});

  @override
  State<WholeChildBlurScreen> createState() => _WholeChildBlurScreenState();
}

class _WholeChildBlurScreenState extends State<WholeChildBlurScreen> {
  final ScrollController _scroll = ScrollController();
  late final AutoScroller _auto = AutoScroller(_scroll);
  final ValueNotifier<double> _offset = ValueNotifier<double>(0);

  /// Keeps the list's State alive when the blur wrapper above it appears,
  /// disappears or switches between sigma 0 (bare child) and sigma > 0.
  final GlobalKey _listKey = GlobalKey();

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
    final Widget list = SongsListView(key: _listKey, controller: _scroll);
    return ScenarioScaffold(
      title: 'S2 · Whole-child blur (stock)',
      info: _info,
      controls: ControlsRow(
        children: <Widget>[
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
