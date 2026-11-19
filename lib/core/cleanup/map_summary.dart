import '../valetudo/json_utils.dart';

/// A room of a [MapSummary].
class SummaryRoom {
  SummaryRoom({
    required this.id,
    required this.name,
    required this.active,
    required this.areaCm2,
    required this.runs,
  });

  final String id;
  final String? name;

  /// Marked by Valetudo as part of the running job.
  final bool active;
  final double areaCm2;

  /// Pixel rows of the room: row → flat `[x, length, x, length, …]` runs.
  final Map<int, List<int>> runs;

  String get displayName =>
      (name == null || name!.trim().isEmpty) ? 'Room $id' : name!;

  bool contains(int x, int y) {
    final row = runs[y];
    if (row == null) return false;
    for (var i = 0; i < row.length; i += 2) {
      if (x >= row[i] && x < row[i] + row[i + 1]) return true;
    }
    return false;
  }
}

/// An obstacle the robot reported on the map.
typedef MapObstacle = ({String? id, String label, int x, int y});

/// The parts of a Valetudo map the cleanup tracker needs: rooms, the robot's
/// path and obstacles. Light enough to parse on any isolate.
class MapSummary {
  MapSummary({
    required this.pixelSize,
    required this.rooms,
    required this.path,
    this.obstacleEntities = const [],
    this.robot,
  });

  factory MapSummary.fromJson(Object? json) {
    final map = asJson(json);
    final pixelSize = asInt(map['pixelSize'], 5);
    final rooms = <SummaryRoom>[];
    for (final layer in asJsonList(map['layers'])) {
      if (asString(layer['type']) != 'segment') continue;
      final meta = asJson(layer['metaData']);
      final id = asStringOrNull(meta['segmentId']);
      if (id == null) continue;
      final pixels = asList(layer['compressedPixels']);
      final runs = <int, List<int>>{};
      for (var i = 0; i + 2 < pixels.length; i += 3) {
        final x = asInt(pixels[i]);
        final y = asInt(pixels[i + 1]);
        (runs[y] ??= []).addAll([x, asInt(pixels[i + 2])]);
      }
      rooms.add(
        SummaryRoom(
          id: id,
          name: asStringOrNull(meta['name']),
          active: asBool(meta['active']),
          areaCm2: asDouble(meta['area']),
          runs: runs,
        ),
      );
    }
    final path = <int>[];
    final obstacles = <MapObstacle>[];
    ({int x, int y})? robot;
    for (final entity in asJsonList(map['entities'])) {
      final type = asString(entity['type']);
      final points = asList(entity['points']);
      if (type == 'path') {
        for (final p in points) {
          path.add(asInt(p));
        }
      } else if (type == 'obstacle' && points.length >= 2) {
        final meta = asJson(entity['metaData']);
        obstacles.add((
          id: asStringOrNull(meta['id']),
          label: asStringOrNull(meta['label']) ?? 'Obstacle',
          x: asInt(points[0]),
          y: asInt(points[1]),
        ));
      } else if (type == 'robot_position' && points.length >= 2) {
        robot = (x: asInt(points[0]), y: asInt(points[1]));
      }
    }
    return MapSummary(
      pixelSize: pixelSize,
      rooms: rooms,
      path: path,
      obstacleEntities: obstacles,
      robot: robot,
    );
  }

  /// Centimetres per map pixel.
  final int pixelSize;
  final List<SummaryRoom> rooms;

  /// Robot path as flat `[x, y, x, y, …]` centimetres.
  final List<int> path;

  final List<MapObstacle> obstacleEntities;

  /// Where the robot is, in centimetres.
  final ({int x, int y})? robot;

  /// Labels of the obstacles on the map ("Sock (92%)").
  List<String> get obstacles => [for (final o in obstacleEntities) o.label];

  SummaryRoom? room(String id) => rooms.where((r) => r.id == id).firstOrNull;

  /// The room containing the point [x], [y] (centimetres).
  SummaryRoom? roomAt(int x, int y) {
    final px = x ~/ pixelSize;
    final py = y ~/ pixelSize;
    return rooms.where((r) => r.contains(px, py)).firstOrNull;
  }

  /// How many points of [path] (centimetres) lie in each room.
  Map<String, int> pathPointsPerRoom([List<int>? path]) {
    final points = path ?? this.path;
    final counts = <String, int>{};
    for (var i = 0; i + 1 < points.length; i += 2) {
      final x = points[i] ~/ pixelSize;
      final y = points[i + 1] ~/ pixelSize;
      for (final room in rooms) {
        if (room.contains(x, y)) {
          counts[room.id] = (counts[room.id] ?? 0) + 1;
          break;
        }
      }
    }
    return counts;
  }
}

/// Thins a flat `[x, y, …]` polyline to at most [maxPoints] points, keeping
/// the first and last one.
List<int> thinPath(List<int> path, {int maxPoints = 1500}) {
  final n = path.length ~/ 2;
  if (n <= maxPoints) return List.of(path);
  final out = <int>[];
  for (var i = 0; i < maxPoints; i++) {
    final j = (i * (n - 1) / (maxPoints - 1)).round();
    out
      ..add(path[j * 2])
      ..add(path[j * 2 + 1]);
  }
  return out;
}
