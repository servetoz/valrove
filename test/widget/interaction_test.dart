import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:material_ui/material_ui.dart';
import 'package:valrove/app.dart';
import 'package:valrove/map/map_controller.dart';
import 'package:valrove/map/widgets/map_canvas.dart';
import 'package:valrove/state/session.dart';

import '../support/fake_robot.dart';
import '../support/test_support.dart';

Future<void> settle(WidgetTester tester, {int rounds = 10}) async {
  for (var i = 0; i < rounds; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pump(const Duration(milliseconds: 100));
  }
}

List<Map<String, dynamic>> puts(FixtureHttpClient fake, String pathSuffix) => [
  for (final r in fake.requests.whereType<http.Request>())
    if (r.method == 'PUT' && r.url.path.endsWith(pathSuffix))
      jsonDecode(r.body) as Map<String, dynamic>,
];

void main() {
  setUpAll(loadAppFonts);

  Future<FixtureHttpClient> start(WidgetTester tester) async {
    final client = FixtureHttpClient();
    final overrides = await fakeRobotOverrides(
      client,
      prefs: {'settings.theme': 'light'},
    );
    await tester.pumpWidget(
      ProviderScope(overrides: overrides, child: const ValroveApp()),
    );
    await settle(tester);
    return client;
  }

  Offset roomCenter(WidgetTester tester, String id) {
    final canvas = tester.widget<MapCanvas>(find.byType(MapCanvas));
    final container = ProviderScope.containerOf(
      tester.element(find.byType(MapCanvas)),
    );
    final data = container.read(liveMapProvider).scene!.data;
    final segment = data.segment(id)!;
    // The label anchor is guaranteed to lie inside the room.
    expect(data.segmentAt(segment.labelX, segment.labelY), id);
    final local = canvas.controller.viewport.worldToScreen(
      Offset(segment.labelX, segment.labelY),
    );
    return tester.getTopLeft(find.byType(MapCanvas)) + local;
  }

  testWidgets('select a room and start a segment cleanup', (tester) async {
    await withPhoneSurface(tester, () async {
      final client = await start(tester);
      final canvas = tester.widget<MapCanvas>(find.byType(MapCanvas));
      expect(canvas.controller.mode, MapMode.segments);

      await tester.tapAt(roomCenter(tester, '4'));
      await settle(tester, rounds: 4);
      expect(canvas.controller.selectedSegments, ['4']);
      expect(find.text('Clean 1 room'), findsOneWidget);

      await tester.tapAt(roomCenter(tester, '1'));
      await settle(tester, rounds: 4);
      expect(find.text('Clean 2 rooms'), findsOneWidget);

      await tester.tap(find.text('Clean 2 rooms'));
      await settle(tester, rounds: 6);
      final sent = puts(client, '/MapSegmentationCapability');
      expect(sent, [
        {
          'action': 'start_segment_action',
          'segment_ids': ['4', '1'],
          'iterations': 1,
          'customOrder': true,
        },
      ]);
      // Selection is cleared after a successful start.
      expect(canvas.controller.selectedSegments, isEmpty);

      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 2));
    });
  });

  testWidgets('draw a zone and clean it', (tester) async {
    await withPhoneSurface(tester, () async {
      final client = await start(tester);
      await tester.tap(find.text('Zones'));
      await settle(tester, rounds: 4);
      expect(find.text('Draw a zone'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.add_rounded));
      await settle(tester, rounds: 4);
      expect(find.text('Clean 1 zone'), findsOneWidget);

      await tester.tap(find.text('Clean 1 zone'));
      await settle(tester, rounds: 6);
      final sent = puts(client, '/ZoneCleaningCapability');
      expect(sent, hasLength(1));
      expect(sent.single['action'], 'clean');
      final points =
          (sent.single['zones'] as List).single['points']
              as Map<String, dynamic>;
      expect(points.keys, containsAll(['pA', 'pB', 'pC', 'pD']));
      // 30×30 map pixels at 5 cm/px.
      expect(points['pB']['x'] - points['pA']['x'], 150);

      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 2));
    });
  });

  testWidgets('basic controls send commands', (tester) async {
    await withPhoneSurface(tester, () async {
      final client = await start(tester);
      await tester.tap(find.text('Start'));
      await settle(tester, rounds: 6);
      expect(puts(client, '/BasicControlCapability'), [
        {'action': 'start'},
      ]);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 2));
    });
  });
}
