import 'package:flutter/material.dart';

import 'app/repro_app.dart';
import 'stock/scenarios.dart';

/// Scenarios S1 to S3 on API that exists in pristine inspire_blur 0.4.1.
///
/// Never import anything under `lib/patched` from here: this file has to
/// compile after `git checkout origin/upstream-0.4.1 -- packages/inspire_blur`.
void main() {
  runApp(
    ReproApp(
      entrypoint: 'main_stock.dart (API of pristine 0.4.1)',
      scenarios: buildStockScenarios(),
    ),
  );
}
