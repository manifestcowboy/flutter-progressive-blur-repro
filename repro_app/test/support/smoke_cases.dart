import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inspire_blur_repro/app/repro_app.dart';
import 'package:inspire_blur_repro/app/scenario.dart';
import 'package:inspire_blur_repro/common/scenario_scaffold.dart';
import 'package:inspire_blur_repro/stock/scenarios.dart';

/// Pumps a few frames. `pumpAndSettle` would never return: several scenarios
/// animate forever.
Future<void> pumpFrames(WidgetTester tester, {int frames = 6}) async {
  for (int i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// A 402 x 874 pt phone at 3x.
void usePhoneSurface(WidgetTester tester) {
  tester.view.devicePixelRatio = 3;
  tester.view.physicalSize = const Size(1206, 2622);
  addTearDown(tester.view.reset);
}

Scenario scenarioById(List<Scenario> scenarios, String id) =>
    scenarios.firstWhere((Scenario s) => s.id == id);

/// Drags the scenario's list by [dy] from a point near the top of the area,
/// away from the HUD.
Future<void> scrollList(WidgetTester tester, double dy) async {
  final Offset start =
      tester.getTopLeft(find.byType(ListView).last) + const Offset(200, 160);
  await tester.dragFrom(start, Offset(0, dy));
}

Future<void> mount(WidgetTester tester, Scenario scenario) async {
  usePhoneSurface(tester);
  // As a user would: collapse the info card to give the scenario room.
  infoCardExpanded.value = false;
  await tester.pumpWidget(
    MaterialApp(home: Builder(builder: scenario.builder)),
  );
  await pumpFrames(tester);
}

/// Leaves the tree so tickers, timers and listeners are disposed, and lets
/// anything still scheduled run out.
Future<void> unmount(WidgetTester tester) async {
  expect(tester.takeException(), isNull);
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(seconds: 2));
}

/// Home lists every scenario, and every scenario screen builds and animates
/// for a few frames without throwing.
void defineSmokeTests(String name, List<Scenario> Function() scenarios) {
  group(name, () {
    testWidgets('home lists every scenario', (WidgetTester tester) async {
      usePhoneSurface(tester);
      final List<Scenario> all = scenarios();
      await tester.pumpWidget(ReproApp(scenarios: all, entrypoint: name));
      await tester.pump();
      expect(find.text('Blur repro'), findsWidgets);
      expect(find.text('S1'), findsOneWidget);
      expect(find.text(all.first.title), findsOneWidget);
    });

    for (final Scenario scenario in scenarios()) {
      testWidgets('${scenario.id} ${scenario.title} pumps', (
        WidgetTester tester,
      ) async {
        await mount(tester, scenario);
        await unmount(tester);
      });
    }
  });
}

/// Finger-level behaviour of the scenarios that exist in pristine 0.4.1.
void defineStockInteractionTests() {
  group('stock interactions', () {
    testWidgets('S1 scrolls and toggles the blur', (WidgetTester tester) async {
      await mount(tester, scenarioById(buildStockScenarios(), 'S1'));
      await scrollList(tester, -300);
      await pumpFrames(tester);
      await tester.tap(find.text('Blur on'));
      await pumpFrames(tester);
      await scrollList(tester, 300);
      await pumpFrames(tester);
      await unmount(tester);
    });

    testWidgets('S3 dissolves a row, then removes it', (
      WidgetTester tester,
    ) async {
      await mount(tester, scenarioById(buildStockScenarios(), 'S3'));
      // The third song (index 2) is the target.
      expect(find.text('Slow River'), findsOneWidget);
      await tester.tap(find.text('Play once'));
      // 1.25 s of dissolve and 0.18 s of collapse; the first pump only starts
      // the ticker.
      await pumpFrames(tester, frames: 18);
      expect(find.text('Slow River'), findsNothing);

      // Paint-only drive, a fling, and the restore.
      await tester.tap(find.text('paint only'));
      await pumpFrames(tester, frames: 3);
      await tester.tap(find.text('Play once'));
      await pumpFrames(tester, frames: 18);
      await tester.tap(find.text('Fling list'));
      await pumpFrames(tester, frames: 16);
      await tester.tap(find.text('Fling list'));
      await pumpFrames(tester, frames: 16);
      await tester.tap(find.text('Restore songs'));
      await pumpFrames(tester, frames: 3);
      expect(find.text('Slow River'), findsOneWidget);
      await unmount(tester);
    });

    testWidgets('S3 swipe removes a song', (WidgetTester tester) async {
      await mount(tester, scenarioById(buildStockScenarios(), 'S3'));
      expect(find.text('Slow River'), findsOneWidget);
      await tester.drag(find.text('Slow River'), const Offset(200, 0));
      await pumpFrames(tester, frames: 18);
      expect(find.text('Slow River'), findsNothing);
      await unmount(tester);
    });
  });
}
