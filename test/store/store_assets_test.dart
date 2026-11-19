// Renders the Google Play screenshots and feature graphic into
// docs/play-store/. Skipped in normal test runs; to render them again:
//
//   flutter test test/store --update-goldens --dart-define=STORE_ASSETS=true
//
// The icon (docs/play-store/icon-512.png) comes from tool/icons/render.mjs.
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:valrove/app.dart';
import 'package:valrove/features/map/map_management_page.dart';
import 'package:valrove/features/robot/consumables_page.dart';
import 'package:valrove/features/settings/settings_hub.dart';
import 'package:valrove/features/timers/timers_page.dart';
import 'package:valrove/ui/theme.dart';

import '../support/test_support.dart';
import '../visual/screens_test.dart'
    show cleaningOverrides, pumpApp, pumpPage, settle, tearDownApp;

const _render = bool.fromEnvironment('STORE_ASSETS');
const _out = '../../docs/play-store';

/// Runs [body] on a 1080×2160 screen (Play allows at most 2:1).
Future<void> _onPhone(WidgetTester tester, Future<void> Function() body) =>
    _onScreen(tester, const Size(1080, 2160), 2.625, body);

Future<void> _onScreen(
  WidgetTester tester,
  Size pixels,
  double ratio,
  Future<void> Function() body,
) async {
  tester.view.physicalSize = pixels;
  tester.view.devicePixelRatio = ratio;
  debugDisableShadows = false;
  try {
    await body();
  } finally {
    debugDisableShadows = true;
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  }
}

void main() {
  setUpAll(loadAppFonts);

  Future<void> shoot(WidgetTester tester, String name) => expectLater(
    find.byType(ValroveApp).evaluate().isEmpty
        ? find.byType(MaterialApp)
        : find.byType(ValroveApp),
    matchesGoldenFile('$_out/screenshots/$name.png'),
  );

  testWidgets('1 map while cleaning', skip: !_render, (tester) async {
    await _onPhone(tester, () async {
      await pumpApp(tester, dark: true, overrides: cleaningOverrides());
      await shoot(tester, '1-map-cleaning');
      await tearDownApp(tester);
    });
  });

  testWidgets('2 controls', skip: !_render, (tester) async {
    await _onPhone(tester, () async {
      await pumpApp(tester, dark: true);
      await tester.drag(find.text('Docked').last, const Offset(0, -560));
      await settle(tester, rounds: 6);
      await shoot(tester, '2-controls');
      await tearDownApp(tester);
    });
  });

  testWidgets('3 map in light', skip: !_render, (tester) async {
    await _onPhone(tester, () async {
      await pumpApp(tester, dark: false);
      await shoot(tester, '3-map-light');
      await tearDownApp(tester);
    });
  });

  final pages = {
    '4-map-management': const MapManagementPage(),
    '5-schedules': const TimersPage(),
    '6-consumables': const ConsumablesPage(),
    '7-settings': const SettingsHubPage(),
  };
  for (final MapEntry(key: name, value: page) in pages.entries) {
    testWidgets('$name page', skip: !_render, (tester) async {
      await _onPhone(tester, () async {
        await pumpPage(tester, page, dark: name != '5-schedules');
        await shoot(tester, name);
        await tearDownApp(tester);
      });
    });
  }

  testWidgets('feature graphic', skip: !_render, (tester) async {
    // 1024×500, as Play requires.
    await _onScreen(tester, const Size(1024, 500), 2, () async {
      final phone = File('docs/play-store/screenshots/1-map-cleaning.png')
          .readAsBytesSync();
      await tester.pumpWidget(
        MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: AppTheme.dark(),
          home: _FeatureGraphic(phone: phone),
        ),
      );
      await tester.runAsync(() async {
        for (final element in find.byType(Image).evaluate()) {
          final image = element.widget as Image;
          await precacheImage(image.image, element);
        }
      });
      await tester.pump();
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('$_out/feature-graphic.png'),
      );
    });
  });
}

class _FeatureGraphic extends StatelessWidget {
  const _FeatureGraphic({required this.phone});

  final List<int> phone;

  @override
  Widget build(BuildContext context) {
    const accent = Color(0xFF00D4FF);
    final text = context.text;
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF000429), Color(0xFF0A1A44), Color(0xFF00304A)],
        ),
      ),
      child: Stack(
        children: [
          Positioned(
            left: 36,
            top: 0,
            bottom: 0,
            width: 280,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Image.asset('assets/brand/logo.png', width: 40),
                    const SizedBox(width: 10),
                    Text(
                      'Valrove',
                      style: text.headlineMedium?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Text(
                  'The app your Valetudo robot deserves.',
                  style: text.titleLarge?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                    height: 1.2,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  'Live map · One-tap cleanups · No cloud',
                  style: text.bodyMedium?.copyWith(color: accent),
                ),
              ],
            ),
          ),
          // The phone, cut off by the bottom edge.
          Positioned(
            right: 44,
            top: 26,
            width: 136,
            height: 272,
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.white24, width: 3),
                boxShadow: [
                  BoxShadow(
                    color: accent.withValues(alpha: 0.25),
                    blurRadius: 30,
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(17),
                child: Image.memory(
                  Uint8List.fromList(phone),
                  fit: BoxFit.cover,
                  alignment: Alignment.topCenter,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
