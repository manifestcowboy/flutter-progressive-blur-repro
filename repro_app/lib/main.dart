import 'package:flutter/material.dart';

import 'app/repro_app.dart';
import 'patched/scenarios.dart';

/// Every scenario S1 to S3, with the patched-only options (the band sampler
/// A/B toggles and debug counters). Needs the patched package in
/// `packages/inspire_blur`; for the original problems on pristine 0.4.1 run
/// `main_stock.dart` instead.
void main() {
  runApp(
    ReproApp(
      entrypoint: 'main.dart (everything, needs the patched package)',
      scenarios: buildAllScenarios(),
    ),
  );
}
