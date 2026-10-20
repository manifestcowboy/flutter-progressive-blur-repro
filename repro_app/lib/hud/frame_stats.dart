import 'dart:collection';
import 'dart:math' as math;
import 'dart:ui' show FramePhase;
import 'package:flutter/scheduler.dart';

/// One frame budget at 60 Hz, in milliseconds.
const double kBudget60Hz = 1000 / 60;

/// One frame budget at 120 Hz, in milliseconds.
const double kBudget120Hz = 1000 / 120;

/// Summary of one phase (UI build or raster) over the rolling window.
class PhaseStats {
  const PhaseStats({
    required this.meanMs,
    required this.p95Ms,
    required this.over60Fraction,
    required this.over120Fraction,
    required this.maxMs,
  });

  static const PhaseStats empty = PhaseStats(
    meanMs: 0,
    p95Ms: 0,
    over60Fraction: 0,
    over120Fraction: 0,
    maxMs: 0,
  );

  final double meanMs;
  final double p95Ms;

  /// Fraction (0..1) of frames slower than [kBudget60Hz].
  final double over60Fraction;

  /// Fraction (0..1) of frames slower than [kBudget120Hz].
  final double over120Fraction;
  final double maxMs;
}

/// Everything the HUD shows about frame timing.
class FrameStatsSnapshot {
  const FrameStatsSnapshot({
    required this.frames,
    required this.ui,
    required this.raster,
    required this.worstUiLastSecondMs,
    required this.worstUiSinceResetMs,
  });

  static const FrameStatsSnapshot empty = FrameStatsSnapshot(
    frames: 0,
    ui: PhaseStats.empty,
    raster: PhaseStats.empty,
    worstUiLastSecondMs: 0,
    worstUiSinceResetMs: 0,
  );

  /// Frames currently in the rolling window.
  final int frames;

  /// `FrameTiming.buildDuration`: the UI thread (build + layout + paint).
  final PhaseStats ui;

  /// `FrameTiming.rasterDuration`: the raster thread.
  final PhaseStats raster;

  /// Slowest UI-thread frame that finished rasterising within the last second.
  /// A one-frame stall (S4) is visible here for a second, then scrolls out.
  final double worstUiLastSecondMs;

  /// Slowest UI-thread frame since the last reset.
  final double worstUiSinceResetMs;
}

class _Sample {
  const _Sample(this.uiMs, this.rasterMs, this.finishedMicros);

  final double uiMs;
  final double rasterMs;

  /// Wall-clock time (microseconds since epoch) the raster phase finished.
  final int finishedMicros;
}

/// Collects `FrameTiming`s into a rolling window.
///
/// Timings are reported by the engine in batches (about 100 ms in profile
/// mode, up to 1 s in release), so the numbers trail the screen slightly.
class FrameStatsCollector {
  FrameStatsCollector({this.capacity = 600}) {
    SchedulerBinding.instance.addTimingsCallback(_onTimings);
  }

  /// Frames kept: about 10 s at 60 Hz, 5 s at 120 Hz.
  final int capacity;

  final ListQueue<_Sample> _window = ListQueue<_Sample>();
  double _worstUiSinceReset = 0;

  void dispose() {
    SchedulerBinding.instance.removeTimingsCallback(_onTimings);
  }

  /// Forgets everything collected so far.
  void reset() {
    _window.clear();
    _worstUiSinceReset = 0;
  }

  void _onTimings(List<FrameTiming> timings) {
    for (final FrameTiming t in timings) {
      final double uiMs = t.buildDuration.inMicroseconds / 1000;
      _window.addLast(
        _Sample(
          uiMs,
          t.rasterDuration.inMicroseconds / 1000,
          t.timestampInMicroseconds(FramePhase.rasterFinishWallTime),
        ),
      );
      _worstUiSinceReset = math.max(_worstUiSinceReset, uiMs);
      if (_window.length > capacity) _window.removeFirst();
    }
  }

  FrameStatsSnapshot snapshot() {
    if (_window.isEmpty) return FrameStatsSnapshot.empty;
    final int nowMicros = DateTime.now().microsecondsSinceEpoch;
    double worstLastSecond = 0;
    for (final _Sample s in _window) {
      if (nowMicros - s.finishedMicros <= 1000000) {
        worstLastSecond = math.max(worstLastSecond, s.uiMs);
      }
    }
    return FrameStatsSnapshot(
      frames: _window.length,
      ui: _phase(_window.map((_Sample s) => s.uiMs).toList()),
      raster: _phase(_window.map((_Sample s) => s.rasterMs).toList()),
      worstUiLastSecondMs: worstLastSecond,
      worstUiSinceResetMs: _worstUiSinceReset,
    );
  }

  static PhaseStats _phase(List<double> ms) {
    final List<double> sorted = List<double>.of(ms)..sort();
    final int n = sorted.length;
    final double mean = sorted.fold<double>(0, (double a, double b) => a + b) / n;
    final double p95 = sorted[math.min(n - 1, (n * 0.95).floor())];
    return PhaseStats(
      meanMs: mean,
      p95Ms: p95,
      over60Fraction: sorted.where((double v) => v > kBudget60Hz).length / n,
      over120Fraction: sorted.where((double v) => v > kBudget120Hz).length / n,
      maxMs: sorted.last,
    );
  }
}
