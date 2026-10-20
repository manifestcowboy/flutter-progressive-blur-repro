// Runs against pristine inspire_blur 0.4.1 as well as the patched package:
// it only touches `lib/stock`, `lib/common`, `lib/hud` and `lib/app`.
import 'package:inspire_blur_repro/stock/scenarios.dart';

import 'support/smoke_cases.dart';

void main() {
  defineSmokeTests('main_stock', buildStockScenarios);
  defineStockInteractionTests();
}
