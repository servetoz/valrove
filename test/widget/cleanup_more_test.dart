import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:valrove/app.dart';
import 'package:valrove/core/cleanup/consumable_forecast.dart';
import 'package:valrove/core/cleanup/lost_found.dart';
import 'package:valrove/core/cleanup/map_summary.dart';
import 'package:valrove/core/cleanup/presets.dart';
import 'package:valrove/core/cleanup/robot_files.dart';
import 'package:valrove/core/cleanup/sequence.dart';
import 'package:valrove/core/cleanup/wifi_coverage.dart';
import 'package:valrove/core/valetudo/models/models.dart';
import 'package:valrove/features/cleanup/launchers.dart';
import 'package:valrove/features/cleanup/lost_found_page.dart';
import 'package:valrove/features/cleanup/wifi_coverage_page.dart';
import 'package:valrove/features/home/home_screen.dart';
import 'package:valrove/features/robot/consumables_page.dart';
import 'package:valrove/map/widgets/map_canvas.dart';
import 'package:valrove/state/session.dart';
import 'package:valrove/ui/theme.dart';

import '../support/fake_robot.dart';
import '../support/test_support.dart';
import 'interaction_test.dart' show puts, settle;

void main() {
  setUpAll(loadAppFonts);

  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('more'));
  tearDown(() => dir.deleteSync(recursive: true));

  const evening = CleanupPreset(
    id: 'p2',
    name: 'Evening',
    rooms: ['4', '1', '2'],
    fanSpeed: 'low',
    roomSettings: {'4': RoomSettings(operationMode: 'mop', fanSpeed: 'off')},
  );

  Future<FixtureHttpClient> startApp(
    WidgetTester tester, {
    List<CleanupPreset> presets = const [],
  }) async {
    final fake = FixtureHttpClient();
    final scope = await fakeRobotOverrides(
      fake,
      prefs: {
        'settings.theme': 'light',
        if (presets.isNotEmpty)
          'cleanupPresets.test': jsonEncode([
            for (final p in presets) p.toJson(),
          ]),
      },
      historyDir: dir,
    );
    await tester.pumpWidget(
      ProviderScope(overrides: scope, child: const ValroveApp()),
    );
    await settle(tester);
    return fake;
  }

  Future<void> pumpPage(WidgetTester tester, Widget page) async {
    final scope = await fakeRobotOverrides(
      FixtureHttpClient(),
      historyDir: dir,
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: scope,
        child: MaterialApp(theme: AppTheme.light(), home: page),
      ),
    );
  }

  /// Real file I/O needs real time between frames.
  Future<void> settleUntil(WidgetTester tester, bool Function() done) async {
    for (var i = 0; i < 40 && !done(); i++) {
      await settle(tester, rounds: 1);
    }
  }

  ProviderContainer container(WidgetTester tester) =>
      ProviderScope.containerOf(tester.element(find.byType(HomeScreen)));

  testWidgets('a preset with room settings runs step by step', (tester) async {
    await withPhoneSurface(tester, () async {
      final fake = await startApp(tester, presets: [evening]);
      container(tester)
          .read(launchActionsProvider.notifier)
          .receive(LaunchAction.presetUri('test', 'p2'));
      await settle(tester, rounds: 6);

      // Step 1 only: the kitchen, mopping without suction.
      expect(puts(fake, '/OperationModeControlCapability/preset'), [
        {'name': 'mop'},
      ]);
      expect(puts(fake, '/MapSegmentationCapability').single['segment_ids'], [
        '4',
      ]);
      PendingSequence? pending;
      for (var i = 0; i < 20 && pending == null; i++) {
        pending = await tester.runAsync<PendingSequence?>(
          () => SequenceStore(RobotFiles(dir)).load('test'),
        );
        await settle(tester, rounds: 1);
      }
      expect(pending!.remaining.single.rooms, ['1', '2']);

      // The robot finishes step 1; the app starts step 2.
      final live = container(tester).read(liveStateProvider.notifier);
      RobotState state(String value, [String flag = 'none']) =>
          RobotState.fromJson([
            {'__class': 'StatusStateAttribute', 'value': value, 'flag': flag},
          ]);
      live.set(state('cleaning', 'segment'));
      await tester.pump();
      live.set(state('returning'));
      await tester.pump();
      live.set(state('docked'));
      await settleUntil(
        tester,
        () => puts(fake, '/MapSegmentationCapability').length == 2,
      );
      expect(puts(fake, '/MapSegmentationCapability').last['segment_ids'], [
        '1',
        '2',
      ]);
      expect(puts(fake, '/FanSpeedControlCapability/preset').last, {
        'name': 'low',
      });
    });
  });

  testWidgets('the preset editor sets room settings and shows the steps', (
    tester,
  ) async {
    await withPhoneSurface(tester, () async {
      await startApp(
        tester,
        presets: [
          const CleanupPreset(id: 'p', name: 'Two', rooms: ['4', '1']),
        ],
      );
      await tester.drag(find.text('Docked').last, const Offset(0, -520));
      await settle(tester, rounds: 4);
      await tester.longPress(find.text('Two'));
      await settle(tester, rounds: 4);
      expect(find.textContaining('cleanups in a row'), findsNothing);

      await tester.tap(find.byTooltip('Settings for this room').first);
      await settle(tester, rounds: 4);
      // The room's sheet lies over the editor: its field comes last.
      await tester.tap(
        find.widgetWithText(DropdownButtonFormField<String?>, 'Suction').last,
      );
      await settle(tester, rounds: 2);
      await tester.tap(find.text('Low').last);
      await settle(tester, rounds: 2);
      await tester.tap(find.text('Done'));
      await settle(tester, rounds: 4);

      expect(find.text('Runs as 2 cleanups in a row'), findsOneWidget);
      expect(find.textContaining('1. Room 4 · Low'), findsOneWidget);
    });
  });

  testWidgets('typed and linked commands control the robot', (tester) async {
    await withPhoneSurface(tester, () async {
      final fake = await startApp(tester);
      await tester.tap(find.byTooltip('Voice command'));
      await settle(tester, rounds: 4);
      // No speech recognizer in tests: typing works the same way.
      expect(find.text('Speech recognition is not available'), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'clean room 4 twice');
      await tester.testTextInput.receiveAction(TextInputAction.go);
      await settle(tester, rounds: 6);
      expect(puts(fake, '/MapSegmentationCapability'), [
        {
          'action': 'start_segment_action',
          'segment_ids': ['4'],
          'iterations': 2,
          'customOrder': false,
        },
      ]);

      container(tester)
          .read(launchActionsProvider.notifier)
          .receive(
            Uri.parse('valrove://command?text=go%20back%20to%20the%20dock'),
          );
      await settle(tester, rounds: 6);
      expect(puts(fake, '/BasicControlCapability'), [
        {'action': 'home'},
      ]);
    });
  });

  testWidgets('Wi-Fi coverage shows readings on the map', (tester) async {
    await withPhoneSurface(tester, () async {
      await tester.runAsync(() async {
        final store = WifiCoverageStore(RobotFiles(dir));
        final now = DateTime.now();
        await store.add('test', 3278, 3229, -48, now);
        await store.add('test', 3000, 3000, -83, now);
      });
      await pumpPage(tester, const WifiCoveragePage());
      await settleUntil(
        tester,
        () => find.text('Summary').evaluate().isNotEmpty,
      );
      expect(
        tester.widget<MapCanvas>(find.byType(MapCanvas)).overlayRects.length,
        2,
      );
      expect(find.text('-66 dBm · Fair'), findsOneWidget);
      expect(find.textContaining('-83 dBm'), findsOneWidget);
    });
  });

  testWidgets('lost & found keeps photos of what the robot found', (
    tester,
  ) async {
    await withPhoneSurface(tester, () async {
      await tester.runAsync(() async {
        final map = MapSummary.fromJson({
          'pixelSize': 5,
          'layers': [],
          'entities': [
            {
              'type': 'obstacle',
              'points': [3278, 3229],
              'metaData': {'id': 'o1', 'label': 'Sock (92%)'},
            },
          ],
        });
        await LostFoundStore(RobotFiles(dir))
            .collect('test', map, DateTime.now());
      });
      await pumpPage(tester, const LostFoundPage());
      await settleUntil(tester, () => find.text('Sock').evaluate().isNotEmpty);
      expect(find.text('Sock'), findsOneWidget);
      await tester.tap(find.text('Sock'));
      await settleUntil(
        tester,
        () => find.byType(MapCanvas).evaluate().isNotEmpty,
      );
      expect(find.text('Picked it up, remove'), findsOneWidget);
      expect(
        tester.widget<MapCanvas>(find.byType(MapCanvas)).markers.length,
        1,
      );
    });
  });

  testWidgets('consumables show when they will wear out', (tester) async {
    await withPhoneSurface(tester, () async {
      await tester.runAsync(() async {
        // The main brush (8640 min left) lost 300 min in ten days.
        final forecasts = ConsumableForecasts()
          ..record([
            (key: 'brush.main', value: 8940, unit: 'minutes'),
          ], DateTime.now().subtract(const Duration(days: 10)));
        await ConsumableForecastStore(RobotFiles(dir)).save('test', forecasts);
      });
      await pumpPage(tester, const ConsumablesPage());
      await settleUntil(
        tester,
        () => find.textContaining('months left').evaluate().isNotEmpty,
      );
      // 30 min a day: 8640 / 30 = 288 days.
      expect(find.textContaining('About 10 months left'), findsOneWidget);
    });
  });
}
