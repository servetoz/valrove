import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:valrove/app.dart';
import 'package:valrove/core/cleanup/history_store.dart';
import 'package:valrove/core/cleanup/robot_files.dart';
import 'package:valrove/core/persistence/stores.dart';
import 'package:valrove/map/widgets/map_canvas.dart';
import 'package:valrove/state/app_state.dart';
import 'package:valrove/state/cleanup.dart';
import 'package:valrove/state/demo_robot.dart';

import '../support/test_support.dart';
import 'interaction_test.dart' show settle;

void main() {
  setUpAll(loadAppFonts);

  testWidgets('the demo robot plays along with commands', (tester) async {
    final robot = DemoRobot();
    // Loads the recordings.
    await tester.runAsync(() async {
      for (final path in [
        'robot/state/attributes',
        'robot/state/map',
        'robot/capabilities/KeyLockCapability',
        'valetudo/config/duststreaming',
      ]) {
        await robot.get(path);
      }
    });
    Future<Map<String, Object?>> attribute(String type) async {
      final list = jsonDecode((await robot.get('robot/state/attributes'))!);
      return (list as List).cast<Map<String, Object?>>().firstWhere(
        (a) => a['__class'] == type || a['type'] == type,
      );
    }

    Future<Object?> status() async =>
        (await attribute('StatusStateAttribute'))['value'];
    Future<void> control(String action) => robot.command(
      'robot/capabilities/BasicControlCapability',
      {'action': action},
    );

    // The app follows the robot through its event stream.
    final events = <String>[];
    final sub = robot
        .events('robot/state/attributes/sse')
        .map(utf8.decode)
        .listen(events.add);
    await tester.pump();
    expect(await status(), 'docked');
    expect(events.single, startsWith('event: StateAttributesUpdated\n'));

    await control('start');
    expect(await status(), 'cleaning');
    expect(events.last, contains('"cleaning"'));

    await robot.command('robot/capabilities/FanSpeedControlCapability/preset', {
      'name': 'low',
    });
    expect((await attribute('fan_speed'))['value'], 'low');

    await control('home');
    expect(await status(), 'returning');
    await tester.pump(DemoRobot.tick * DemoRobot.driveTicks);
    expect(await status(), 'docked');
    final level = (await attribute('BatteryStateAttribute'))['level']! as int;
    await tester.pump(DemoRobot.tick);
    final battery = await attribute('BatteryStateAttribute');
    expect(battery['level'], level + 1);
    expect(battery['flag'], 'charging');

    // Switches stay as set; the camera stays off (there's nothing to show).
    const keyLock = 'robot/capabilities/KeyLockCapability';
    await robot.command(keyLock, {'action': 'enable'});
    expect(jsonDecode((await robot.get(keyLock))!), {'enabled': true});
    await robot.command('valetudo/config/duststreaming', {'enabled': true});
    expect(jsonDecode((await robot.get('valetudo/config/duststreaming'))!), {
      'enabled': false,
    });

    // Unwatched, the robot pauses (no timer is left running). Awaiting the
    // cancel would hang the fake-async test zone.
    unawaited(sub.cancel());
    await tester.pump();
  });

  testWidgets('the welcome screen opens the demo', (tester) async {
    await withPhoneSurface(tester, () async {
      SharedPreferences.setMockInitialValues({'settings.theme': 'light'});
      final prefs = await SharedPreferences.getInstance();
      final dir = Directory.systemTemp.createTempSync('valrove_demo');
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sharedPreferencesProvider.overrideWithValue(prefs),
            secretStoreProvider.overrideWithValue(MemorySecretStore()),
            historyStoreProvider.overrideWith((ref) async => HistoryStore(dir)),
            robotFilesProvider.overrideWith((ref) async => RobotFiles(dir)),
          ],
          child: const ValroveApp(),
        ),
      );
      await settle(tester);

      final demo = find.text('No robot at hand? Try the demo');
      await tester.scrollUntilVisible(
        demo,
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(demo);
      await settle(tester, rounds: 20);
      expect(find.text('Demo robot'), findsOneWidget);
      expect(find.byType(MapCanvas), findsOneWidget);
      expect(find.text('Docked'), findsWidgets);

      await tester.tap(find.text('Start'));
      await settle(tester);
      expect(find.text('Cleaning'), findsWidgets);

      // Closes the app, which pauses the demo robot.
      await tester.pumpWidget(const SizedBox());
    });
  });
}
