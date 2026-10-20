import 'dart:async';
import 'dart:io' show ProcessInfo;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'frame_stats.dart';
import 'hud_counter.dart';

/// The wording the brief asks the RSS line to carry.
const String kRssNote =
    'Dart-visible RSS, GPU textures are NOT included — use the Xcode memory '
    'gauge / Instruments (Allocations + VM Tracker: IOSurface, IOAccelerator) '
    'on iOS, or `adb shell dumpsys meminfo <pkg>` (Graphics and GL mtrack rows) '
    'on Android, for graphics memory.';

/// A small, draggable frame-timing overlay.
///
/// Shows rolling UI-build and raster stats from [collector], the worst single
/// UI frame (one-frame stalls), the process RSS and any scenario [counters].
/// Tap the title to collapse it to one line; drag it out of the way.
class HudOverlay extends StatefulWidget {
  const HudOverlay({
    super.key,
    required this.collector,
    required this.counters,
    required this.onReset,
  });

  final FrameStatsCollector collector;
  final List<HudCounter> counters;

  /// Called after the HUD's own stats are reset, so the scenario can clear
  /// whatever it counts itself.
  final VoidCallback onReset;

  @override
  State<HudOverlay> createState() => _HudOverlayState();
}

class _HudOverlayState extends State<HudOverlay> {
  Timer? _timer;
  final Map<int, num> _baseline = <int, num>{};
  DateTime _resetAt = DateTime.now();
  Offset _drag = Offset.zero;
  bool _compact = true; // one line until tapped, so it does not cover the screen

  @override
  void initState() {
    super.initState();
    _captureBaseline();
    // Two trivial frames per second; they are in the stats like any other.
    _timer = Timer.periodic(
      const Duration(milliseconds: 500),
      (_) => setState(() {}),
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _captureBaseline() {
    _resetAt = DateTime.now();
    _baseline.clear();
    for (int i = 0; i < widget.counters.length; i++) {
      final num Function()? read = widget.counters[i].readCount;
      if (read != null) _baseline[i] = read();
    }
  }

  void _reset() {
    widget.collector.reset();
    widget.onReset();
    setState(_captureBaseline);
  }

  void _showRssNote() {
    showDialog<void>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: const Text('About the RSS line'),
        content: const Text(kRssNote),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  static String _ms(double v) => v.toStringAsFixed(1);
  static String _pct(double v) => '${(v * 100).toStringAsFixed(0)}%';

  String _phaseLine(String name, PhaseStats p) =>
      '$name mean ${_ms(p.meanMs)} p95 ${_ms(p.p95Ms)} '
      '>16.7: ${_pct(p.over60Fraction)} >8.3: ${_pct(p.over120Fraction)}';

  String _counterLine(int i, HudCounter c) {
    if (c.debugOnly && !kDebugMode) return '${c.label}: n/a (debug build only)';
    final String Function()? text = c.readText;
    if (text != null) return '${c.label}: ${text()}';
    final num now = c.readCount!();
    final num delta = now - (_baseline[i] ?? 0);
    final double seconds =
        DateTime.now().difference(_resetAt).inMilliseconds / 1000;
    final String rate = seconds > 0.5
        ? ' (${(delta / seconds).toStringAsFixed(1)}/s)'
        : '';
    return '${c.label}: ${_fmt(now)}  Δ ${_fmt(delta)}$rate';
  }

  static String _fmt(num v) =>
      v is int || v == v.roundToDouble() ? '${v.round()}' : v.toStringAsFixed(2);

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final FrameStatsSnapshot s = widget.collector.snapshot();
    // dart:io's ProcessInfo throws on web; report 0 there.
    final double rssMb = kIsWeb ? 0 : ProcessInfo.currentRss / (1024 * 1024);
    final double rssPeakMb = kIsWeb ? 0 : ProcessInfo.maxRss / (1024 * 1024);

    final TextStyle mono = TextStyle(
      fontFamily: 'monospace',
      fontFamilyFallback: const <String>['Menlo', 'Courier New'],
      fontSize: 10,
      height: 1.25,
      color: scheme.onInverseSurface,
      fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
    );

    final List<String> lines = <String>[
      _phaseLine('UI    ', s.ui),
      _phaseLine('Raster', s.raster),
      'worst UI frame: ${_ms(s.worstUiLastSecondMs)} ms last 1 s, '
          '${_ms(s.worstUiSinceResetMs)} ms since reset',
      'frames in window: ${s.frames}   (ms; >16.7 / >8.3 = % of frames)',
      for (int i = 0; i < widget.counters.length; i++)
        _counterLine(i, widget.counters[i]),
    ];
    final bool hasDebugOnly = widget.counters.any((HudCounter c) => c.debugOnly);

    final Widget header = Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Flexible(
          child: GestureDetector(
            onTap: () => setState(() => _compact = !_compact),
            child: Text(
              _compact
                  ? 'HUD ▸ UI p95 ${_ms(s.ui.p95Ms)} '
                      'raster p95 ${_ms(s.raster.p95Ms)} '
                      'worst ${_ms(s.worstUiLastSecondMs)}'
                  : 'HUD ▾ tap: collapse, drag: move',
              style: mono.copyWith(fontWeight: FontWeight.bold),
            ),
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          height: 26,
          child: TextButton(
            onPressed: _reset,
            style: TextButton.styleFrom(
              minimumSize: Size.zero,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              foregroundColor: scheme.inversePrimary,
              textStyle: mono,
            ),
            child: const Text('Reset stats'),
          ),
        ),
      ],
    );

    final Widget rssLine = Text.rich(
      TextSpan(
        children: <InlineSpan>[
          TextSpan(
            text: 'RSS* ${rssMb.toStringAsFixed(0)} MB '
                '(peak ${rssPeakMb.toStringAsFixed(0)}), '
                '- Dart-visible RSS, GPU textures are NOT included ',
          ),
          WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            child: GestureDetector(
              onTap: _showRssNote,
              child: Padding(
                padding: const EdgeInsets.all(4),
                child: Icon(
                  Icons.info_outline,
                  size: 14,
                  color: scheme.onInverseSurface,
                ),
              ),
            ),
          ),
        ],
      ),
    );

    return RepaintBoundary(
      child: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints area) {
          // Text wraps at the area's width; a HUD taller than the area (many
          // counters in a short area) scales down instead of overflowing.
          final double maxWidth = area.maxWidth - 16 - 16;
          return Align(
            alignment: Alignment.bottomLeft,
            child: Transform.translate(
              offset: _drag,
              child: GestureDetector(
                onPanUpdate: (DragUpdateDetails d) =>
                    setState(() => _drag += d.delta),
                child: Container(
                  margin: const EdgeInsets.all(8),
                  padding: const EdgeInsets.fromLTRB(10, 6, 6, 6),
                  constraints: BoxConstraints(maxHeight: area.maxHeight - 16),
                  decoration: BoxDecoration(
                    color: scheme.inverseSurface.withValues(alpha: 0.88),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.topLeft,
                    child: ConstrainedBox(
                      constraints: BoxConstraints(maxWidth: maxWidth),
                      child: DefaultTextStyle(
                        style: mono,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            header,
                            if (!_compact) ...<Widget>[
                              for (final String line in lines) Text(line),
                              rssLine,
                              if (hasDebugOnly && !kDebugMode)
                                const Text(
                                  'package counters only move in debug builds',
                                ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
