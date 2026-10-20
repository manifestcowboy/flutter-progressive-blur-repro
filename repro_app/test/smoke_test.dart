// Needs the PATCHED package in packages/inspire_blur (the default tree). For
// a pristine 0.4.1 checkout run test/stock_smoke_test.dart instead.
import 'package:flutter_test/flutter_test.dart';
import 'package:inspire_blur_repro/app/scenario.dart';
import 'package:inspire_blur_repro/patched/scenarios.dart';
import 'package:inspire_blur_repro/stock/scenarios.dart';

import 'support/smoke_cases.dart';

void main() {
  test('entrypoint scenario lists', () {
    expect(
      buildStockScenarios().map((Scenario s) => s.id),
      <String>['S1', 'S2', 'S3'],
    );
    expect(
      buildAllScenarios().map((Scenario s) => s.id),
      <String>['S1', 'S2', 'S3'],
    );
    expect(
      buildStockScenarios().every((Scenario s) => s.kind == ScenarioKind.stock),
      isTrue,
    );
    expect(
      scenarioById(buildAllScenarios(), 'S2').kind,
      ScenarioKind.stockWithBand,
    );
  });

  defineSmokeTests('main_stock', buildStockScenarios);
  defineSmokeTests('main', buildAllScenarios);
  defineStockInteractionTests();

  group('patched interactions', () {
    testWidgets('S2 and S3 switch to the band sampler', (
      WidgetTester tester,
    ) async {
      for (final String id in <String>['S2', 'S3']) {
        await mount(tester, scenarioById(buildAllScenarios(), id));
        await tester.tap(find.text('Inspire.childBlurBand'));
        await pumpFrames(tester);
        await tester.tap(find.text('Inspire.childBlur'));
        await pumpFrames(tester, frames: 3);
        await unmount(tester);
      }
    });
  });
}
