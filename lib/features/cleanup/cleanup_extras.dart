import '../../core/cleanup/cleanup_record.dart';
import '../../core/cleanup/cleanup_tracker.dart';
import '../../core/cleanup/consumable_forecast.dart';
import '../../core/cleanup/history_store.dart';
import '../../core/cleanup/lost_found.dart';
import '../../core/cleanup/map_summary.dart';
import '../../core/cleanup/presets.dart';
import '../../core/cleanup/robot_files.dart';
import '../../core/cleanup/sequence.dart';
import '../../core/cleanup/wifi_coverage.dart';
import '../../core/util/format.dart';
import '../../core/valetudo/capabilities.dart';
import '../../core/valetudo/client/valetudo_client.dart';

/// What happened after a cleanup ended.
typedef AfterCleanup = ({List<CleanupAlert> alerts, bool nextStepStarted});

/// Work around a cleanup besides following it: Wi-Fi readings, obstacle
/// photos, consumable forecasts and the next step of a preset. Used by the
/// background service and by the app itself.
class CleanupExtras {
  CleanupExtras({
    required this.client,
    required this.robotId,
    required this.caps,
    required RobotFiles files,
    required this.history,
  }) : wifi = WifiCoverageStore(files),
       found = LostFoundStore(files),
       consumables = ConsumableForecastStore(files),
       sequences = SequenceStore(files);

  final ValetudoClient client;
  final String robotId;
  final Capabilities caps;
  final HistoryStore history;
  final WifiCoverageStore wifi;
  final LostFoundStore found;
  final ConsumableForecastStore consumables;
  final SequenceStore sequences;

  /// Records the Wi-Fi signal where the robot is now.
  Future<void> sampleWifi(MapSummary map) async {
    final position = map.robot;
    if (position == null || !caps.has(Cap.wifiConfiguration)) return;
    final signal = (await client.getWifiStatus()).signal;
    if (signal == null || signal >= 0) return;
    await wifi.add(robotId, position.x, position.y, signal, DateTime.now());
  }

  /// Keeps the obstacles on [map] (with their photos) for lost & found.
  Future<List<FoundObstacle>> collectObstacles(MapSummary map) => found.collect(
    robotId,
    map,
    DateTime.now(),
    photoOf: caps.has(Cap.obstacleImages) ? client.getObstacleImage : null,
  );

  /// Continues a preset that runs in steps and updates the consumable
  /// forecasts (with reminders) after [record].
  Future<AfterCleanup> afterCleanup(
    CleanupRecord record, {
    MapSummary? map,
  }) async {
    final alerts = <CleanupAlert>[];
    var started = false;
    final now = DateTime.now();

    final pending = await sequences.load(robotId);
    switch (decideNextStep(pending, record, now)) {
      case SequenceIdle():
        if (pending != null) await sequences.save(robotId, null);
      case SequenceStopped(:final sequence):
        await sequences.save(robotId, null);
        alerts.add(
          CleanupAlert(
            'sequence',
            '"${sequence.presetName}" stopped',
            'Step ${sequence.stepNumber} of ${sequence.stepCount} did not '
                'finish, so the remaining steps were skipped.',
          ),
        );
      case SequenceContinue(
        :final step,
        :final next,
        :final stepNumber,
        :final stepCount,
      ):
        try {
          await startStep(
            client,
            step,
            caps: caps,
            customOrder: pending!.customOrder,
          );
          await sequences.save(robotId, next);
          started = true;
          alerts.add(
            CleanupAlert(
              'sequence',
              '"${pending.presetName}": step $stepNumber of $stepCount',
              describeStep(step, map),
            ),
          );
        } catch (e) {
          await sequences.save(robotId, null);
          alerts.add(
            CleanupAlert(
              'sequence',
              'Could not start step $stepNumber of "${pending!.presetName}"',
              '$e',
            ),
          );
        }
    }

    if (caps.has(Cap.consumableMonitoring)) {
      try {
        final readings = await client.getConsumables();
        final forecasts = await consumables.load(robotId)
          ..record([
            for (final c in readings)
              (key: c.key, value: c.value, unit: c.unit),
          ], now);
        final perDay = cleaningMinutesPerDay(await history.load(robotId), now);
        for (final key in forecasts.takeDue(
          cleaningMinutesPerDay: perDay,
          now: now,
        )) {
          final c = readings.where((r) => r.key == key).firstOrNull;
          if (c == null) continue;
          final left = forecasts.remaining(
            key,
            cleaningMinutesPerDay: perDay,
            now: now,
          )!;
          alerts.add(
            CleanupAlert(
              'consumable-$key',
              '${consumableName(c.type, c.subType)} wears out soon',
              '${forecastLabel(left)}. Time to get a replacement.',
            ),
          );
        }
        await consumables.save(robotId, forecasts);
      } catch (_) {
        // Next time.
      }
    }
    return (alerts: alerts, nextStepStarted: started);
  }
}

/// "Bedroom, Hallway · Vacuum · Low".
String describeStep(CleanupStep step, MapSummary? map) => [
  if (step.rooms.isEmpty)
    'Whole home'
  else
    joinNames([
      for (final id in step.rooms) map?.room(id)?.displayName ?? 'Room $id',
    ]),
  for (final s in [step.operationMode, step.fanSpeed, step.waterGrade])
    if (s != null) presetLabel(s),
].join(' · ');

/// "About 3 weeks left".
String forecastLabel(Duration left) {
  final days = left.inHours / 24;
  if (days < 1) return 'Less than a day left';
  if (days < 14) return 'About ${days.round()} days left';
  if (days < 60) return 'About ${(days / 7).round()} weeks left';
  return 'About ${(days / 30).round()} months left';
}
