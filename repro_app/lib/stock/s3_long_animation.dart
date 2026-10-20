import 'dart:async';

import 'package:flutter/material.dart';

import '../common/blur_variant.dart';
import '../common/constants.dart';
import '../common/controls.dart';
import '../common/dissolve_row.dart';
import '../common/music_chrome.dart';
import '../common/music_data.dart';
import '../common/nested_blur_body.dart';
import '../common/scenario_scaffold.dart';
import '../hud/hud_counter.dart';

/// The row the buttons dissolve: third from the top, below the header zone.
const int _targetPosition = 2;
const int _songCount = 80;

ScenarioInfo _info(bool hasBand) => ScenarioInfo(
      finger:
          'Swipe a song sideways: it breaks into particles over 1.25 s, then '
          'is removed. Or press "Play once" / "Play 20 in a row", and "Fling '
          'list" while it plays. Compare Animation "rebuild" with "paint '
          'only"${hasBand ? ', and the stock blur with the band blur' : ''}. '
          '"Restore songs" refills the list.',
      watch:
          'A long animation sits under both blur layers. Every dirty frame '
          'makes new textures per layer and the GPU reclaims them late, so '
          'graphics memory climbs while Dart RSS stays flat. Use the Xcode '
          'memory gauge or `adb shell dumpsys meminfo`, not the HUD RSS.'
          '${hasBand ? '\nIn debug builds the HUD counters show band productions and window skips.' : ''}',
      saw: 'This crashed the app on iPhone (graphics memory, jetsam). On a '
          'Nothing Phone (2) (Android) it still feels laggy even with the '
          'band variant.',
      warning: 'On stock this can kill the app. Watch graphics memory, not '
          'RSS.',
    );

/// S3: a playlist where removing a song plays a particle dissolve under the
/// blurs.
class LongAnimationScreen extends StatefulWidget {
  const LongAnimationScreen({
    super.key,
    required this.variants,
    this.counters = const <HudCounter>[],
  });

  final List<BlurVariant> variants;
  final List<HudCounter> counters;

  @override
  State<LongAnimationScreen> createState() => _LongAnimationScreenState();
}

class _LongAnimationScreenState extends State<LongAnimationScreen> {
  final ScrollController _scroll = ScrollController();
  final GlobalKey _listKey = GlobalKey();
  final Map<int, GlobalKey<DissolveSongRowState>> _rowKeys =
      <int, GlobalKey<DissolveSongRowState>>{};

  List<int> _ids = List<int>.generate(_songCount, (int i) => i);
  int _variant = 0;
  DissolveDrive _drive = DissolveDrive.rebuild;
  bool _footer = true;
  bool _playingRun = false;
  int _removed = 0;

  @override
  void dispose() {
    _playingRun = false;
    _scroll.dispose();
    super.dispose();
  }

  GlobalKey<DissolveSongRowState> _keyFor(int id) =>
      _rowKeys.putIfAbsent(id, GlobalKey<DissolveSongRowState>.new);

  void _remove(int id) {
    if (!mounted) return;
    setState(() {
      _ids = List<int>.of(_ids)..remove(id);
      _rowKeys.remove(id);
      _removed++;
    });
  }

  Future<void> _dissolveTarget() async {
    if (_ids.length <= _targetPosition) return;
    await _rowKeys[_ids[_targetPosition]]?.currentState?.startDissolve();
  }

  Future<void> _playRun(int times) async {
    if (_playingRun) {
      setState(() => _playingRun = false);
      return;
    }
    setState(() => _playingRun = true);
    for (int i = 0; i < times && _playingRun && mounted; i++) {
      await _dissolveTarget();
      await Future<void>.delayed(const Duration(milliseconds: 150));
    }
    if (mounted) setState(() => _playingRun = false);
  }

  void _fling() {
    if (!_scroll.hasClients) return;
    final double max = _scroll.position.maxScrollExtent;
    final bool down = _scroll.offset < max / 2;
    unawaited(
      _scroll.animateTo(
        down ? (_scroll.offset + 5000).clamp(0.0, max) : 0.0,
        duration: const Duration(milliseconds: 1400),
        curve: Curves.easeOutCubic,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ScenarioScaffold(
      title: 'S3 · Long animation under the blur',
      info: _info(widget.variants.length > 1),
      counters: <HudCounter>[
        HudCounter.count('songs removed', () => _removed),
        ...widget.counters,
      ],
      onReset: () => _removed = 0,
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
          SegmentChoice<DissolveDrive>(
            label: 'Animation',
            value: _drive,
            options: const <DissolveDrive, String>{
              DissolveDrive.rebuild: 'rebuild',
              DissolveDrive.paintOnly: 'paint only',
            },
            onChanged: (DissolveDrive v) => setState(() => _drive = v),
          ),
          ToggleChip(
            label: 'Footer blur',
            value: _footer,
            onChanged: (bool v) => setState(() => _footer = v),
          ),
          ActionButton(label: 'Play once', onPressed: _dissolveTarget),
          ActionButton(
            label: _playingRun ? 'Stop run' : 'Play 20 in a row',
            onPressed: () => _playRun(20),
          ),
          ActionButton(label: 'Fling list', onPressed: _fling),
          ActionButton(
            label: 'Restore songs',
            onPressed: () => setState(() {
              _ids = List<int>.generate(_songCount, (int i) => i);
              _rowKeys.clear();
            }),
          ),
        ],
      ),
      body: MusicFrame(
        title: 'Road trip',
        bottom: const _PlaylistSubtitle(),
        bottomBars: _footer,
        body: NestedBlurBody(
          variant: widget.variants[_variant],
          footer: _footer,
          list: ListView.builder(
            key: _listKey,
            controller: _scroll,
            padding: EdgeInsets.only(
              top: kHeaderHeight,
              bottom: (_footer ? kBottomBarsHeight : 0) + 16,
            ),
            itemCount: _ids.length,
            itemBuilder: (BuildContext context, int i) {
              final int id = _ids[i];
              return DissolveSongRow(
                key: _keyFor(id),
                song: songAt(id),
                drive: _drive,
                onRemoved: () => _remove(id),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _PlaylistSubtitle extends StatelessWidget {
  const _PlaylistSubtitle();

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(
          'Playlist · swipe a song to remove it',
          style: theme.textTheme.bodyMedium
              ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
      ),
    );
  }
}
