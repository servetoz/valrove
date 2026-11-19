import 'dart:typed_data';

import '../../core/valetudo/models/map_data.dart';

/// Assigns colors to map segments so that no two adjacent segments share a
/// color (port of Valetudo's `FourColorTheoremSolver`).
///
/// The map is scanned row-by-row and column-by-column (skipping
/// `30 / pixelSize` pixels, roughly a robot diameter) to find segments that
/// are in "line of sight" of each other. Those pairs become graph edges and
/// a greedy coloring, starting with the most connected segment, assigns the
/// lowest free color index.
class FourColorSolver {
  FourColorSolver(List<MapLayer> layers, int pixelSize) {
    final resolution = (30 / pixelSize).floor().clamp(1, 1 << 20);
    final segments = layers
        .where((l) => l.isSegment && l.segmentId != null)
        .toList();
    if (segments.isEmpty) return;

    var minX = 1 << 30, minY = 1 << 30, maxX = -(1 << 30), maxY = -(1 << 30);
    for (final layer in segments) {
      final p = layer.pixels;
      for (var i = 0; i + 1 < p.length; i += 2) {
        final x = p[i], y = p[i + 1];
        if (x < minX) minX = x;
        if (x > maxX) maxX = x;
        if (y < minY) minY = y;
        if (y > maxY) maxY = y;
      }
    }
    if (minX > maxX) return;

    final width = maxX - minX + 1;
    final height = maxY - minY + 1;
    // 0 = no segment, otherwise index + 1 into [ids].
    final grid = Int32List(width * height);
    final ids = <String>[];
    for (final layer in segments) {
      ids.add(layer.segmentId!);
      final marker = ids.length;
      final p = layer.pixels;
      for (var i = 0; i + 1 < p.length; i += 2) {
        grid[(p[i] - minX) + (p[i + 1] - minY) * width] = marker;
      }
    }

    final adjacency = List.generate(ids.length, (_) => <int>{});
    void connect(int a, int b) {
      if (a == 0 || b == 0 || a == b) return;
      adjacency[a - 1].add(b - 1);
      adjacency[b - 1].add(a - 1);
    }

    for (var y = minY; y <= maxY; y += resolution) {
      var current = 0;
      for (var x = minX; x <= maxX; x += resolution) {
        final next = grid[(x - minX) + (y - minY) * width];
        connect(current, next);
        if (next != 0) current = next;
      }
    }
    for (var x = minX; x <= maxX; x += resolution) {
      var current = 0;
      for (var y = minY; y <= maxY; y += resolution) {
        final next = grid[(x - minX) + (y - minY) * width];
        connect(current, next);
        if (next != 0) current = next;
      }
    }

    // Greedy coloring, most connected vertex first (stable for equal degree).
    final order = List.generate(ids.length, (i) => i)
      ..sort((a, b) {
        final byDegree = adjacency[b].length.compareTo(adjacency[a].length);
        return byDegree != 0 ? byDegree : a.compareTo(b);
      });
    final colors = List<int?>.filled(ids.length, null);
    for (final v in order) {
      if (adjacency[v].isEmpty) {
        colors[v] = 0;
        continue;
      }
      final used = <int>{
        for (final n in adjacency[v])
          if (colors[n] != null) colors[n]!,
      };
      var color = 0;
      while (used.contains(color)) {
        color++;
      }
      colors[v] = color;
    }
    for (var i = 0; i < ids.length; i++) {
      _colors[ids[i]] = colors[i] ?? 0;
    }
  }

  final Map<String, int> _colors = {};

  /// Color index for [segmentId], starting at 0.
  int colorOf(String segmentId) => _colors[segmentId] ?? 0;
}
