import 'cleanup_record.dart';

/// How long a cleanup should take and how much battery it should use.
class CleanupEstimate {
  const CleanupEstimate({
    required this.duration,
    required this.batteryPercent,
    required this.basedOn,
  });

  final Duration duration;
  final int batteryPercent;

  /// Number of recorded cleanups the time is based on; 0 means typical
  /// values, because nothing was recorded yet.
  final int basedOn;

  /// "≈ 24 min · 15% battery".
  String get label {
    final minutes = duration.inMinutes;
    final time = minutes >= 60
        ? '${minutes ~/ 60} h ${(minutes % 60).toString().padLeft(2, '0')} min'
        : '$minutes min';
    return '≈ $time · $batteryPercent% battery';
  }
}

/// Predicts cleanups from the ones recorded on this phone.
///
/// Speed is measured as room area (as the map reports it) per minute, so it
/// already includes furniture, travelling and the trips back to the dock.
class CleanupEstimator {
  CleanupEstimator(Iterable<CleanupRecord> history)
    : _runs = [
        for (final r in history)
          if (r.outcome == CleanupOutcome.finished &&
              (r.kind == CleanupKind.full || r.kind == CleanupKind.rooms) &&
              r.roomAreaCm2 > 0 &&
              r.duration.inSeconds >= 180)
            r,
      ].take(20).toList(),
      _batteryRuns = [
        for (final r in history)
          if (!r.recharged &&
              r.batteryStart != null &&
              r.batteryEnd != null &&
              r.batteryStart! > r.batteryEnd! &&
              r.duration.inSeconds >= 300)
            r,
      ].take(20).toList();

  final List<CleanupRecord> _runs;
  final List<CleanupRecord> _batteryRuns;

  /// Typical room area (m²) a robot covers per minute.
  static const defaultVacuumRate = 1.3;
  static const defaultMopRate = 0.9;

  /// Typical battery use (%) per minute of cleaning.
  static const defaultBatteryRate = 0.55;

  static bool _mops(String? mode) => mode != null && mode.contains('mop');

  CleanupEstimate estimate({
    required double roomAreaCm2,
    int iterations = 1,
    String? operationMode,
  }) {
    final sameMode = [
      for (final r in _runs)
        if (r.operationMode == operationMode) r,
    ];
    final runs = sameMode.length >= 2 ? sameMode : _runs;
    double rate;
    if (runs.isEmpty) {
      rate = _mops(operationMode) ? defaultMopRate : defaultVacuumRate;
    } else {
      final area = runs.fold(0.0, (s, r) => s + r.roomAreaCm2 / 10000);
      final minutes = runs.fold(0.0, (s, r) => s + r.duration.inSeconds / 60);
      rate = area / minutes;
    }
    final minutes = (roomAreaCm2 / 10000 * iterations / rate).ceil();

    var batteryRate = defaultBatteryRate;
    if (_batteryRuns.isNotEmpty) {
      final used = _batteryRuns.fold(
        0,
        (s, r) => s + r.batteryStart! - r.batteryEnd!,
      );
      final time = _batteryRuns.fold(
        0.0,
        (s, r) => s + r.duration.inSeconds / 60,
      );
      batteryRate = used / time;
    }
    return CleanupEstimate(
      duration: Duration(minutes: minutes < 1 ? 1 : minutes),
      batteryPercent: (minutes * batteryRate).round().clamp(1, 100),
      basedOn: runs.length,
    );
  }
}

/// When each room was last cleaned, from [history] (newest first).
Map<String, DateTime> lastCleaned(Iterable<CleanupRecord> history) {
  final out = <String, DateTime>{};
  for (final r in history) {
    final counts =
        r.outcome == CleanupOutcome.finished ||
        (r.duration.inSeconds >= 180 && (r.areaCm2 ?? 0) > 0);
    if (!counts) continue;
    for (final room in r.rooms) {
      final previous = out[room.id];
      if (previous == null || previous.isBefore(r.endedAt)) {
        out[room.id] = r.endedAt;
      }
    }
  }
  return out;
}
