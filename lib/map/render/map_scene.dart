import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';

import '../processing/map_processor.dart';

/// A rasterized layer ready to be drawn.
class SceneLayer {
  const SceneLayer({required this.raster, required this.image});

  final LayerRaster raster;
  final ui.Image image;

  Rect get rect => Rect.fromLTWH(
    raster.rect.left.toDouble(),
    raster.rect.top.toDouble(),
    raster.rect.width.toDouble(),
    raster.rect.height.toDouble(),
  );
}

/// Everything the map painter needs for one map revision.
class MapScene {
  MapScene({
    required this.data,
    required this.layers,
    required this.shadow,
    required this.shadowRect,
    required this.trail,
    required this.trailHead,
    required this.predicted,
  });

  final ProcessedMap data;
  final List<SceneLayer> layers;
  final ui.Image? shadow;
  final Rect shadowRect;

  /// Full robot path in map pixels.
  final ui.Path? trail;

  /// The most recent stretch of the path, drawn highlighted.
  final ui.Path? trailHead;
  final ui.Path? predicted;

  Rect get bounds => Rect.fromLTWH(
    data.bounds.left.toDouble(),
    data.bounds.top.toDouble(),
    data.bounds.width.toDouble(),
    data.bounds.height.toDouble(),
  );
}

/// Builds [MapScene]s and keeps GPU images of unchanged layers across updates.
class MapSceneBuilder {
  final Map<int, ui.Image> _cache = {};
  bool _disposed = false;

  Future<MapScene> build(ProcessedMap data) async {
    final used = <int>{};
    final layers = <SceneLayer>[];
    for (final raster in data.rasters) {
      final key =
          raster.hash ^
          (data.paletteKey << 3) ^
          raster.rect.width ^
          (raster.rect.height << 16);
      used.add(key);
      var image = _cache[key];
      if (image == null) {
        image = await _decode(
          raster.rgba,
          raster.rect.width,
          raster.rect.height,
        );
        if (_disposed) {
          image.dispose();
          throw StateError('MapSceneBuilder disposed');
        }
        _cache[key] = image;
      }
      layers.add(SceneLayer(raster: raster, image: image));
    }

    // Evict images that are no longer referenced. Painters may still hold
    // the previous scene for a frame, so the old images are released lazily.
    final stale = _cache.keys.where((k) => !used.contains(k)).toList();
    for (final key in stale) {
      final image = _cache.remove(key)!;
      scheduleMicrotask(
        () => Future<void>.delayed(const Duration(seconds: 2), image.dispose),
      );
    }

    final (shadow, shadowRect) = _buildShadow(layers, data);
    final (trail, head) = _buildTrail(data.paths);

    return MapScene(
      data: data,
      layers: layers,
      shadow: shadow,
      shadowRect: shadowRect,
      trail: trail,
      trailHead: head,
      predicted: _buildPaths(data.predictedPaths),
    );
  }

  static Future<ui.Image> _decode(Uint8List rgba, int width, int height) {
    final completer = Completer<ui.Image>();
    ui.decodeImageFromPixels(
      rgba,
      width,
      height,
      ui.PixelFormat.rgba8888,
      completer.complete,
    );
    return completer.future;
  }

  /// A soft, pre-blurred silhouette of the floor plan used as a drop shadow.
  static (ui.Image?, Rect) _buildShadow(
    List<SceneLayer> layers,
    ProcessedMap data,
  ) {
    if (layers.isEmpty || data.bounds.isEmpty) return (null, Rect.zero);
    const pad = 10.0;
    final b = data.bounds;
    final rect = Rect.fromLTWH(
      b.left - pad,
      b.top - pad,
      b.width + pad * 2,
      b.height + pad * 2,
    );
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.translate(-rect.left, -rect.top);
    final paint = Paint()
      ..colorFilter = const ColorFilter.mode(Color(0xFF000000), BlendMode.srcIn)
      ..imageFilter = ui.ImageFilter.blur(
        sigmaX: 2.6,
        sigmaY: 2.6,
        tileMode: TileMode.decal,
      );
    canvas.saveLayer(rect, paint);
    for (final layer in layers) {
      canvas.drawImage(
        layer.image,
        Offset(layer.rect.left, layer.rect.top),
        Paint(),
      );
    }
    canvas.restore();
    final picture = recorder.endRecording();
    try {
      final image = picture.toImageSync(rect.width.ceil(), rect.height.ceil());
      return (image, rect);
    } finally {
      picture.dispose();
    }
  }

  static ui.Path? _buildPaths(List<Float32List> paths) {
    if (paths.isEmpty) return null;
    final path = ui.Path();
    for (final p in paths) {
      if (p.length < 4) continue;
      path.moveTo(p[0], p[1]);
      for (var i = 2; i + 1 < p.length; i += 2) {
        path.lineTo(p[i], p[i + 1]);
      }
    }
    return path;
  }

  /// Splits off the last ~3 m of travel as the highlighted "trail head".
  static (ui.Path?, ui.Path?) _buildTrail(List<Float32List> paths) {
    final full = _buildPaths(paths);
    if (full == null) return (null, null);
    final last = paths.lastWhere(
      (p) => p.length >= 4,
      orElse: () => Float32List(0),
    );
    if (last.isEmpty) return (full, null);
    const headLength = 60.0; // map pixels (~3 m at 5 cm/px)
    var travelled = 0.0;
    var start = last.length - 2;
    while (start >= 2 && travelled < headLength) {
      final dx = last[start] - last[start - 2];
      final dy = last[start + 1] - last[start - 1];
      travelled += math.sqrt(dx * dx + dy * dy);
      start -= 2;
    }
    final head = ui.Path()..moveTo(last[start], last[start + 1]);
    for (var i = start + 2; i + 1 < last.length; i += 2) {
      head.lineTo(last[i], last[i + 1]);
    }
    return (full, head);
  }

  void dispose() {
    _disposed = true;
    for (final image in _cache.values) {
      image.dispose();
    }
    _cache.clear();
  }
}
