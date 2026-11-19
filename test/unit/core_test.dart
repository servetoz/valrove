import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:valrove/core/util/format.dart';
import 'package:valrove/core/valetudo/capabilities.dart';
import 'package:valrove/core/valetudo/client/valetudo_client.dart';
import 'package:valrove/core/valetudo/json_utils.dart';
import 'package:valrove/core/valetudo/models/models.dart';
import 'package:valrove/features/system/log_page.dart';
import 'package:valrove/features/timers/timers_page.dart';
import 'package:valrove/map/editing/shapes.dart';
import 'package:valrove/map/processing/map_palette.dart';
import 'package:valrove/map/processing/map_processor.dart';

import '../support/test_support.dart';

void main() {
  group('SSE parser', () {
    Future<List<SseEvent>> parse(List<String> chunks) {
      final controller = StreamController<String>();
      final events = controller.stream
          .transform(const LineSplitter())
          .transform(const SseParser())
          .toList();
      chunks.forEach(controller.add);
      controller.close();
      return events;
    }

    test('parses events split across chunks, ignores comments', () async {
      final events = await parse([
        ': sse-keep-alive\n\n',
        'event: StateAttributesUpdated\nda',
        'ta: [{"a":1}]\n\n',
        'event: MapUpdated\ndata: line1\ndata: line2\n\n',
      ]);
      expect(events.map((e) => e.event), [
        'StateAttributesUpdated',
        'MapUpdated',
      ]);
      expect(events[0].data, '[{"a":1}]');
      expect(events[1].data, 'line1\nline2');
    });

    test('defaults the event name to message', () async {
      final events = await parse(['data: hi\n\n']);
      expect(events.single.event, 'message');
    });
  });

  group('Endpoint', () {
    test('normalizes user input', () {
      expect(
        ValetudoEndpoint.tryParse('192.168.1.5').toString(),
        'http://192.168.1.5/',
      );
      expect(
        ValetudoEndpoint.tryParse('robot.local:8080').toString(),
        'http://robot.local:8080/',
      );
      expect(
        ValetudoEndpoint.tryParse('https://proxy/valetudo').toString(),
        'https://proxy/valetudo/',
      );
      expect(ValetudoEndpoint.tryParse('ftp://x'), isNull);
      expect(ValetudoEndpoint.tryParse(''), isNull);
    });

    test('resolves API paths below reverse-proxy prefixes', () {
      final e = ValetudoEndpoint(baseUri: Uri.parse('https://proxy/valetudo'));
      expect(
        e.api('/robot/state').toString(),
        'https://proxy/valetudo/api/v2/robot/state',
      );
    });

    test('adds basic auth only with credentials', () {
      expect(
        ValetudoEndpoint(baseUri: Uri.parse('http://x/')).authHeaders,
        isEmpty,
      );
      final e = ValetudoEndpoint(
        baseUri: Uri.parse('http://x/'),
        username: 'u',
        password: 'p',
      );
      expect(
        e.authHeaders['authorization'],
        'Basic ${base64Encode(utf8.encode('u:p'))}',
      );
    });
  });

  group('Transport', () {
    ValetudoTransport transport(MockClientHandler handler) {
      final client = MockClient(handler);
      return ValetudoTransport(
        ValetudoEndpoint(baseUri: Uri.parse('http://robot/')),
        client: client,
        streamClient: client,
      );
    }

    test('maps HTTP errors to typed exceptions', () async {
      final t = transport(
        (r) async => switch (r.url.path) {
          '/api/v2/a' => http.Response('No credentials provided', 401),
          '/api/v2/b' => http.Response('Invalid action', 400),
          _ => http.Response(
            '{"ok":true}',
            200,
            headers: {'content-type': 'application/json'},
          ),
        },
      );
      await expectLater(
        t.get('/a'),
        throwsA(isA<ValetudoUnauthorizedException>()),
      );
      await expectLater(
        t.get('/b'),
        throwsA(
          isA<ValetudoApiException>().having(
            (e) => e.message,
            'message',
            'Invalid action',
          ),
        ),
      );
      expect(await t.get('/c'), {'ok': true});
    });

    test('reports backend updates via the commit id header', () async {
      var commit = 'one';
      final t = transport(
        (r) async =>
            http.Response('OK', 200, headers: {'x-valetudo-commit-id': commit}),
      );
      final changes = <String>[];
      t.commitIdChanges.listen(changes.add);
      await t.get('/x');
      await t.get('/x');
      commit = 'two';
      await t.get('/x');
      await Future<void>.delayed(Duration.zero);
      expect(changes, ['two']);
    });

    test('sends JSON bodies for commands', () async {
      late http.Request seen;
      final t = transport((r) async {
        seen = r;
        return http.Response('OK', 200);
      });
      await ValetudoClient(t)
          .cleanSegments(['1', '4'], iterations: 2, customOrder: true);
      expect(seen.method, 'PUT');
      expect(
        seen.url.path,
        '/api/v2/robot/capabilities/MapSegmentationCapability',
      );
      expect(jsonDecode(seen.body), {
        'action': 'start_segment_action',
        'segment_ids': ['1', '4'],
        'iterations': 2,
        'customOrder': true,
      });
    });
  });

  group('Fixtures from a real robot', () {
    test('every captured response parses', () {
      final dir = Directory('test/fixtures/l40');
      for (final file in dir.listSync().whereType<File>()) {
        expect(
          () => jsonDecode(file.readAsStringSync()),
          returnsNormally,
          reason: file.path,
        );
      }
      final caps = Capabilities.fromJson(fixtureJson('robot__capabilities'));
      expect(caps.has(Cap.mapSegmentation), isTrue);
      expect(caps.has(Cap.multipleMap), isTrue);

      final state = RobotState.fromJson(
        fixtureJson('robot__state__attributes'),
      );
      expect(state.status.value, RobotStatus.docked);
      expect(state.battery, isNotNull);
      expect(state.dockComponents.length, 4);
      expect(state.attachment('mop')?.attached, isTrue);

      final consumables = asJsonList(
        fixtureJson('robot__capabilities__ConsumableMonitoringCapability'),
      ).map(ConsumableState.fromJson);
      expect(consumables.first.unit, 'minutes');
      final timers = TimerProperties.fromJson(
        fixtureJson('timers__properties'),
      );
      expect(timers.supportedActions, contains(TimerActionType.segmentCleanup));
      final updater = UpdaterState.fromJson(fixtureJson('updater__state'));
      expect(updater.className, 'ValetudoUpdaterIdleState');
      final ntp = NtpStatus.fromJson(fixtureJson('ntpclient__status'));
      expect(ntp.offset, isNotNull);
      final maps = asJsonList(
        fixtureJson('robot__capabilities__MultipleMapCapability'),
      ).map(RobotMapEntry.fromJson).toList();
      expect(maps.single.active, isTrue);
    });

    test('map v2 compressed pixels are expanded', () {
      final map = ValetudoMap.fromJson(
        asJson(fixtureJson('robot__state__map')),
      );
      expect(map.version, 2);
      final segment = map.segments.firstWhere((s) => s.segmentId == '1');
      expect(segment.pixels.length ~/ 2, segment.pixelCount);
      expect(segment.cleanOrder, 1);
      expect(segment.material, 'wood_horizontal');
    });
  });

  group('Map processing', () {
    test('adjacent rooms get different colors', () {
      final processed = processMapJson(
        fixtureText('robot__state__map'),
        MapPalette.light,
        0,
      );
      final byId = {for (final s in processed.segments) s.id: s.colorIndex};
      // Living room (1) touches the hallway (3) and the room below (2).
      expect(byId['1'], isNot(byId['3']));
      expect(byId['1'], isNot(byId['2']));
      expect(processed.rasters.length, processed.map.layers.length);
      for (final s in processed.segments) {
        expect(
          processed.segmentAt(s.labelX, s.labelY),
          s.id,
          reason: 'label of ${s.id} lies inside its room',
        );
      }
    });
  });

  group('Shapes', () {
    test('zones convert to clockwise quads in cm', () {
      final zone = RectShape(
        kind: ShapeKind.zone,
        a: const Offset(10, 20),
        b: const Offset(4, 2),
      );
      final quad = zone.toQuad(5);
      expect(quad.pA.toJson(), {'x': 20, 'y': 10});
      expect(quad.pB.toJson(), {'x': 50, 'y': 10});
      expect(quad.pC.toJson(), {'x': 50, 'y': 100});
      expect(quad.pD.toJson(), {'x': 20, 'y': 100});
    });

    test('ramp rotation snaps to 5 degrees and keeps its size', () {
      final ramp = RampShape(
        points: const [
          Offset(0, 0),
          Offset(10, 0),
          Offset(10, 4),
          Offset(0, 4),
        ],
      );
      ramp.drag(
        HandleKind.rotate,
        const Offset(0, 1.3),
        const Offset(10, 1.3),
        minSize: 1,
      );
      ramp.settle();
      final edge = ramp.points[1] - ramp.points[0];
      expect(edge.distance, closeTo(10, 0.001));
      final degrees = edge.direction * 180 / 3.141592653589793;
      expect((degrees / 5 - (degrees / 5).round()).abs(), lessThan(1e-6));
    });

    test('restrictions round-trip through map entities', () {
      final map = ValetudoMap.fromJson({
        'metaData': {'version': 2, 'nonce': 'n'},
        'size': {'x': 1000, 'y': 1000},
        'pixelSize': 5,
        'layers': [],
        'entities': [
          {
            'type': 'virtual_wall',
            'metaData': {},
            'points': [100, 100, 300, 100],
          },
          {
            'type': 'no_mop_area',
            'metaData': {},
            'points': [100, 100, 200, 100, 200, 200, 100, 200],
          },
        ],
      });
      final shapes = restrictionShapesFromMap(map);
      expect(virtualWallsFromShapes(shapes, 5).single.toJson(), {
        'points': {
          'pA': {'x': 100, 'y': 100},
          'pB': {'x': 300, 'y': 100},
        },
      });
      expect(restrictedZonesFromShapes(shapes, 5).single.type, 'mop');
    });
  });

  group('Timers', () {
    ValetudoTimer timer(int hour, int minute, List<int> dow) => ValetudoTimer(
      id: 't',
      enabled: true,
      label: null,
      dow: dow,
      hour: hour,
      minute: minute,
      action: const TimerAction(type: TimerActionType.fullCleanup),
      preActions: const [],
    );

    test('shifting across midnight moves the weekdays', () {
      final local = shiftTimer(timer(23, 30, [0, 6]), 90);
      expect((local.hour, local.minute), (1, 0));
      expect(local.dow, [1, 0]);
      final back = shiftTimer(local, -90);
      expect((back.hour, back.minute), (23, 30));
      expect(back.dow, [0, 6]);
    });

    test('half-hour zones', () {
      final local = shiftTimer(timer(0, 15, [1]), -330);
      expect((local.hour, local.minute), (18, 45));
      expect(local.dow, [0]);
    });
  });

  group('Robot state', () {
    RobotState withStatus(String value, [String flag = 'none']) =>
        RobotState.fromJson([
          {'__class': 'StatusStateAttribute', 'value': value, 'flag': flag},
        ]);

    test('derives whether a job is in progress', () {
      // After a cancelled cleanup the map may still flag rooms as active.
      expect(withStatus('docked').job, JobState.none);
      expect(withStatus('idle').job, JobState.none);
      expect(withStatus('returning').job, JobState.none);
      expect(withStatus('cleaning', 'segment').job, JobState.running);
      expect(withStatus('paused').job, JobState.interrupted);
      // Back at the dock to wash the mops in the middle of a job.
      expect(withStatus('docked', 'resumable').job, JobState.interrupted);
    });
  });

  group('Formatting', () {
    test('durations and areas', () {
      expect(secondsToHuman(3725, showDays: false), '01h 02m 05s');
      expect(secondsToHuman(150 * 60, showSeconds: false), '0d 02h 30m');
      expect(areaFromCm2(55000, decimals: 2), '5.50 m²');
      expect(compactDuration(3900), '1 h 05 min');
      expect(bytesToHuman(1536), '1.50 KiB');
    });

    test('consumable names match the web interface', () {
      expect(consumableName('brush', 'side_left'), 'Left Brush');
      expect(consumableName('mop', 'all'), 'Mop');
      expect(consumableName('cleaning', 'sensor'), 'Sensor Cleaning');
      expect(consumableName('x', 'y'), 'Unknown consumable: x, y');
    });

    test('capability options are ordered canonically', () {
      final options = optionsFor(Cap.carpetSensorModeControl, [
        'avoid',
        'off',
        'lift',
        'detach',
      ]);
      expect(options.map((o) => o.$1), ['lift', 'avoid', 'detach', 'off']);
      expect(options.first.$2, 'Lift Mop');
    });
  });

  test('log lines are parsed with continuations', () {
    final entries = parseLog(
      '[2026-11-14T10:00:00.000Z] [INFO] Hello\n  continued\n[2026-11-14T10:00:01.000Z] [WARN] Careful',
    );
    expect(entries.length, 2);
    expect(entries[0].level, 'info');
    expect(entries[0].content, 'Hello\n  continued');
    expect(entries[1].level, 'warn');
  });
}
