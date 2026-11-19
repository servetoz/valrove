import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:valrove/core/cleanup/cleanup_record.dart';
import 'package:valrove/core/cleanup/consumable_forecast.dart';
import 'package:valrove/core/cleanup/lost_found.dart';
import 'package:valrove/core/cleanup/map_summary.dart';
import 'package:valrove/core/cleanup/presets.dart';
import 'package:valrove/core/cleanup/robot_files.dart';
import 'package:valrove/core/cleanup/sequence.dart';
import 'package:valrove/core/cleanup/wifi_coverage.dart';
import 'package:valrove/features/voice/voice_commands.dart';

import '../support/test_support.dart';

MapSummary fixtureMap({List<Map<String, Object?>> extra = const []}) {
  final json = jsonDecode(fixtureText('robot__state__map')) as Map;
  for (final layer in (json['layers'] as List).cast<Map>()) {
    final meta = layer['metaData'] as Map;
    if (meta['segmentId'] == '4') meta['name'] = 'Kitchen';
  }
  (json['entities'] as List).addAll(extra);
  return MapSummary.fromJson(json);
}

void main() {
  final t0 = DateTime(2026, 11, 15, 10);

  late Directory dir;
  late RobotFiles files;
  setUp(() {
    dir = Directory.systemTemp.createTempSync('extras');
    files = RobotFiles(dir);
  });
  tearDown(() => dir.deleteSync(recursive: true));

  group('Wi-Fi coverage', () {
    test('averages readings per 50 cm square, favouring recent ones', () {
      final c = WifiCoverage()
        ..add(120, 130, -50, t0)
        ..add(140, 149, -60, t0)
        ..add(160, 130, -80, t0);
      expect(c.cells.length, 2);
      expect(c.cells[(2, 2)]!.average, -55);
      expect(c.cells[(3, 2)]!.average, -80);
      expect(c.weakest!.average, -80);
      expect(c.centreOf(c.cells[(3, 2)]!), (175, 125));
      for (var i = 0; i < 100; i++) {
        c.add(120, 130, -40, t0);
      }
      // A moved router shows up instead of being averaged away forever.
      expect(c.cells[(2, 2)]!.average, greaterThan(-41));
    });

    test('names signal levels', () {
      expect(SignalQuality.of(-45), SignalQuality.excellent);
      expect(SignalQuality.of(-66), SignalQuality.fair);
      expect(SignalQuality.of(-79), SignalQuality.weak);
      expect(SignalQuality.of(-90), SignalQuality.poor);
    });

    test('is stored per robot', () async {
      final store = WifiCoverageStore(files);
      await store.add('r1', 3278, 3229, -61, t0);
      await store.add('r1', 3278, 3229, -63, t0);
      final back = await store.load('r1');
      expect(back.cells.values.single.average, -62);
      expect((await store.load('r2')).isEmpty, isTrue);
    });
  });

  group('Lost & found', () {
    test('keeps new obstacles with their room and photo', () async {
      final store = LostFoundStore(files);
      final map = fixtureMap(
        extra: [
          {
            'type': 'obstacle',
            'points': [3278, 3229],
            'metaData': {'id': 'o1', 'label': 'Sock (92%)'},
          },
          {
            'type': 'obstacle',
            'points': [3000, 3000],
            'metaData': {'id': 'o2', 'label': 'Cable (70%)'},
          },
        ],
      );
      final photos = <String>[];
      final added = await store.collect(
        'r1',
        map,
        t0,
        photoOf: (id) async {
          photos.add(id);
          return id == 'o1' ? [1, 2, 3] : null;
        },
      );
      expect(added.map((o) => o.id), ['o1', 'o2']);
      expect(photos, ['o1', 'o2']);
      final sock = (await store.load('r1')).firstWhere((o) => o.id == 'o1');
      expect(sock.name, 'Sock');
      expect(sock.roomName, 'Kitchen');
      expect(sock.hasPhoto, isTrue);
      expect(store.photo('r1', 'o1').readAsBytesSync(), [1, 2, 3]);

      // Seen again on the next map: nothing new, no second download.
      expect(
        await store.collect('r1', map, t0, photoOf: (id) async => [9]),
        isEmpty,
      );

      await store.delete('r1', 'o1');
      expect((await store.load('r1')).map((o) => o.id), ['o2']);
      expect(store.photo('r1', 'o1').existsSync(), isFalse);
    });
  });

  group('Presets with settings per room', () {
    const preset = CleanupPreset(
      id: 'p',
      name: 'Evening',
      rooms: ['4', '1', '2', '3'],
      operationMode: 'vacuum',
      fanSpeed: 'low',
      roomSettings: {
        '4': RoomSettings(operationMode: 'vacuum_and_mop', fanSpeed: 'max'),
        '3': RoomSettings(fanSpeed: 'max'),
      },
    );

    test('run neighbouring rooms with equal settings together', () {
      final steps = preset.steps;
      expect(
        [for (final s in steps) s.rooms],
        [
          ['4'],
          ['1', '2'],
          ['3'],
        ],
      );
      expect(steps[0].settings, ('vacuum_and_mop', 'max', null));
      expect(steps[1].settings, ('vacuum', 'low', null));
      expect(steps[2].settings, ('vacuum', 'max', null));
    });

    test('survive a JSON round trip', () {
      final back = CleanupPreset.fromJson(
        jsonDecode(jsonEncode(preset.toJson())),
      );
      expect(back.steps.length, 3);
      expect(back.roomSettings['4']!.fanSpeed, 'max');
    });

    test('without overrides they are one step', () {
      expect(
        const CleanupPreset(id: 'p', name: 'x', rooms: ['1', '2']).steps.length,
        1,
      );
    });
  });

  group('Step sequences', () {
    CleanupRecord ended(List<String> rooms, String outcome) => CleanupRecord(
      robotId: 'r1',
      startedAt: t0,
      endedAt: t0.add(const Duration(minutes: 20)),
      kind: CleanupKind.rooms,
      outcome: outcome,
      rooms: [for (final r in rooms) (id: r, name: 'Room $r')],
    );
    final sequence = PendingSequence(
      presetName: 'Evening',
      currentRooms: const ['4'],
      remaining: const [
        CleanupStep(rooms: ['1', '2'], fanSpeed: 'low'),
        CleanupStep(rooms: ['3'], fanSpeed: 'max'),
      ],
      stepNumber: 1,
      stepCount: 3,
      startedAt: t0,
    );

    test('continue with the next step after a finished one', () {
      final d = decideNextStep(
        sequence,
        ended(['4'], CleanupOutcome.finished),
        t0.add(const Duration(minutes: 25)),
      );
      expect(d, isA<SequenceContinue>());
      final next = d as SequenceContinue;
      expect(next.step.rooms, ['1', '2']);
      expect(next.stepNumber, 2);
      expect(next.next!.currentRooms, ['1', '2']);
      expect(next.next!.remaining.single.rooms, ['3']);

      final last = decideNextStep(
        next.next,
        ended(['1', '2'], CleanupOutcome.finished),
        t0.add(const Duration(minutes: 50)),
      ) as SequenceContinue;
      expect(last.step.rooms, ['3']);
      expect(last.next, isNull);
    });

    test('stop when a step was cut short', () {
      expect(
        decideNextStep(sequence, ended(['4'], CleanupOutcome.stopped), t0),
        isA<SequenceStopped>(),
      );
    });

    test("don't continue after someone else's cleanup or much later", () {
      expect(
        decideNextStep(sequence, ended(['2'], CleanupOutcome.finished), t0),
        isA<SequenceIdle>(),
      );
      expect(
        decideNextStep(
          sequence,
          ended(['4'], CleanupOutcome.finished),
          t0.add(const Duration(hours: 13)),
        ),
        isA<SequenceIdle>(),
      );
    });

    test('are stored per robot', () async {
      final store = SequenceStore(files);
      await store.save('r1', sequence);
      expect((await store.load('r1'))!.remaining.last.fanSpeed, 'max');
      await store.save('r1', null);
      expect(await store.load('r1'), isNull);
    });
  });

  group('Consumable forecast', () {
    test('learns the wear rate and counts down from now', () {
      final f = ConsumableForecasts()
        ..record([(key: 'brush.main', value: 100, unit: 'percent')], t0)
        ..record([
          (key: 'brush.main', value: 90, unit: 'percent'),
        ], t0.add(const Duration(days: 10)));
      // 1% a day, 90% left, read 5 days ago.
      expect(
        f.remaining('brush.main', now: t0.add(const Duration(days: 15))),
        const Duration(days: 85),
      );
    });

    test('estimates minute-based parts from cleaning time per day', () {
      final f = ConsumableForecasts()
        ..record([(key: 'filter.main', value: 600, unit: 'minutes')], t0);
      expect(f.remaining('filter.main', now: t0), isNull);
      expect(
        f.remaining('filter.main', cleaningMinutesPerDay: 30, now: t0),
        const Duration(days: 20),
      );
    });

    test('a replaced part starts over, and reminders go out once', () {
      final f = ConsumableForecasts()
        ..record([(key: 'brush.side', value: 20, unit: 'percent')], t0)
        ..record([
          (key: 'brush.side', value: 5, unit: 'percent'),
        ], t0.add(const Duration(days: 20)));
      // 1% a day with 5% left.
      final now = t0.add(const Duration(days: 15));
      expect(f.takeDue(now: now), ['brush.side']);
      expect(f.takeDue(now: now), isEmpty);

      f.record([
        (key: 'brush.side', value: 100, unit: 'percent'),
      ], now.add(const Duration(days: 1)));
      expect(f.tracks['brush.side']!.samples.length, 1);
      expect(f.tracks['brush.side']!.remindedAt, isNull);

      final back = ConsumableForecasts.fromJson(
        jsonDecode(jsonEncode(f.toJson())),
      );
      expect(back.tracks['brush.side']!.latest, 100);
    });

    test('measures cleaning minutes per day from the history', () {
      final now = t0.add(const Duration(days: 14));
      final history = [
        for (var d = 0; d < 14; d += 2)
          CleanupRecord(
            robotId: 'r1',
            startedAt: t0.add(Duration(days: d)),
            endedAt: t0.add(Duration(days: d, minutes: 42)),
            kind: CleanupKind.full,
            outcome: CleanupOutcome.finished,
          ),
      ];
      expect(cleaningMinutesPerDay(history, now), closeTo(21, 0.01));
    });
  });

  group('Voice commands', () {
    const rooms = <Named>[
      (id: '1', name: 'Wohnzimmer'),
      (id: '2', name: 'Küche'),
      (id: '3', name: 'Bedroom'),
      (id: '4', name: 'Bedroom 2'),
      (id: '5', name: 'Room 5'),
    ];
    const presets = <Named>[(id: 'p1', name: 'After dinner')];

    VoiceCommand parse(String text) =>
        parseVoiceCommand(text, rooms: rooms, presets: presets);

    test('clean rooms by name or by kind, in the order said', () {
      final c = parse(
        'Clean the kitchen and the living room twice',
      ) as CleanRoomsCommand;
      expect(c.roomIds, ['2', '1']);
      expect(c.iterations, 2);
      expect((parse('Küche saugen') as CleanRoomsCommand).roomIds, ['2']);
      expect((parse('clean room five') as CleanRoomsCommand).roomIds, ['5']);
    });

    test('prefer the longer room name', () {
      expect((parse('clean bedroom 2') as CleanRoomsCommand).roomIds, ['4']);
      expect((parse('clean the bedroom') as CleanRoomsCommand).roomIds, ['3']);
    });

    test('presets, the whole home and robot controls', () {
      expect((parse('Start after dinner') as RunPresetCommand).presetId, 'p1');
      expect(parse('clean everything'), isA<CleanHomeCommand>());
      expect(parse('start cleaning'), isA<CleanHomeCommand>());
      expect(parse('go back to the dock'), isA<DockCommand>());
      expect(parse('fahr nach hause'), isA<DockCommand>());
      expect(parse('pause'), isA<PauseCommand>());
      expect(parse('continue please'), isA<ResumeCommand>());
      expect(parse('stop'), isA<StopCommand>());
      expect(parse('where are you'), isA<LocateCommand>());
      expect(parse('what is the weather'), isA<UnknownCommand>());
    });
  });
}
