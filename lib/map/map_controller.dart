import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

import 'editing/shapes.dart';
import 'render/viewport.dart';

/// What a tap on the map does.
enum MapMode {
  /// Pan/zoom only (spectator, read-only views).
  view,

  /// Select segments (rooms) for cleaning.
  segments,

  /// Draw cleaning zones.
  zones,

  /// Place a go-to target.
  goTo,

  /// Select up to two segments for join/split/rename/material.
  editSegments,

  /// Edit virtual walls, no-go and no-mop areas.
  editRestrictions,

  /// Edit thresholds, curtains and ramps.
  editAnnotations,

  /// Thick-path coverage view (read-only).
  coverage,
}

/// Interaction state of a map view, shared by the canvas and the controls
/// around it.
class MapController extends ChangeNotifier {
  MapController({MapMode mode = MapMode.view})
    : _mode = mode; // ignore: prefer_initializing_formals

  MapMode _mode;
  final List<String> _selected = [];
  final List<EditableShape> _shapes = [];
  Offset? _goTo;
  bool _interactionEnabled = true;
  int _revision = 0;

  /// Updated by the canvas on every frame; used to place new shapes in the
  /// middle of what the user is looking at.
  MapViewport viewport = MapViewport.identity;
  Size viewSize = Size.zero;
  EdgeInsets viewInsets = EdgeInsets.zero;

  /// Callbacks the canvas registers so that controls can move the camera.
  VoidCallback? onFitRequested;

  MapMode get mode => _mode;

  /// Selected segment ids in selection order.
  List<String> get selectedSegments => List.unmodifiable(_selected);

  List<EditableShape> get shapes => List.unmodifiable(_shapes);

  Offset? get goToTarget => _goTo;

  bool get interactionEnabled => _interactionEnabled;

  /// Bumped on any change of shapes so editors can track unsaved changes.
  int get revision => _revision;

  /// A map action (selection, zones or go-to target) is waiting to be sent.
  bool get hasPendingAction =>
      _selected.isNotEmpty ||
      _goTo != null ||
      _shapes.any((s) => s.kind == ShapeKind.zone);

  Iterable<RectShape> get zones =>
      _shapes.whereType<RectShape>().where((s) => s.kind == ShapeKind.zone);

  LineShape? get cuttingLine => _shapes
      .whereType<LineShape>()
      .where((s) => s.kind == ShapeKind.cuttingLine)
      .firstOrNull;

  int countOf(ShapeKind kind) => _shapes.where((s) => s.kind == kind).length;

  set interactionEnabled(bool value) {
    if (value == _interactionEnabled) return;
    _interactionEnabled = value;
    notifyListeners();
  }

  void setMode(MapMode mode) {
    if (mode == _mode) return;
    _mode = mode;
    _selected.clear();
    _shapes.clear();
    _goTo = null;
    _revision++;
    notifyListeners();
  }

  /// Toggles [id]; returns false if the selection limit prevented it.
  bool toggleSegment(String id, {int? maxSelection}) {
    if (_selected.contains(id)) {
      _selected.remove(id);
    } else {
      if (maxSelection != null && _selected.length >= maxSelection) {
        return false;
      }
      _selected.add(id);
    }
    notifyListeners();
    return true;
  }

  void selectSegments(Iterable<String> ids) {
    _selected
      ..clear()
      ..addAll(ids);
    notifyListeners();
  }

  void clearSelection() {
    if (_selected.isEmpty && cuttingLine == null) return;
    _selected.clear();
    _shapes.removeWhere((s) => s.kind == ShapeKind.cuttingLine);
    notifyListeners();
  }

  /// Drops selected ids that no longer exist after a map update.
  void retainSegments(Set<String> existing) {
    final before = _selected.length;
    _selected.removeWhere((id) => !existing.contains(id));
    if (_selected.length != before) notifyListeners();
  }

  /// Adds a new shape centered in the visible part of the map.
  EditableShape addShape(ShapeKind kind) {
    for (final s in _shapes) {
      s.active = false;
    }
    final shape = createShape(kind, visibleCenter);
    _shapes.add(shape);
    _revision++;
    notifyListeners();
    return shape;
  }

  void removeShape(EditableShape shape) {
    _shapes.remove(shape);
    _revision++;
    notifyListeners();
  }

  void removeShapesWhere(bool Function(EditableShape) test) {
    _shapes.removeWhere(test);
    _revision++;
    notifyListeners();
  }

  void replaceShapes(Iterable<EditableShape> shapes) {
    _shapes
      ..clear()
      ..addAll(shapes);
    _revision++;
    notifyListeners();
  }

  void activateShape(EditableShape? shape) {
    var changed = false;
    for (final s in _shapes) {
      final active = identical(s, shape);
      if (s.active != active) {
        s.active = active;
        changed = true;
      }
    }
    if (changed) notifyListeners();
  }

  /// Called by the canvas while a shape is being dragged.
  void shapeChanged() {
    _revision++;
    notifyListeners();
  }

  void setGoTo(Offset world) {
    _goTo = world;
    notifyListeners();
  }

  void clearGoTo() {
    if (_goTo == null) return;
    _goTo = null;
    notifyListeners();
  }

  /// Clears everything the user has drawn or selected.
  void clearAll() {
    _selected.clear();
    _shapes.removeWhere(
      (s) => s.kind == ShapeKind.zone || s.kind == ShapeKind.cuttingLine,
    );
    _goTo = null;
    _revision++;
    notifyListeners();
  }

  /// World coordinate at the center of the unobstructed part of the view.
  Offset get visibleCenter {
    if (viewSize.isEmpty) return Offset.zero;
    final rect = viewInsets.deflateRect(Offset.zero & viewSize);
    return viewport.screenToWorld(
      rect.isEmpty ? viewSize.center(Offset.zero) : rect.center,
    );
  }

  void requestFit() => onFitRequested?.call();
}
