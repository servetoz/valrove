import '../valetudo/capabilities.dart';
import '../valetudo/client/valetudo_client.dart';
import '../valetudo/json_utils.dart';

/// Settings for one room of a preset; null keeps the preset's setting.
class RoomSettings {
  const RoomSettings({this.operationMode, this.fanSpeed, this.waterGrade});

  factory RoomSettings.fromJson(Object? json) {
    final j = asJson(json);
    return RoomSettings(
      operationMode: asStringOrNull(j['operationMode']),
      fanSpeed: asStringOrNull(j['fanSpeed']),
      waterGrade: asStringOrNull(j['waterGrade']),
    );
  }

  final String? operationMode;
  final String? fanSpeed;
  final String? waterGrade;

  bool get isEmpty =>
      operationMode == null && fanSpeed == null && waterGrade == null;

  Json toJson() => {
    'operationMode': ?operationMode,
    'fanSpeed': ?fanSpeed,
    'waterGrade': ?waterGrade,
  };
}

/// One cleanup job. A preset whose rooms need different settings runs as
/// several steps, one after the other.
class CleanupStep {
  const CleanupStep({
    required this.rooms,
    this.iterations = 1,
    this.operationMode,
    this.fanSpeed,
    this.waterGrade,
  });

  factory CleanupStep.fromJson(Object? json) {
    final j = asJson(json);
    return CleanupStep(
      rooms: asStringList(j['rooms']),
      iterations: asInt(j['iterations'], 1),
      operationMode: asStringOrNull(j['operationMode']),
      fanSpeed: asStringOrNull(j['fanSpeed']),
      waterGrade: asStringOrNull(j['waterGrade']),
    );
  }

  /// Empty for the whole home.
  final List<String> rooms;
  final int iterations;
  final String? operationMode;
  final String? fanSpeed;
  final String? waterGrade;

  (String?, String?, String?) get settings =>
      (operationMode, fanSpeed, waterGrade);

  CleanupStep withRooms(List<String> rooms) => CleanupStep(
    rooms: rooms,
    iterations: iterations,
    operationMode: operationMode,
    fanSpeed: fanSpeed,
    waterGrade: waterGrade,
  );

  Json toJson() => {
    'rooms': rooms,
    'iterations': iterations,
    'operationMode': ?operationMode,
    'fanSpeed': ?fanSpeed,
    'waterGrade': ?waterGrade,
  };
}

/// A saved cleanup: which rooms, how often and with which settings.
class CleanupPreset {
  const CleanupPreset({
    required this.id,
    required this.name,
    this.rooms = const [],
    this.iterations = 1,
    this.operationMode,
    this.fanSpeed,
    this.waterGrade,
    this.roomSettings = const {},
  });

  factory CleanupPreset.fromJson(Object? json) {
    final j = asJson(json);
    return CleanupPreset(
      id: asString(j['id']),
      name: asString(j['name'], 'Preset'),
      rooms: asStringList(j['rooms']),
      iterations: asInt(j['iterations'], 1),
      operationMode: asStringOrNull(j['operationMode']),
      fanSpeed: asStringOrNull(j['fanSpeed']),
      waterGrade: asStringOrNull(j['waterGrade']),
      roomSettings: {
        for (final MapEntry(:key, :value) in asJson(j['roomSettings']).entries)
          key: RoomSettings.fromJson(value),
      },
    );
  }

  final String id;
  final String name;

  /// Segment ids in cleaning order; empty cleans the whole home.
  final List<String> rooms;
  final int iterations;

  /// Settings applied before starting; null keeps the robot's current one.
  final String? operationMode;
  final String? fanSpeed;
  final String? waterGrade;

  /// Rooms that use other settings than the preset's.
  final Map<String, RoomSettings> roomSettings;

  bool get wholeHome => rooms.isEmpty;

  /// The jobs to run: neighbouring rooms with the same settings share one.
  List<CleanupStep> get steps {
    if (wholeHome) {
      return [
        CleanupStep(
          rooms: const [],
          operationMode: operationMode,
          fanSpeed: fanSpeed,
          waterGrade: waterGrade,
        ),
      ];
    }
    final out = <CleanupStep>[];
    for (final room in rooms) {
      final own = roomSettings[room];
      final step = CleanupStep(
        rooms: [room],
        iterations: iterations,
        operationMode: own?.operationMode ?? operationMode,
        fanSpeed: own?.fanSpeed ?? fanSpeed,
        waterGrade: own?.waterGrade ?? waterGrade,
      );
      if (out.isNotEmpty && out.last.settings == step.settings) {
        out.last = out.last.withRooms([...out.last.rooms, room]);
      } else {
        out.add(step);
      }
    }
    return out;
  }

  CleanupPreset copyWith({
    String? name,
    List<String>? rooms,
    int? iterations,
    String? Function()? operationMode,
    String? Function()? fanSpeed,
    String? Function()? waterGrade,
    Map<String, RoomSettings>? roomSettings,
  }) => CleanupPreset(
    id: id,
    name: name ?? this.name,
    rooms: rooms ?? this.rooms,
    iterations: iterations ?? this.iterations,
    operationMode: operationMode == null ? this.operationMode : operationMode(),
    fanSpeed: fanSpeed == null ? this.fanSpeed : fanSpeed(),
    waterGrade: waterGrade == null ? this.waterGrade : waterGrade(),
    roomSettings: roomSettings ?? this.roomSettings,
  );

  Json toJson() => {
    'id': id,
    'name': name,
    'rooms': rooms,
    'iterations': iterations,
    'operationMode': ?operationMode,
    'fanSpeed': ?fanSpeed,
    'waterGrade': ?waterGrade,
    if (roomSettings.isNotEmpty)
      'roomSettings': {
        for (final MapEntry(:key, :value) in roomSettings.entries)
          if (rooms.contains(key) && !value.isEmpty) key: value.toJson(),
      },
  };
}

/// None of a preset's rooms exist on the current map.
class PresetRoomsMissing implements Exception {
  const PresetRoomsMissing();

  @override
  String toString() =>
      "The preset's rooms are no longer on the map. Edit the preset.";
}

/// Starts the first step of [preset] and returns it with the steps still to
/// run (presets with per-room settings run in several steps). Rooms that no
/// longer exist (not in [existingRooms]) are skipped.
Future<({CleanupStep first, List<CleanupStep> rest})> startPreset(
  ValetudoClient client,
  CleanupPreset preset, {
  required Capabilities caps,
  required Set<String> existingRooms,
  bool customOrder = false,
}) async {
  final steps = [
    for (final step in preset.steps)
      if (step.rooms.isEmpty)
        step
      else if (step.rooms.where(existingRooms.contains).toList()
          case final rooms when rooms.isNotEmpty)
        step.withRooms(rooms),
  ];
  if (steps.isEmpty) throw const PresetRoomsMissing();
  await startStep(client, steps.first, caps: caps, customOrder: customOrder);
  return (first: steps.first, rest: steps.skip(1).toList());
}

/// Applies [step]'s settings, then starts it.
Future<void> startStep(
  ValetudoClient client,
  CleanupStep step, {
  required Capabilities caps,
  bool customOrder = false,
}) async {
  // The mode first: it decides which suction and water settings apply.
  for (final (cap, value) in [
    (Cap.operationModeControl, step.operationMode),
    (Cap.fanSpeedControl, step.fanSpeed),
    (Cap.waterUsageControl, step.waterGrade),
  ]) {
    if (value != null && caps.has(cap)) await client.setPreset(cap, value);
  }
  if (step.rooms.isEmpty) {
    await client.basicControl('start');
    return;
  }
  await client.cleanSegments(
    step.rooms,
    iterations: step.iterations,
    customOrder: customOrder && step.rooms.length > 1,
  );
}
