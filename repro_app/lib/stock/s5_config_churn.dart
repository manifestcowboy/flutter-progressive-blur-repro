import 'dart:collection';
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
      '1. Leave "Config" on "new mask image per build". 2. Press and hold a '
      'song\'s drag handle (the three lines on the right), then drag it up '
      'and down the playlist for 10 to 20 seconds, slowly across many rows. '
      '3. Let go. 4. Repeat with "new directional per build", then with '
      '"memoized" for the safe comparison.',
  watch:
      'While the handle is held, the screen rebuilds on every frame (a '
      'Ticker, standing in for a drag offset in state). In the two churn '
      'variants each build hands Inspire.childBlur a config that is not == '
      'the previous one, so InspireBlurWrapper.didUpdateWidget regenerates '
      'its distribution map every frame. A new customMask image costs a '
      'texture and a setState per frame; a new directional ramp costs the '
      'synchronous size x size Dart loop and a 1.6 MB RGBA image per frame '
      '(reading the source: the package does not dispose the '
      'ImmutableBuffer, ImageDescriptor and Codec it creates for that map, '
      'so native memory trails the Dart GC). Watch the HUD counters, UI p95, '
      'and the platform graphics-memory gauge: RSS will not show GPU memory.',
  saw: 'On an iPhone 17 Pro release build this kind of churn got the app '
      'SIGKILLed with no crash log while dragging to reorder.',
  warning: 'May kill the app. Keep the Xcode memory gauge open on iOS, or run '
      '`adb shell dumpsys meminfo dev.repro.inspire_blur_repro` on Android.',
);

enum _Churn { maskImage, directional, memoized }

/// S5: a playlist edit screen where the config handed to the blur is rebuilt
/// every frame while a row is being dragged.
class ConfigChurnScreen extends StatefulWidget {
  const ConfigChurnScreen({super.key});

  @override
  State<ConfigChurnScreen> createState() => _ConfigChurnScreenState();
}

class _ConfigChurnScreenState extends State<ConfigChurnScreen>
    with SingleTickerProviderStateMixin {
  final ScrollController _scroll = ScrollController();
  late final Ticker _ticker = createTicker((_) => setState(() {}));
  final List<int> _order = List<int>.generate(60, (int i) => i);

  _Churn _churn = _Churn.maskImage;
  int _configBuilds = 0;
  int _masksCreated = 0;
  int _masksDisposed = 0;

  /// Recent masks. The wrapper holds only the latest, but it adopts it one
  /// microtask late, so retire with a margin.
  final Queue<ui.Image> _recent = Queue<ui.Image>();
  ui.Image? _memoMask;
  InspireBlurConfig? _memoConfig;
  double _memoExtent = -1;

  @override
  void dispose() {
    _ticker.dispose();
    _scroll.dispose();
    for (final ui.Image image in _recent) {
      image.dispose();
    }
    _memoMask?.dispose();
    super.dispose();
  }

  ui.Image _newMask(double extent) {
    _masksCreated++;
    final ui.Image image = buildRampMaskImage(extent: extent);
    _recent.addLast(image);
    while (_recent.length > 8) {
      _recent.removeFirst().dispose();
      _masksDisposed++;
    }
    return image;
  }

  InspireBlurConfig _config(BuildContext context, double extent) {
    _configBuilds++;
    final double sigma = deviceSigma(context, kBlurLogicalSigma);
    switch (_churn) {
      case _Churn.maskImage:
        return InspireBlurConfig.customMask(
          maskImage: _newMask(extent),
          sigma: sigma,
        );
      case _Churn.directional:
        // A hair's difference in extent: never == the previous build's ramp.
        return InspireBlurConfig.topToBottom(
          sigma: sigma,
          extent: extent * (1 + (_configBuilds % 100000) * 1e-7),
        );
      case _Churn.memoized:
        if (_memoConfig == null || (extent - _memoExtent).abs() > 1e-4) {
          _memoMask?.dispose();
          _memoMask = buildRampMaskImage(extent: extent);
          _memoExtent = extent;
          _memoConfig =
              InspireBlurConfig.customMask(maskImage: _memoMask!, sigma: sigma);
        }
        return _memoConfig!;
    }
  }

  @override
  Widget build(BuildContext context) {
    return ScenarioScaffold(
      title: 'S5 · Reorder drag: new config per frame (stock)',
      info: _info,
      counters: <HudCounter>[
        HudCounter.count('config builds', () => _configBuilds),
        HudCounter.count('mask images created', () => _masksCreated),
        HudCounter.count('mask images disposed', () => _masksDisposed),
        HudCounter.text('per-frame rebuild', () => _ticker.isActive ? 'ON (dragging)' : 'off'),
      ],
      onReset: () {
        _configBuilds = 0;
        _masksCreated = 0;
        _masksDisposed = 0;
      },
      controls: ControlsRow(
        children: <Widget>[
          SegmentChoice<_Churn>(
            label: 'Config',
            value: _churn,
            options: const <_Churn, String>{
              _Churn.maskImage: 'new mask image',
              _Churn.directional: 'new directional',
              _Churn.memoized: 'memoized',
            },
            onChanged: (_Churn v) => setState(() => _churn = v),
          ),
        ],
      ),
      body: MusicFrame(
        title: 'Edit playlist',
        leading: const Padding(
          padding: EdgeInsets.symmetric(horizontal: 16),
          child: Icon(Icons.close),
        ),
        actions: <Widget>[
          TextButton(onPressed: () {}, child: const Text('Done')),
          const SizedBox(width: 8),
        ],
        body: LayoutBuilder(
          builder: (BuildContext context, BoxConstraints box) {
            final double extent = zoneExtent(kZoneHeight, box.maxHeight);
            return Inspire.childBlur(
              config: _config(context, extent),
              mode: InspireBlurMode.animatedSampler,
              child: ReorderableListView.builder(
                scrollController: _scroll,
                padding: const EdgeInsets.only(top: 56, bottom: 24),
                buildDefaultDragHandles: false,
                itemCount: _order.length,
                onReorderStart: (_) {
                  if (!_ticker.isActive) _ticker.start();
                },
                onReorderEnd: (_) {
                  if (_ticker.isActive) _ticker.stop();
                  setState(() {});
                },
                onReorderItem: (int from, int to) => setState(() {
                  _order.insert(to, _order.removeAt(from));
                }),
                itemBuilder: (BuildContext context, int i) => Material(
                  key: ValueKey<int>(_order[i]),
                  type: MaterialType.transparency,
                  child: SongTile(
                    song: songAt(_order[i]),
                    trailing: ReorderableDragStartListener(
                      index: i,
                      child: const Padding(
                        padding: EdgeInsets.all(12),
                        child: Icon(Icons.drag_handle),
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
