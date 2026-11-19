import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';

import '../../core/valetudo/models/models.dart';
import '../render/viewport.dart';

/// Kinds of client-side shapes that can be drawn on the map.
enum ShapeKind {
  zone,
  noGoArea,
  noMopArea,
  virtualWall,
  cuttingLine,
  threshold,
  curtain,
  ramp;

  String get label => switch (this) {
    ShapeKind.zone => 'Zone',
    ShapeKind.noGoArea => 'No-Go',
    ShapeKind.noMopArea => 'No-Mop',
    ShapeKind.virtualWall => 'Wall',
    ShapeKind.cuttingLine => 'Cutting line',
    ShapeKind.threshold => 'Threshold',
    ShapeKind.curtain => 'Curtain',
    ShapeKind.ramp => 'Ramp',
  };
}

/// Interactive handle of a shape.
enum HandleKind { delete, resize, rotate, body }

class ShapeHit {
  const ShapeHit(this.shape, this.handle);

  final EditableShape shape;
  final HandleKind handle;
}

/// Radius (logical pixels) of the touch target around a handle.
const double handleTouchRadius = 24;

/// Visual radius of a handle.
const double handleRadius = 13;

/// Base class of editable shapes. Coordinates are in map pixels (world).
sealed class EditableShape {
  EditableShape({required this.kind, this.active = true});

  final ShapeKind kind;

  /// Selected for editing; inactive shapes show no handles.
  bool active;

  /// Hit test in screen space. Inactive shapes only report body hits.
  ShapeHit? hitTest(Offset screen, MapViewport viewport);

  /// Applies a drag of [handle] by [delta] (world units) to [world] (world).
  void drag(
    HandleKind handle,
    Offset delta,
    Offset world, {
    required double minSize,
  });

  /// Rounds coordinates to whole map pixels after a gesture.
  void settle();

  Offset get center;

  EditableShape copy();
}

double _floorCm(double px, int pixelSize) => (px * pixelSize).floorToDouble();

CmPoint toCm(Offset px, int pixelSize) =>
    CmPoint(_floorCm(px.dx, pixelSize), _floorCm(px.dy, pixelSize));

Offset fromCm(double x, double y, int pixelSize) =>
    Offset((x / pixelSize).floorToDouble(), (y / pixelSize).floorToDouble());

/// Axis-aligned rectangle (cleaning zones, no-go and no-mop areas).
class RectShape extends EditableShape {
  RectShape({
    required super.kind,
    required Offset a,
    required Offset b,
    super.active,
  }) : x0 = math.min(a.dx, b.dx),
       y0 = math.min(a.dy, b.dy),
       x1 = math.max(a.dx, b.dx),
       y1 = math.max(a.dy, b.dy);

  double x0, y0, x1, y1;

  Offset get topLeft => Offset(x0, y0);
  Offset get bottomRight => Offset(x1, y1);

  @override
  Offset get center => Offset((x0 + x1) / 2, (y0 + y1) / 2);

  List<Offset> get corners => [
    Offset(x0, y0),
    Offset(x1, y0),
    Offset(x1, y1),
    Offset(x0, y1),
  ];

  @override
  ShapeHit? hitTest(Offset screen, MapViewport viewport) {
    if (active) {
      if ((viewport.worldToScreen(topLeft) - screen).distance <=
          handleTouchRadius) {
        return ShapeHit(this, HandleKind.delete);
      }
      if ((viewport.worldToScreen(bottomRight) - screen).distance <=
          handleTouchRadius) {
        return ShapeHit(this, HandleKind.resize);
      }
    }
    final w = viewport.screenToWorld(screen);
    if (w.dx >= x0 && w.dx <= x1 && w.dy >= y0 && w.dy <= y1) {
      return ShapeHit(this, HandleKind.body);
    }
    return null;
  }

  @override
  void drag(
    HandleKind handle,
    Offset delta,
    Offset world, {
    required double minSize,
  }) {
    switch (handle) {
      case HandleKind.resize:
        if (world.dx > x0 + minSize && x1 + delta.dx > x0 + minSize) {
          x1 += delta.dx;
        }
        if (world.dy > y0 + minSize && y1 + delta.dy > y0 + minSize) {
          y1 += delta.dy;
        }
      case HandleKind.body:
        x0 += delta.dx;
        x1 += delta.dx;
        y0 += delta.dy;
        y1 += delta.dy;
      case HandleKind.delete:
      case HandleKind.rotate:
        break;
    }
  }

  @override
  void settle() {
    x0 = x0.roundToDouble();
    y0 = y0.roundToDouble();
    x1 = x1.roundToDouble();
    y1 = y1.roundToDouble();
  }

  /// Width × height in meters.
  (double, double) sizeMeters(int pixelSize) =>
      ((x1 - x0) * pixelSize / 100, (y1 - y0) * pixelSize / 100);

  CmQuad toQuad(int pixelSize) => CmQuad(
    toCm(Offset(x0, y0), pixelSize),
    toCm(Offset(x1, y0), pixelSize),
    toCm(Offset(x1, y1), pixelSize),
    toCm(Offset(x0, y1), pixelSize),
  );

  @override
  RectShape copy() =>
      RectShape(kind: kind, a: topLeft, b: bottomRight, active: active);
}

/// Two-point line (virtual walls, cutting lines, thresholds, curtains).
class LineShape extends EditableShape {
  LineShape({
    required super.kind,
    required this.p0,
    required this.p1,
    super.active,
  });

  Offset p0;
  Offset p1;

  @override
  Offset get center => (p0 + p1) / 2;

  @override
  ShapeHit? hitTest(Offset screen, MapViewport viewport) {
    final s0 = viewport.worldToScreen(p0);
    final s1 = viewport.worldToScreen(p1);
    if (active) {
      if ((s0 - screen).distance <= handleTouchRadius) {
        return ShapeHit(this, HandleKind.delete);
      }
      if ((s1 - screen).distance <= handleTouchRadius) {
        return ShapeHit(this, HandleKind.resize);
      }
    }
    if (_distanceToSegment(screen, s0, s1) <= 18) {
      return ShapeHit(this, HandleKind.body);
    }
    return null;
  }

  @override
  void drag(
    HandleKind handle,
    Offset delta,
    Offset world, {
    required double minSize,
  }) {
    switch (handle) {
      case HandleKind.resize:
        p1 += delta;
      case HandleKind.body:
        p0 += delta;
        p1 += delta;
      case HandleKind.delete:
      case HandleKind.rotate:
        break;
    }
  }

  @override
  void settle() {
    p0 = Offset(p0.dx.roundToDouble(), p0.dy.roundToDouble());
    p1 = Offset(p1.dx.roundToDouble(), p1.dy.roundToDouble());
  }

  double lengthMeters(int pixelSize) => (p1 - p0).distance * pixelSize / 100;

  @override
  LineShape copy() => LineShape(kind: kind, p0: p0, p1: p1, active: active);
}

/// Rotatable rectangle (ramps). Corners are kept in order p0→p1→p2→p3.
/// The arrows point from the p3/p2 edge towards the p0/p1 edge (uphill).
class RampShape extends EditableShape {
  RampShape({required List<Offset> points, super.active})
    : assert(points.length == 4),
      points = List.of(points),
      super(kind: ShapeKind.ramp);

  final List<Offset> points;

  @override
  Offset get center => (points[0] + points[1] + points[2] + points[3]) / 4;

  @override
  ShapeHit? hitTest(Offset screen, MapViewport viewport) {
    final s = points.map(viewport.worldToScreen).toList();
    if (active) {
      if ((s[0] - screen).distance <= handleTouchRadius) {
        return ShapeHit(this, HandleKind.delete);
      }
      if ((s[1] - screen).distance <= handleTouchRadius) {
        return ShapeHit(this, HandleKind.rotate);
      }
      if ((s[2] - screen).distance <= handleTouchRadius) {
        return ShapeHit(this, HandleKind.resize);
      }
    }
    if (_pointInPolygon(screen, s)) return ShapeHit(this, HandleKind.body);
    return null;
  }

  @override
  void drag(
    HandleKind handle,
    Offset delta,
    Offset world, {
    required double minSize,
  }) {
    switch (handle) {
      case HandleKind.body:
        for (var i = 0; i < 4; i++) {
          points[i] += delta;
        }
      case HandleKind.rotate:
        final c = center;
        final before = world - delta - c;
        final after = world - c;
        final angle =
            math.atan2(after.dy, after.dx) - math.atan2(before.dy, before.dx);
        for (var i = 0; i < 4; i++) {
          points[i] = _rotate(points[i], c, angle);
        }
      case HandleKind.resize:
        // Resize along the rectangle's own axes, anchored at p0.
        final u = _unit(points[1] - points[0]);
        final v = _unit(points[3] - points[0]);
        final rel = world - points[0];
        final w = math.max(minSize, rel.dx * u.dx + rel.dy * u.dy);
        final h = math.max(minSize, rel.dx * v.dx + rel.dy * v.dy);
        points[1] = points[0] + u * w;
        points[3] = points[0] + v * h;
        points[2] = points[0] + u * w + v * h;
      case HandleKind.delete:
        break;
    }
  }

  @override
  void settle() {
    // Snap the angle to 5° steps and the position to whole pixels, keeping
    // the rectangle's size (mirrors the web editor).
    final c = center;
    final edge = points[1] - points[0];
    final width = edge.distance;
    final height = (points[3] - points[0]).distance;
    var angle = math.atan2(edge.dy, edge.dx);
    final snapped = (angle * 180 / math.pi / 5).round() * 5;
    angle = snapped * math.pi / 180;
    final cx = (c.dx - width / 2).roundToDouble() + width / 2;
    final cy = (c.dy - height / 2).roundToDouble() + height / 2;
    final u = Offset(math.cos(angle), math.sin(angle));
    final v = Offset(-u.dy, u.dx);
    final origin = Offset(cx, cy) - u * (width / 2) - v * (height / 2);
    points[0] = origin;
    points[1] = origin + u * width;
    points[2] = origin + u * width + v * height;
    points[3] = origin + v * height;
  }

  @override
  RampShape copy() => RampShape(points: points, active: active);
}

Offset _unit(Offset v) {
  final d = v.distance;
  return d == 0 ? const Offset(1, 0) : v / d;
}

Offset _rotate(Offset p, Offset c, double angle) {
  final s = math.sin(angle), co = math.cos(angle);
  final d = p - c;
  return Offset(c.dx + d.dx * co - d.dy * s, c.dy + d.dx * s + d.dy * co);
}

double _distanceToSegment(Offset p, Offset a, Offset b) {
  final ab = b - a;
  final len2 = ab.dx * ab.dx + ab.dy * ab.dy;
  if (len2 == 0) return (p - a).distance;
  final t = (((p.dx - a.dx) * ab.dx + (p.dy - a.dy) * ab.dy) / len2).clamp(
    0.0,
    1.0,
  );
  return (p - (a + ab * t)).distance;
}

bool _pointInPolygon(Offset p, List<Offset> poly) {
  var inside = false;
  for (var i = 0, j = poly.length - 1; i < poly.length; j = i++) {
    final a = poly[i], b = poly[j];
    if (((a.dy > p.dy) != (b.dy > p.dy)) &&
        (p.dx < (b.dx - a.dx) * (p.dy - a.dy) / (b.dy - a.dy) + a.dx)) {
      inside = !inside;
    }
  }
  return inside;
}

// ---------------------------------------------------------------------------
// Factories & conversion
// ---------------------------------------------------------------------------

/// Creates a new shape of [kind] centered at [center] (world).
EditableShape createShape(ShapeKind kind, Offset center) {
  switch (kind) {
    case ShapeKind.zone:
    case ShapeKind.noGoArea:
    case ShapeKind.noMopArea:
      return RectShape(
        kind: kind,
        a: center - const Offset(15, 15),
        b: center + const Offset(15, 15),
      );
    case ShapeKind.virtualWall:
    case ShapeKind.cuttingLine:
      return LineShape(
        kind: kind,
        p0: center - const Offset(15, 15),
        p1: center + const Offset(15, 15),
      );
    case ShapeKind.threshold:
    case ShapeKind.curtain:
      return LineShape(
        kind: kind,
        p0: center - const Offset(10, 10),
        p1: center + const Offset(10, 10),
      );
    case ShapeKind.ramp:
      return RampShape(
        points: [
          center + const Offset(-5, -5),
          center + const Offset(5, -5),
          center + const Offset(5, 5),
          center + const Offset(-5, 5),
        ],
      );
  }
}

/// Builds editable shapes from the restriction entities of the current map.
List<EditableShape> restrictionShapesFromMap(ValetudoMap map) {
  final ps = map.pixelSize;
  final shapes = <EditableShape>[];
  for (final e in map.entities) {
    final p = e.points;
    switch (e.type) {
      case MapEntityType.virtualWall when p.length >= 4:
        shapes.add(
          LineShape(
            kind: ShapeKind.virtualWall,
            p0: fromCm(p[0], p[1], ps),
            p1: fromCm(p[2], p[3], ps),
            active: false,
          ),
        );
      case MapEntityType.noGoArea when p.length >= 8:
        shapes.add(
          RectShape(
            kind: ShapeKind.noGoArea,
            a: fromCm(p[0], p[1], ps),
            b: fromCm(p[4], p[5], ps),
            active: false,
          ),
        );
      case MapEntityType.noMopArea when p.length >= 8:
        shapes.add(
          RectShape(
            kind: ShapeKind.noMopArea,
            a: fromCm(p[0], p[1], ps),
            b: fromCm(p[4], p[5], ps),
            active: false,
          ),
        );
      default:
        break;
    }
  }
  return shapes;
}

/// Builds editable shapes from the annotation entities of the current map.
List<EditableShape> annotationShapesFromMap(ValetudoMap map) {
  final ps = map.pixelSize;
  final shapes = <EditableShape>[];
  for (final e in map.entities) {
    final p = e.points;
    switch (e.type) {
      case MapEntityType.threshold when p.length >= 4:
        shapes.add(
          LineShape(
            kind: ShapeKind.threshold,
            p0: fromCm(p[0], p[1], ps),
            p1: fromCm(p[2], p[3], ps),
            active: false,
          ),
        );
      case MapEntityType.curtain when p.length >= 4:
        shapes.add(
          LineShape(
            kind: ShapeKind.curtain,
            p0: fromCm(p[0], p[1], ps),
            p1: fromCm(p[2], p[3], ps),
            active: false,
          ),
        );
      case MapEntityType.ramp when p.length >= 8:
        shapes.add(
          RampShape(
            points: [for (var i = 0; i < 8; i += 2) fromCm(p[i], p[i + 1], ps)],
            active: false,
          ),
        );
      default:
        break;
    }
  }
  return shapes;
}

List<VirtualWall> virtualWallsFromShapes(
  Iterable<EditableShape> shapes,
  int pixelSize,
) => [
  for (final s in shapes.whereType<LineShape>())
    if (s.kind == ShapeKind.virtualWall)
      VirtualWall(toCm(s.p0, pixelSize), toCm(s.p1, pixelSize)),
];

List<RestrictedZone> restrictedZonesFromShapes(
  Iterable<EditableShape> shapes,
  int pixelSize,
) => [
  for (final s in shapes.whereType<RectShape>())
    if (s.kind == ShapeKind.noGoArea || s.kind == ShapeKind.noMopArea)
      RestrictedZone(
        type: s.kind == ShapeKind.noMopArea ? 'mop' : 'regular',
        quad: s.toQuad(pixelSize),
      ),
];

List<MapAnnotation> annotationsFromShapes(
  Iterable<EditableShape> shapes,
  int pixelSize,
) => [
  for (final s in shapes)
    switch (s) {
      LineShape(kind: ShapeKind.threshold) => MapAnnotation(
        type: 'threshold',
        points: [toCm(s.p0, pixelSize), toCm(s.p1, pixelSize)],
      ),
      LineShape(kind: ShapeKind.curtain) => MapAnnotation(
        type: 'curtain',
        points: [toCm(s.p0, pixelSize), toCm(s.p1, pixelSize)],
      ),
      RampShape() => MapAnnotation(
        type: 'ramp',
        points: [for (final p in s.points) toCm(p, pixelSize)],
      ),
      _ => null,
    },
].nonNulls.toList();

// ---------------------------------------------------------------------------
// Painting
// ---------------------------------------------------------------------------

class ShapeStyle {
  const ShapeStyle({
    required this.stroke,
    required this.fill,
    this.strokeWidth = 2,
    this.dashed = false,
  });

  final Color stroke;
  final Color fill;
  final double strokeWidth;
  final bool dashed;
}

ShapeStyle styleFor(EditableShape shape, {required Color accent}) =>
    switch (shape.kind) {
      ShapeKind.zone => ShapeStyle(
        stroke: const Color(0xFFFFFFFF),
        fill: shape.active
            ? accent.withValues(alpha: 0.16)
            : const Color(0x66FFFFFF),
        dashed: shape.active,
      ),
      ShapeKind.noGoArea => const ShapeStyle(
        stroke: Color(0xC0EF4444),
        fill: Color(0x30EF4444),
      ),
      ShapeKind.noMopArea => const ShapeStyle(
        stroke: Color(0xB0D946EF),
        fill: Color(0x30D946EF),
      ),
      ShapeKind.virtualWall => const ShapeStyle(
        stroke: Color(0xE0EF4444),
        fill: Color(0x00000000),
        strokeWidth: 5,
      ),
      ShapeKind.cuttingLine => const ShapeStyle(
        stroke: Color(0xFFFFFFFF),
        fill: Color(0x00000000),
        strokeWidth: 3,
        dashed: true,
      ),
      ShapeKind.threshold => const ShapeStyle(
        stroke: Color(0xFF10B981),
        fill: Color(0x3310B981),
        strokeWidth: 1.5,
      ),
      ShapeKind.curtain => const ShapeStyle(
        stroke: Color(0xFF06B6D4),
        fill: Color(0x00000000),
        strokeWidth: 3,
      ),
      ShapeKind.ramp => ShapeStyle(
        stroke: const Color(0xFF06B6D4),
        fill: shape.active ? const Color(0x2606B6D4) : const Color(0x1A06B6D4),
        dashed: shape.active,
      ),
    };

/// Paints [shape] in screen space.
void paintShape(
  Canvas canvas,
  EditableShape shape,
  MapViewport viewport, {
  required Color accent,
  required int pixelSize,
}) {
  final style = styleFor(shape, accent: accent);
  switch (shape) {
    case RectShape():
      final pts = shape.corners.map(viewport.worldToScreen).toList();
      final path = Path()..addPolygon(pts, true);
      canvas.drawPath(path, Paint()..color = style.fill);
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = style.strokeWidth + 2
          ..color = const Color(0x99000000),
      );
      _strokePath(canvas, path, style);
      if (shape.kind == ShapeKind.zone) {
        final (w, h) = shape.sizeMeters(pixelSize);
        _drawLabel(
          canvas,
          '${w.toStringAsFixed(2)} × ${h.toStringAsFixed(2)} m',
          pts[0] + const Offset(18, -26),
        );
      }
      if (shape.active) {
        _drawHandle(canvas, pts[0], HandleKind.delete, accent);
        _drawHandle(canvas, pts[2], HandleKind.resize, accent);
      }
    case LineShape():
      final a = viewport.worldToScreen(shape.p0);
      final b = viewport.worldToScreen(shape.p1);
      switch (shape.kind) {
        case ShapeKind.threshold:
          _paintThreshold(canvas, a, b, viewport.scale, style);
        case ShapeKind.curtain:
          _paintCurtain(canvas, a, b, viewport.scale, style);
        default:
          final path = Path()
            ..moveTo(a.dx, a.dy)
            ..lineTo(b.dx, b.dy);
          canvas.drawPath(
            path,
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = style.strokeWidth + 3
              ..strokeCap = StrokeCap.round
              ..color = const Color(0x66000000),
          );
          _strokePath(canvas, path, style);
      }
      if (shape.active) {
        _drawLabel(
          canvas,
          '${shape.lengthMeters(pixelSize).toStringAsFixed(2)} m',
          (a + b) / 2 + const Offset(0, -28),
          center: true,
        );
        _drawHandle(canvas, a, HandleKind.delete, accent);
        _drawHandle(canvas, b, HandleKind.resize, accent);
      }
    case RampShape():
      final pts = shape.points.map(viewport.worldToScreen).toList();
      _paintRamp(canvas, pts, viewport.scale, style);
      if (shape.active) {
        _drawHandle(canvas, pts[0], HandleKind.delete, accent);
        _drawHandle(canvas, pts[1], HandleKind.rotate, accent);
        _drawHandle(canvas, pts[2], HandleKind.resize, accent);
      }
  }
}

void _strokePath(Canvas canvas, Path path, ShapeStyle style) {
  final paint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = style.strokeWidth
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round
    ..color = style.stroke;
  canvas.drawPath(style.dashed ? dashPath(path, 12, 6) : path, paint);
}

/// Returns a dashed version of [source].
Path dashPath(Path source, double dash, double gap) {
  final out = Path();
  for (final metric in source.computeMetrics()) {
    var d = 0.0;
    while (d < metric.length) {
      out.addPath(
        metric.extractPath(d, math.min(d + dash, metric.length)),
        Offset.zero,
      );
      d += dash + gap;
    }
  }
  return out;
}

/// Thresholds are 1.5 map pixels wide bands.
void _paintThreshold(
  Canvas canvas,
  Offset a,
  Offset b,
  double scale,
  ShapeStyle style,
) {
  final width = math.max(6.0, 1.5 * scale);
  final dir = _unit(b - a);
  final n = Offset(-dir.dy, dir.dx) * (width / 2);
  final poly = Path()..addPolygon([a + n, b + n, b - n, a - n], true);
  canvas.drawPath(poly, Paint()..color = style.fill);
  canvas.drawPath(
    poly,
    Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = style.strokeWidth
      ..color = style.stroke,
  );
  canvas.drawLine(
    a,
    b,
    Paint()
      ..strokeWidth = 1
      ..color = style.stroke.withValues(alpha: 0.5),
  );
}

void _paintCurtain(
  Canvas canvas,
  Offset a,
  Offset b,
  double scale,
  ShapeStyle style,
) {
  final length = (b - a).distance;
  if (length < 1) return;
  final dir = _unit(b - a);
  final n = Offset(-dir.dy, dir.dx);
  final wavelength = math.max(8.0, 3 * scale);
  final amplitude = math.max(2.5, 0.6 * scale);
  final path = Path()..moveTo(a.dx, a.dy);
  for (var d = 2.0; d <= length; d += 2) {
    final p =
        a + dir * d + n * (math.sin(d / wavelength * 2 * math.pi) * amplitude);
    path.lineTo(p.dx, p.dy);
  }
  canvas.drawPath(
    path,
    Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5
      ..strokeCap = StrokeCap.round
      ..color = const Color(0x99000000),
  );
  canvas.drawPath(
    path,
    Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round
      ..color = style.stroke,
  );
}

void _paintRamp(Canvas canvas, List<Offset> p, double scale, ShapeStyle style) {
  final poly = Path()..addPolygon(p, true);
  canvas.drawPath(poly, Paint()..color = style.fill);
  _strokePath(
    canvas,
    poly,
    ShapeStyle(
      stroke: style.stroke.withValues(alpha: 0.75),
      fill: style.fill,
      dashed: style.dashed,
    ),
  );
  canvas.save();
  canvas.clipPath(poly);
  final vW = p[1] - p[0];
  final vH = p[3] - p[0];
  final lenW = vW.distance, lenH = vH.distance;
  if (lenW > 0 && lenH > 0) {
    final uW = vW / lenW, uH = vH / lenH;
    final arrowWidth = math.min(lenW * 0.75, 50.0);
    final arrowHeight = arrowWidth * 0.5;
    final spacing = arrowHeight * 1.4;
    final top = p[0] + vW * 0.5;
    final count = (lenH / spacing).ceil() + 1;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color = style.stroke.withValues(alpha: 0.8);
    for (var i = 0; i < count; i++) {
      final c = top + uH * (arrowHeight * 0.75 + i * spacing);
      final tip = c - uH * (arrowHeight * 0.5);
      final base = c + uH * (arrowHeight * 0.5);
      final path = Path()
        ..moveTo(
          (base - uW * (arrowWidth / 2)).dx,
          (base - uW * (arrowWidth / 2)).dy,
        )
        ..lineTo(tip.dx, tip.dy)
        ..lineTo(
          (base + uW * (arrowWidth / 2)).dx,
          (base + uW * (arrowWidth / 2)).dy,
        );
      canvas.drawPath(path, paint);
    }
  }
  canvas.restore();
}

void _drawLabel(Canvas canvas, String text, Offset at, {bool center = false}) {
  final tp = TextPainter(
    text: TextSpan(
      text: text,
      style: const TextStyle(
        fontFamily: 'Inter',
        fontSize: 12,
        fontWeight: FontWeight.w600,
        color: Color(0xFFFFFFFF),
      ),
    ),
    textDirection: TextDirection.ltr,
  )..layout();
  final rect = Rect.fromLTWH(
    center ? at.dx - tp.width / 2 - 8 : at.dx - 8,
    at.dy - 3,
    tp.width + 16,
    tp.height + 6,
  );
  canvas.drawRRect(
    RRect.fromRectAndRadius(rect, const Radius.circular(9)),
    Paint()..color = const Color(0xB3000000),
  );
  tp.paint(canvas, Offset(rect.left + 8, rect.top + 3));
}

void _drawHandle(Canvas canvas, Offset c, HandleKind kind, Color accent) {
  canvas.drawCircle(
    c + const Offset(0, 1.5),
    handleRadius + 1,
    Paint()
      ..color = const Color(0x40000000)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
  );
  canvas.drawCircle(
    c,
    handleRadius,
    Paint()
      ..color = kind == HandleKind.delete
          ? const Color(0xFFEF4444)
          : const Color(0xFFFFFFFF),
  );
  final ink = kind == HandleKind.delete ? const Color(0xFFFFFFFF) : accent;
  final paint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 2
    ..strokeCap = StrokeCap.round
    ..color = ink;
  const r = 4.5;
  switch (kind) {
    case HandleKind.delete:
      canvas.drawLine(c + const Offset(-r, -r), c + const Offset(r, r), paint);
      canvas.drawLine(c + const Offset(r, -r), c + const Offset(-r, r), paint);
    case HandleKind.resize:
      canvas.drawLine(c + const Offset(-r, -r), c + const Offset(r, r), paint);
      final head = Path()
        ..moveTo(c.dx + r - 4, c.dy + r)
        ..lineTo(c.dx + r, c.dy + r)
        ..lineTo(c.dx + r, c.dy + r - 4)
        ..moveTo(c.dx - r + 4, c.dy - r)
        ..lineTo(c.dx - r, c.dy - r)
        ..lineTo(c.dx - r, c.dy - r + 4);
      canvas.drawPath(head, paint);
    case HandleKind.rotate:
      canvas.drawArc(
        Rect.fromCircle(center: c, radius: r + 0.5),
        -math.pi * 0.9,
        math.pi * 1.5,
        false,
        paint,
      );
      final tip =
          c +
          Offset(
            math.cos(math.pi * 0.6) * (r + 0.5),
            math.sin(math.pi * 0.6) * (r + 0.5),
          );
      canvas.drawLine(tip, tip + const Offset(3.5, -1), paint);
      canvas.drawLine(tip, tip + const Offset(0.5, -3.5), paint);
    case HandleKind.body:
      break;
  }
}

/// Paints a go-to target pin at [screen].
void paintGoToPin(
  Canvas canvas,
  Offset screen,
  Color accent, {
  double drop = 1,
}) {
  final y = screen.dy - (1 - drop) * 30;
  final tip = Offset(screen.dx, y);
  canvas.drawOval(
    Rect.fromCenter(center: screen, width: 14 * drop, height: 5 * drop),
    Paint()
      ..color = Color.fromRGBO(0, 0, 0, 0.35 * drop)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2),
  );
  final head = Offset(tip.dx, tip.dy - 26);
  final pin = Path()
    ..moveTo(tip.dx, tip.dy)
    ..cubicTo(
      tip.dx - 4,
      tip.dy - 9,
      head.dx - 13,
      head.dy + 7,
      head.dx - 13,
      head.dy,
    )
    ..arcToPoint(
      Offset(head.dx + 13, head.dy),
      radius: const Radius.circular(13),
    )
    ..cubicTo(head.dx + 13, head.dy + 7, tip.dx + 4, tip.dy - 9, tip.dx, tip.dy)
    ..close();
  canvas.drawPath(pin, Paint()..color = accent);
  canvas.drawPath(
    pin,
    Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..color = const Color(0xFFFFFFFF),
  );
  canvas.drawCircle(head, 5, Paint()..color = const Color(0xFFFFFFFF));
}

/// Draws a filled polygon with [ui.Path] helpers (used for map entities).
Path polygonPath(List<Offset> points) => Path()..addPolygon(points, true);
