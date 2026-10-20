import 'dart:math' as math;

import 'package:flutter/widgets.dart';

/// Scrolls a controller up and down forever, so a run does not depend on how
/// steadily a finger moves. Touching the list fights it; switch it off first.
class AutoScroller extends ChangeNotifier {
  AutoScroller(this.controller);

  final ScrollController controller;
  bool _running = false;
  bool _disposed = false;

  bool get running => _running;

  void toggle() => _running ? stop() : start();

  void start() {
    if (_running) return;
    _running = true;
    notifyListeners();
    _loop();
  }

  void stop() {
    if (!_running) return;
    _running = false;
    notifyListeners();
  }

  Future<void> _loop() async {
    bool down = true;
    while (_running && !_disposed && controller.hasClients) {
      final double max = controller.position.maxScrollExtent;
      if (max <= 0) break;
      await controller.animateTo(
        down ? math.min(max, 6000.0) : 0.0,
        duration: const Duration(seconds: 5),
        curve: Curves.easeInOut,
      );
      down = !down;
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    if (_running && !_disposed) stop();
  }

  @override
  void dispose() {
    _disposed = true;
    _running = false;
    super.dispose();
  }
}
