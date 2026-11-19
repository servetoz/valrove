import 'dart:typed_data';

import '../json_utils.dart';

abstract final class MapLayerType {
  static const floor = 'floor';
  static const segment = 'segment';
  static const wall = 'wall';
}

abstract final class MapEntityType {
  static const chargerLocation = 'charger_location';
  static const robotPosition = 'robot_position';
  static const goToTarget = 'go_to_target';
  static const obstacle = 'obstacle';
  static const path = 'path';
  static const predictedPath = 'predicted_path';
  static const virtualWall = 'virtual_wall';
  static const noGoArea = 'no_go_area';
  static const noMopArea = 'no_mop_area';
  static const activeZone = 'active_zone';
  static const carpet = 'carpet';
  static const threshold = 'threshold';
  static const curtain = 'curtain';
  static const ramp = 'ramp';
}

/// Floor materials (`MapSegmentMaterialControlCapability`).
abstract final class SegmentMaterial {
  static const generic = 'generic';
  static const tile = 'tile';
  static const wood = 'wood';
  static const woodHorizontal = 'wood_horizontal';
  static const woodVertical = 'wood_vertical';
  static const carpet = 'carpet';
  static const carpetLow = 'carpet_low';
  static const carpetHigh = 'carpet_high';

  static String label(String material) => switch (material) {
    generic => 'Generic',
    tile => 'Tile',
    wood => 'Wood',
    woodHorizontal => 'Wood (Horizontal)',
    woodVertical => 'Wood (Vertical)',
    carpet => 'Carpet',
    carpetLow => 'Carpet (Low)',
    carpetHigh => 'Carpet (High)',
    _ => material,
  };
}

class LayerAxis {
  const LayerAxis({
    required this.min,
    required this.max,
    required this.mid,
    required this.avg,
  });

  factory LayerAxis.fromJson(Json json) => LayerAxis(
    min: asInt(json['min']),
    max: asInt(json['max']),
    mid: asDouble(json['mid']),
    avg: asDouble(json['avg']),
  );

  final int min;
  final int max;
  final double mid;
  final double avg;
}

class MapLayer {
  MapLayer({
    required this.type,
    required this.pixels,
    required this.x,
    required this.y,
    required this.pixelCount,
    required this.area,
    this.segmentId,
    this.name,
    this.active = false,
    this.material,
    this.cleanOrder,
  });

  /// Parses a layer and expands Valetudo map v2 run-length compressed pixels
  /// (`[xStart, y, count, ...]`) into the flat `[x, y, x, y, ...]` form.
  factory MapLayer.fromJson(Json json) {
    final meta = asJson(json['metaData']);
    final dims = asJson(json['dimensions']);
    final raw = asList(json['pixels']);
    final compressed = asList(json['compressedPixels']);

    Int32List pixels;
    if (raw.isEmpty && compressed.isNotEmpty) {
      var total = 0;
      for (var i = 2; i < compressed.length; i += 3) {
        total += asInt(compressed[i]);
      }
      pixels = Int32List(total * 2);
      var o = 0;
      for (var i = 0; i + 2 < compressed.length; i += 3) {
        final xStart = asInt(compressed[i]);
        final y = asInt(compressed[i + 1]);
        final count = asInt(compressed[i + 2]);
        for (var j = 0; j < count; j++) {
          pixels[o++] = xStart + j;
          pixels[o++] = y;
        }
      }
    } else {
      pixels = Int32List(raw.length - raw.length % 2);
      for (var i = 0; i < pixels.length; i++) {
        pixels[i] = asInt(raw[i]);
      }
    }

    return MapLayer(
      type: asString(json['type']),
      pixels: pixels,
      x: LayerAxis.fromJson(asJson(dims['x'])),
      y: LayerAxis.fromJson(asJson(dims['y'])),
      pixelCount: asInt(dims['pixelCount'], pixels.length ~/ 2),
      area: asDouble(meta['area']),
      segmentId: asStringOrNull(meta['segmentId']),
      name: asStringOrNull(meta['name']),
      active: asBool(meta['active']),
      material: asStringOrNull(meta['material']),
      cleanOrder: asIntOrNull(meta['cleanOrder']),
    );
  }

  final String type;

  /// Flat `[x0, y0, x1, y1, ...]` list of map pixel coordinates.
  final Int32List pixels;
  final LayerAxis x;
  final LayerAxis y;
  final int pixelCount;

  /// Area in cm².
  final double area;
  final String? segmentId;
  final String? name;
  final bool active;
  final String? material;

  /// Clean order (only reported by forks supporting segment ordering).
  final int? cleanOrder;

  bool get isSegment => type == MapLayerType.segment;
}

class MapEntity {
  const MapEntity({
    required this.type,
    required this.points,
    this.angle,
    this.label,
    this.id,
  });

  factory MapEntity.fromJson(Json json) {
    final meta = asJson(json['metaData']);
    final raw = asList(json['points']);
    final points = Float64List(raw.length);
    for (var i = 0; i < raw.length; i++) {
      points[i] = asDouble(raw[i]);
    }
    return MapEntity(
      type: asString(json['type']),
      points: points,
      angle: asNumOrNull(meta['angle'])?.toDouble(),
      label: asStringOrNull(meta['label']),
      id: asStringOrNull(meta['id']),
    );
  }

  final String type;

  /// Flat `[x0, y0, x1, y1, ...]` list in centimeters.
  final Float64List points;
  final double? angle;
  final String? label;
  final String? id;
}

class ValetudoMap {
  ValetudoMap({
    required this.version,
    required this.nonce,
    required this.sizeX,
    required this.sizeY,
    required this.pixelSize,
    required this.layers,
    required this.entities,
    this.rotation = 0,
    this.mapId,
    this.totalLayerArea,
  });

  factory ValetudoMap.fromJson(Json json) {
    final meta = asJson(json['metaData']);
    final size = asJson(json['size']);
    return ValetudoMap(
      version: asInt(meta['version'], 1),
      nonce: asString(meta['nonce']),
      sizeX: asInt(size['x']),
      sizeY: asInt(size['y']),
      pixelSize: asInt(json['pixelSize'], 5).clamp(1, 1000),
      layers: asJsonList(json['layers'])
          .map(MapLayer.fromJson)
          .toList(growable: false),
      entities: asJsonList(json['entities'])
          .map(MapEntity.fromJson)
          .toList(growable: false),
      rotation: asDouble(meta['rotation']),
      mapId: asStringOrNull(meta['id']),
      totalLayerArea: asNumOrNull(meta['totalLayerArea'])?.toDouble(),
    );
  }

  final int version;
  final String nonce;

  /// Map extent in centimeters.
  final int sizeX;
  final int sizeY;

  /// Centimeters per map pixel.
  final int pixelSize;
  final List<MapLayer> layers;
  final List<MapEntity> entities;

  /// Display rotation in degrees (reported by forks with map rotation support).
  final double rotation;
  final String? mapId;
  final double? totalLayerArea;

  bool get isEmpty => layers.isEmpty;

  Iterable<MapLayer> get segments => layers.where((l) => l.isSegment);

  Iterable<MapEntity> entitiesOfType(String type) =>
      entities.where((e) => e.type == type);

  MapEntity? entityOfType(String type) => entitiesOfType(type).firstOrNull;
}
