import 'package:flutter/widgets.dart';

/// A mutable count that a widget bumps from `build`.
class Counter {
  int value = 0;

  void reset() => value = 0;
}

/// Counts how many times its own `build` runs.
///
/// Place it around a widget to see whether that widget's element is rebuilt.
/// The count is read by the HUD on its timer; it does not notify.
class BuildCounter extends StatelessWidget {
  const BuildCounter({super.key, required this.counter, required this.child});

  final Counter counter;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    counter.value++;
    return child;
  }
}
