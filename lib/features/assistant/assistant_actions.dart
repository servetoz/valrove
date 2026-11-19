import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/cleanup/cleanup_tracker.dart' show joinNames;
import '../../core/cleanup/presets.dart';
import '../../core/cleanup/robot_files.dart';
import '../../core/persistence/robot_profile.dart';
import '../../core/persistence/stores.dart';
import '../../core/util/format.dart';
import '../../core/valetudo/capabilities.dart';
import '../../core/valetudo/client/valetudo_client.dart';
import '../../core/valetudo/models/models.dart';
import '../../state/commands.dart' show describeError;
import '../cleanup/preset_start.dart';
import '../voice/voice_commands.dart';

/// Carries out what an assistant asked Valrove's AppFunctions for (Android,
/// see `BaseValroveAppFunctionService.kt`). Works on the robot selected in
/// the app. Failures are [PlatformException]s whose code the Kotlin side
/// turns into AppFunction errors: `invalid_argument`, `not_found` or
/// `unavailable`.
class AssistantActions {
  AssistantActions({
    required this.prefs,
    required this.secrets,
    required this.files,
    ValetudoClient Function(ValetudoEndpoint endpoint)? connect,
    this.onCleaningStarted,
  }) : connect = connect ?? ValetudoClient.connect;

  final SharedPreferences prefs;
  final SecretStore secrets;
  final Future<RobotFiles> Function() files;
  final ValetudoClient Function(ValetudoEndpoint endpoint) connect;

  /// After a cleanup started, e.g. to follow it in the background.
  final Future<void> Function(String robotId)? onCleaningStarted;

  Future<Object?> handle(String method, Map<Object?, Object?> args) async {
    // The app may have changed robots or presets since the last request.
    await prefs.reload();
    final robot = await _robot();
    final client = connect(robot.endpoint);
    try {
      return await switch (method) {
        'status' => _status(client, robot),
        'rooms' => _rooms(client),
        'presets' => _presets(client, robot),
        'cleanRooms' => _cleanRooms(client, robot, args),
        'cleanHome' => _cleanHome(client, robot),
        'startPreset' => _startPreset(client, robot, args),
        'pause' => _control(client, 'pause', 'Paused the cleaning.'),
        'resume' => _control(client, 'start', 'Carrying on with the cleaning.'),
        'stop' => _control(
          client,
          'stop',
          'Stopped. The robot stays where it is.',
        ),
        'dock' => _control(client, 'home', 'Going back to the dock.'),
        'locate' => _locate(client),
        _ => throw PlatformException(
          code: 'not_implemented',
          message: 'Unknown request: $method',
        ),
      };
    } on PlatformException {
      rethrow;
    } on PresetRoomsMissing catch (e) {
      throw _invalid(e.toString());
    } on ValetudoConnectionException catch (e) {
      throw PlatformException(
        code: 'unavailable',
        message:
            "Valrove can't reach ${robot.name} (${e.message}). Is the phone "
            'on the home network?',
      );
    } catch (e) {
      throw PlatformException(code: 'unavailable', message: describeError(e));
    } finally {
      client.close();
    }
  }

  Future<RobotProfile> _robot() async {
    final repository = ProfileRepository(prefs, secrets);
    final profiles = await repository.load();
    if (profiles.isEmpty) {
      throw PlatformException(
        code: 'not_found',
        message: 'No robot is set up in Valrove yet. Open Valrove to add one.',
      );
    }
    return profiles.where((p) => p.id == repository.activeId).firstOrNull ??
        profiles.first;
  }

  static PlatformException _invalid(String message) =>
      PlatformException(code: 'invalid_argument', message: message);

  static String _roomName(Segment s) =>
      (s.name == null || s.name!.trim().isEmpty) ? 'Room ${s.id}' : s.name!;

  Future<Map<String, Object?>> _status(
    ValetudoClient c,
    RobotProfile robot,
  ) async {
    final state = await c.getStateAttributes();
    final s = state.status;
    final status = switch (s.value) {
      RobotStatus.cleaning => switch (s.flag) {
        StatusFlag.segment => 'Cleaning rooms',
        StatusFlag.zone => 'Cleaning zones',
        StatusFlag.spot => 'Spot cleaning',
        StatusFlag.mapping => 'Mapping',
        _ => 'Cleaning',
      },
      RobotStatus.docked when s.flag == StatusFlag.resumable =>
        'Docked, will resume the cleaning',
      _ => statusLabel(s.value),
    };
    return {
      'robotName': robot.name,
      'status': status,
      'batteryPercent': state.battery?.level.round(),
      'problem': s.value == RobotStatus.error
          ? (s.error?.message.isNotEmpty == true
                ? s.error!.message
                : 'The robot needs help')
          : null,
    };
  }

  Future<List<Map<String, Object?>>> _rooms(ValetudoClient c) async => [
    for (final s in await c.getSegments()) {'id': s.id, 'name': _roomName(s)},
  ];

  List<CleanupPreset> _savedPresets(RobotProfile robot) {
    final raw = prefs.getString('cleanupPresets.${robot.id}');
    if (raw == null) return const [];
    try {
      return [
        for (final p in jsonDecode(raw) as List) CleanupPreset.fromJson(p),
      ];
    } catch (_) {
      return const [];
    }
  }

  Future<List<Map<String, Object?>>> _presets(
    ValetudoClient c,
    RobotProfile robot,
  ) async {
    final presets = _savedPresets(robot);
    var names = const <String, String>{};
    try {
      names = {for (final s in await c.getSegments()) s.id: _roomName(s)};
    } catch (_) {
      // Room ids will do.
    }
    return [
      for (final p in presets)
        {
          'name': p.name,
          'summary': [
            if (p.wholeHome)
              'Whole home'
            else
              joinNames([for (final id in p.rooms) names[id] ?? 'Room $id']),
            if (!p.wholeHome && p.iterations > 1) '${p.iterations} passes',
            if (p.steps.length > 1) '${p.steps.length} steps',
            for (final v in [p.operationMode, p.fanSpeed, p.waterGrade])
              if (v != null) presetLabel(v),
          ].join(' · '),
        },
    ];
  }

  /// A cleanup can only start when the robot isn't busy with another job.
  Future<void> _ensureFree(ValetudoClient c, RobotProfile robot) async {
    final state = await c.getStateAttributes();
    if (!state.canStartAction) {
      throw _invalid(
        '${robot.name} is busy (${statusLabel(state.status.value)}). Pause, '
        'stop or send it to its dock first.',
      );
    }
  }

  Future<String> _cleanRooms(
    ValetudoClient c,
    RobotProfile robot,
    Map<Object?, Object?> args,
  ) async {
    final requested = [
      for (final r in (args['rooms'] as List?) ?? const [])
        if ('$r'.trim().isNotEmpty) '$r',
    ];
    if (requested.isEmpty) throw _invalid('Say which rooms to clean.');
    final rooms = [
      for (final s in await c.getSegments()) (id: s.id, name: _roomName(s)),
    ];
    final ids = <String>[];
    final unknown = <String>[];
    for (final name in requested) {
      final wanted = normalizeSpeech(name);
      final exact = [
        for (final r in rooms)
          if (normalizeSpeech(r.name) == wanted) r.id,
      ];
      final found = exact.isNotEmpty ? exact : findRoomsInText(name, rooms);
      if (found.isEmpty) unknown.add(name);
      for (final id in found) {
        if (!ids.contains(id)) ids.add(id);
      }
    }
    if (unknown.isNotEmpty) {
      throw _invalid(
        '${unknown.map((n) => '"$n"').join(', ')} '
        '${unknown.length == 1 ? 'is' : 'are'} not on the map. The rooms are: '
        '${rooms.map((r) => r.name).join(', ')}.',
      );
    }
    await _ensureFree(c, robot);
    final props = await c.getMapSegmentationProperties();
    final passes = ((args['passes'] as num?)?.round() ?? 1).clamp(
      1,
      props.iterationCount.max,
    );
    await c.cleanSegments(
      ids,
      iterations: passes,
      customOrder: props.customOrderSupport && ids.length > 1,
    );
    await onCleaningStarted?.call(robot.id);
    final names = {for (final r in rooms) r.id: r.name};
    return 'Cleaning ${joinNames([for (final id in ids) names[id]!], max: 6)}'
        '${passes > 1 ? ', $passes passes' : ''}.';
  }

  Future<String> _cleanHome(ValetudoClient c, RobotProfile robot) async {
    await _ensureFree(c, robot);
    await c.basicControl('start');
    await onCleaningStarted?.call(robot.id);
    return 'Cleaning the whole home.';
  }

  Future<String> _startPreset(
    ValetudoClient c,
    RobotProfile robot,
    Map<Object?, Object?> args,
  ) async {
    final wanted = normalizeSpeech('${args['name'] ?? ''}').trim();
    final presets = _savedPresets(robot);
    if (presets.isEmpty) {
      throw PlatformException(
        code: 'not_found',
        message: 'There are no presets yet. Save one in Valrove first.',
      );
    }
    final preset =
        presets
            .where((p) => normalizeSpeech(p.name).trim() == wanted)
            .firstOrNull ??
        presets.where((p) {
          final name = normalizeSpeech(p.name).trim();
          return wanted.isNotEmpty &&
              (name.contains(wanted) || wanted.contains(name));
        }).firstOrNull;
    if (preset == null) {
      throw PlatformException(
        code: 'not_found',
        message:
            'There is no preset called "${args['name']}". The presets are: '
            '${presets.map((p) => p.name).join(', ')}.',
      );
    }
    await _ensureFree(c, robot);
    final started = await startPresetWithSteps(
      c,
      preset,
      robotId: robot.id,
      files: await files(),
    );
    await onCleaningStarted?.call(robot.id);
    return started.stepCount > 1
        ? 'Started "${preset.name}", step 1 of ${started.stepCount}.'
        : 'Started "${preset.name}".';
  }

  Future<String> _control(
    ValetudoClient c,
    String action,
    String message,
  ) async {
    await c.basicControl(action);
    return message;
  }

  Future<String> _locate(ValetudoClient c) async {
    if (!(await c.getCapabilities()).has(Cap.locate)) {
      throw _invalid('This robot cannot play a sound to be found.');
    }
    await c.locate();
    return 'The robot plays a sound.';
  }
}
