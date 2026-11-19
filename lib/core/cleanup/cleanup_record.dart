import '../valetudo/json_utils.dart';

/// What a cleanup was started as.
abstract final class CleanupKind {
  static const full = 'full';
  static const rooms = 'rooms';
  static const zones = 'zones';
  static const spot = 'spot';
  static const mapping = 'mapping';

  static String fromStatusFlag(String flag) => switch (flag) {
    'segment' => rooms,
    'zone' => zones,
    'spot' => spot,
    'mapping' => mapping,
    _ => full,
  };
}

/// How a cleanup ended.
abstract final class CleanupOutcome {
  /// The robot went back to its dock on its own.
  static const finished = 'finished';

  /// Stopped before the robot returned (by the user or another client).
  static const stopped = 'stopped';

  /// Ended while the robot reported an error.
  static const error = 'error';
}

/// One cleanup, as recorded on this phone.
class CleanupRecord {
  const CleanupRecord({
    required this.robotId,
    required this.startedAt,
    required this.endedAt,
    required this.kind,
    required this.outcome,
    this.cleaningSeconds,
    this.areaCm2,
    this.rooms = const [],
    this.roomAreaCm2 = 0,
    this.batteryStart,
    this.batteryEnd,
    this.recharged = false,
    this.operationMode,
    this.fanSpeed,
    this.error,
    this.pixelSize = 5,
    this.path = const [],
    this.obstacles = const [],
  });

  factory CleanupRecord.fromJson(Object? json) {
    final j = asJson(json);
    return CleanupRecord(
      robotId: asString(j['robotId']),
      startedAt: DateTime.fromMillisecondsSinceEpoch(asInt(j['startedAt'])),
      endedAt: DateTime.fromMillisecondsSinceEpoch(asInt(j['endedAt'])),
      kind: asString(j['kind'], CleanupKind.full),
      outcome: asString(j['outcome'], CleanupOutcome.finished),
      cleaningSeconds: asIntOrNull(j['cleaningSeconds']),
      areaCm2: asNumOrNull(j['areaCm2'])?.toDouble(),
      rooms: [
        for (final r in asJsonList(j['rooms']))
          (id: asString(r['id']), name: asString(r['name'])),
      ],
      roomAreaCm2: asDouble(j['roomAreaCm2']),
      batteryStart: asIntOrNull(j['batteryStart']),
      batteryEnd: asIntOrNull(j['batteryEnd']),
      recharged: asBool(j['recharged']),
      operationMode: asStringOrNull(j['operationMode']),
      fanSpeed: asStringOrNull(j['fanSpeed']),
      error: asStringOrNull(j['error']),
      pixelSize: asInt(j['pixelSize'], 5),
      path: [for (final p in asList(j['path'])) asInt(p)],
      obstacles: asStringList(j['obstacles']),
    );
  }

  final String robotId;
  final DateTime startedAt;
  final DateTime endedAt;

  /// A [CleanupKind].
  final String kind;

  /// A [CleanupOutcome].
  final String outcome;

  /// Cleaning time the robot reported (excludes charging breaks).
  final int? cleaningSeconds;

  /// Area the robot reported as cleaned.
  final double? areaCm2;
  final List<({String id, String name})> rooms;

  /// Map area of [rooms]; what estimates are based on.
  final double roomAreaCm2;
  final int? batteryStart;
  final int? batteryEnd;

  /// The robot charged in between (its battery use says little then).
  final bool recharged;
  final String? operationMode;
  final String? fanSpeed;

  /// Last error the robot reported during the cleanup.
  final String? error;

  /// Centimetres per map pixel, for drawing [path].
  final int pixelSize;

  /// Path as flat `[x, y, …]` centimetres (thinned).
  final List<int> path;
  final List<String> obstacles;

  String get id => '${robotId}_${startedAt.millisecondsSinceEpoch}';

  Duration get wallTime => endedAt.difference(startedAt);

  /// Time spent cleaning: the robot's figure, else the time it took.
  Duration get duration => cleaningSeconds != null && cleaningSeconds! > 0
      ? Duration(seconds: cleaningSeconds!)
      : wallTime;

  Json toJson() => {
    'robotId': robotId,
    'startedAt': startedAt.millisecondsSinceEpoch,
    'endedAt': endedAt.millisecondsSinceEpoch,
    'kind': kind,
    'outcome': outcome,
    'cleaningSeconds': ?cleaningSeconds,
    'areaCm2': ?areaCm2,
    'rooms': [
      for (final r in rooms) {'id': r.id, 'name': r.name},
    ],
    'roomAreaCm2': roomAreaCm2,
    'batteryStart': ?batteryStart,
    'batteryEnd': ?batteryEnd,
    'recharged': recharged,
    'operationMode': ?operationMode,
    'fanSpeed': ?fanSpeed,
    'error': ?error,
    'pixelSize': pixelSize,
    'path': path,
    'obstacles': obstacles,
  };
}
