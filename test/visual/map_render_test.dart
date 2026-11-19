import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:valrove/core/valetudo/models/robot_state.dart';
import 'package:valrove/map/map_controller.dart';
import 'package:valrove/map/processing/map_palette.dart';
import 'package:valrove/map/processing/map_processor.dart';
import 'package:valrove/map/render/map_painter.dart';
import 'package:valrove/map/render/map_scene.dart';
import 'package:valrove/map/widgets/map_canvas.dart';

import '../support/test_support.dart';

/// Adds a synthetic cleaning path, obstacles and restrictions to the real
/// map so every render path is exercised.
String decorate(String json) {
  final map = jsonDecode(json) as Map<String, dynamic>;
  final entities = map['entities'] as List;
  final path = <int>[];
  for (var i = 0; i < 40; i++) {
    path
      ..add(3000 + i * 12)
      ..add(i.isEven ? 2900 : 3020);
  }
  for (var i = 0; i < 30; i++) {
    path
      ..add(3480 - (i % 2) * 30)
      ..add(3040 + i * 10);
  }
  entities.add({
    '__class': 'PathMapEntity',
    'type': 'path',
    'metaData': {},
    'points': path,
  });
  entities.add({
    '__class': 'PointMapEntity',
    'type': 'obstacle',
    'metaData': {'label': 'Sock (92%)', 'id': 'abc'},
    'points': [3200, 3300],
  });
  entities.add({
    '__class': 'LineMapEntity',
    'type': 'virtual_wall',
    'metaData': {},
    'points': [2900, 3200, 2900, 3400],
  });
  entities.add({
    '__class': 'PolygonMapEntity',
    'type': 'no_go_area',
    'metaData': {},
    'points': [3250, 3180, 3350, 3180, 3350, 3260, 3250, 3260],
  });
  entities.add({
    '__class': 'PolygonMapEntity',
    'type': 'no_mop_area',
    'metaData': {},
    'points': [3000, 3250, 3080, 3250, 3080, 3330, 3000, 3330],
  });
  entities.add({
    '__class': 'LineMapEntity',
    'type': 'threshold',
    'metaData': {},
    'points': [2950, 3100, 2950, 3160],
  });
  final robot = entities.firstWhere(
    (e) => e['type'] == 'robot_position',
  ) as Map<String, dynamic>;
  robot['points'] = [3480, 3330];
  robot['metaData'] = {'angle': 135};
  final layers = map['layers'] as List;
  (layers[0] as Map)['metaData']['name'] = 'Living Room';
  (layers[1] as Map)['metaData']['name'] = 'Kitchen';
  (layers[2] as Map)['metaData']['name'] = 'Hallway';
  (layers[3] as Map)['metaData']['name'] = 'Bedroom';
  (layers[3] as Map)['metaData']['active'] = true;
  return jsonEncode(map);
}

void main() {
  setUpAll(loadAppFonts);

  for (final dark in [false, true]) {
    testWidgets('renders the real L40 map (${dark ? 'dark' : 'light'})', (
      tester,
    ) async {
      await withPhoneSurface(tester, () async {
        final palette = dark ? MapPalette.dark : MapPalette.light;
        final processed = processMapJson(
          decorate(fixtureText('robot__state__map')),
          palette,
          dark ? 1 : 0,
        );
        expect(processed.segments.length, 4);
        expect(processed.paths, isNotEmpty);

        final builder = MapSceneBuilder();
        final scene = (await tester.runAsync(() => builder.build(processed)))!;
        final controller = MapController(mode: MapMode.segments)
          ..selectSegments(['1', '4']);
        final background = dark
            ? const Color(0xFF000000)
            : const Color(0xFFEFF2F7);

        await tester.pumpWidget(
          MaterialApp(
            debugShowCheckedModeBanner: false,
            home: ColoredBox(
              color: background,
              child: MapCanvas(
                scene: scene,
                controller: controller,
                style: MapStyle.of(
                  dark: dark,
                  accent: const Color(0xFF2DD4BF),
                  background: background,
                ),
                robotActive: true,
                job: JobState.running,
                showSelectionOrder: true,
              ),
            ),
          ),
        );
        await tester.pump(const Duration(milliseconds: 600));
        await tester.pump(const Duration(milliseconds: 600));
        await expectLater(
          find.byType(MapCanvas),
          matchesGoldenFile('../goldens/map_${dark ? 'dark' : 'light'}.png'),
        );
        await tester.pumpWidget(const SizedBox());
        builder.dispose();
      });
    });
  }

  testWidgets('only rooms that are being cleaned keep the map animating', (
    tester,
  ) async {
    // Room 4 is flagged `active`, like the robot reports it after a cancelled
    // room cleanup.
    final processed = processMapJson(
      decorate(fixtureText('robot__state__map')),
      MapPalette.light,
      0,
    );
    expect(processed.segments.where((s) => s.active).map((s) => s.id), ['4']);
    final builder = MapSceneBuilder();
    final scene = (await tester.runAsync(() => builder.build(processed)))!;
    final controller = MapController(mode: MapMode.segments);

    Future<bool> animatesWith(JobState job) async {
      await tester.pumpWidget(
        MaterialApp(
          home: MapCanvas(
            scene: scene,
            controller: controller,
            style: MapStyle.of(
              dark: false,
              accent: const Color(0xFF2DD4BF),
              background: const Color(0xFFEFF2F7),
            ),
            job: job,
          ),
        ),
      );
      // Let the camera fit and the intro animations finish.
      for (var i = 0; i < 4; i++) {
        await tester.pump(const Duration(seconds: 1));
      }
      return tester.binding.hasScheduledFrame;
    }

    expect(await animatesWith(JobState.none), isFalse, reason: 'stale flag');
    expect(await animatesWith(JobState.interrupted), isFalse, reason: 'paused');
    expect(await animatesWith(JobState.running), isTrue, reason: 'cleaning');

    await tester.pumpWidget(const SizedBox());
    builder.dispose();
  });

  test('segment hit-testing matches the web lookup', () {
    final processed = processMapJson(
      fixtureText('robot__state__map'),
      MapPalette.light,
      0,
    );
    final s4 = processed.segment('4')!;
    expect(processed.segmentAt(s4.labelX, s4.labelY), '4');
    expect(processed.segmentAt(-10, -10), isNull);
  });
}
