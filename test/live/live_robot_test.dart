// End-to-end smoke test against a real Valetudo robot (read-only: the app
// only performs its startup GET requests and opens SSE streams).
//
//   flutter test test/live --run-skipped --dart-define=ROBOT=192.168.1.122
@Tags(['live'])
library;

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:valrove/app.dart';
import 'package:valrove/core/persistence/robot_profile.dart';
import 'package:valrove/core/persistence/stores.dart';
import 'package:valrove/state/app_state.dart';
import 'package:valrove/state/session.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/test_support.dart';

const robot = String.fromEnvironment('ROBOT', defaultValue: '192.168.1.122');

void main() {
  setUpAll(() async {
    await loadAppFonts();
    HttpOverrides.global = null; // allow real network access
  });

  for (final dark in [true, false]) {
    testWidgets('live home screen (${dark ? 'dark' : 'light'})', (
      tester,
    ) async {
      await withPhoneSurface(tester, () async {
        SharedPreferences.setMockInitialValues({
          'settings.theme': dark ? 'dark' : 'light',
        });
        final prefs = await SharedPreferences.getInstance();
        final profile = RobotProfile(
          id: 'live',
          name: 'Live robot',
          url: 'http://$robot/',
          addedAt: DateTime.now(),
        );
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              sharedPreferencesProvider.overrideWithValue(prefs),
              secretStoreProvider.overrideWithValue(MemorySecretStore()),
              initialProfilesProvider.overrideWithValue([profile]),
            ],
            child: const ValroveApp(),
          ),
        );

        // Let real network I/O, the map isolate and image decoding complete.
        for (var i = 0; i < 40; i++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 150)),
          );
          await tester.pump(const Duration(milliseconds: 100));
        }

        final container = ProviderScope.containerOf(
          tester.element(find.byType(ValroveApp)),
        );
        final state = container.read(liveStateProvider);
        final map = container.read(liveMapProvider);
        final caps = container.read(capabilitiesProvider);
        expect(caps.hasValue, isTrue, reason: 'capabilities loaded');
        expect(
          state.hasValue,
          isTrue,
          reason: 'robot state loaded: ${state.error}',
        );
        expect(map.hasMap, isTrue, reason: 'map loaded: ${map.error}');
        expect(container.read(connectionHealthProvider).isOnline, isTrue);

        // Live data changes all the time, so screenshots are saved for
        // inspection instead of being compared against goldens.
        await tester.runAsync(() async {
          final image = await captureImage(
            tester.element(find.byType(ValroveApp)),
          );
          final png = await image.toByteData(format: ui.ImageByteFormat.png);
          File('build/live_screenshots/home_${dark ? 'dark' : 'light'}.png')
            ..createSync(recursive: true)
            ..writeAsBytesSync(png!.buffer.asUint8List());
        });
        await tester.pumpWidget(const SizedBox());
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 800)),
        );
      });
    });
  }
}
