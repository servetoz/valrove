import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../core/cleanup/cleanup_record.dart';
import '../core/cleanup/consumable_forecast.dart';
import '../core/cleanup/estimator.dart';
import '../core/cleanup/history_store.dart';
import '../core/cleanup/lost_found.dart';
import '../core/cleanup/presets.dart';
import '../core/cleanup/robot_files.dart';
import '../core/cleanup/wifi_coverage.dart';
import 'app_state.dart';
import 'data.dart';

/// Where recorded cleanups are kept (also used by the background service).
Future<Directory> historyDirectory() async =>
    Directory('${(await getApplicationSupportDirectory()).path}/history');

/// Overridden in tests.
final historyStoreProvider = FutureProvider<HistoryStore>(
  (ref) async => HistoryStore(await historyDirectory()),
);

/// Per-robot files next to the history. Overridden in tests.
final robotFilesProvider = FutureProvider<RobotFiles>(
  (ref) async => RobotFiles(await historyDirectory()),
);

/// Wi-Fi signal measured during cleanups of the active robot.
final wifiCoverageProvider = FutureProvider<WifiCoverage>((ref) async {
  final robotId = ref.watch(activeProfileProvider.select((p) => p?.id));
  if (robotId == null) return WifiCoverage();
  return WifiCoverageStore(await ref.watch(robotFilesProvider.future))
      .load(robotId);
});

/// Obstacles the active robot photographed, newest first.
final lostFoundProvider = FutureProvider<List<FoundObstacle>>((ref) async {
  final robotId = ref.watch(activeProfileProvider.select((p) => p?.id));
  if (robotId == null) return const [];
  return LostFoundStore(await ref.watch(robotFilesProvider.future))
      .load(robotId);
});

/// Consumable wear of the active robot, updated whenever the consumables are
/// fetched.
final consumableForecastsProvider = FutureProvider<ConsumableForecasts>((
  ref,
) async {
  final robotId = ref.watch(activeProfileProvider.select((p) => p?.id));
  if (robotId == null) return ConsumableForecasts();
  final store = ConsumableForecastStore(
    await ref.watch(robotFilesProvider.future),
  );
  final forecasts = await store.load(robotId);
  final readings = ref.watch(consumablesProvider).value;
  if (readings != null && readings.isNotEmpty) {
    forecasts.record([
      for (final c in readings) (key: c.key, value: c.value, unit: c.unit),
    ], DateTime.now());
    await store.save(robotId, forecasts);
  }
  return forecasts;
});

/// Average cleaning minutes per day, for parts measured in minutes.
final cleaningMinutesPerDayProvider = Provider<double>(
  (ref) => cleaningMinutesPerDay(
    ref.watch(historyProvider).value ?? const [],
    DateTime.now(),
  ),
);

/// Cleanups recorded for the active robot, newest first.
final historyProvider = FutureProvider<List<CleanupRecord>>((ref) async {
  final robotId = ref.watch(activeProfileProvider.select((p) => p?.id));
  if (robotId == null) return const [];
  final store = await ref.watch(historyStoreProvider.future);
  return store.load(robotId);
});

final estimatorProvider = Provider<CleanupEstimator>(
  (ref) => CleanupEstimator(ref.watch(historyProvider).value ?? const []),
);

/// When each room of the active robot was cleaned last.
final lastCleanedProvider = Provider<Map<String, DateTime>>(
  (ref) => lastCleaned(ref.watch(historyProvider).value ?? const []),
);

/// Saved cleanups of the active robot, in the user's order (the first ones
/// go to the widget, the shortcuts and the quick settings tile).
class CleanupPresets extends Notifier<List<CleanupPreset>> {
  String? get _key {
    final id = ref.read(activeProfileProvider)?.id;
    return id == null ? null : 'cleanupPresets.$id';
  }

  @override
  List<CleanupPreset> build() {
    ref.watch(activeProfileProvider.select((p) => p?.id));
    final key = _key;
    final raw = key == null
        ? null
        : ref.read(sharedPreferencesProvider).getString(key);
    if (raw == null) return const [];
    try {
      return [
        for (final p in jsonDecode(raw) as List) CleanupPreset.fromJson(p),
      ];
    } catch (_) {
      return const [];
    }
  }

  static String newId() =>
      '${DateTime.now().millisecondsSinceEpoch.toRadixString(36)}'
      '${math.Random().nextInt(1 << 20).toRadixString(36)}';

  /// Adds [preset], or replaces the one with its id.
  void save(CleanupPreset preset) {
    final i = state.indexWhere((p) => p.id == preset.id);
    _set(i < 0 ? [...state, preset] : ([...state]..[i] = preset));
  }

  void delete(String id) => _set([
    for (final p in state)
      if (p.id != id) p,
  ]);

  void move(int from, int to) {
    final next = [...state];
    next.insert(to, next.removeAt(from));
    _set(next);
  }

  void _set(List<CleanupPreset> presets) {
    state = presets;
    final key = _key;
    if (key == null) return;
    ref
        .read(sharedPreferencesProvider)
        .setString(key, jsonEncode([for (final p in presets) p.toJson()]));
  }
}

final cleanupPresetsProvider =
    NotifierProvider<CleanupPresets, List<CleanupPreset>>(CleanupPresets.new);
