import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:valrove/app.dart';
import 'package:valrove/features/map/map_management_page.dart';
import 'package:valrove/features/robot/consumables_page.dart';
import 'package:valrove/features/robot/robot_options_page.dart';
import 'package:valrove/features/robots/robot_setup.dart';
import 'package:valrove/features/settings/settings_hub.dart';
import 'package:valrove/features/system/system_info_page.dart';
import 'package:valrove/features/timers/timers_page.dart';
import 'package:valrove/ui/theme.dart';
import 'package:valrove/ui/toast_host.dart';

import '../support/fake_robot.dart';
import '../support/test_support.dart';
import 'map_render_test.dart' show decorate;

/// Lets isolates, image decoding and animations settle.
Future<void> settle(WidgetTester tester, {int rounds = 12}) async {
  for (var i = 0; i < rounds; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 60)),
    );
    await tester.pump(const Duration(milliseconds: 120));
  }
}

Map<String, Object?> cleaningOverrides() {
  final attrs = jsonDecode(fixtureText('robot__state__attributes')) as List;
  for (final a in attrs.cast<Map<String, dynamic>>()) {
    if (a['__class'] == 'StatusStateAttribute') {
      a['value'] = 'cleaning';
      a['flag'] = 'segment';
    }
    if (a['__class'] == 'BatteryStateAttribute') {
      a['level'] = 72;
      a['flag'] = 'discharging';
    }
    if (a['__class'] == 'DockStatusStateAttribute') a['value'] = 'idle';
  }
  return {
    'robot/state/attributes': attrs,
    'robot/state/map': jsonDecode(decorate(fixtureText('robot__state__map'))),
    'robot/capabilities/CurrentStatisticsCapability': [
      {
        '__class': 'ValetudoDataPoint',
        'metaData': {},
        'timestamp': '2026-11-14T12:00:00Z',
        'type': 'time',
        'value': 1265,
      },
      {
        '__class': 'ValetudoDataPoint',
        'metaData': {},
        'timestamp': '2026-11-14T12:00:00Z',
        'type': 'area',
        'value': 184000,
      },
    ],
  };
}

Future<void> pumpApp(
  WidgetTester tester, {
  required bool dark,
  Map<String, Object?> overrides = const {},
  bool noRobots = false,
}) async {
  final http = FixtureHttpClient(overrides: overrides);
  final scope = await fakeRobotOverrides(
    http,
    prefs: {'settings.theme': dark ? 'dark' : 'light'},
    profiles: noRobots ? [] : null,
  );
  await tester.pumpWidget(
    ProviderScope(overrides: scope, child: const ValroveApp()),
  );
  await settle(tester);
}

Future<void> pumpPage(
  WidgetTester tester,
  Widget page, {
  required bool dark,
  Map<String, Object?> overrides = const {},
}) async {
  final http = FixtureHttpClient(overrides: overrides);
  final scope = await fakeRobotOverrides(http);
  await tester.pumpWidget(
    ProviderScope(
      overrides: scope,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light(),
        darkTheme: AppTheme.dark(),
        themeMode: dark ? ThemeMode.dark : ThemeMode.light,
        builder: (context, child) => ToastHost(child: child!),
        home: page,
      ),
    ),
  );
  await settle(tester, rounds: 8);
}

Future<void> tearDownApp(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(seconds: 2));
}

void main() {
  setUpAll(loadAppFonts);

  testWidgets('home — docked, light', (tester) async {
    await withPhoneSurface(tester, () async {
      await pumpApp(tester, dark: false);
      await expectLater(
        find.byType(ValroveApp),
        matchesGoldenFile('../goldens/home_docked_light.png'),
      );
      await tearDownApp(tester);
    });
  });

  testWidgets('home — cleaning, dark', (tester) async {
    await withPhoneSurface(tester, () async {
      await pumpApp(tester, dark: true, overrides: cleaningOverrides());
      await expectLater(
        find.byType(ValroveApp),
        matchesGoldenFile('../goldens/home_cleaning_dark.png'),
      );
      await tearDownApp(tester);
    });
  });

  testWidgets('home — sheet expanded, dark', (tester) async {
    await withPhoneSurface(tester, () async {
      await pumpApp(tester, dark: true);
      await tester.drag(find.text('Docked').last, const Offset(0, -520));
      await settle(tester, rounds: 6);
      await expectLater(
        find.byType(ValroveApp),
        matchesGoldenFile('../goldens/home_sheet_dark.png'),
      );
      await tearDownApp(tester);
    });
  });

  testWidgets('onboarding — light', (tester) async {
    await withPhoneSurface(tester, () async {
      await pumpApp(tester, dark: false, noRobots: true);
      expect(find.byType(OnboardingScreen), findsOneWidget);
      await expectLater(
        find.byType(ValroveApp),
        matchesGoldenFile('../goldens/onboarding_light.png'),
      );
      await tearDownApp(tester);
    });
  });

  final pages = <String, Widget>{
    'settings_hub_dark': const SettingsHubPage(),
    'robot_options_light': const RobotOptionsPage(),
    'consumables_dark': const ConsumablesPage(),
    'timers_light': const TimersPage(),
    'map_management_dark': const MapManagementPage(),
    'system_info_light': const SystemInfoPage(),
  };
  for (final entry in pages.entries) {
    testWidgets('page ${entry.key}', (tester) async {
      await withPhoneSurface(tester, () async {
        await pumpPage(tester, entry.value, dark: entry.key.endsWith('dark'));
        await expectLater(
          find.byType(MaterialApp),
          matchesGoldenFile('../goldens/${entry.key}.png'),
        );
        await tearDownApp(tester);
      });
    });
  }
}
