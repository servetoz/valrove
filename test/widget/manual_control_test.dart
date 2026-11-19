import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:valrove/features/robot/manual_control_page.dart';
import 'package:valrove/state/toasts.dart';
import 'package:valrove/ui/theme.dart';

import '../support/fake_robot.dart';
import '../support/test_support.dart';
import 'interaction_test.dart' show puts, settle;

void main() {
  setUpAll(loadAppFonts);

  Future<FixtureHttpClient> open(
    WidgetTester tester, {
    Map<String, Object?> overrides = const {},
  }) async {
    final fake = FixtureHttpClient(
      overrides: {
        'robot/capabilities/HighResolutionManualControlCapability': {
          'enabled': true,
        },
        ...overrides,
      },
    );
    final scope = await fakeRobotOverrides(fake);
    await tester.pumpWidget(
      ProviderScope(
        overrides: scope,
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const ManualControlPage(),
        ),
      ),
    );
    await settle(tester);
    return fake;
  }

  List<Object?> vectors(FixtureHttpClient fake) => [
    for (final body in puts(fake, '/HighResolutionManualControlCapability'))
      if (body['action'] == 'move') body['vector'],
  ];

  testWidgets('dragging the joystick drives instead of scrolling', (
    tester,
  ) async {
    await withPhoneSurface(tester, () async {
      final fake = await open(tester);
      expect(find.byType(Scrollable), findsNothing);

      final knob = find.byIcon(Icons.navigation_rounded);
      final start = tester.getCenter(knob);
      final finger = await tester.startGesture(start);
      await tester.pump();
      // A straight vertical drag: what a scrolling page used to take over.
      await finger.moveBy(const Offset(0, -20));
      await tester.pump();
      // The joystick reports at most every 100 ms of wall time.
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 120)),
      );
      await finger.moveBy(const Offset(0, -60));
      await tester.pump(const Duration(milliseconds: 50));

      expect(tester.getCenter(knob).dy, closeTo(start.dy - 80, 0.5));
      final drive = vectors(fake).single! as Map;
      expect(drive['velocity'], closeTo(80 / 110, 0.001));
      expect(drive['angle'], 0);

      await finger.up();
      await settle(tester, rounds: 4);
      expect(vectors(fake).last, {'velocity': 0, 'angle': 0});
    });
  });

  testWidgets('W A S D key caps drive while held', (tester) async {
    await withPhoneSurface(tester, () async {
      final fake = await open(tester);
      await tester.tap(find.text('Keys'));
      await settle(tester, rounds: 2);

      final w = await tester.startGesture(tester.getCenter(find.text('W')));
      await tester.pump(const Duration(milliseconds: 50));
      expect(vectors(fake), [
        {'velocity': 1, 'angle': 0},
      ]);
      expect(find.text('Velocity 100% · Steering 0°'), findsOneWidget);

      // A second finger on D steers while W is still held.
      final d = await tester.startGesture(tester.getCenter(find.text('D')));
      await tester.pump(const Duration(milliseconds: 300));
      final steer = vectors(fake).last! as Map;
      expect(steer['velocity'], closeTo(0.7071, 0.001));
      expect(steer['angle'], closeTo(84.85, 0.01));

      await w.up();
      await d.up();
      await settle(tester, rounds: 4);
      expect(vectors(fake).last, {'velocity': 0, 'angle': 0});
      expect(find.text('Velocity 0% · Steering 0°'), findsOneWidget);
    });
  });

  const light = 'robot/capabilities/CameraLightControlCapability';

  testWidgets('the camera light is switched on the camera view', (
    tester,
  ) async {
    await withPhoneSurface(tester, () async {
      final fake = await open(
        tester,
        overrides: {
          'valetudo/config/duststreaming': {'enabled': true},
        },
      );
      // The camera view (its stream isn't set up in the fixture), with the
      // button on it instead of a switch in the card.
      expect(find.text('Setup incomplete'), findsOneWidget);
      expect(find.text('Camera light'), findsNothing);

      fake.overrides[light] = {'enabled': false};
      await tester.tap(find.byTooltip('Camera light on'));
      await settle(tester);
      expect(puts(fake, '/CameraLightControlCapability'), [
        {'action': 'disable'},
      ]);
      expect(find.byIcon(Icons.flashlight_off_rounded), findsOneWidget);

      // Switching it on says what the setting does.
      fake.overrides[light] = {'enabled': true};
      await tester.tap(find.byTooltip('Camera light off'));
      await settle(tester);
      expect(puts(fake, '/CameraLightControlCapability').last, {
        'action': 'enable',
      });
      expect(find.byIcon(Icons.flashlight_on_rounded), findsOneWidget);
      final toasts = ProviderScope.containerOf(
        tester.element(find.byType(ManualControlPage)),
      ).read(toastProvider).toasts;
      expect(toasts.last.message, contains("when it's dark"));
    });
  });

  testWidgets('without the camera view the switch is in the card', (
    tester,
  ) async {
    await withPhoneSurface(tester, () async {
      final fake = await open(tester);
      expect(find.text('Setup incomplete'), findsNothing);
      expect(find.byTooltip('Camera light on'), findsNothing);

      fake.overrides[light] = {'enabled': false};
      await tester.tap(find.text('Camera light'));
      await settle(tester);
      expect(puts(fake, '/CameraLightControlCapability'), [
        {'action': 'disable'},
      ]);
      expect(tester.widget<Switch>(find.byType(Switch).last).value, isFalse);
      // The controls still fit without scrolling.
      expect(find.byType(Scrollable), findsNothing);
      expect(find.byIcon(Icons.navigation_rounded), findsOneWidget);
    });
  });
}
