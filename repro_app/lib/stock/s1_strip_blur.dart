import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../common/auto_scroller.dart';
import '../common/constants.dart';
import '../common/controls.dart';
import '../common/music_chrome.dart';
import '../common/music_widgets.dart';
import '../common/scenario_scaffold.dart';

const ScenarioInfo _info = ScenarioInfo(
  finger:
      'Scroll the song list up and down with one finger, or switch on '
      'Auto-scroll for a repeatable run. Try 32, 64 and 96 strips, and '
      'switch Blur off to see what the list alone costs.',
  watch:
      '1. Banding: horizontal stripes under the app bar where sigma steps '
      'from one strip to the next. Look at the cover art and chips as they '
      'slide into the top 120 pt. Strongest at 32 strips.\n'
      '2. Missed frames: HUD raster p95 and the ">16.7" / ">8.3" columns. '
      'Every strip is its own ClipRect + BackdropFilter (a save layer that '
      'reads the whole backdrop), so cost grows with the strip count.\n'
      'Strip i, counted from the outer edge of the zone, gets '
      'sigma = 13 * (i / N)^1.8 logical px, so the strip under the app bar is '
      'the blurriest.',
  saw: 'Visible banding (stripes) and missed frames while scrolling. This is '
      'what the app did before moving to inspire_blur.',
);

/// S1: the stacked `BackdropFilter` strips that inspire_blur replaced.
class StripBlurScreen extends StatefulWidget {
  const StripBlurScreen({super.key});

  @override
  State<StripBlurScreen> createState() => _StripBlurScreenState();
}

class _StripBlurScreenState extends State<StripBlurScreen> {
  final ScrollController _scroll = ScrollController();
  late final AutoScroller _auto = AutoScroller(_scroll);
  int _strips = 64;
  bool _blurOn = true;

  @override
  void dispose() {
    _auto.dispose();
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ScenarioScaffold(
      title: 'S1 · Strip blur (before inspire_blur)',
      info: _info,
      controls: ControlsRow(
        children: <Widget>[
          SegmentChoice<int>(
            label: 'Strips',
            value: _strips,
            options: const <int, String>{32: '32', 64: '64', 96: '96'},
            onChanged: (int v) => setState(() => _strips = v),
          ),
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
        ],
      ),
      body: MusicFrame(
        title: 'Songs',
        bottom: const LibraryChips(),
        body: Stack(
          children: <Widget>[
            Positioned.fill(child: SongsListView(controller: _scroll)),
            if (_blurOn)
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                height: kZoneHeight,
                child: _StripBlur(strips: _strips, maxSigma: 13),
              ),
          ],
        ),
      ),
    );
  }
}

/// [strips] stacked `ClipRect` + `BackdropFilter`s covering the zone, with
/// sigma rising towards the top edge.
class _StripBlur extends StatelessWidget {
  const _StripBlur({required this.strips, required this.maxSigma});

  final int strips;
  final double maxSigma;

  @override
  Widget build(BuildContext context) {
    final double stripHeight = kZoneHeight / strips;
    return Column(
      children: <Widget>[
        // Strip j=0 is at the top; i counts from the zone's outer edge.
        for (int j = 0; j < strips; j++)
          SizedBox(
            height: stripHeight,
            child: _strip(maxSigma * math.pow((strips - 1 - j) / strips, 1.8)),
          ),
      ],
    );
  }

  Widget _strip(double sigma) {
    if (sigma < 0.05) return const SizedBox.shrink();
    return ClipRect(
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
        child: const SizedBox.expand(),
      ),
    );
  }
}
