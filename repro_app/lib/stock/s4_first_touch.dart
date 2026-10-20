import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:inspire_blur/inspire_blur.dart';

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
      '1. Pick "naive". 2. Leave the album at the top, wait a second, then '
      'put a finger on the list and start to drag, or just tap it. Watch '
      'the HUD "worst UI frame (last 1 s)" and "last mount frame". 3. Lift, '
      'scroll back to the very top, wait, and touch again: it repeats on '
      'every touch from rest, not only the first. 4. Repeat with "mounted" '
      'and "fixed" (leave the screen and reopen it first, so the screen-open '
      'cost is not mixed in).',
  watch:
      'One long UI frame at the moment of touch, then smooth scrolling. In '
      'the naive pattern the blur wrapper is mounted when the list leaves '
      'rest and unmounted when it returns, and InspireBlurWrapper builds its '
      'distribution map synchronously on the UI thread in '
      'didChangeDependencies (a size x size Dart loop: about 408k iterations '
      'and a 1.6 MB image on an 852 pt screen). "mounted" keeps the wrapper '
      'at sigma 0 so the cost is paid once when the screen opens. "fixed" '
      'also passes a cached InspireBlurConfig.customMask image (a vertical '
      'gradient drawn once into a 4x2048 image with toImageSync), so there is '
      'no Dart loop at all.',
  saw: 'The app felt unresponsive on the first touch. The map build was '
      'measured at 13.9 ms on mount on the dev rig (macOS AOT, 852 pt); '
      'expect more on a mid-range phone.',
);

enum _Pattern { naive, mounted, fixed }

/// S4: an album screen whose header blur is mounted only while touched or
/// scrolled away from the top.
class FirstTouchScreen extends StatefulWidget {
  const FirstTouchScreen({super.key});

  @override
  State<FirstTouchScreen> createState() => _FirstTouchScreenState();
}

class _FirstTouchScreenState extends State<FirstTouchScreen> {
  final ScrollController _scroll = ScrollController();
  final GlobalKey _listKey = GlobalKey();
  final ValueNotifier<double> _offset = ValueNotifier<double>(0);
  final ValueNotifier<bool> _pointerDown = ValueNotifier<bool>(false);
  int _pointers = 0;

  _Pattern _pattern = _Pattern.naive;
  bool _wasActive = false;
  int _mounts = 0;
  double _lastMountFrameMs = 0;
  final Stopwatch _mountWatch = Stopwatch();
  bool _mountPending = false;

  ui.Image? _mask;
  double _maskExtent = -1;

  /// Replaced masks, kept alive: the package's wrapper may still hold the old
  /// image for a frame, and disposing it under the shader would throw.
  final List<ui.Image> _retiredMasks = <ui.Image>[];

  @override
  void initState() {
    super.initState();
    _scroll.addListener(
      () => _offset.value = _scroll.hasClients ? _scroll.offset : 0,
    );
  }

  @override
  void dispose() {
    _mask?.dispose();
    for (final ui.Image image in _retiredMasks) {
      image.dispose();
    }
    _scroll.dispose();
    _offset.dispose();
    _pointerDown.dispose();
    super.dispose();
  }

  void _pointer(int delta) {
    _pointers = (_pointers + delta).clamp(0, 10);
    _pointerDown.value = _pointers > 0;
  }

  /// The cached ramp image for [extent], drawn once and reused.
  ui.Image? _maskFor(double extent) {
    if (_mask != null && (extent - _maskExtent).abs() < 1e-4) return _mask;
    try {
      final ui.Image fresh = buildRampMaskImage(extent: extent);
      if (_mask != null) _retiredMasks.add(_mask!);
      _mask = fresh;
      _maskExtent = extent;
    } catch (e) {
      debugPrint('toImageSync unavailable, falling back to directional: $e');
      _mask = null;
    }
    return _mask;
  }

  void _noteMount() {
    _mounts++;
    _mountPending = true;
  }

  Widget _blur(BuildContext context, double extent, double ramp, Widget list) {
    final double sigma = deviceSigma(context, kBlurLogicalSigma) * ramp;
    final bool active = _pointerDown.value || _offset.value > 0.5;

    if (_pattern == _Pattern.naive) {
      if (active && !_wasActive) _noteMount();
      _wasActive = active;
      if (!active) return list;
    }

    if (_mountPending) {
      // Time the rest of this frame on the UI thread: the wrapper mounts and
      // builds its map during the build that follows this builder.
      _mountWatch
        ..reset()
        ..start();
      _mountPending = false;
      SchedulerBinding.instance.addPostFrameCallback((_) {
        _lastMountFrameMs = _mountWatch.elapsedMicroseconds / 1000;
        _mountWatch.stop();
      });
    }

    final ui.Image? mask = _pattern == _Pattern.fixed ? _maskFor(extent) : null;
    return Inspire.childBlur(
      config: mask != null
          ? InspireBlurConfig.customMask(maskImage: mask, sigma: sigma)
          : InspireBlurConfig.topToBottom(sigma: sigma, extent: extent),
      mode: InspireBlurMode.animatedSampler,
      child: list,
    );
  }

  @override
  Widget build(BuildContext context) {
    final Widget list = _AlbumTrackList(key: _listKey, controller: _scroll);
    return ScenarioScaffold(
      title: 'S4 · First-touch stall (stock)',
      info: _info,
      counters: <HudCounter>[
        HudCounter.count('blur mounts (naive)', () => _mounts),
        HudCounter.text(
          'last mount frame (app-timed UI ms)',
          () => _lastMountFrameMs.toStringAsFixed(1),
        ),
      ],
      onReset: () {
        _mounts = 0;
        _lastMountFrameMs = 0;
      },
      controls: ControlsRow(
        children: <Widget>[
          SegmentChoice<_Pattern>(
            label: 'Blur wrapper',
            value: _pattern,
            options: const <_Pattern, String>{
              _Pattern.naive: 'naive',
              _Pattern.mounted: 'mounted',
              _Pattern.fixed: 'fixed',
            },
            onChanged: (_Pattern v) => setState(() {
              _pattern = v;
              _wasActive = false;
            }),
          ),
          Text(
            switch (_pattern) {
              _Pattern.naive => 'mounted only while touched or scrolled',
              _Pattern.mounted => 'always mounted at sigma 0',
              _Pattern.fixed => 'always mounted + cached customMask image',
            },
            style: Theme.of(context).textTheme.labelSmall,
          ),
        ],
      ),
      body: Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: (_) => _pointer(1),
        onPointerUp: (_) => _pointer(-1),
        onPointerCancel: (_) => _pointer(-1),
        child: MusicFrame(
          title: 'Album',
          leading: const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: Icon(Icons.arrow_back),
          ),
          body: LayoutBuilder(
            builder: (BuildContext context, BoxConstraints box) {
              final double extent = zoneExtent(kZoneHeight, box.maxHeight);
              return ListenableBuilder(
                listenable: Listenable.merge(<Listenable>[_offset, _pointerDown]),
                builder: (BuildContext context, Widget? _) {
                  final double ramp =
                      (_offset.value / kScrollRampDistance).clamp(0.0, 1.0);
                  return _blur(context, extent, ramp, list);
                },
              );
            },
          ),
        ),
      ),
    );
  }
}

/// An album page: big cover art and title, then the track list.
class _AlbumTrackList extends StatelessWidget {
  const _AlbumTrackList({super.key, required this.controller});

  final ScrollController controller;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Song album = songAt(12);
    return ListView.builder(
      controller: controller,
      padding: const EdgeInsets.only(top: 56, bottom: 24),
      itemCount: 41,
      itemBuilder: (BuildContext context, int i) {
        if (i > 0) {
          return SongTile(
            song: songAt(i + 20),
            trailing: Text(
              songAt(i + 20).durationLabel,
              style: theme.textTheme.bodySmall,
            ),
          );
        }
        return Padding(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
          child: Column(
            children: <Widget>[
              CoverArt(seed: album.id + 100, size: 220, radius: 16),
              const SizedBox(height: 16),
              Text(album.album, style: theme.textTheme.headlineSmall),
              Text(
                '${album.artist} · 2019 · 40 songs',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: () {},
                icon: const Icon(Icons.play_arrow),
                label: const Text('Play'),
              ),
            ],
          ),
        );
      },
    );
  }
}
