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
import '../common/zone_ruler.dart';

const ScenarioInfo _info = ScenarioInfo(
  finger:
      'Scroll slowly so the big genre chips and round artist avatars pass '
      'through the top 120 pt. Then, with the list stopped on a row of chips: '
      '1. switch mode between auto, animatedSampler and imageFilter; '
      '2. drag the sigma slider towards 30; '
      '3. switch on "Child paints 250 px above" and "Zone ruler" and compare '
      'where the blur fades out against the dashed line in each mode.',
  watch:
      '1. auto: the label under the controls says what it resolved to. Here '
      'the blur is the PARENT of the scroll view, so there is no Scrollable '
      'ancestor and auto picks imageFilter. On web (and without Impeller) it '
      'picks animatedSampler, so the same code renders two ways.\n'
      '2. Boxy blur: in imageFilter mode the shader receives sigma in device '
      'px and truncates the kernel at MAX_RADIUS 64 device px, so above about '
      '7 logical px (21 device px at 3x) it stops being Gaussian and rounded '
      'chips and circles square off. The sampler pass divides by dpr first, '
      'so it only squares off above 64/3 = 21 logical px; push the slider '
      'past that to see it. (Pristine 0.4.1 has MAX_RADIUS 64; the patched '
      'shader raises it to 192.)\n'
      '3. Coverage: ImageFilter.shader sizes its mask by what the child '
      'painted, not by the box. With the toggle on, imageFilter stretches and '
      'shifts the ramp (its end moves against the ruler); animatedSampler '
      'does not move.',
  saw: 'At dpr 3, imageFilter truncated the kernel and rounded shapes squared '
      'off. A child painting 250 px above the box shifted the ramp: 248.5 '
      'device px of overhang started the mask at 0.37 instead of 1.0.',
);

/// S3: the same ramp under three renderer choices, over rounded shapes.
class RendererMismatchScreen extends StatefulWidget {
  const RendererMismatchScreen({super.key});

  @override
  State<RendererMismatchScreen> createState() => _RendererMismatchScreenState();
}

class _RendererMismatchScreenState extends State<RendererMismatchScreen> {
  final ScrollController _scroll = ScrollController();
  late final AutoScroller _auto = AutoScroller(_scroll);
  InspireBlurMode _mode = InspireBlurMode.auto;
  double _sigma = kBlurLogicalSigma;
  bool _overhang = false;
  bool _ruler = true;

  @override
  void dispose() {
    _auto.dispose();
    _scroll.dispose();
    super.dispose();
  }

  /// A re-statement of the package's `auto` rule, for the label only.
  String _resolved(BuildContext context) {
    if (_mode == InspireBlurMode.animatedSampler) return 'animatedSampler';
    if (!ui.ImageFilter.isShaderFilterSupported) {
      return 'animatedSampler (shader image filters unsupported here)';
    }
    if (_mode == InspireBlurMode.imageFilter) return 'imageFilter';
    return Scrollable.maybeOf(context) == null
        ? 'imageFilter (blur is the parent of the Scrollable)'
        : 'animatedSampler (inside a Scrollable)';
  }

  @override
  Widget build(BuildContext context) {
    return ScenarioScaffold(
      title: 'S3 · Renderer mismatch, boxy blur (stock)',
      info: _info,
      controls: ControlsRow(
        children: <Widget>[
          SegmentChoice<InspireBlurMode>(
            label: 'Mode',
            value: _mode,
            options: const <InspireBlurMode, String>{
              InspireBlurMode.auto: 'auto',
              InspireBlurMode.animatedSampler: 'animatedSampler',
              InspireBlurMode.imageFilter: 'imageFilter',
            },
            onChanged: (InspireBlurMode v) => setState(() => _mode = v),
          ),
          Builder(
            builder: (BuildContext context) => Text(
              'resolves to: ${_resolved(context)}',
              style: Theme.of(context).textTheme.labelSmall,
            ),
          ),
          LabeledSlider(
            label: 'Sigma',
            value: _sigma,
            min: 1,
            max: 30,
            divisions: 58,
            unit: ' pt',
            onChanged: (double v) => setState(() => _sigma = v),
          ),
          ToggleChip(
            label: 'Child paints 250 px above',
            value: _overhang,
            onChanged: (bool v) => setState(() => _overhang = v),
          ),
          ToggleChip(
            label: 'Zone ruler',
            value: _ruler,
            onChanged: (bool v) => setState(() => _ruler = v),
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
            Positioned.fill(
              child: LayoutBuilder(
                builder: (BuildContext context, BoxConstraints box) {
                  return Inspire.childBlur(
                    config: InspireBlurConfig.topToBottom(
                      sigma: deviceSigma(context, _sigma),
                      extent: zoneExtent(kZoneHeight, box.maxHeight),
                    ),
                    mode: _mode,
                    child: Stack(
                      fit: StackFit.expand,
                      // The overhanging child must not be clipped by the Stack.
                      clipBehavior: Clip.none,
                      children: <Widget>[
                        _ShapesList(controller: _scroll),
                        if (_overhang)
                          Positioned(
                            top: 0,
                            left: 0,
                            right: 0,
                            height: 60,
                            // Painted 250 px ABOVE the blurred box.
                            child: Transform.translate(
                              offset: const Offset(0, -250),
                              child: const DecoratedBox(
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    colors: <Color>[
                                      Color(0xFFE91E63),
                                      Color(0xFFFFC107),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
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

/// Rows of large rounded shapes: artist avatars with genre chips, chip rows
/// and avatar rows. Big saturated fills make kernel truncation obvious.
class _ShapesList extends StatelessWidget {
  const _ShapesList({required this.controller});

  final ScrollController controller;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return ListView.builder(
      controller: controller,
      padding: const EdgeInsets.only(top: kHeaderHeight, bottom: 24),
      itemCount: 300,
      itemBuilder: (BuildContext context, int i) {
        final Song song = songAt(i);
        switch (i % 3) {
          case 0:
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: <Widget>[
                  ArtistAvatar(name: song.artist, radius: 32),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(song.artist, style: theme.textTheme.titleMedium),
                  ),
                  GenreChip(genre: song.genre, height: 40),
                ],
              ),
            );
          case 1:
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Wrap(
                spacing: 10,
                runSpacing: 10,
                children: <Widget>[
                  for (int k = 0; k < 3; k++)
                    GenreChip(genre: kGenres[(i + k * 3) % kGenres.length], height: 44),
                ],
              ),
            );
          default:
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: <Widget>[
                  for (int k = 0; k < 5; k++)
                    ArtistAvatar(name: songAt(i + k * 2).artist, radius: 30),
                ],
              ),
            );
        }
      },
    );
  }
}
