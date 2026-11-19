import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:valrove/core/cleanup/presets.dart';
import 'package:valrove/core/cleanup/robot_files.dart';
import 'package:valrove/core/cleanup/sequence.dart';
import 'package:valrove/core/persistence/stores.dart';
import 'package:valrove/core/valetudo/client/valetudo_client.dart';
import 'package:valrove/features/assistant/assistant_actions.dart';

import '../support/fake_robot.dart';
import '../support/test_support.dart';
import '../widget/interaction_test.dart' show puts;

/// Fails every request like an unreachable robot.
class _Offline extends http.BaseClient {
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) =>
      Future.error(const SocketException('No route to host'));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory dir;
  late List<String> started;
  setUp(() {
    dir = Directory.systemTemp.createTempSync('assistant');
    started = [];
  });
  tearDown(() => dir.deleteSync(recursive: true));

  Future<AssistantActions> actions(
    http.Client http, {
    List<CleanupPreset> presets = const [],
    bool withRobot = true,
  }) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final secrets = MemorySecretStore();
    if (withRobot) {
      final repository = ProfileRepository(prefs, secrets);
      await repository.save([testProfile]);
      await repository.setActiveId(testProfile.id);
    }
    if (presets.isNotEmpty) {
      await prefs.setString(
        'cleanupPresets.${testProfile.id}',
        jsonEncode([for (final p in presets) p.toJson()]),
      );
    }
    return AssistantActions(
      prefs: prefs,
      secrets: secrets,
      files: () async => RobotFiles(dir),
      connect: (endpoint) => ValetudoClient(
        ValetudoTransport(endpoint, client: http, streamClient: http),
      ),
      onCleaningStarted: (robotId) async => started.add(robotId),
    );
  }

  /// The fixture robot with named rooms (and optionally another status).
  FixtureHttpClient robot({String status = 'docked'}) {
    final attributes =
        jsonDecode(fixtureText('robot__state__attributes')) as List;
    for (final a in attributes.cast<Map<String, dynamic>>()) {
      if (a['__class'] == 'StatusStateAttribute') a['value'] = status;
    }
    return FixtureHttpClient(
      overrides: {
        'robot/state/attributes': attributes,
        'robot/capabilities/MapSegmentationCapability': [
          {'id': '1', 'name': 'Wohnzimmer'},
          {'id': '2', 'name': 'Küche'},
          {'id': '3', 'name': 'Bedroom'},
          {'id': '4'},
        ],
      },
    );
  }

  Matcher failsWith(String code, [String? containing]) => throwsA(
    isA<PlatformException>()
        .having((e) => e.code, 'code', code)
        .having((e) => e.message, 'message', contains(containing ?? '')),
  );

  test('reports the robot and its rooms', () async {
    final a = await actions(robot());
    expect(await a.handle('status', const {}), {
      'robotName': 'L40 Ultra',
      'status': 'Docked',
      'batteryPercent': 74,
      'problem': null,
    });
    expect(await a.handle('rooms', const {}), [
      {'id': '1', 'name': 'Wohnzimmer'},
      {'id': '2', 'name': 'Küche'},
      {'id': '3', 'name': 'Bedroom'},
      {'id': '4', 'name': 'Room 4'},
    ]);
  });

  test('cleans rooms named like the user says them', () async {
    final fake = robot();
    final a = await actions(fake);
    final message = await a.handle('cleanRooms', {
      'rooms': ['kitchen', 'living room', 'room four'],
      'passes': 2,
    });
    expect(message, 'Cleaning Küche, Wohnzimmer, Room 4, 2 passes.');
    expect(puts(fake, '/MapSegmentationCapability'), [
      {
        'action': 'start_segment_action',
        'segment_ids': ['2', '1', '4'],
        'iterations': 2,
        'customOrder': true,
      },
    ]);
    expect(started, ['test']);
  });

  test('names the rooms when one is unknown, and sends nothing', () async {
    final fake = robot();
    final a = await actions(fake);
    await expectLater(
      a.handle('cleanRooms', {
        'rooms': ['garage'],
      }),
      failsWith(
        'invalid_argument',
        '"garage" is not on the map. The rooms are: Wohnzimmer, Küche, '
            'Bedroom, Room 4.',
      ),
    );
    expect(puts(fake, '/MapSegmentationCapability'), isEmpty);
  });

  test("doesn't start a cleanup while the robot is busy", () async {
    final fake = robot(status: 'cleaning');
    final a = await actions(fake);
    await expectLater(
      a.handle('cleanHome', const {}),
      failsWith('invalid_argument', 'L40 Ultra is busy (Cleaning)'),
    );
    expect(puts(fake, '/BasicControlCapability'), isEmpty);
    expect(started, isEmpty);
  });

  test('starts presets by name, step by step', () async {
    final fake = robot();
    final a = await actions(
      fake,
      presets: const [
        CleanupPreset(
          id: 'p',
          name: 'After dinner',
          rooms: ['2', '1'],
          fanSpeed: 'low',
          roomSettings: {'2': RoomSettings(fanSpeed: 'max')},
        ),
      ],
    );
    expect(await a.handle('presets', const {}), [
      {'name': 'After dinner', 'summary': 'Küche, Wohnzimmer · 2 steps · Low'},
    ]);
    expect(
      await a.handle('startPreset', {'name': 'after dinner'}),
      'Started "After dinner", step 1 of 2.',
    );
    expect(puts(fake, '/FanSpeedControlCapability/preset'), [
      {'name': 'max'},
    ]);
    expect(puts(fake, '/MapSegmentationCapability').single['segment_ids'], [
      '2',
    ]);
    final pending = await SequenceStore(RobotFiles(dir)).load('test');
    expect(pending!.remaining.single.rooms, ['1']);

    await expectLater(
      a.handle('startPreset', {'name': 'breakfast'}),
      failsWith('not_found', 'The presets are: After dinner.'),
    );
  });

  test('controls the robot', () async {
    final fake = robot(status: 'cleaning');
    final a = await actions(fake);
    expect(await a.handle('pause', const {}), 'Paused the cleaning.');
    expect(await a.handle('dock', const {}), 'Going back to the dock.');
    expect(puts(fake, '/BasicControlCapability'), [
      {'action': 'pause'},
      {'action': 'home'},
    ]);
  });

  test('explains a missing robot or an unreachable one', () async {
    await expectLater(
      (await actions(robot(), withRobot: false)).handle('status', const {}),
      failsWith('not_found', 'No robot is set up'),
    );
    await expectLater(
      (await actions(_Offline())).handle('status', const {}),
      failsWith('unavailable', "Valrove can't reach L40 Ultra"),
    );
  });
}
