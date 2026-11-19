import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:valrove/app.dart';
import 'package:valrove/core/cleanup/cleanup_record.dart';
import 'package:valrove/core/cleanup/history_store.dart';
import 'package:valrove/core/cleanup/presets.dart';
import 'package:valrove/core/valetudo/models/models.dart';
import 'package:valrove/features/cleanup/history_page.dart';
import 'package:valrove/features/cleanup/launchers.dart';
import 'package:valrove/features/home/home_screen.dart';
import 'package:valrove/map/widgets/map_canvas.dart';
import 'package:valrove/state/session.dart';
import 'package:valrove/ui/theme.dart';

import '../support/fake_robot.dart';
import '../support/test_support.dart';
import 'interaction_test.dart' show puts, settle;

void main() {
  setUpAll(loadAppFonts);

  late Directory historyDir;
  setUp(() => historyDir = Directory.systemTemp.createTempSync('history'));
  tearDown(() => historyDir.deleteSync(recursive: true));

  const afterDinner = CleanupPreset(
    id: 'p1',
    name: 'After dinner',
    rooms: ['4', '1'],
    iterations: 2,
    fanSpeed: 'turbo',
  );

  Future<FixtureHttpClient> start(
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
      historyDir: historyDir,
    );
    await tester.pumpWidget(
      ProviderScope(overrides: scope, child: const ValroveApp()),
    );
    await settle(tester);
    return fake;
  }

  ProviderContainer container(WidgetTester tester) =>
      ProviderScope.containerOf(tester.element(find.byType(HomeScreen)));

  Future<void> openSheet(WidgetTester tester) async {
    await tester.drag(find.text('Docked').last, const Offset(0, -520));
    await settle(tester, rounds: 4);
  }

  testWidgets('a preset starts with one tap from the home sheet', (
    tester,
  ) async {
    await withPhoneSurface(tester, () async {
      final fake = await start(tester, presets: [afterDinner]);
      await openSheet(tester);
      expect(find.text('After dinner'), findsOneWidget);

      await tester.tap(find.text('After dinner'));
      await settle(tester, rounds: 6);
      expect(puts(fake, '/FanSpeedControlCapability/preset'), [
        {'name': 'turbo'},
      ]);
      expect(puts(fake, '/MapSegmentationCapability'), [
        {
          'action': 'start_segment_action',
          'segment_ids': ['4', '1'],
          'iterations': 2,
          'customOrder': true,
        },
      ]);
      expect(find.text('Started "After dinner"'), findsOneWidget);
    });
  });

  testWidgets('selected rooms show an estimate and can be saved as a preset', (
    tester,
  ) async {
    await withPhoneSurface(tester, () async {
      await start(tester);
      final canvas = tester.widget<MapCanvas>(find.byType(MapCanvas));
      final room = container(tester)
          .read(liveMapProvider)
          .scene!
          .data
          .segment('4')!;
      await tester.tapAt(
        tester.getTopLeft(find.byType(MapCanvas)) +
            canvas.controller.viewport.worldToScreen(
              Offset(room.labelX, room.labelY),
            ),
      );
      await settle(tester, rounds: 4);
      // 16.7 m² in "vacuum and mop" at a typical 0.9 m²/min.
      expect(find.text('≈ 19 min · 10% battery'), findsOneWidget);

      await tester.tap(find.byTooltip('Save as preset'));
      await settle(tester, rounds: 4);
      expect(find.text('New preset'), findsOneWidget);
      expect(find.text('Room 4'), findsWidgets);
      await tester.enterText(
        find.widgetWithText(TextField, 'Name'),
        'Big room',
      );
      await tester.ensureVisible(find.text('Save'));
      await tester.tap(find.text('Save'));
      await settle(tester, rounds: 4);

      final prefs = await SharedPreferences.getInstance();
      final saved = [
        for (final p in jsonDecode(prefs.getString('cleanupPresets.test')!))
          CleanupPreset.fromJson(p),
      ];
      expect(saved.single.name, 'Big room');
      expect(saved.single.rooms, ['4']);
      // New presets keep the robot's current settings.
      expect(saved.single.operationMode, 'vacuum_and_mop');
      expect(saved.single.fanSpeed, 'max');
    });
  });

  testWidgets('the widget, tile and shortcuts start presets or dock', (
    tester,
  ) async {
    await withPhoneSurface(tester, () async {
      final fake = await start(tester, presets: [afterDinner]);
      final launches = container(tester).read(launchActionsProvider.notifier);

      launches.receive(LaunchAction.dockUri('test'));
      await settle(tester, rounds: 6);
      expect(puts(fake, '/BasicControlCapability'), [
        {'action': 'home'},
      ]);

      launches.receive(LaunchAction.presetUri('test', 'p1'));
      await settle(tester, rounds: 6);
      expect(puts(fake, '/MapSegmentationCapability').single['segment_ids'], [
        '4',
        '1',
      ]);

      launches.receive(LaunchAction.presetUri('test', 'gone'));
      await settle(tester, rounds: 4);
      expect(find.text('This preset no longer exists'), findsOneWidget);
    });
  });

  testWidgets('the app records a cleanup it sees from start to dock', (
    tester,
  ) async {
    await withPhoneSurface(tester, () async {
      await start(tester);
      final live = container(tester).read(liveStateProvider.notifier);
      RobotState state(String value, [String flag = 'none']) =>
          RobotState.fromJson([
            {'__class': 'StatusStateAttribute', 'value': value, 'flag': flag},
            {'__class': 'BatteryStateAttribute', 'level': 70, 'flag': 'none'},
          ]);
      live.set(state('cleaning', 'segment'));
      await tester.pump();
      live.set(state('returning'));
      await tester.pump();
      live.set(state('docked'));
      // Saving takes several turns of real file I/O.
      List<CleanupRecord>? records;
      for (var i = 0; i < 40 && (records?.isEmpty ?? true); i++) {
        await settle(tester, rounds: 1);
        records = await tester.runAsync(
          () => HistoryStore(historyDir).load('test'),
        );
      }
      expect(records!.single.kind, CleanupKind.rooms);
      expect(records.single.outcome, CleanupOutcome.finished);
      expect(records.single.batteryEnd, 70);
    });
  });

  testWidgets('history lists cleanups and colours rooms by last cleaning', (
    tester,
  ) async {
    await withPhoneSurface(tester, () async {
      final now = DateTime.now();
      await tester.runAsync(
        () => HistoryStore(historyDir).add(
          CleanupRecord(
            robotId: 'test',
            startedAt: now.subtract(const Duration(minutes: 30)),
            endedAt: now.subtract(const Duration(minutes: 5)),
            kind: CleanupKind.rooms,
            outcome: CleanupOutcome.finished,
            cleaningSeconds: 1380,
            areaCm2: 152000,
            rooms: const [(id: '4', name: 'Kitchen')],
            roomAreaCm2: 167250,
            batteryStart: 98,
            batteryEnd: 80,
            path: const [3200, 3200, 3300, 3250, 3280, 3300],
            obstacles: const ['Sock (92%)'],
          ),
        ),
      );
      final scope = await fakeRobotOverrides(
        FixtureHttpClient(),
        historyDir: historyDir,
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: scope,
          child: MaterialApp(
            theme: AppTheme.light(),
            home: const HistoryPage(),
          ),
        ),
      );
      await settle(tester);

      expect(find.text('TODAY'), findsOneWidget);
      expect(find.text('Kitchen'), findsOneWidget);
      expect(find.text('Last day'), findsOneWidget);
      final map = tester.widget<MapCanvas>(find.byType(MapCanvas));
      expect(map.roomNotes['4'], 'today');
      expect(map.roomNotes['1'], 'never');

      await tester.tap(find.text('Kitchen'));
      await settle(tester, rounds: 4);
      expect(find.text('Area cleaned'), findsOneWidget);
      expect(find.text('15.2 m²'), findsOneWidget);
      expect(find.text('98% → 80%'), findsOneWidget);
      expect(find.text('Sock (92%)'), findsOneWidget);
      expect(
        tester.widget<MapCanvas>(find.byType(MapCanvas).last).overlayPath,
        isNotNull,
      );
    });
  });
}
