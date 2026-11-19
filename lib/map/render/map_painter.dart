import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/animation.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart' show IconData;

import '../../core/valetudo/models/map_data.dart';
import '../../core/valetudo/models/robot_state.dart';
import '../editing/shapes.dart';
import '../map_controller.dart';
import '../processing/map_processor.dart';
import 'map_scene.dart';
import 'viewport.dart';

/// Theme-dependent colors of the map.
class MapStyle {
  const MapStyle({
    required this.isDark,
    required this.accent,
    required this.background,
    required this.labelBackground,
    required this.labelForeground,
    required this.labelBorder,
    required this.pathColor,
    required this.coveragePathColor,
    required this.chargerBackground,
    required this.chargerForeground,
  });

  /// The robot's trail, in both themes.
  static const trailColor = Color(0xFF000000);

  factory MapStyle.of({
    required bool dark,
    required Color accent,
    required Color background,
  }) => dark
      ? MapStyle(
          isDark: true,
          accent: accent,
          background: background,
          labelBackground: const Color(0xD9161A22),
          labelForeground: const Color(0xFFF1F4F9),
          labelBorder: const Color(0x26FFFFFF),
          pathColor: trailColor,
          coveragePathColor: const Color(0xB3FFFFFF),
          chargerBackground: const Color(0xFF232937),
          chargerForeground: const Color(0xFF34D399),
        )
      : MapStyle(
          isDark: false,
          accent: accent,
          background: background,
          labelBackground: const Color(0xEBFFFFFF),
          labelForeground: const Color(0xFF151A23),
          labelBorder: const Color(0x14000000),
          pathColor: trailColor,
          coveragePathColor: const Color(0xF2FFFFFF),
          chargerBackground: const Color(0xFFFFFFFF),
          chargerForeground: const Color(0xFF059669),
        );

  final bool isDark;
  final Color accent;
  final Color background;
  final Color labelBackground;
  final Color labelForeground;
  final Color labelBorder;

  /// The robot's trail and its planned route.
  final Color pathColor;

  /// The line inside the coverage map's wide trail.
  final Color coveragePathColor;
  final Color chargerBackground;
  final Color chargerForeground;
}

/// Animated robot pose in world coordinates.
class RobotPose {
  const RobotPose(this.position, this.angle);

  final Offset position;

  /// Degrees, clockwise from "up".
  final double angle;

  static RobotPose lerp(RobotPose a, RobotPose b, double t) {
    var d = (b.angle - a.angle) % 360;
    if (d > 180) d -= 360;
    if (d < -180) d += 360;
    return RobotPose(Offset.lerp(a.position, b.position, t)!, a.angle + d * t);
  }
}

/// Mutable inputs of [MapPainter]; notifying repaints the map without
/// rebuilding any widgets.
class MapRenderState extends ChangeNotifier {
  MapScene? scene;
  MapViewport viewport = MapViewport.identity;
  MapStyle? style;
  RobotPose? robot;
  RobotPose? charger;

  /// 0..1 repeating phase of the beacon animation.
  double pulse = 0;

  /// Whether the robot is actively moving (pulse rings, heading cone).
  bool robotActive = false;

  /// Robot is charging (dock glows).
  bool charging = false;

  /// How rooms the map marks as `active` are shown: pulsing while they are
  /// cleaned, highlighted while the job is interrupted, hidden when stale.
  JobState job = JobState.none;

  /// Icons drawn in the labels of rooms with a known kind, by segment id.
  Map<String, IconData> roomIcons = const {};

  /// Colour laid over rooms (e.g. by when they were cleaned last).
  Map<String, Color> roomTints = const {};

  /// Short text shown in a room's label instead of its area ("2 d").
  Map<String, String> roomNotes = const {};

  /// A path to draw instead of the robot's current one (world pixels).
  Path? overlayPath;

  /// Coloured squares over the floor (world pixels), e.g. Wi-Fi readings.
  List<({Rect rect, Color color})> overlayRects = const [];

  /// Marked spots (world pixels), e.g. where an obstacle was found.
  List<Offset> markers = const [];

  /// Draw the robot's current path.
  bool showLivePath = true;

  /// Show room labels at every zoom level.
  bool alwaysShowLabels = false;

  /// 0..1 progress of the latest selection change.
  double selectionT = 1;
  Set<String> previousSelection = const {};

  /// 0..1 drop-in animation of the go-to pin.
  double pinDrop = 1;

  /// Map entities converted to shapes (restrictions & annotations).
  List<EditableShape> entityShapes = const [];

  /// Segments rendered with an order badge (custom order support).
  bool showSelectionOrder = false;

  /// Persisted clean order (fork feature) shown in labels when available.
  bool showCleanOrder = false;

  bool showLabels = true;

  void markNeedsPaint() => notifyListeners();
}

class MapPainter extends CustomPainter {
  MapPainter({
    required this.state,
    required this.controller,
    required this.labels,
  }) : super(repaint: Listenable.merge([state, controller]));

  final MapRenderState state;
  final MapController controller;
  final LabelCache labels;

  static const _dimLight = Color(0xFFF2F4F8);
  static const _dimDark = Color(0xFF0B0D12);

  @override
  void paint(Canvas canvas, Size size) {
    final scene = state.scene;
    final style = state.style;
    if (scene == null || style == null) return;
    final vp = state.viewport;
    final mode = controller.mode;
    final selected = controller.selectedSegments;
    final selectedSet = selected.toSet();
    final selectionMode =
        mode == MapMode.segments || mode == MapMode.editSegments;
    final hasSelection = selectionMode && selected.isNotEmpty;
    final hadSelection = selectionMode && state.previousSelection.isNotEmpty;
    final t = Curves.easeOutCubic.transform(state.selectionT.clamp(0, 1));

    // --- 1. Shadow / ambient glow beneath the floor plan -------------------
    final shadow = scene.shadow;
    if (shadow != null) {
      canvas.save();
      canvas.translate(0, style.isDark ? 0 : 7);
      vp.apply(canvas);
      final glow = style.isDark
          ? style.accent.withValues(alpha: 0.42)
          : const Color(0x33101828);
      canvas.drawImageRect(
        shadow,
        Rect.fromLTWH(0, 0, shadow.width.toDouble(), shadow.height.toDouble()),
        scene.shadowRect.inflate(style.isDark ? 1.5 : 0.6),
        Paint()
          ..filterQuality = FilterQuality.low
          ..colorFilter = ColorFilter.mode(glow, BlendMode.srcIn),
      );
      canvas.restore();
    }

    // --- 2. Raster layers ---------------------------------------------------
    canvas.save();
    vp.apply(canvas);
    final dimTarget = style.isDark ? _dimDark : _dimLight;
    final outlineWidth = 1.6 / vp.scale;
    for (final layer in scene.layers) {
      final id = layer.raster.segmentId;
      final isSegment = layer.raster.type == MapLayerType.segment && id != null;
      // Dim amount for this layer (animated between selection states).
      double dimFor(bool anySelected, Set<String> sel) {
        if (!anySelected) return 0;
        if (isSegment && sel.contains(id)) return 0;
        return layer.raster.type == MapLayerType.wall
            ? 0.25
            : (style.isDark ? 0.55 : 0.5);
      }

      final dim = ui.lerpDouble(
        dimFor(hadSelection, state.previousSelection),
        dimFor(hasSelection, selectedSet),
        t,
      )!;
      final src = Rect.fromLTWH(
        0,
        0,
        layer.image.width.toDouble(),
        layer.image.height.toDouble(),
      );
      final dst = layer.rect;

      final isSelected = isSegment && selectedSet.contains(id);
      final wasSelected = isSegment && state.previousSelection.contains(id);
      final outline = ui.lerpDouble(
        wasSelected ? 1 : 0,
        isSelected ? 1 : 0,
        t,
      )!;
      if (outline > 0.01) {
        final outlinePaint = Paint()
          ..filterQuality = FilterQuality.none
          ..colorFilter = ColorFilter.mode(
            (style.isDark ? const Color(0xFFFFFFFF) : const Color(0xFF0F172A))
                .withValues(alpha: 0.9 * outline),
            BlendMode.srcIn,
          );
        for (final o in const [
          Offset(1, 0),
          Offset(-1, 0),
          Offset(0, 1),
          Offset(0, -1),
        ]) {
          canvas.drawImageRect(
            layer.image,
            src,
            dst.shift(o * outlineWidth),
            outlinePaint,
          );
        }
      }

      final paint = Paint()..filterQuality = FilterQuality.none;
      if (dim > 0.001) paint.colorFilter = _mixFilter(dimTarget, dim);
      canvas.drawImageRect(layer.image, src, dst, paint);

      final tint = isSegment ? state.roomTints[id] : null;
      if (tint != null) {
        canvas.drawImageRect(
          layer.image,
          src,
          dst,
          Paint()
            ..filterQuality = FilterQuality.none
            ..colorFilter = ColorFilter.mode(tint, BlendMode.srcATop),
        );
      }

      final info = isSegment ? scene.data.segment(id) : null;
      if (info != null && info.active && state.job != JobState.none) {
        // A slow "breathing" highlight while the room is being cleaned.
        final a = state.job == JobState.running
            ? 0.16 + 0.16 * (0.5 + 0.5 * math.sin(state.pulse * 2 * math.pi))
            : 0.22;
        canvas.drawImageRect(
          layer.image,
          src,
          dst,
          Paint()
            ..filterQuality = FilterQuality.none
            ..colorFilter = ColorFilter.mode(
              style.accent.withValues(alpha: a),
              BlendMode.srcATop,
            ),
        );
      }
    }

    // --- 3. World-space entities -------------------------------------------
    final map = scene.data.map;
    final ps = map.pixelSize.toDouble();
    for (final e in map.entitiesOfType(MapEntityType.carpet)) {
      _paintCarpet(canvas, e, ps, vp.scale, style);
    }

    final coverage = mode == MapMode.coverage;
    if (coverage && scene.trail != null) {
      canvas.drawPath(
        scene.trail!,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 5
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..color = style.accent.withValues(alpha: style.isDark ? 0.75 : 0.85),
      );
    }

    for (final e in map.entitiesOfType(MapEntityType.activeZone)) {
      if (e.points.length < 8) continue;
      final path = Path()
        ..addPolygon([
          for (var i = 0; i < 8; i += 2)
            Offset(e.points[i] / ps, e.points[i + 1] / ps),
        ], true);
      canvas.drawPath(path, Paint()..color = const Color(0x4D6BF442));
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2 / vp.scale
          ..color = const Color(0xFF35911A),
      );
    }

    for (final r in state.overlayRects) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(r.rect, Radius.circular(r.rect.width * 0.18)),
        Paint()..color = r.color,
      );
    }

    final overlay = state.overlayPath;
    if (overlay != null) {
      canvas.drawPath(
        overlay,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = math.max(0.7, 1.6 / vp.scale)
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..color = style.accent,
      );
    }

    if (scene.trail != null &&
        state.showLivePath &&
        mode != MapMode.editSegments) {
      canvas.drawPath(
        scene.trail!,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = math.max(0.5, 1.15 / vp.scale)
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..color = switch (mode) {
            MapMode.editRestrictions => style.pathColor.withValues(alpha: 0.45),
            MapMode.coverage => style.coveragePathColor,
            _ => style.pathColor,
          },
      );
    }
    canvas.restore();

    // --- 4. Screen-space overlays -------------------------------------------
    final matrix = _matrixOf(vp);
    if (scene.trailHead != null &&
        state.showLivePath &&
        !coverage &&
        mode != MapMode.editSegments &&
        mode != MapMode.editRestrictions) {
      // The latest stretch: the trail's colour, wider, with a soft shadow.
      final head = scene.trailHead!.transform(matrix);
      canvas.drawPath(
        head,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 6
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..color = style.pathColor.withValues(alpha: 0.22)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
      );
      canvas.drawPath(
        head,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.4
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..color = style.pathColor,
      );
    }
    for (final m in state.markers) {
      final p = vp.worldToScreen(m);
      canvas.drawCircle(
        p,
        14,
        Paint()..color = style.accent.withValues(alpha: 0.25),
      );
      canvas.drawCircle(p, 7, Paint()..color = style.accent);
      canvas.drawCircle(
        p,
        7,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = const Color(0xFFFFFFFF),
      );
    }
    if (scene.predicted != null && state.showLivePath) {
      canvas.drawPath(
        dashPath(scene.predicted!.transform(matrix), 5, 5),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..strokeCap = StrokeCap.round
          ..color = style.pathColor.withValues(alpha: 0.85),
      );
    }

    // Restrictions and annotations from the map (hidden while editing them).
    for (final shape in state.entityShapes) {
      final editingRestrictions =
          mode == MapMode.editRestrictions &&
          (shape.kind == ShapeKind.virtualWall ||
              shape.kind == ShapeKind.noGoArea ||
              shape.kind == ShapeKind.noMopArea);
      final editingAnnotations =
          mode == MapMode.editAnnotations &&
          (shape.kind == ShapeKind.threshold ||
              shape.kind == ShapeKind.curtain ||
              shape.kind == ShapeKind.ramp);
      if (editingRestrictions || editingAnnotations) continue;
      paintShape(
        canvas,
        shape,
        vp,
        accent: style.accent,
        pixelSize: map.pixelSize,
      );
    }

    // Robot's own go-to target.
    for (final e in map.entitiesOfType(MapEntityType.goToTarget)) {
      if (e.points.length < 2) continue;
      final p = vp.worldToScreen(Offset(e.points[0] / ps, e.points[1] / ps));
      _paintFlag(canvas, p, style);
    }

    for (final e in map.entitiesOfType(MapEntityType.obstacle)) {
      if (e.points.length < 2) continue;
      _paintObstacle(
        canvas,
        vp.worldToScreen(Offset(e.points[0] / ps, e.points[1] / ps)),
        e,
        vp.scale,
        style,
      );
    }

    if (state.charger != null) _paintCharger(canvas, vp, state.charger!, style);
    if (state.robot != null) _paintRobot(canvas, vp, state.robot!, style);

    if (state.showLabels &&
        mode != MapMode.editRestrictions &&
        mode != MapMode.coverage) {
      _paintLabels(canvas, scene, vp, style, selected, t);
    }

    for (final shape in controller.shapes) {
      paintShape(
        canvas,
        shape,
        vp,
        accent: style.accent,
        pixelSize: map.pixelSize,
      );
    }

    final goTo = controller.goToTarget;
    if (goTo != null) {
      paintGoToPin(
        canvas,
        vp.worldToScreen(goTo),
        style.accent,
        drop: Curves.elasticOut.transform(state.pinDrop.clamp(0, 1)),
      );
    }
  }

  static Float64List _matrixOf(MapViewport vp) {
    final c = math.cos(vp.rotation) * vp.scale;
    final s = math.sin(vp.rotation) * vp.scale;
    return Float64List.fromList([
      c,
      s,
      0,
      0,
      -s,
      c,
      0,
      0,
      0,
      0,
      1,
      0,
      vp.translation.dx,
      vp.translation.dy,
      0,
      1,
    ]);
  }

  /// Color filter mixing every pixel towards [target] by [amount].
  static ColorFilter _mixFilter(Color target, double amount) {
    final k = 1 - amount;
    return ColorFilter.matrix(<double>[
      k, 0, 0, 0, target.r * 255 * amount, //
      0, k, 0, 0, target.g * 255 * amount, //
      0, 0, k, 0, target.b * 255 * amount, //
      0, 0, 0, 1, 0, //
    ]);
  }

  void _paintCarpet(
    Canvas canvas,
    MapEntity e,
    double ps,
    double scale,
    MapStyle style,
  ) {
    if (e.points.length < 6) return;
    final pts = [
      for (var i = 0; i + 1 < e.points.length; i += 2)
        Offset(e.points[i] / ps, e.points[i + 1] / ps),
    ];
    final path = Path()..addPolygon(pts, true);
    canvas.save();
    canvas.clipPath(path);
    final bounds = path.getBounds();
    final hatch = Paint()
      ..strokeWidth = 1 / scale
      ..color =
          (style.isDark ? const Color(0xFFFFFFFF) : const Color(0xFF000000))
              .withValues(alpha: 0.22);
    const step = 1.6;
    for (var d = bounds.left - bounds.height; d < bounds.right; d += step) {
      canvas.drawLine(
        Offset(d, bounds.bottom),
        Offset(d + bounds.height, bounds.top),
        hatch,
      );
    }
    canvas.restore();
  }

  void _paintFlag(Canvas canvas, Offset p, MapStyle style) {
    canvas.drawCircle(
      p,
      6,
      Paint()..color = style.accent.withValues(alpha: 0.25),
    );
    canvas.drawCircle(p, 3, Paint()..color = style.accent);
    final pole = Paint()
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round
      ..color = style.labelForeground;
    canvas.drawLine(p, p + const Offset(0, -20), pole);
    final flag = Path()
      ..moveTo(p.dx, p.dy - 20)
      ..lineTo(p.dx + 12, p.dy - 16)
      ..lineTo(p.dx, p.dy - 12)
      ..close();
    canvas.drawPath(flag, Paint()..color = style.accent);
  }

  void _paintObstacle(
    Canvas canvas,
    Offset p,
    MapEntity e,
    double scale,
    MapStyle style,
  ) {
    final r = (scale * 1.6).clamp(5.0, 12.0);
    canvas.drawCircle(
      p + const Offset(0, 1),
      r + 1,
      Paint()
        ..color = const Color(0x40000000)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2),
    );
    canvas.drawCircle(p, r, Paint()..color = const Color(0xFFF59E0B));
    canvas.drawCircle(
      p,
      r,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = const Color(0xFFFFFFFF),
    );
    if (r >= 7) {
      final ink = Paint()
        ..strokeWidth = math.max(1.6, r * 0.22)
        ..strokeCap = StrokeCap.round
        ..color = const Color(0xFFFFFFFF);
      if (e.id != null) {
        // Camera glyph: obstacle has a photo.
        final body = RRect.fromRectAndRadius(
          Rect.fromCenter(center: p, width: r * 1.1, height: r * 0.8),
          Radius.circular(r * 0.15),
        );
        canvas.drawRRect(body, Paint()..color = const Color(0xFFFFFFFF));
        canvas.drawCircle(
          p,
          r * 0.22,
          Paint()..color = const Color(0xFFF59E0B),
        );
      } else {
        canvas.drawLine(p + Offset(0, -r * 0.45), p + Offset(0, r * 0.1), ink);
        canvas.drawCircle(
          p + Offset(0, r * 0.45),
          ink.strokeWidth * 0.55,
          Paint()..color = const Color(0xFFFFFFFF),
        );
      }
    }
    if (e.label != null && scale >= 9) {
      _paintPill(canvas, p + Offset(0, r + 14), e.label!, style, fontSize: 11);
    }
  }

  void _paintCharger(
    Canvas canvas,
    MapViewport vp,
    RobotPose charger,
    MapStyle style,
  ) {
    final p = vp.worldToScreen(charger.position);
    final size = (vp.scale * 5).clamp(18.0, 30.0);
    final rect = RRect.fromRectAndRadius(
      Rect.fromCenter(center: p, width: size, height: size),
      Radius.circular(size * 0.32),
    );
    if (state.charging) {
      canvas.drawRRect(
        rect.inflate(4),
        Paint()
          ..color = style.chargerForeground.withValues(alpha: 0.35)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
      );
    }
    canvas.drawRRect(
      rect.shift(const Offset(0, 1.5)),
      Paint()
        ..color = const Color(0x33000000)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
    );
    canvas.drawRRect(rect, Paint()..color = style.chargerBackground);
    canvas.drawRRect(
      rect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = style.chargerForeground.withValues(alpha: 0.6),
    );
    final s = size / 24;
    final bolt = Path()
      ..moveTo(p.dx + 1.5 * s, p.dy - 7 * s)
      ..lineTo(p.dx - 4.5 * s, p.dy + 1 * s)
      ..lineTo(p.dx - 0.5 * s, p.dy + 1 * s)
      ..lineTo(p.dx - 1.5 * s, p.dy + 7 * s)
      ..lineTo(p.dx + 4.5 * s, p.dy - 1 * s)
      ..lineTo(p.dx + 0.5 * s, p.dy - 1 * s)
      ..close();
    canvas.drawPath(bolt, Paint()..color = style.chargerForeground);
  }

  void _paintRobot(
    Canvas canvas,
    MapViewport vp,
    RobotPose robot,
    MapStyle style,
  ) {
    final c = vp.worldToScreen(robot.position);
    final d = (vp.scale * 7).clamp(22.0, 46.0);
    final r = d / 2;
    final heading = robot.angle * math.pi / 180 + vp.rotation;
    final dir = Offset(math.sin(heading), -math.cos(heading));
    final accent = style.accent;

    if (state.robotActive) {
      for (var k = 0; k < 2; k++) {
        final phase = (state.pulse + k * 0.5) % 1.0;
        final radius = r * (1.1 + phase * 1.9);
        final alpha = (1 - phase) * 0.32;
        canvas.drawCircle(
          c,
          radius,
          Paint()..color = accent.withValues(alpha: alpha * 0.45),
        );
        canvas.drawCircle(
          c,
          radius,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.5
            ..color = accent.withValues(alpha: alpha),
        );
      }
      // Heading cone.
      const spread = 0.5;
      final len = d * 1.9;
      final cone = Path()
        ..moveTo(c.dx, c.dy)
        ..arcTo(
          Rect.fromCircle(center: c, radius: len),
          heading - math.pi / 2 - spread,
          spread * 2,
          false,
        )
        ..close();
      canvas.drawPath(
        cone,
        Paint()
          ..shader = ui.Gradient.radial(c, len, [
            accent.withValues(alpha: 0.42),
            accent.withValues(alpha: 0),
          ]),
      );
    } else {
      canvas.drawCircle(
        c,
        r * 1.8,
        Paint()
          ..shader = ui.Gradient.radial(c, r * 1.8, [
            accent.withValues(alpha: 0.30),
            accent.withValues(alpha: 0),
          ]),
      );
    }

    canvas.drawCircle(
      c + const Offset(0, 2),
      r,
      Paint()
        ..color = const Color(0x55000000)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
    );
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..shader = ui.Gradient.linear(
          c - Offset(r, r),
          c + Offset(r, r),
          style.isDark
              ? [const Color(0xFFF8FAFC), const Color(0xFFCBD5E1)]
              : [const Color(0xFFFFFFFF), const Color(0xFFE2E8F0)],
        ),
    );
    canvas.drawCircle(
      c,
      r - 1,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(2, d * 0.08)
        ..color = accent,
    );
    // Front bumper arc.
    canvas.drawArc(
      Rect.fromCircle(center: c, radius: r * 0.72),
      heading - math.pi / 2 - 0.9,
      1.8,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(1.4, d * 0.06)
        ..strokeCap = StrokeCap.round
        ..color = const Color(0xFF94A3B8),
    );
    // Lidar turret.
    final turret = c - dir * (r * 0.12);
    canvas.drawCircle(
      turret,
      r * 0.3,
      Paint()..color = const Color(0xFF1E293B),
    );
    canvas.drawCircle(turret, r * 0.12, Paint()..color = accent);
  }

  void _paintLabels(
    Canvas canvas,
    MapScene scene,
    MapViewport vp,
    MapStyle style,
    List<String> selected,
    double t,
  ) {
    final zoomedOut = vp.scale < 1.6;
    for (final seg in scene.data.segments) {
      final index = selected.indexOf(seg.id);
      final isSelected = index >= 0;
      if (zoomedOut && !isSelected && !state.alwaysShowLabels) continue;
      final p = vp.worldToScreen(Offset(seg.labelX, seg.labelY));
      final showArea = vp.scale >= 6;
      final order = state.showSelectionOrder && isSelected
          ? '${index + 1}'
          : (state.showCleanOrder && seg.cleanOrder != null && !isSelected
                ? '${seg.cleanOrder}'
                : null);
      _paintRoomLabel(
        canvas,
        p,
        seg,
        style,
        selected: isSelected,
        order: order,
        orderIsSelection: state.showSelectionOrder && isSelected,
        showArea: showArea,
        popIn: isSelected && !state.previousSelection.contains(seg.id) ? t : 1,
      );
    }
  }

  void _paintRoomLabel(
    Canvas canvas,
    Offset p,
    SegmentInfo seg,
    MapStyle style, {
    required bool selected,
    required String? order,
    required bool orderIsSelection,
    required bool showArea,
    required double popIn,
  }) {
    final fg = selected ? const Color(0xFFFFFFFF) : style.labelForeground;
    final title = labels.get(seg.displayName, 12.5, FontWeight.w600, fg);
    final roomIcon = state.roomIcons[seg.id];
    final icon = roomIcon == null ? null : labels.icon(roomIcon, 14, fg);
    final note = state.roomNotes[seg.id];
    final area = note != null || showArea
        ? labels.get(
            note ?? '${seg.areaSquareMeters.toStringAsFixed(1)} m²',
            10.5,
            FontWeight.w500,
            fg.withValues(alpha: 0.7),
          )
        : null;
    final badgeSize = order != null ? 18.0 : 0.0;
    final activeDot = seg.active && state.job != JobState.none ? 8.0 : 0.0;
    final padH = 10.0;
    final width =
        padH * 2 +
        (icon != null ? icon.width + 5 : 0) +
        title.width +
        (area != null ? 6 + area.width : 0) +
        (badgeSize > 0 ? badgeSize + 6 : 0) +
        (activeDot > 0 ? activeDot + 6 : 0);
    const height = 28.0;
    final scale = 0.85 + 0.15 * popIn;
    canvas.save();
    canvas.translate(p.dx, p.dy);
    canvas.scale(scale);
    final rect = RRect.fromRectAndRadius(
      Rect.fromCenter(center: Offset.zero, width: width, height: height),
      const Radius.circular(14),
    );
    canvas.drawRRect(
      rect.shift(const Offset(0, 2)),
      Paint()
        ..color = const Color(0x2E000000)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5),
    );
    canvas.drawRRect(
      rect,
      Paint()..color = selected ? style.accent : style.labelBackground,
    );
    canvas.drawRRect(
      rect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = selected ? const Color(0x40FFFFFF) : style.labelBorder,
    );
    var x = rect.left + padH;
    if (activeDot > 0) {
      final a = state.job == JobState.running
          ? 0.45 + 0.55 * (0.5 + 0.5 * math.sin(state.pulse * 2 * math.pi))
          : 1.0;
      canvas.drawCircle(
        Offset(x + activeDot / 2, 0),
        activeDot / 2,
        Paint()
          ..color = (selected ? const Color(0xFFFFFFFF) : style.accent)
              .withValues(alpha: a),
      );
      x += activeDot + 6;
    }
    if (badgeSize > 0) {
      final center = Offset(x + badgeSize / 2, 0);
      canvas.drawCircle(
        center,
        badgeSize / 2,
        Paint()
          ..color = orderIsSelection
              ? const Color(0xFFFFFFFF)
              : style.accent.withValues(alpha: 0.18),
      );
      final num = labels.get(
        order!,
        10.5,
        FontWeight.w700,
        orderIsSelection ? style.accent : style.labelForeground,
      );
      num.paint(canvas, center - Offset(num.width / 2, num.height / 2));
      x += badgeSize + 6;
    }
    if (icon != null) {
      icon.paint(canvas, Offset(x, -icon.height / 2));
      x += icon.width + 5;
    }
    title.paint(canvas, Offset(x, -title.height / 2));
    x += title.width;
    if (area != null) {
      area.paint(canvas, Offset(x + 6, -area.height / 2));
    }
    canvas.restore();
  }

  void _paintPill(
    Canvas canvas,
    Offset center,
    String text,
    MapStyle style, {
    double fontSize = 12,
  }) {
    final tp = labels.get(
      text,
      fontSize,
      FontWeight.w500,
      style.labelForeground,
    );
    final rect = RRect.fromRectAndRadius(
      Rect.fromCenter(
        center: center,
        width: tp.width + 14,
        height: tp.height + 6,
      ),
      Radius.circular((tp.height + 6) / 2),
    );
    canvas.drawRRect(rect, Paint()..color = style.labelBackground);
    tp.paint(canvas, Offset(rect.left + 7, rect.top + 3));
  }

  @override
  bool shouldRepaint(MapPainter oldDelegate) =>
      oldDelegate.state != state ||
      oldDelegate.controller != controller ||
      oldDelegate.labels != labels;
}

/// Caches laid-out text so labels are not re-laid-out on every frame.
class LabelCache {
  final Map<(String, double, FontWeight, int), TextPainter> _cache = {};

  TextPainter get(String text, double size, FontWeight weight, Color color) {
    final key = (text, size, weight, color.toARGB32());
    return _cache.putIfAbsent(key, () {
      if (_cache.length > 400) _clear();
      return TextPainter(
        text: TextSpan(
          text: text,
          style: TextStyle(
            fontFamily: 'Inter',
            fontSize: size,
            fontWeight: weight,
            color: color,
            height: 1.1,
          ),
        ),
        textDirection: TextDirection.ltr,
        maxLines: 1,
        ellipsis: '…',
      )..layout(maxWidth: 180);
    });
  }

  final Map<(int, String?, double, int), TextPainter> _icons = {};

  /// A Material icon glyph, laid out like text.
  TextPainter icon(IconData icon, double size, Color color) {
    final key = (icon.codePoint, icon.fontFamily, size, color.toARGB32());
    return _icons.putIfAbsent(key, () {
      if (_icons.length > 200) _clear();
      return TextPainter(
        text: TextSpan(
          text: String.fromCharCode(icon.codePoint),
          style: TextStyle(
            fontFamily: icon.fontFamily,
            package: icon.fontPackage,
            fontSize: size,
            color: color,
            height: 1,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
    });
  }

  void _clear() {
    for (final tp in [..._cache.values, ..._icons.values]) {
      tp.dispose();
    }
    _cache.clear();
    _icons.clear();
  }

  void dispose() => _clear();
}

/// Converts restriction/annotation entities of [map] to (inactive) shapes.
List<EditableShape> entityShapesOf(ValetudoMap map) => [
  ...restrictionShapesFromMap(map),
  ...annotationShapesFromMap(map),
];

/// Robot and charger poses of [map] in world coordinates.
(RobotPose?, RobotPose?) posesOf(ValetudoMap map) {
  RobotPose? pose(String type) {
    final e = map.entityOfType(type);
    if (e == null || e.points.length < 2) return null;
    return RobotPose(
      Offset(e.points[0] / map.pixelSize, e.points[1] / map.pixelSize),
      e.angle ?? 0,
    );
  }

  return (
    pose(MapEntityType.robotPosition),
    pose(MapEntityType.chargerLocation),
  );
}
