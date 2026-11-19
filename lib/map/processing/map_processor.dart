import 'dart:convert';
import 'dart:isolate';
import 'dart:typed_data';

import '../../core/valetudo/json_utils.dart';
import '../../core/valetudo/models/map_data.dart';
import 'four_color.dart';
import 'map_palette.dart';
import 'patterns.dart';
import 'simplify.dart';

/// Integer rectangle in map-pixel space (inclusive `left/top`, exclusive
/// `right/bottom`).
class PixelRect {
  const PixelRect(this.left, this.top, this.width, this.height);

  final int left;
  final int top;
  final int width;
  final int height;

  int get right => left + width;
  int get bottom => top + height;
  bool get isEmpty => width <= 0 || height <= 0;
  double get centerX => left + width / 2;
  double get centerY => top + height / 2;

  PixelRect union(PixelRect other) {
    if (isEmpty) return other;
    if (other.isEmpty) return this;
    final l = left < other.left ? left : other.left;
    final t = top < other.top ? top : other.top;
    final r = right > other.right ? right : other.right;
    final b = bottom > other.bottom ? bottom : other.bottom;
    return PixelRect(l, t, r - l, b - t);
  }

  static const empty = PixelRect(0, 0, 0, 0);
}

/// One rasterized layer, cropped to its own bounding box.
class LayerRaster {
  const LayerRaster({
    required this.type,
    required this.rect,
    required this.rgba,
    required this.hash,
    this.segmentId,
  });

  final String type;
  final String? segmentId;
  final PixelRect rect;
  final Uint8List rgba;

  /// Content hash; identical rasters across map updates reuse their GPU image.
  final int hash;
}

/// Derived information about a segment (room).
class SegmentInfo {
  const SegmentInfo({
    required this.id,
    required this.name,
    required this.area,
    required this.material,
    required this.active,
    required this.labelX,
    required this.labelY,
    required this.colorIndex,
    required this.rect,
    this.cleanOrder,
  });

  final String id;
  final String? name;

  /// cm².
  final double area;
  final String? material;

  /// Currently being cleaned.
  final bool active;

  /// Label anchor in map pixels.
  final double labelX;
  final double labelY;
  final int colorIndex;
  final PixelRect rect;
  final int? cleanOrder;

  String get displayName =>
      (name == null || name!.trim().isEmpty) ? 'Room $id' : name!;

  double get areaSquareMeters => area / 10000;
}

/// Map data prepared for rendering. Produced off the UI isolate.
class ProcessedMap {
  const ProcessedMap({
    required this.map,
    required this.rasters,
    required this.segments,
    required this.bounds,
    required this.lookup,
    required this.lookupRect,
    required this.lookupIds,
    required this.paths,
    required this.predictedPaths,
    required this.paletteKey,
  });

  final ValetudoMap map;

  /// Draw order: floor, segments, walls.
  final List<LayerRaster> rasters;
  final List<SegmentInfo> segments;

  /// Union of all layers, in map pixels.
  final PixelRect bounds;

  /// Segment hit-test grid over [lookupRect]: 0 = none, n = lookupIds[n - 1].
  final Uint16List lookup;
  final PixelRect lookupRect;
  final List<String> lookupIds;

  /// Simplified robot paths in map pixels (flat x/y lists).
  final List<Float32List> paths;
  final List<Float32List> predictedPaths;
  final int paletteKey;

  int get pixelSize => map.pixelSize;

  bool get hasLayers => rasters.isNotEmpty;

  SegmentInfo? segment(String id) {
    for (final s in segments) {
      if (s.id == id) return s;
    }
    return null;
  }

  /// Segment id at a map-pixel position, or null.
  String? segmentAt(double x, double y) {
    final ix = x.floor() - lookupRect.left;
    final iy = y.floor() - lookupRect.top;
    if (ix < 0 || iy < 0 || ix >= lookupRect.width || iy >= lookupRect.height) {
      return null;
    }
    final v = lookup[ix + iy * lookupRect.width];
    return v == 0 ? null : lookupIds[v - 1];
  }
}

/// Parses and rasterizes a map on a background isolate.
Future<ProcessedMap> processMapInBackground(
  String json,
  MapPalette palette,
  int paletteKey,
) {
  final paletteList = palette.toList();
  return Isolate.run(
    () => processMapJson(json, MapPalette.fromList(paletteList), paletteKey),
  );
}

ProcessedMap processMapJson(String json, MapPalette palette, int paletteKey) {
  final decoded = jsonDecode(json);
  return processMap(ValetudoMap.fromJson(asJson(decoded)), palette, paletteKey);
}

const _layerOrder = {
  MapLayerType.floor: 14,
  MapLayerType.segment: 15,
  MapLayerType.wall: 16,
};

ProcessedMap processMap(ValetudoMap map, MapPalette palette, int paletteKey) {
  final solver = FourColorSolver(map.layers, map.pixelSize);
  final layers = [...map.layers]
    ..sort(
      (a, b) => (_layerOrder[a.type] ?? 0).compareTo(_layerOrder[b.type] ?? 0),
    );

  final rasters = <LayerRaster>[];
  final segments = <SegmentInfo>[];
  var bounds = PixelRect.empty;
  final layerRects = <PixelRect>[];

  for (final layer in layers) {
    final rect = _boundsOf(layer.pixels);
    layerRects.add(rect);
    if (rect.isEmpty) continue;
    bounds = bounds.union(rect);

    int color;
    var colorIndex = 0;
    switch (layer.type) {
      case MapLayerType.wall:
        color = palette.wall;
      case MapLayerType.segment:
        colorIndex = solver.colorOf(layer.segmentId ?? '');
        color = palette.segmentColor(colorIndex);
      default:
        color = palette.floor;
    }
    final accent = adjustBrightness(color, palette.accentAmount);
    final pattern = patternForMaterial(layer.material);

    final rgba = Uint8List(rect.width * rect.height * 4);
    final p = layer.pixels;
    final cr = (color >> 16) & 0xFF,
        cg = (color >> 8) & 0xFF,
        cb = color & 0xFF;
    final ar = (accent >> 16) & 0xFF,
        ag = (accent >> 8) & 0xFF,
        ab = accent & 0xFF;
    var hash =
        0x811C9DC5 ^
        color ^
        (layer.material?.hashCode ?? 0) ^
        rect.left ^
        (rect.top << 12);
    for (var i = 0; i + 1 < p.length; i += 2) {
      final x = p[i], y = p[i + 1];
      final o = ((x - rect.left) + (y - rect.top) * rect.width) * 4;
      if (pattern(x, y)) {
        rgba[o] = ar;
        rgba[o + 1] = ag;
        rgba[o + 2] = ab;
      } else {
        rgba[o] = cr;
        rgba[o + 1] = cg;
        rgba[o + 2] = cb;
      }
      rgba[o + 3] = 255;
      hash = ((hash ^ x) * 0x01000193) & 0x7FFFFFFF;
      hash = ((hash ^ y) * 0x01000193) & 0x7FFFFFFF;
    }

    rasters.add(
      LayerRaster(
        type: layer.type,
        segmentId: layer.segmentId,
        rect: rect,
        rgba: rgba,
        hash: hash,
      ),
    );

    if (layer.isSegment && layer.segmentId != null) {
      final label = _labelPosition(layer);
      segments.add(
        SegmentInfo(
          id: layer.segmentId!,
          name: layer.name,
          area: layer.area,
          material: layer.material,
          active: layer.active,
          labelX: label.$1 + 0.5,
          labelY: label.$2 + 0.5,
          colorIndex: colorIndex,
          rect: rect,
          cleanOrder: layer.cleanOrder,
        ),
      );
    }
  }

  // Segment hit-test grid. Walls are written last and clear the cell, exactly
  // like the web interface's lookup buffer.
  final lookupIds = <String>[];
  final lookup = Uint16List(bounds.isEmpty ? 0 : bounds.width * bounds.height);
  for (var li = 0; li < layers.length; li++) {
    final layer = layers[li];
    var marker = 0;
    if (layer.isSegment && layer.segmentId != null) {
      lookupIds.add(layer.segmentId!);
      marker = lookupIds.length;
    }
    final p = layer.pixels;
    for (var i = 0; i + 1 < p.length; i += 2) {
      final ix = p[i] - bounds.left, iy = p[i + 1] - bounds.top;
      if (ix < 0 || iy < 0 || ix >= bounds.width || iy >= bounds.height) {
        continue;
      }
      lookup[ix + iy * bounds.width] = marker;
    }
  }

  Float32List toPixels(Float64List cm) {
    final simplified = simplifyPolyline(cm, 0.8);
    final out = Float32List(simplified.length);
    final ps = map.pixelSize.toDouble();
    for (var i = 0; i < simplified.length; i++) {
      out[i] = simplified[i] / ps;
    }
    return out;
  }

  final paths = [
    for (final e in map.entitiesOfType(MapEntityType.path))
      if (e.points.length >= 4) toPixels(e.points),
  ];
  final predicted = [
    for (final e in map.entitiesOfType(MapEntityType.predictedPath))
      if (e.points.length >= 4) toPixels(e.points),
  ];

  // Entities may extend beyond the layers (e.g. a robot outside the map).
  for (final e in map.entities) {
    if (e.type == MapEntityType.path || e.type == MapEntityType.predictedPath) {
      continue;
    }
    for (var i = 0; i + 1 < e.points.length; i += 2) {
      final x = (e.points[i] / map.pixelSize).floor();
      final y = (e.points[i + 1] / map.pixelSize).floor();
      bounds = bounds.union(PixelRect(x, y, 1, 1));
    }
  }

  return ProcessedMap(
    map: map,
    rasters: rasters,
    segments: segments,
    bounds: bounds,
    lookup: lookup,
    lookupRect: bounds.isEmpty
        ? PixelRect.empty
        : PixelRect(
            bounds.left,
            bounds.top,
            lookup.isEmpty ? 0 : bounds.width,
            lookup.isEmpty ? 0 : bounds.height,
          ),
    lookupIds: lookupIds,
    paths: paths,
    predictedPaths: predicted,
    paletteKey: paletteKey,
  );
}

PixelRect _boundsOf(Int32List pixels) {
  if (pixels.length < 2) return PixelRect.empty;
  var minX = pixels[0], maxX = pixels[0], minY = pixels[1], maxY = pixels[1];
  for (var i = 2; i + 1 < pixels.length; i += 2) {
    final x = pixels[i], y = pixels[i + 1];
    if (x < minX) minX = x;
    if (x > maxX) maxX = x;
    if (y < minY) minY = y;
    if (y > maxY) maxY = y;
  }
  return PixelRect(minX, minY, maxX - minX + 1, maxY - minY + 1);
}

/// Label anchor: the average position, or the median when average and mid
/// diverge (oddly shaped rooms such as L-shaped hallways), as in the web UI.
(double, double) _labelPosition(MapLayer layer) {
  var x = layer.x.avg;
  var y = layer.y.avg;
  if ((layer.x.mid - layer.x.avg).abs() >= 8 ||
      (layer.y.mid - layer.y.avg).abs() >= 8) {
    final n = layer.pixels.length ~/ 2;
    if (n > 0) {
      final xs = Int32List(n), ys = Int32List(n);
      for (var i = 0; i < n; i++) {
        xs[i] = layer.pixels[i * 2];
        ys[i] = layer.pixels[i * 2 + 1];
      }
      xs.sort();
      ys.sort();
      x = _median(xs);
      y = _median(ys);
    }
  }
  if (x == 0 && y == 0 && layer.pixels.length >= 2) {
    final r = _boundsOf(layer.pixels);
    return (r.centerX, r.centerY);
  }
  return (x, y);
}

double _median(Int32List sorted) {
  final mid = sorted.length ~/ 2;
  return sorted.length.isOdd
      ? sorted[mid].toDouble()
      : (sorted[mid - 1] + sorted[mid]) / 2;
}
