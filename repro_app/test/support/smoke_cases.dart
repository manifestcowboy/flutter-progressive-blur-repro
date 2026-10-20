import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inspire_blur_repro/app/repro_app.dart';
import 'package:inspire_blur_repro/app/scenario.dart';
import 'package:inspire_blur_repro/common/ambient_background.dart';
import 'package:inspire_blur_repro/common/load.dart';
import 'package:inspire_blur_repro/common/real_app_content.dart';
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

/// Mounts [scenario] under [load] (the app's default, Real-app, unless given).
Future<void> mount(
  WidgetTester tester,
  Scenario scenario, {
  AppLoad load = AppLoad.realApp,
}) async {
  usePhoneSurface(tester);
  // As a user would: collapse the info card to give the scenario room.
  infoCardExpanded.value = false;
  appLoad.value = load;
  addTearDown(() => appLoad.value = AppLoad.realApp);
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
      for (final AppLoad load in AppLoad.values) {
        testWidgets('${scenario.id} ${scenario.title} pumps (${load.label})', (
          WidgetTester tester,
        ) async {
          await mount(tester, scenario, load: load);
          await unmount(tester);
        });
      }
    }
  });
}

/// Opens the HUD (it starts as one line) so its counters can be read.
Future<void> openHud(WidgetTester tester) async {
  await tester.tap(find.textContaining('HUD'));
  await pumpFrames(tester, frames: 6);
}

/// Finger-level behaviour of the scenarios that exist in pristine 0.4.1.
void defineStockInteractionTests() {
  group('stock interactions', () {
    for (final AppLoad load in AppLoad.values) {
      testWidgets('S1 scrolls and toggles the blur (${load.label})', (
        WidgetTester tester,
      ) async {
        await mount(tester, scenarioById(buildStockScenarios(), 'S1'),
            load: load);
        await scrollList(tester, -300);
        await pumpFrames(tester);
        await tester.tap(find.text('Blur on'));
        await pumpFrames(tester);
        await scrollList(tester, 300);
        await pumpFrames(tester);
        await unmount(tester);
      });
    }

    testWidgets('Load switches the content under the blur on every screen', (
      WidgetTester tester,
    ) async {
      for (final String id in <String>['S1', 'S2', 'S3']) {
        await mount(tester, scenarioById(buildStockScenarios(), id));
        // Real-app is the default: ambient background, glass cards, covers.
        expect(find.byType(AmbientBackground), findsOneWidget, reason: id);
        expect(find.byType(RecentlyPlayedRow), findsOneWidget, reason: id);
        expect(find.byType(GlassPanel), findsWidgets, reason: id);

        await tester.tap(find.text('Light'));
        await pumpFrames(tester);
        expect(appLoad.value, AppLoad.light);
        expect(find.byType(AmbientBackground), findsNothing, reason: id);
        expect(find.byType(GlassPanel), findsNothing, reason: id);

        await tester.tap(find.text('Real-app'));
        await pumpFrames(tester);
        expect(appLoad.value, AppLoad.realApp);
        expect(find.byType(AmbientBackground), findsOneWidget, reason: id);
        expect(find.byType(GlassPanel), findsWidgets, reason: id);
        await unmount(tester);
      }
    });

    testWidgets('S3 dissolves a row, then removes it', (
      WidgetTester tester,
    ) async {
      await mount(
        tester,
        scenarioById(buildStockScenarios(), 'S3'),
        load: AppLoad.light,
      );
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

    for (final AppLoad load in AppLoad.values) {
      testWidgets(
          'S3 "Play 20 in a row" keeps going through "Fling list" '
          '(${load.label})', (WidgetTester tester) async {
        await mount(tester, scenarioById(buildStockScenarios(), 'S3'),
            load: load);
        await openHud(tester);

        await tester.tap(find.text('Play 20 in a row'));
        // About two songs (1.25 s dissolve + 0.18 s collapse + 0.15 s gap
        // each), then fling the list away from the row that is dissolving.
        // (This used to freeze the run: the row was built lazily, so
        // scrolling disposed it mid-dissolve and its animation never
        // completed.)
        await pumpFrames(tester, frames: 34);
        expect(find.textContaining('songs removed: 2'), findsOneWidget);
        await tester.tap(find.text('Fling list'));
        await pumpFrames(tester, frames: 40);
        await tester.tap(find.text('Fling list'));

        // The run has to finish by itself: about 1.6 s per song, 20 songs.
        for (int i = 0;
            i < 700 && find.text('Stop run').evaluate().isNotEmpty;
            i++) {
          await tester.pump(const Duration(milliseconds: 100));
        }
        await pumpFrames(tester, frames: 8); // let the HUD refresh
        expect(find.text('Play 20 in a row'), findsOneWidget);
        expect(find.textContaining('songs removed: 20'), findsOneWidget);
        await unmount(tester);
      });
    }

    testWidgets('S3 "Stop run" ends a run, "Play once" removes one song', (
      WidgetTester tester,
    ) async {
      await mount(tester, scenarioById(buildStockScenarios(), 'S3'));
      await openHud(tester);
      await tester.tap(find.text('Play 20 in a row'));
      await pumpFrames(tester, frames: 5);
      await tester.tap(find.text('Stop run'));
      await pumpFrames(tester, frames: 30);
      expect(find.text('Play 20 in a row'), findsOneWidget);
      expect(find.textContaining('songs removed: 1'), findsOneWidget);

      // Nothing runs on its own now.
      await pumpFrames(tester, frames: 30);
      expect(find.textContaining('songs removed: 1'), findsOneWidget);

      await tester.tap(find.text('Play once'));
      await pumpFrames(tester, frames: 20);
      expect(find.textContaining('songs removed: 2'), findsOneWidget);
      await unmount(tester);
    });

    testWidgets('S3 swipe removes a song', (WidgetTester tester) async {
      await mount(
        tester,
        scenarioById(buildStockScenarios(), 'S3'),
        load: AppLoad.light,
      );
      expect(find.text('Slow River'), findsOneWidget);
      await tester.drag(find.text('Slow River'), const Offset(200, 0));
      await pumpFrames(tester, frames: 18);
      expect(find.text('Slow River'), findsNothing);
      await unmount(tester);
    });
  });
}
