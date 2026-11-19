import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/scheduler.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/valetudo/models/robot_state.dart';
import '../../core/valetudo/models/map_data.dart';
import '../editing/shapes.dart';
import '../map_controller.dart';
import '../processing/map_processor.dart';
import '../render/map_painter.dart';
import '../render/map_scene.dart';
import '../render/viewport.dart';
import '../../ui/haptics.dart';

/// Interactive, animated map view.
class MapCanvas extends StatefulWidget {
  const MapCanvas({
    super.key,
    required this.scene,
    required this.controller,
    required this.style,
    this.robotActive = false,
    this.charging = false,
    this.job = JobState.none,
    this.roomIcons = const {},
    this.roomTints = const {},
    this.roomNotes = const {},
    this.overlayPath,
    this.overlayRects = const [],
    this.markers = const [],
    this.showLivePath = true,
    this.alwaysShowLabels = false,
    this.insets = EdgeInsets.zero,
    this.showSelectionOrder = false,
    this.showCleanOrder = false,
    this.maxSegmentSelection,
    this.editingAllowed = true,
    this.onBlockedInteraction,
    this.onObstacleTap,
    this.onSegmentLongPress,
    this.onSelectionLimit,
  });

  final MapScene? scene;
  final MapController controller;
  final MapStyle style;

  /// Robot is moving (pulse rings and heading cone).
  final bool robotActive;
  final bool charging;

  /// Whether the rooms the map marks as `active` are being cleaned (they
  /// pulse), belong to an interrupted job (highlighted) or are stale (hidden).
  final JobState job;

  /// Icons for room labels, by segment id.
  final Map<String, IconData> roomIcons;

  /// Colours laid over rooms, by segment id.
  final Map<String, Color> roomTints;

  /// Text shown in room labels instead of the area, by segment id.
  final Map<String, String> roomNotes;

  /// A recorded path drawn over the map (world pixels).
  final Path? overlayPath;

  /// Coloured squares over the floor (world pixels).
  final List<({Rect rect, Color color})> overlayRects;

  /// Marked spots (world pixels).
  final List<Offset> markers;

  /// Draw the robot's current path.
  final bool showLivePath;

  /// Room labels at every zoom level (small, read-only maps).
  final bool alwaysShowLabels;

  /// Parts of the view covered by overlays; the map is fit into the rest.
  final EdgeInsets insets;
  final bool showSelectionOrder;
  final bool showCleanOrder;
  final int? maxSegmentSelection;

  /// Whether edit interactions (selecting in edit mode, dragging shapes) are
  /// allowed right now (Valetudo only allows editing while docked).
  final bool editingAllowed;
  final VoidCallback? onBlockedInteraction;
  final ValueChanged<MapEntity>? onObstacleTap;
  final ValueChanged<SegmentInfo>? onSegmentLongPress;
  final VoidCallback? onSelectionLimit;

  @override
  State<MapCanvas> createState() => _MapCanvasState();
}

class _MapCanvasState extends State<MapCanvas> with TickerProviderStateMixin {
  final _render = MapRenderState();
  final _labels = LabelCache();

  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2200),
  );
  late final AnimationController _pose = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 650),
  );
  late final AnimationController _camera = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 520),
  );
  late final AnimationController _selection = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 260),
  );
  late final AnimationController _pin = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 700),
  );
  Ticker? _flingTicker;

  RobotPose? _poseFrom;
  RobotPose? _poseTo;
  MapViewport? _cameraFrom;
  MapViewport? _cameraTo;
  Size _size = Size.zero;
  bool _fitted = false;
  String? _fittedMapKey;
  List<String> _lastSelection = const [];
  Offset? _lastGoTo;

  // Gesture state.
  ShapeHit? _dragHit;
  Offset _lastFocal = Offset.zero;
  double _lastScale = 1;
  int _pointers = 0;
  DateTime _lastTapAt = DateTime.fromMillisecondsSinceEpoch(0);
  Offset _lastTapPos = Offset.zero;

  MapController get _controller => widget.controller;

  @override
  void initState() {
    super.initState();
    _pulse.addListener(() {
      _render.pulse = _pulse.value;
      _render.markNeedsPaint();
    });
    _pose.addListener(_updatePose);
    _camera.addListener(_updateCamera);
    _selection.addListener(() {
      _render.selectionT = _selection.value;
      _render.markNeedsPaint();
    });
    _pin.addListener(() {
      _render.pinDrop = _pin.value;
      _render.markNeedsPaint();
    });
    _controller.addListener(_onControllerChanged);
    _controller.onFitRequested = () => _fit(animate: true);
    _lastSelection = _controller.selectedSegments;
    _applyWidget(null);
  }

  @override
  void didUpdateWidget(MapCanvas oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onControllerChanged);
      oldWidget.controller.onFitRequested = null;
      widget.controller.addListener(_onControllerChanged);
      widget.controller.onFitRequested = () => _fit(animate: true);
    }
    _applyWidget(oldWidget);
  }

  void _applyWidget(MapCanvas? old) {
    final scene = widget.scene;
    _render
      ..style = widget.style
      ..robotActive = widget.robotActive
      ..charging = widget.charging
      ..job = widget.job
      ..roomIcons = widget.roomIcons
      ..roomTints = widget.roomTints
      ..roomNotes = widget.roomNotes
      ..overlayPath = widget.overlayPath
      ..overlayRects = widget.overlayRects
      ..markers = widget.markers
      ..showLivePath = widget.showLivePath
      ..alwaysShowLabels = widget.alwaysShowLabels
      ..showSelectionOrder = widget.showSelectionOrder
      ..showCleanOrder = widget.showCleanOrder;

    if (scene != null && !identical(scene, old?.scene)) {
      _render.scene = scene;
      _render.entityShapes = entityShapesOf(scene.data.map);
      final (robot, charger) = posesOf(scene.data.map);
      _render.charger = charger;
      _setRobotPose(robot);
      _controller.retainSegments(scene.data.segments.map((s) => s.id).toSet());

      // Re-fit when a different map is shown (multi-map switch, rotation or
      // first load), otherwise keep the user's camera.
      final key = '${scene.data.map.mapId}|${scene.data.map.rotation}';
      if (!_fitted || key != _fittedMapKey) {
        _fittedMapKey = key;
        if (_size != Size.zero) _fit(animate: _fitted);
      }
    }
    if (old != null &&
        old.insets != widget.insets &&
        _fitted &&
        !_userMovedCamera) {
      _fit(animate: true);
    }
    _syncTicker();
    _render.markNeedsPaint();
  }

  bool _userMovedCamera = false;

  void _setRobotPose(RobotPose? pose) {
    if (pose == null) {
      _render.robot = null;
      _poseFrom = _poseTo = null;
      return;
    }
    final current = _render.robot;
    if (current == null || (current.position - pose.position).distance > 120) {
      _poseFrom = _poseTo = pose;
      _render.robot = pose;
      return;
    }
    if (_poseTo != null &&
        (_poseTo!.position - pose.position).distance < 0.01 &&
        (_poseTo!.angle - pose.angle).abs() < 0.5) {
      return;
    }
    _poseFrom = current;
    _poseTo = pose;
    _pose.forward(from: 0);
  }

  void _updatePose() {
    if (_poseFrom == null || _poseTo == null) return;
    _render.robot = RobotPose.lerp(
      _poseFrom!,
      _poseTo!,
      Curves.easeInOutCubic.transform(_pose.value),
    );
    _render.markNeedsPaint();
  }

  void _updateCamera() {
    if (_cameraFrom == null || _cameraTo == null) return;
    _setViewport(
      MapViewport.lerp(
        _cameraFrom!,
        _cameraTo!,
        Curves.easeOutCubic.transform(_camera.value),
      ),
    );
  }

  void _setViewport(MapViewport vp) {
    _render.viewport = vp;
    _controller.viewport = vp;
    _render.markNeedsPaint();
  }

  void _syncTicker() {
    final scene = widget.scene;
    // Rooms only pulse while they are cleaned; stale `active` flags of a
    // finished or cancelled job must not keep the map animating.
    final needsPulse =
        widget.robotActive ||
        (widget.job == JobState.running &&
            (scene?.data.segments.any((s) => s.active) ?? false));
    if (needsPulse && !_pulse.isAnimating) {
      _pulse.repeat();
    } else if (!needsPulse && _pulse.isAnimating) {
      _pulse.stop();
    }
  }

  void _onControllerChanged() {
    final selection = _controller.selectedSegments;
    if (!_listEquals(selection, _lastSelection)) {
      _render.previousSelection = _lastSelection.toSet();
      _lastSelection = selection;
      _selection.forward(from: 0);
    }
    final goTo = _controller.goToTarget;
    if (goTo != _lastGoTo) {
      if (goTo != null) _pin.forward(from: 0);
      _lastGoTo = goTo;
    }
  }

  static bool _listEquals(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  Rect get _visibleRect {
    final rect = widget.insets.deflateRect(Offset.zero & _size);
    return rect.width < 80 || rect.height < 80 ? Offset.zero & _size : rect;
  }

  double get _fitScale {
    final scene = widget.scene;
    if (scene == null) return 1;
    return MapViewport.fit(
      scene.bounds,
      _visibleRect,
      rotation: _rotation(scene),
      padding: 0.12,
    ).scale;
  }

  double _rotation(MapScene scene) => scene.data.map.rotation * math.pi / 180;

  void _fit({required bool animate}) {
    final scene = widget.scene;
    if (scene == null || _size == Size.zero) return;
    final target = MapViewport.fit(
      scene.bounds,
      _visibleRect,
      rotation: _rotation(scene),
      padding: 0.12,
    );
    _fitted = true;
    _userMovedCamera = false;
    if (animate) {
      _animateTo(target);
    } else {
      _setViewport(target);
    }
  }

  void _animateTo(MapViewport target) {
    _stopFling();
    _cameraFrom = _render.viewport;
    _cameraTo = target;
    _camera.forward(from: 0);
  }

  // ---------------------------------------------------------------------------
  // Gestures
  // ---------------------------------------------------------------------------

  bool get _editMode =>
      _controller.mode == MapMode.editSegments ||
      _controller.mode == MapMode.editRestrictions ||
      _controller.mode == MapMode.editAnnotations;

  ShapeHit? _hitShape(Offset screen) {
    final vp = _render.viewport;
    // Active shapes first so their handles win over overlapping shapes.
    final ordered = [
      ..._controller.shapes.where((s) => s.active),
      ..._controller.shapes.where((s) => !s.active),
    ];
    for (final shape in ordered) {
      final hit = shape.hitTest(screen, vp);
      if (hit != null) return hit;
    }
    return null;
  }

  void _onScaleStart(ScaleStartDetails d) {
    _stopFling();
    _camera.stop();
    _lastFocal = d.localFocalPoint;
    _lastScale = 1;
    _pointers = d.pointerCount;
    _dragHit = null;
    if (d.pointerCount == 1 && _controller.interactionEnabled) {
      final hit = _hitShape(d.localFocalPoint);
      if (hit != null && hit.handle != HandleKind.delete) {
        if (_editMode && !widget.editingAllowed) {
          widget.onBlockedInteraction?.call();
          return;
        }
        if (!hit.shape.active) _controller.activateShape(hit.shape);
        _dragHit = hit;
        Haptics.selection();
      }
    }
  }

  void _onScaleUpdate(ScaleUpdateDetails d) {
    final vp = _render.viewport;
    if (_dragHit != null && d.pointerCount == 1) {
      final before = vp.screenToWorld(_lastFocal);
      final after = vp.screenToWorld(d.localFocalPoint);
      _dragHit!.shape.drag(
        _dragHit!.handle,
        after - before,
        after,
        minSize: widget.scene?.data.pixelSize.toDouble() ?? 5,
      );
      _lastFocal = d.localFocalPoint;
      _controller.shapeChanged();
      return;
    }
    _dragHit = null;
    _userMovedCamera = true;
    var next = vp;
    if (d.pointerCount != _pointers) {
      // Finger added/removed: re-anchor to avoid jumps.
      _pointers = d.pointerCount;
      _lastScale = d.scale;
      _lastFocal = d.localFocalPoint;
      return;
    }
    if (d.pointerCount >= 2 && _lastScale > 0) {
      final factor = d.scale / _lastScale;
      next = next.zoomedAt(
        d.localFocalPoint,
        factor,
        minScale: _fitScale * 0.5,
        maxScale: 60,
      );
    }
    next = next.panned(d.localFocalPoint - _lastFocal);
    _lastScale = d.scale;
    _lastFocal = d.localFocalPoint;
    _setViewport(next);
  }

  void _onScaleEnd(ScaleEndDetails d) {
    if (_dragHit != null) {
      _dragHit!.shape.settle();
      _dragHit = null;
      _controller.shapeChanged();
      return;
    }
    final v = d.velocity.pixelsPerSecond;
    if (d.pointerCount == 0 && v.distance > 250) _startFling(v);
  }

  void _startFling(Offset velocity) {
    _stopFling();
    final sx = FrictionSimulation(0.012, 0, velocity.dx);
    final sy = FrictionSimulation(0.012, 0, velocity.dy);
    var lastX = 0.0, lastY = 0.0;
    _flingTicker = createTicker((elapsed) {
      final t = elapsed.inMicroseconds / 1e6;
      final x = sx.x(t), y = sy.x(t);
      _setViewport(_render.viewport.panned(Offset(x - lastX, y - lastY)));
      lastX = x;
      lastY = y;
      if (sx.isDone(t) && sy.isDone(t)) _stopFling();
    })..start();
  }

  void _stopFling() {
    _flingTicker?.dispose();
    _flingTicker = null;
  }

  void _onTapUp(TapUpDetails d) {
    final now = DateTime.now();
    final isDouble =
        now.difference(_lastTapAt) < const Duration(milliseconds: 280) &&
        (d.localPosition - _lastTapPos).distance < 40;
    _lastTapAt = now;
    _lastTapPos = d.localPosition;
    if (!_controller.interactionEnabled) return;

    final vp = _render.viewport;
    final hit = _hitShape(d.localPosition);
    if (hit != null) {
      if (_editMode && !widget.editingAllowed) {
        widget.onBlockedInteraction?.call();
        return;
      }
      if (hit.handle == HandleKind.delete && hit.shape.active) {
        Haptics.light();
        _controller.removeShape(hit.shape);
      } else {
        _controller.activateShape(hit.shape);
      }
      return;
    }
    final hadActiveShape = _controller.shapes.any((s) => s.active);
    if (hadActiveShape) _controller.activateShape(null);

    final obstacle = _obstacleAt(d.localPosition);
    if (obstacle != null && widget.onObstacleTap != null) {
      widget.onObstacleTap!(obstacle);
      return;
    }

    final scene = widget.scene;
    if (scene == null) return;
    final world = vp.screenToWorld(d.localPosition);
    switch (_controller.mode) {
      case MapMode.segments:
      case MapMode.editSegments:
        if (_controller.mode == MapMode.editSegments) {
          if (!widget.editingAllowed) {
            widget.onBlockedInteraction?.call();
            return;
          }
          if (_controller.cuttingLine != null) return;
        }
        final id = scene.data.segmentAt(world.dx, world.dy);
        if (id != null) {
          final ok = _controller.toggleSegment(
            id,
            maxSelection: widget.maxSegmentSelection,
          );
          if (ok) {
            Haptics.selection();
          } else {
            widget.onSelectionLimit?.call();
          }
        }
      case MapMode.goTo:
        Haptics.selection();
        _controller.setGoTo(world);
      case MapMode.view:
      case MapMode.zones:
      case MapMode.editRestrictions:
      case MapMode.editAnnotations:
      case MapMode.coverage:
        if (isDouble && !hadActiveShape) {
          _animateTo(
            vp.zoomedAt(
              d.localPosition,
              2,
              minScale: _fitScale * 0.5,
              maxScale: 60,
            ),
          );
          _userMovedCamera = true;
        }
    }
  }

  void _onLongPressStart(LongPressStartDetails d) {
    final scene = widget.scene;
    if (scene == null || widget.onSegmentLongPress == null) return;
    final world = _render.viewport.screenToWorld(d.localPosition);
    final id = scene.data.segmentAt(world.dx, world.dy);
    final info = id == null ? null : scene.data.segment(id);
    if (info != null) {
      Haptics.medium();
      widget.onSegmentLongPress!(info);
    }
  }

  MapEntity? _obstacleAt(Offset screen) {
    final scene = widget.scene;
    if (scene == null) return null;
    final vp = _render.viewport;
    if (vp.scale < 1.2) return null;
    final ps = scene.data.pixelSize.toDouble();
    final r = (vp.scale * 1.6).clamp(5.0, 12.0) + 10;
    for (final e in scene.data.map.entitiesOfType(MapEntityType.obstacle)) {
      if (e.points.length < 2) continue;
      final p = vp.worldToScreen(Offset(e.points[0] / ps, e.points[1] / ps));
      if ((p - screen).distance <= r) return e;
    }
    return null;
  }

  void _onPointerSignal(PointerSignalEvent event) {
    if (event is PointerScrollEvent) {
      final factor = math.pow(0.998, event.scrollDelta.dy).toDouble();
      _userMovedCamera = true;
      _setViewport(
        _render.viewport.zoomedAt(
          event.localPosition,
          factor,
          minScale: _fitScale * 0.5,
          maxScale: 60,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = constraints.biggest;
        if (size != _size) {
          final first = _size == Size.zero;
          _size = size;
          _controller.viewSize = size;
          if (first || !_userMovedCamera) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) _fit(animate: !first && _fitted);
            });
          }
        }
        _controller.viewInsets = widget.insets;
        return Listener(
          onPointerSignal: _onPointerSignal,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onScaleStart: _onScaleStart,
            onScaleUpdate: _onScaleUpdate,
            onScaleEnd: _onScaleEnd,
            onTapUp: _onTapUp,
            onLongPressStart: widget.onSegmentLongPress == null
                ? null
                : _onLongPressStart,
            child: RepaintBoundary(
              child: CustomPaint(
                size: size,
                painter: MapPainter(
                  state: _render,
                  controller: _controller,
                  labels: _labels,
                ),
                isComplex: true,
                willChange: true,
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  void dispose() {
    _controller.removeListener(_onControllerChanged);
    if (_controller.onFitRequested != null) _controller.onFitRequested = null;
    _stopFling();
    _pulse.dispose();
    _pose.dispose();
    _camera.dispose();
    _selection.dispose();
    _pin.dispose();
    _labels.dispose();
    _render.dispose();
    super.dispose();
  }
}
