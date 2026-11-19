import 'dart:math' as math;

import 'package:flutter/painting.dart';

/// Camera of the map: maps world coordinates (map pixels) to screen
/// coordinates (logical pixels).
///
/// `screen = translation + scale · R(rotation) · world`
class MapViewport {
  const MapViewport({
    required this.scale,
    required this.rotation,
    required this.translation,
  });

  static const identity = MapViewport(
    scale: 1,
    rotation: 0,
    translation: Offset.zero,
  );

  /// Screen pixels per map pixel.
  final double scale;

  /// Radians, clockwise.
  final double rotation;
  final Offset translation;

  double get _cos => math.cos(rotation);
  double get _sin => math.sin(rotation);

  Offset worldToScreen(Offset world) {
    final c = _cos, s = _sin;
    return Offset(
      translation.dx + scale * (c * world.dx - s * world.dy),
      translation.dy + scale * (s * world.dx + c * world.dy),
    );
  }

  Offset screenToWorld(Offset screen) {
    final c = _cos, s = _sin;
    final x = (screen.dx - translation.dx) / scale;
    final y = (screen.dy - translation.dy) / scale;
    return Offset(c * x + s * y, -s * x + c * y);
  }

  /// Applies the world → screen transform to [canvas].
  void apply(Canvas canvas) {
    canvas.translate(translation.dx, translation.dy);
    canvas.rotate(rotation);
    canvas.scale(scale);
  }

  /// Zooms by [factor] keeping the world point under [focal] (screen) fixed.
  MapViewport zoomedAt(
    Offset focal,
    double factor, {
    double minScale = 0.05,
    double maxScale = 80,
  }) {
    final newScale = (scale * factor).clamp(minScale, maxScale);
    final world = screenToWorld(focal);
    final moved = MapViewport(
      scale: newScale,
      rotation: rotation,
      translation: translation,
    );
    final drift = moved.worldToScreen(world) - focal;
    return MapViewport(
      scale: newScale,
      rotation: rotation,
      translation: translation - drift,
    );
  }

  MapViewport panned(Offset delta) => MapViewport(
    scale: scale,
    rotation: rotation,
    translation: translation + delta,
  );

  /// A viewport centering [world] at [screenPoint].
  MapViewport centeredOn(Offset world, Offset screenPoint, {double? newScale}) {
    final next = MapViewport(
      scale: newScale ?? scale,
      rotation: rotation,
      translation: Offset.zero,
    );
    final at = next.worldToScreen(world);
    return MapViewport(
      scale: next.scale,
      rotation: rotation,
      translation: screenPoint - at,
    );
  }

  /// Fits [bounds] (world) into [viewport] (screen rect, e.g. the area not
  /// covered by overlays), with relative [padding].
  static MapViewport fit(
    Rect bounds,
    Rect viewport, {
    double rotation = 0,
    double padding = 0.1,
  }) {
    if (bounds.isEmpty || viewport.isEmpty) {
      return MapViewport(
        scale: 1,
        rotation: rotation,
        translation: viewport.center,
      );
    }
    final c = math.cos(rotation).abs(), s = math.sin(rotation).abs();
    final w = bounds.width * c + bounds.height * s;
    final h = bounds.width * s + bounds.height * c;
    final scale = math.min(
      viewport.width / (w * (1 + padding)),
      viewport.height / (h * (1 + padding)),
    );
    return MapViewport(
      scale: scale,
      rotation: rotation,
      translation: Offset.zero,
    ).centeredOn(bounds.center, viewport.center);
  }

  static MapViewport lerp(MapViewport a, MapViewport b, double t) {
    // Interpolate in log-scale for a natural zoom feel.
    final scale = math.exp(_lerp(math.log(a.scale), math.log(b.scale), t));
    var dr = b.rotation - a.rotation;
    while (dr > math.pi) {
      dr -= 2 * math.pi;
    }
    while (dr < -math.pi) {
      dr += 2 * math.pi;
    }
    return MapViewport(
      scale: scale,
      rotation: a.rotation + dr * t,
      translation: Offset.lerp(a.translation, b.translation, t)!,
    );
  }

  static double _lerp(double a, double b, double t) => a + (b - a) * t;

  @override
  bool operator ==(Object other) =>
      other is MapViewport &&
      other.scale == scale &&
      other.rotation == rotation &&
      other.translation == translation;

  @override
  int get hashCode => Object.hash(scale, rotation, translation);
}
