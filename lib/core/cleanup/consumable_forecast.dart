import '../valetudo/json_utils.dart';
import 'cleanup_record.dart';
import 'robot_files.dart';

/// Readings of one consumable since it was last replaced.
class ConsumableTrack {
  ConsumableTrack({required this.unit, List<(DateTime, double)>? samples})
    : samples = samples ?? [];

  /// `minutes` or `percent`.
  String unit;
  final List<(DateTime, double)> samples;

  /// When a reminder went out for the current part.
  DateTime? remindedAt;

  double? get latest => samples.isEmpty ? null : samples.last.$2;
}

/// Learns how fast consumables wear and predicts when they run out.
class ConsumableForecasts {
  ConsumableForecasts([Map<String, ConsumableTrack>? tracks])
    : tracks = tracks ?? {};

  factory ConsumableForecasts.fromJson(Object? json) {
    final out = ConsumableForecasts();
    for (final MapEntry(:key, :value) in asJson(json).entries) {
      final j = asJson(value);
      final track = ConsumableTrack(
        unit: asString(j['unit'], 'percent'),
        samples: [
          for (final s in asList(j['samples']))
            if (asList(s).length == 2)
              (
                DateTime.fromMillisecondsSinceEpoch(asInt(asList(s)[0])),
                asDouble(asList(s)[1]),
              ),
        ],
      );
      final reminded = asIntOrNull(j['remindedAt']);
      if (reminded != null) {
        track.remindedAt = DateTime.fromMillisecondsSinceEpoch(reminded);
      }
      out.tracks[key] = track;
    }
    return out;
  }

  /// Keyed by `type.subType`.
  final Map<String, ConsumableTrack> tracks;

  static const maxSamples = 200;

  /// Only this much history goes into the wear rate.
  static const window = Duration(days: 60);

  /// Reminders go out this long before a part runs out.
  static const remindBefore = Duration(days: 7);

  /// Adds readings taken at [at]. A value that went up means the part was
  /// replaced (or reset), which starts its history over.
  void record(
    Iterable<({String key, double value, String unit})> readings,
    DateTime at,
  ) {
    for (final r in readings) {
      final track = tracks[r.key] ??= ConsumableTrack(unit: r.unit);
      track.unit = r.unit;
      final last = track.samples.lastOrNull;
      if (last != null && r.value > last.$2 + 1) {
        track.samples.clear();
        track.remindedAt = null;
      }
      final previous = track.samples.lastOrNull;
      if (previous == null ||
          previous.$2 != r.value ||
          at.difference(previous.$1) >= const Duration(hours: 12)) {
        track.samples.add((at, r.value));
      }
      if (track.samples.length > maxSamples) {
        track.samples.removeRange(0, track.samples.length - maxSamples);
      }
    }
  }

  /// Time left for [key] at the measured wear rate. Without enough readings,
  /// parts measured in minutes are estimated from [cleaningMinutesPerDay].
  Duration? remaining(
    String key, {
    double cleaningMinutesPerDay = 0,
    DateTime? now,
  }) {
    final track = tracks[key];
    final latest = track?.latest;
    if (track == null || latest == null) return null;
    if (latest <= 0) return Duration.zero;
    final last = track.samples.last;
    final from = last.$1.subtract(window);
    final first = track.samples.firstWhere((s) => !s.$1.isBefore(from));
    final days = last.$1.difference(first.$1).inMinutes / (24 * 60);
    final used = first.$2 - last.$2;
    double? perDay;
    if (days >= 1 && used > 0) {
      perDay = used / days;
    } else if (track.unit == 'minutes' && cleaningMinutesPerDay > 0) {
      perDay = cleaningMinutesPerDay;
    }
    if (perDay == null) return null;
    final left = Duration(minutes: (latest / perDay * 24 * 60).round());
    // Count from now, not from the last reading.
    final since = (now ?? DateTime.now()).difference(last.$1);
    if (since.isNegative) return left;
    return since >= left ? Duration.zero : left - since;
  }

  /// Parts that run out within [remindBefore] and weren't announced yet;
  /// they are marked as announced.
  List<String> takeDue({double cleaningMinutesPerDay = 0, DateTime? now}) {
    final out = <String>[];
    for (final MapEntry(:key, :value) in tracks.entries) {
      if (value.remindedAt != null) continue;
      final left = remaining(
        key,
        cleaningMinutesPerDay: cleaningMinutesPerDay,
        now: now,
      );
      if (left != null && left <= remindBefore) {
        value.remindedAt = now ?? DateTime.now();
        out.add(key);
      }
    }
    return out;
  }

  Json toJson() => {
    for (final MapEntry(:key, :value) in tracks.entries)
      key: {
        'unit': value.unit,
        'samples': [
          for (final (at, v) in value.samples) [at.millisecondsSinceEpoch, v],
        ],
        if (value.remindedAt != null)
          'remindedAt': value.remindedAt!.millisecondsSinceEpoch,
      },
  };
}

/// Average cleaning minutes per day over the last weeks of [history].
double cleaningMinutesPerDay(Iterable<CleanupRecord> history, DateTime now) {
  final recent = [
    for (final r in history)
      if (now.difference(r.startedAt) <= const Duration(days: 30)) r,
  ];
  if (recent.isEmpty) return 0;
  final oldest = recent
      .map((r) => r.startedAt)
      .reduce((a, b) => a.isBefore(b) ? a : b);
  final span = now.difference(oldest).inHours / 24;
  final minutes = recent.fold(0.0, (s, r) => s + r.duration.inSeconds / 60);
  return minutes / (span < 7 ? 7 : span);
}

class ConsumableForecastStore {
  ConsumableForecastStore(this.files);

  final RobotFiles files;
  static const _name = 'consumables';

  Future<ConsumableForecasts> load(String robotId) async =>
      ConsumableForecasts.fromJson(await files.read(robotId, _name));

  Future<void> save(String robotId, ConsumableForecasts forecasts) =>
      files.write(robotId, _name, forecasts.toJson());
}
