import 'dart:io';

import '../valetudo/json_utils.dart';
import 'map_summary.dart';
import 'robot_files.dart';

/// An obstacle the robot photographed, kept after the map forgot it.
class FoundObstacle {
  const FoundObstacle({
    required this.id,
    required this.label,
    required this.seenAt,
    required this.x,
    required this.y,
    this.roomId,
    this.roomName,
    this.hasPhoto = false,
  });

  factory FoundObstacle.fromJson(Object? json) {
    final j = asJson(json);
    return FoundObstacle(
      id: asString(j['id']),
      label: asString(j['label'], 'Obstacle'),
      seenAt: DateTime.fromMillisecondsSinceEpoch(asInt(j['seenAt'])),
      x: asInt(j['x']),
      y: asInt(j['y']),
      roomId: asStringOrNull(j['roomId']),
      roomName: asStringOrNull(j['roomName']),
      hasPhoto: asBool(j['hasPhoto']),
    );
  }

  /// Valetudo's id of the obstacle.
  final String id;

  /// As reported, e.g. "Sock (92%)".
  final String label;
  final DateTime seenAt;

  /// Position in centimetres.
  final int x;
  final int y;
  final String? roomId;
  final String? roomName;
  final bool hasPhoto;

  /// "Sock" from "Sock (92%)".
  String get name {
    final i = label.lastIndexOf(' (');
    return i > 0 && label.endsWith('%)') ? label.substring(0, i) : label;
  }

  Json toJson() => {
    'id': id,
    'label': label,
    'seenAt': seenAt.millisecondsSinceEpoch,
    'x': x,
    'y': y,
    'roomId': ?roomId,
    'roomName': ?roomName,
    'hasPhoto': hasPhoto,
  };
}

/// Obstacles (with photos) found during cleanups, per robot.
class LostFoundStore {
  LostFoundStore(this.files);

  final RobotFiles files;
  static const _name = 'found';

  /// Older finds are dropped beyond this.
  static const maxItems = 300;

  Directory _photos(String robotId) => files.folder(robotId, 'found_photos');

  File photo(String robotId, String id) => File(
    '${_photos(robotId).path}/${id.replaceAll(RegExp('[^A-Za-z0-9_-]'), '_')}.jpg',
  );

  /// Newest first.
  Future<List<FoundObstacle>> load(String robotId) async {
    final json = await files.read(robotId, _name);
    return [for (final o in asList(json)) FoundObstacle.fromJson(o)]
      ..sort((a, b) => b.seenAt.compareTo(a.seenAt));
  }

  /// Saves the obstacles of [map] not seen before. [photoOf] fetches a
  /// photo (null when there is none).
  Future<List<FoundObstacle>> collect(
    String robotId,
    MapSummary map,
    DateTime at, {
    Future<List<int>?> Function(String id)? photoOf,
  }) async {
    final known = await load(robotId);
    final ids = {for (final o in known) o.id};
    final added = <FoundObstacle>[];
    for (final o in map.obstacleEntities) {
      final id = o.id;
      if (id == null || ids.contains(id)) continue;
      var hasPhoto = false;
      if (photoOf != null) {
        try {
          final bytes = await photoOf(id);
          if (bytes != null && bytes.isNotEmpty) {
            final file = photo(robotId, id);
            await file.parent.create(recursive: true);
            await file.writeAsBytes(bytes, flush: true);
            hasPhoto = true;
          }
        } catch (_) {
          // Saved without a photo.
        }
      }
      final room = map.roomAt(o.x, o.y);
      added.add(
        FoundObstacle(
          id: id,
          label: o.label,
          seenAt: at,
          x: o.x,
          y: o.y,
          roomId: room?.id,
          roomName: room?.displayName,
          hasPhoto: hasPhoto,
        ),
      );
    }
    if (added.isEmpty) return const [];
    final all = [...added, ...known]
      ..sort((a, b) => b.seenAt.compareTo(a.seenAt));
    for (final dropped in all.skip(maxItems)) {
      await _deletePhoto(robotId, dropped.id);
    }
    await _save(robotId, all.take(maxItems).toList());
    return added;
  }

  Future<void> delete(String robotId, String id) async {
    final all = await load(robotId)
      ..removeWhere((o) => o.id == id);
    await _deletePhoto(robotId, id);
    await _save(robotId, all);
  }

  Future<void> clear(String robotId) async {
    await files.delete(robotId, _name);
    final dir = _photos(robotId);
    if (await dir.exists()) await dir.delete(recursive: true);
  }

  Future<void> _deletePhoto(String robotId, String id) async {
    final file = photo(robotId, id);
    if (await file.exists()) await file.delete();
  }

  Future<void> _save(String robotId, List<FoundObstacle> items) =>
      files.write(robotId, _name, [for (final o in items) o.toJson()]);
}
