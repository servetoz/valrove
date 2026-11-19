import 'dart:typed_data';

/// Polyline simplification (radial distance + Douglas–Peucker), a port of
/// simplify.js which Valetudo's web interface uses for robot paths.
///
/// [points] is a flat `[x0, y0, x1, y1, ...]` list. Returns a new flat list.
Float64List simplifyPolyline(Float64List points, double tolerance) {
  final count = points.length ~/ 2;
  if (count <= 2) return Float64List.fromList(points);
  final sqTolerance = tolerance * tolerance;

  // Radial distance pass.
  final radial = <double>[points[0], points[1]];
  var prevX = points[0], prevY = points[1];
  var lastX = prevX, lastY = prevY;
  for (var i = 1; i < count; i++) {
    final x = points[i * 2], y = points[i * 2 + 1];
    lastX = x;
    lastY = y;
    final dx = x - prevX, dy = y - prevY;
    if (dx * dx + dy * dy > sqTolerance) {
      radial
        ..add(x)
        ..add(y);
      prevX = x;
      prevY = y;
    }
  }
  if (prevX != lastX || prevY != lastY) {
    radial
      ..add(lastX)
      ..add(lastY);
  }

  final n = radial.length ~/ 2;
  if (n <= 2) return Float64List.fromList(radial);

  // Iterative Douglas–Peucker pass.
  final keep = Uint8List(n)
    ..[0] = 1
    ..[n - 1] = 1;
  final stack = <int>[0, n - 1];
  while (stack.isNotEmpty) {
    final last = stack.removeLast();
    final first = stack.removeLast();
    var maxSq = sqTolerance;
    var index = -1;
    for (var i = first + 1; i < last; i++) {
      final sq = _segmentDistanceSq(radial, i, first, last);
      if (sq > maxSq) {
        index = i;
        maxSq = sq;
      }
    }
    if (index != -1) {
      keep[index] = 1;
      if (index - first > 1) stack.addAll([first, index]);
      if (last - index > 1) stack.addAll([index, last]);
    }
  }

  var kept = 0;
  for (var i = 0; i < n; i++) {
    if (keep[i] == 1) kept++;
  }
  final out = Float64List(kept * 2);
  var o = 0;
  for (var i = 0; i < n; i++) {
    if (keep[i] == 1) {
      out[o++] = radial[i * 2];
      out[o++] = radial[i * 2 + 1];
    }
  }
  return out;
}

double _segmentDistanceSq(List<double> p, int i, int a, int b) {
  final px = p[i * 2], py = p[i * 2 + 1];
  var x = p[a * 2], y = p[a * 2 + 1];
  var dx = p[b * 2] - x, dy = p[b * 2 + 1] - y;
  if (dx != 0 || dy != 0) {
    final t = ((px - x) * dx + (py - y) * dy) / (dx * dx + dy * dy);
    if (t > 1) {
      x = p[b * 2];
      y = p[b * 2 + 1];
    } else if (t > 0) {
      x += dx * t;
      y += dy * t;
    }
  }
  dx = px - x;
  dy = py - y;
  return dx * dx + dy * dy;
}
