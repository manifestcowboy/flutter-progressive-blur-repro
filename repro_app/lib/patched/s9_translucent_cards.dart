import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:inspire_blur/inspire_blur.dart';

import '../common/auto_scroller.dart';
import '../common/blur_util.dart';
import '../common/constants.dart';
import '../common/controls.dart';
import '../common/music_chrome.dart';
import '../common/music_data.dart';
import '../common/music_widgets.dart';
import '../common/scenario_scaffold.dart';
import '../hud/hud_counter.dart';

const ScenarioInfo _info = ScenarioInfo(
  finger:
      'Scroll the Home list slowly so a "recently played" card slides under '
      'the bottom edge of the app bar zone (about 120 pt from the top of the '
      'list area) and stop with the card straddling it. Then switch '
      'realUnderlap through 0, 12, 24 and 48.',
  watch:
      'Each card is a translucent BackdropFilter panel over a coloured '
      'banner. With realUnderlap 0 the band sampler cuts the real child at '
      'the seam, so the part of the card below the seam blurs an unpainted '
      'base and goes dark in a strip along the seam (as deep as the '
      'panel\'s own blur reach, about 3 x its sigma). With 24 or more the '
      'real child is also painted that far into the band, under the band '
      'picture, so the panel blurs real pixels and matches the rest of the '
      'card. realUnderlap is only safe when the child is OPAQUE where the '
      'underlap lands (the body here has an opaque base): over translucent '
      'content the strip would be drawn twice.',
  saw: 'Translucent cards straddling the seam went dark with realUnderlap 0 '
      '(about 15/255 against 52/255 expected). Patched package only: the '
      'stock composition has no seam.',
);

/// S9: Home, with translucent cards sliding under a band-sampler header.
class TranslucentCardsScreen extends StatefulWidget {
  const TranslucentCardsScreen({
    super.key,
    this.counters = const <HudCounter>[],
  });

  final List<HudCounter> counters;

  @override
  State<TranslucentCardsScreen> createState() =>
      _TranslucentCardsScreenState();
}

class _TranslucentCardsScreenState extends State<TranslucentCardsScreen> {
  final ScrollController _scroll = ScrollController();
  late final AutoScroller _auto = AutoScroller(_scroll);
  double _underlap = 0;

  @override
  void dispose() {
    _auto.dispose();
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return ScenarioScaffold(
      title: 'S9 · Translucent cards under the band (patched)',
      info: _info,
      counters: widget.counters,
      controls: ControlsRow(
        children: <Widget>[
          SegmentChoice<double>(
            label: 'realUnderlap',
            value: _underlap,
            options: <double, String>{
              0: '0',
              12: '12',
              24: '24',
              48: '48',
            },
            onChanged: (double v) => setState(() => _underlap = v),
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
        title: 'Good evening',
        bottom: const _HomeSubtitle(),
        body: LayoutBuilder(
          builder: (BuildContext context, BoxConstraints box) {
            return Inspire.childBlurBand(
              config: InspireBlurConfig.topToBottom(
                sigma: deviceSigma(context, kBlurLogicalSigma),
                extent: zoneExtent(kZoneHeight, box.maxHeight),
              ),
              realUnderlap: _underlap,
              // The opaque base realUnderlap needs.
              child: ColoredBox(
                color: scheme.surface,
                child: ListView.builder(
                  controller: _scroll,
                  padding: const EdgeInsets.only(top: kHeaderHeight, bottom: 24),
                  itemCount: 200,
                  itemBuilder: (BuildContext context, int i) =>
                      i % 5 == 4 ? AlbumRow(index: i) : _RecentCard(index: i),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _HomeSubtitle extends StatelessWidget {
  const _HomeSubtitle();

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(
          'Recently played',
          style: theme.textTheme.bodyMedium
              ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
      ),
    );
  }
}

/// A "recently played" card: a coloured banner with a translucent
/// BackdropFilter panel over its lower part.
class _RecentCard extends StatelessWidget {
  const _RecentCard({required this.index});

  final int index;

  @override
  Widget build(BuildContext context) {
    final Song song = songAt(index);
    final ThemeData theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: SizedBox(
        height: 136,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: Stack(
            fit: StackFit.expand,
            children: <Widget>[
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: <Color>[
                      seedColor(index * 2),
                      seedColor(index * 2 + 7, value: 0.7),
                    ],
                  ),
                ),
              ),
              Positioned(
                right: -20,
                top: -30,
                child: Container(
                  width: 120,
                  height: 120,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white.withValues(alpha: 0.35),
                  ),
                ),
              ),
              Positioned(
                left: 12,
                right: 12,
                bottom: 12,
                height: 68,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: BackdropFilter(
                    filter: ui.ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                    child: Container(
                      color: Colors.white.withValues(alpha: 0.22),
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      child: Row(
                        children: <Widget>[
                          CoverArt(seed: song.id, size: 48, radius: 8),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: <Widget>[
                                Text(
                                  song.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.titleSmall
                                      ?.copyWith(color: Colors.white),
                                ),
                                Text(
                                  song.artist,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.bodySmall
                                      ?.copyWith(color: Colors.white70),
                                ),
                              ],
                            ),
                          ),
                          const Icon(Icons.play_circle_fill, color: Colors.white),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
