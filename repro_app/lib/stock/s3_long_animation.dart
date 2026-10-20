import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../common/blur_variant.dart';
import '../common/constants.dart';
import '../common/controls.dart';
import '../common/dissolve_row.dart';
import '../common/load.dart';
import '../common/music_chrome.dart';
import '../common/music_data.dart';
import '../common/music_widgets.dart';
import '../common/nested_blur_body.dart';
import '../common/real_app_content.dart';
import '../common/scenario_scaffold.dart';
import '../hud/hud_counter.dart';

/// The buttons dissolve the first song row whose top edge is at least this far
/// down the list: the header zone plus one row, which is the third row from the
/// top when the list is at rest and the equivalent slot wherever it has been
/// scrolled to.
const double _targetSlotTop = kZoneHeight + SongTile.height;
const int _songCount = 160;

ScenarioInfo _info(bool hasBand) => ScenarioInfo(
      finger:
          'Swipe a song sideways: it breaks into particles over 1.25 s, then '
          'is removed. Or press "Play once" / "Play 20 in a row" (they take '
          'the third song from the top of what is on screen), and "Fling list" '
          'while it plays. Compare Animation "rebuild" with "paint '
          'only"${hasBand ? ', and the stock blur with the band blur' : ''}. '
          '"Restore songs" refills the list. Load "Real-app" (default) adds '
          'an ambient background that repaints every frame, glass cards and '
          'large covers under the blur.',
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
  int _runToken = 0;
  int _removed = 0;

  @override
  void dispose() {
    _runToken++; // ends a run in progress
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

  /// The song row to dissolve: the first built one whose top edge is at or
  /// below [_targetSlotTop], measured from the top of the list, so it is always
  /// one the viewer can see, wherever the list has been scrolled (flung) to.
  DissolveSongRowState? _targetRow() {
    final RenderObject? list = _listKey.currentContext?.findRenderObject();
    if (list is! RenderBox || !list.hasSize) return null;
    DissolveSongRowState? best;
    double bestTop = double.infinity;
    for (final int id in _ids) {
      final DissolveSongRowState? row = _rowKeys[id]?.currentState;
      final RenderObject? box = row?.context.findRenderObject();
      if (row == null || box is! RenderBox || !box.attached || !box.hasSize) {
        continue;
      }
      final double top = box.localToGlobal(Offset.zero, ancestor: list).dy;
      if (top >= _targetSlotTop && top < bestTop && top < list.size.height) {
        best = row;
        bestTop = top;
      }
    }
    return best;
  }

  /// Dissolves [_targetRow], completing when it has been removed. False when
  /// there was no row to dissolve (nothing built there right now).
  Future<bool> _dissolveTarget() async {
    final DissolveSongRowState? row = _targetRow();
    if (row == null) return false;
    await row.startDissolve();
    return true;
  }

  /// Nudges the list down to bring more songs into view; nothing at the end.
  void _scrollOn() {
    if (!_scroll.hasClients) return;
    final ScrollPosition position = _scroll.position;
    if (position.pixels >= position.maxScrollExtent - 1) return;
    unawaited(
      position.animateTo(
        math.min(position.maxScrollExtent, position.pixels + 300),
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      ),
    );
  }

  /// Dissolves [times] songs one after another, or stops the run in progress.
  Future<void> _playRun(int times) async {
    if (_playingRun) {
      _runToken++;
      setState(() => _playingRun = false);
      return;
    }
    final int token = ++_runToken;
    bool live() => mounted && token == _runToken;
    setState(() => _playingRun = true);
    int played = 0;
    int misses = 0;
    while (played < times && misses < 40 && live()) {
      if (await _dissolveTarget()) {
        played++;
        misses = 0;
      } else {
        // No song is where it can be dissolved: not built yet, or only cards
        // and covers are on screen. Scroll on and look again shortly.
        misses++;
        _scrollOn();
      }
      if (!live()) return;
      await Future<void>.delayed(const Duration(milliseconds: 150));
    }
    if (live()) setState(() => _playingRun = false);
  }

  /// Down this far, then back to the top on the next press.
  static const double _flingDistance = 5000;

  void _fling() {
    if (!_scroll.hasClients) return;
    final double max = _scroll.position.maxScrollExtent;
    final bool down = _scroll.offset < _flingDistance / 2;
    unawaited(
      _scroll.animateTo(
        down ? (_scroll.offset + _flingDistance).clamp(0.0, max) : 0.0,
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
          const LoadChoice(),
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
          list: LoadStage(
            child: ValueListenableBuilder<AppLoad>(
              valueListenable: appLoad,
              builder: (BuildContext context, AppLoad load, Widget? _) =>
                  _playlist(load),
            ),
          ),
        ),
      ),
    );
  }

  /// The song rows, with the "Recently played" row, glass cards and large
  /// covers between them under [AppLoad.realApp]. The decorations hang on the
  /// original song numbers, so removing a song does not move them.
  Widget _playlist(AppLoad load) {
    final List<({int id, RealAppSlot slot})> entries =
        <({int id, RealAppSlot slot})>[];
    if (load == AppLoad.realApp) {
      entries.add((id: -1, slot: RealAppSlot.recentlyPlayed));
      final Set<int> alive = _ids.toSet();
      for (int n = 0; n < _songCount; n++) {
        if (alive.contains(n)) entries.add((id: n, slot: RealAppSlot.song));
        final RealAppSlot? decor = realAppDecorAfterSong(n);
        if (decor != null) entries.add((id: n, slot: decor));
      }
    } else {
      for (final int id in _ids) {
        entries.add((id: id, slot: RealAppSlot.song));
      }
    }
    return ListView.builder(
      key: _listKey,
      controller: _scroll,
      padding: EdgeInsets.only(
        top: kHeaderHeight,
        bottom: (_footer ? kBottomBarsHeight : 0) + 16,
      ),
      itemCount: entries.length,
      itemBuilder: (BuildContext context, int item) {
        final ({int id, RealAppSlot slot}) entry = entries[item];
        if (entry.slot != RealAppSlot.song) {
          // One row of large covers per grid: a taller grid could fill the
          // whole stretch where the buttons look for a song to dissolve.
          return realAppDecor(entry.slot, entry.id + 1, gridRows: 1);
        }
        return DissolveSongRow(
          key: _keyFor(entry.id),
          song: songAt(entry.id),
          drive: _drive,
          onRemoved: () => _remove(entry.id),
        );
      },
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
