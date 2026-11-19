import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:valrove/core/cleanup/cleanup_record.dart';
import 'package:valrove/core/cleanup/cleanup_tracker.dart';
import 'package:valrove/core/cleanup/estimator.dart';
import 'package:valrove/core/cleanup/history_store.dart';
import 'package:valrove/core/cleanup/map_summary.dart';
import 'package:valrove/core/cleanup/presets.dart';
import 'package:valrove/core/valetudo/capabilities.dart';
import 'package:valrove/core/valetudo/client/valetudo_client.dart';
import 'package:valrove/core/valetudo/models/models.dart';

import '../support/fake_robot.dart';
import '../support/test_support.dart';

RobotState robot(
  String status, {
  String flag = 'none',
  int battery = 80,
  String? error,
  String mode = 'vacuum',
}) => RobotState.fromJson([
  {
    '__class': 'StatusStateAttribute',
    'value': status,
    'flag': flag,
    if (error != null)
      'error': {
        'severity': {'kind': 'transient', 'level': 'error'},
        'subsystem': 'motors',
        'message': error,
      },
  },
  {'__class': 'BatteryStateAttribute', 'level': battery, 'flag': 'none'},
  {
    '__class': 'PresetSelectionStateAttribute',
    'type': 'operation_mode',
    'value': mode,
  },
]);

/// The fixture map with room 4 named "Kitchen", [active] rooms and a [path].
MapSummary map({Set<String> active = const {}, List<int> path = const []}) {
  final json = jsonDecode(fixtureText('robot__state__map')) as Map;
  for (final layer in (json['layers'] as List).cast<Map>()) {
    final meta = layer['metaData'] as Map;
    if (meta['segmentId'] == '4') meta['name'] = 'Kitchen';
    if (active.contains(meta['segmentId'])) meta['active'] = true;
  }
  (json['entities'] as List).add({
    '__class': 'PathMapEntity',
    'type': 'path',
    'metaData': {},
    'points': path,
  });
  return MapSummary.fromJson(json);
}

void main() {
  final t0 = DateTime(2026, 11, 15, 10);
  DateTime at(int minutes) => t0.add(Duration(minutes: minutes));

  group('Map summary', () {
    test('reads rooms, their area and finds which room a point is in', () {
      final m = map(active: {'4'});
      expect(m.rooms.map((r) => r.id), ['1', '2', '3', '4']);
      expect(m.room('4')!.displayName, 'Kitchen');
      expect(m.room('1')!.displayName, 'Room 1');
      expect(m.room('4')!.active, isTrue);
      expect(m.room('1')!.areaCm2, 57900);
      // The robot's position in the fixture is in room 4.
      expect(m.pathPointsPerRoom([3278, 3229]), {'4': 1});
    });

    test('thins long paths to the requested number of points', () {
      final path = [for (var i = 0; i < 10000; i++) i];
      final thin = thinPath(path, maxPoints: 100);
      expect(thin.length, 200);
      expect(thin.take(2), [0, 1]);
      expect(thin.skip(198), [9998, 9999]);
    });
  });

  group('Cleanup tracker', () {
    test('follows a room cleanup from start to the dock', () {
      final tracker = CleanupTracker(robotId: 'r1');
      expect(
        tracker.add(CleanupSample(at: at(0), state: robot('docked'))).ongoing,
        isNull,
      );
      expect(tracker.tracking, isFalse);

      var u = tracker.add(
        CleanupSample(
          at: at(1),
          state: robot('cleaning', flag: 'segment', battery: 90),
          map: map(active: {'4'}),
          events: const [],
        ),
      );
      expect(u.ongoing!.title, 'Cleaning · Kitchen');
      expect(u.ongoing!.actions, [CleanupAction.pause, CleanupAction.dock]);

      u = tracker.add(
        CleanupSample(
          at: at(11),
          state: robot('cleaning', flag: 'segment', battery: 82),
          areaCm2: 120000,
          seconds: 600,
        ),
      );
      expect(u.ongoing!.text, '12.0 m² · 10 min · Battery 82%');

      u = tracker.add(
        CleanupSample(
          at: at(12),
          state: robot('cleaning', flag: 'segment', battery: 81),
          events: [
            ValetudoEvent.fromJson({
              '__class': 'DustBinFullValetudoEvent',
              'id': 'dust_bin_full',
              'timestamp': '2026-11-15T10:12:00Z',
              'processed': false,
            }),
          ],
        ),
      );
      expect(u.alerts.single.title, 'Dust bin full');

      u = tracker.add(
        CleanupSample(
          at: at(13),
          state: robot('error', battery: 80, error: 'Wheel stuck'),
        ),
      );
      expect(u.alerts.single.body, 'Wheel stuck');
      expect(u.ongoing!.title, 'Robot needs help');
      expect(u.ongoing!.actions, [CleanupAction.dock]);
      // The same error is announced once.
      u = tracker.add(
        CleanupSample(
          at: at(14),
          state: robot('error', battery: 80, error: 'Wheel stuck'),
        ),
      );
      expect(u.alerts, isEmpty);

      tracker.add(
        CleanupSample(
          at: at(15),
          state: robot('cleaning', flag: 'segment'),
        ),
      );
      u = tracker.add(
        CleanupSample(at: at(20), state: robot('returning', battery: 75)),
      );
      expect(u.ongoing!.title, 'Returning to the dock');
      u = tracker.add(
        CleanupSample(at: at(21), state: robot('docked', battery: 75)),
      );
      expect(u.ended, isTrue);

      final record = tracker.finish(
        map: map(active: {'4'}, path: [3278, 3229, 3280, 3230]),
      )!;
      expect(record.kind, CleanupKind.rooms);
      expect(record.outcome, CleanupOutcome.finished);
      expect(record.startedAt, at(1));
      expect(record.endedAt, at(21));
      expect(record.rooms, [(id: '4', name: 'Kitchen')]);
      expect(record.roomAreaCm2, 167250);
      expect(record.cleaningSeconds, 600);
      expect(record.batteryStart, 90);
      expect(record.batteryEnd, 75);
      expect(record.recharged, isFalse);
      expect(record.operationMode, 'vacuum');
      expect(record.error, 'Wheel stuck');
      expect(record.path, [3278, 3229, 3280, 3230]);
      expect(tracker.tracking, isFalse);

      final alert = CleanupTracker.finishedAlert(record);
      expect(alert.title, 'Cleaning finished');
      expect(alert.body, 'Kitchen · 12.0 m² · in 10 min');
    });

    test('a cleanup stopped on the spot counts as stopped, for all rooms', () {
      final tracker = CleanupTracker(robotId: 'r1');
      tracker.add(
        CleanupSample(at: at(0), state: robot('cleaning'), map: map()),
      );
      expect(
        tracker.add(CleanupSample(at: at(5), state: robot('idle'))).ended,
        isTrue,
      );
      final record = tracker.finish()!;
      expect(record.kind, CleanupKind.full);
      expect(record.outcome, CleanupOutcome.stopped);
      expect(record.rooms.map((r) => r.id), ['1', '2', '3', '4']);
      expect(CleanupTracker.finishedAlert(record).title, 'Cleaning stopped');
    });

    test('a recharge in the middle does not end the cleanup', () {
      final tracker = CleanupTracker(robotId: 'r1');
      tracker.add(
        CleanupSample(at: at(0), state: robot('cleaning', battery: 30)),
      );
      var u = tracker.add(
        CleanupSample(
          at: at(30),
          state: robot('returning', flag: 'resumable', battery: 15),
        ),
      );
      expect(u.ongoing!.title, 'Returning to recharge');
      u = tracker.add(
        CleanupSample(
          at: at(31),
          state: robot('docked', flag: 'resumable', battery: 16),
        ),
      );
      expect(u.ended, isFalse);
      expect(u.ongoing!.title, 'Charging · resumes when charged');
      expect(u.ongoing!.actions, [CleanupAction.resume]);
      tracker
        ..add(CleanupSample(at: at(90), state: robot('cleaning', battery: 80)))
        ..add(
          CleanupSample(at: at(100), state: robot('returning', battery: 70)),
        );
      expect(
        tracker.add(CleanupSample(at: at(101), state: robot('docked'))).ended,
        isTrue,
      );
      final record = tracker.finish()!;
      expect(record.outcome, CleanupOutcome.finished);
      expect(record.recharged, isTrue);
    });

    test('a cleanup never resumed after a long wait counts as stopped', () {
      final tracker = CleanupTracker(robotId: 'r1');
      tracker
        ..add(CleanupSample(at: at(0), state: robot('cleaning')))
        ..add(
          CleanupSample(
            at: at(10),
            state: robot('docked', flag: 'resumable'),
          ),
        );
      expect(
        tracker
            .add(
              CleanupSample(
                at: at(10 + 6 * 60),
                state: robot('docked', flag: 'resumable'),
              ),
            )
            .ended,
        isTrue,
      );
      expect(tracker.finish()!.outcome, CleanupOutcome.stopped);
    });

    test('joining a running cleanup counts back its time', () {
      final tracker = CleanupTracker(robotId: 'r1');
      tracker.add(
        CleanupSample(at: at(30), state: robot('cleaning'), seconds: 600),
      );
      tracker.add(CleanupSample(at: at(31), state: robot('idle')));
      expect(tracker.finish()!.startedAt, at(20));
    });

    test('zone cleanups list the rooms the robot spent its time in', () {
      final tracker = CleanupTracker(robotId: 'r1');
      tracker
        ..add(
          CleanupSample(
            at: at(0),
            state: robot('cleaning', flag: 'zone'),
          ),
        )
        ..add(CleanupSample(at: at(5), state: robot('returning')))
        ..add(CleanupSample(at: at(6), state: robot('docked')));
      // Nine points in room 4, one passing through room 1.
      final path = [
        for (var i = 0; i < 9; i++) ...[3278 + i, 3229],
        3200,
        2900,
      ];
      final m = map(path: path);
      expect(m.pathPointsPerRoom()['4'], 9);
      final record = tracker.finish(map: m)!;
      expect(record.kind, CleanupKind.zones);
      expect(record.rooms.map((r) => r.id), ['4']);
    });

    test('events that were there before are not announced', () {
      final tracker = CleanupTracker(robotId: 'r1');
      final old = ValetudoEvent.fromJson({
        '__class': 'DustBinFullValetudoEvent',
        'id': 'dust_bin_full',
        'timestamp': '2026-11-15T09:00:00Z',
        'processed': false,
      });
      expect(
        tracker
            .add(
              CleanupSample(at: at(0), state: robot('cleaning'), events: [old]),
            )
            .alerts,
        isEmpty,
      );
      expect(
        tracker
            .add(
              CleanupSample(at: at(1), state: robot('cleaning'), events: [old]),
            )
            .alerts,
        isEmpty,
      );
    });
  });

  group('Estimates', () {
    CleanupRecord run({
      double m2 = 20,
      int minutes = 20,
      int batteryStart = 100,
      int batteryEnd = 80,
      String mode = 'vacuum',
    }) => CleanupRecord(
      robotId: 'r1',
      startedAt: t0,
      endedAt: t0.add(Duration(minutes: minutes)),
      kind: CleanupKind.rooms,
      outcome: CleanupOutcome.finished,
      roomAreaCm2: m2 * 10000,
      batteryStart: batteryStart,
      batteryEnd: batteryEnd,
      operationMode: mode,
    );

    test('uses typical values until cleanups are recorded', () {
      final e = CleanupEstimator(const []).estimate(roomAreaCm2: 100000);
      expect(e.duration, const Duration(minutes: 8));
      expect(e.batteryPercent, 4);
      expect(e.basedOn, 0);
      expect(
        CleanupEstimator(const [])
            .estimate(roomAreaCm2: 90000, operationMode: 'vacuum_and_mop')
            .duration,
        const Duration(minutes: 10),
      );
    });

    test('learns speed and battery use from recorded cleanups', () {
      final e = CleanupEstimator([run(), run()])
          .estimate(roomAreaCm2: 100000, iterations: 2);
      expect(e.duration, const Duration(minutes: 20));
      expect(e.batteryPercent, 20);
      expect(e.basedOn, 2);
      expect(e.label, '≈ 20 min · 20% battery');
    });

    test('prefers cleanups in the same mode', () {
      final e = CleanupEstimator([
        run(mode: 'mop', minutes: 40),
        run(mode: 'mop', minutes: 40),
        run(),
      ]).estimate(roomAreaCm2: 200000, operationMode: 'mop');
      expect(e.duration, const Duration(minutes: 40));
    });

    test('knows when each room was cleaned last', () {
      final older = CleanupRecord(
        robotId: 'r1',
        startedAt: t0,
        endedAt: at(30),
        kind: CleanupKind.rooms,
        outcome: CleanupOutcome.finished,
        rooms: const [(id: '1', name: 'Room 1'), (id: '4', name: 'Kitchen')],
      );
      final newer = CleanupRecord(
        robotId: 'r1',
        startedAt: at(60),
        endedAt: at(90),
        kind: CleanupKind.rooms,
        outcome: CleanupOutcome.finished,
        rooms: const [(id: '4', name: 'Kitchen')],
      );
      final aborted = CleanupRecord(
        robotId: 'r1',
        startedAt: at(100),
        endedAt: at(101),
        kind: CleanupKind.rooms,
        outcome: CleanupOutcome.stopped,
        rooms: const [(id: '1', name: 'Room 1')],
      );
      expect(lastCleaned([aborted, newer, older]), {'4': at(90), '1': at(30)});
    });
  });

  group('History store', () {
    late Directory dir;
    setUp(() => dir = Directory.systemTemp.createTempSync('history'));
    tearDown(() => dir.deleteSync(recursive: true));

    CleanupRecord rec(int minute) => CleanupRecord(
      robotId: 'robot-1',
      startedAt: at(minute),
      endedAt: at(minute + 10),
      kind: CleanupKind.full,
      outcome: CleanupOutcome.finished,
      areaCm2: 1000,
      rooms: const [(id: '4', name: 'Kitchen')],
      path: const [1, 2, 3, 4],
      obstacles: const ['Sock'],
    );

    test('keeps cleanups newest first and survives a round trip', () async {
      final store = HistoryStore(dir);
      await store.add(rec(0));
      await store.add(rec(60));
      await store.add(rec(30));
      final loaded = await store.load('robot-1');
      expect(loaded.map((r) => r.startedAt), [at(60), at(30), at(0)]);
      final r = loaded.last;
      expect(r.rooms, [(id: '4', name: 'Kitchen')]);
      expect(r.path, [1, 2, 3, 4]);
      expect(r.obstacles, ['Sock']);
      expect(r.areaCm2, 1000);

      await store.delete('robot-1', loaded.first.id);
      expect((await store.load('robot-1')).length, 2);
      expect(await store.load('other'), isEmpty);
    });

    test('a damaged file reads as empty', () async {
      File('${dir.path}/cleanups_robot-1.json').writeAsStringSync('{oops');
      expect(await HistoryStore(dir).load('robot-1'), isEmpty);
    });
  });

  group('Presets', () {
    late FixtureHttpClient fake;
    late ValetudoClient client;
    setUp(() {
      fake = FixtureHttpClient();
      client = ValetudoClient(
        ValetudoTransport(
          ValetudoEndpoint(baseUri: Uri.parse('http://robot/')),
          client: fake,
          streamClient: fake,
        ),
      );
    });

    List<List<Object?>> sent() => [
      for (final r in fake.requests.whereType<http.Request>())
        if (r.method == 'PUT') [r.url.path.split('/').last, jsonDecode(r.body)],
    ];

    const caps = Capabilities({
      Cap.operationModeControl,
      Cap.fanSpeedControl,
      Cap.mapSegmentation,
      Cap.basicControl,
    });

    test('apply their settings, then clean the rooms in order', () async {
      const preset = CleanupPreset(
        id: 'p',
        name: 'After dinner',
        rooms: ['4', '9', '1'],
        iterations: 2,
        operationMode: 'vacuum',
        fanSpeed: 'max',
        waterGrade: 'high', // not supported by these capabilities
      );
      await startPreset(
        client,
        preset,
        caps: caps,
        existingRooms: {'1', '2', '3', '4'},
        customOrder: true,
      );
      expect(sent(), [
        [
          'preset',
          {'name': 'vacuum'},
        ],
        [
          'preset',
          {'name': 'max'},
        ],
        [
          'MapSegmentationCapability',
          {
            'action': 'start_segment_action',
            'segment_ids': ['4', '1'],
            'iterations': 2,
            'customOrder': true,
          },
        ],
      ]);
      expect(
        fake.requests.map((r) => r.url.path.split('/').reversed.skip(1).first),
        containsAllInOrder([
          'OperationModeControlCapability',
          'FanSpeedControlCapability',
        ]),
      );
    });

    test('without rooms they clean the whole home', () async {
      await startPreset(
        client,
        const CleanupPreset(id: 'p', name: 'Everything'),
        caps: caps,
        existingRooms: const {},
      );
      expect(sent(), [
        [
          'BasicControlCapability',
          {'action': 'start'},
        ],
      ]);
    });

    test('fail clearly when their rooms are gone', () {
      expect(
        startPreset(
          client,
          const CleanupPreset(id: 'p', name: 'Old', rooms: ['9']),
          caps: caps,
          existingRooms: {'1'},
        ),
        throwsA(isA<PresetRoomsMissing>()),
      );
    });

    test('survive a JSON round trip', () {
      const p = CleanupPreset(
        id: 'p',
        name: 'Kitchen twice',
        rooms: ['4'],
        iterations: 2,
        fanSpeed: 'max',
      );
      final back = CleanupPreset.fromJson(jsonDecode(jsonEncode(p.toJson())));
      expect(back.toJson(), p.toJson());
      expect(back.operationMode, isNull);
    });
  });
}
