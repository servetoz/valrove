import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/valetudo/capabilities.dart';
import '../core/valetudo/client/valetudo_client.dart';
import '../core/valetudo/json_utils.dart';
import '../core/valetudo/models/models.dart';
import 'app_state.dart';
import 'session.dart';

/// Runs [fetch] against the active robot, reporting connectivity and
/// re-running every [poll] while the app is in the foreground.
Future<T> _fetch<T>(
  Ref ref,
  Future<T> Function(ValetudoClient c) fetch, {
  Duration? poll,
}) async {
  final client = requireClient(ref);
  if (poll != null && ref.watch(appInForegroundProvider)) {
    final timer = Timer(poll, ref.invalidateSelf);
    ref.onDispose(timer.cancel);
  }
  try {
    final result = await fetch(client);
    if (ref.mounted) {
      ref.read(connectionHealthProvider.notifier).reportSuccess();
    }
    return result;
  } catch (e) {
    if (ref.mounted) ref.read(connectionHealthProvider.notifier).reportError(e);
    rethrow;
  }
}

// ---------------------------------------------------------------------------
// Presets & cleaning properties
// ---------------------------------------------------------------------------

const presetOrder = [
  'off', 'min', 'low', 'medium', 'high', 'max', 'turbo', //
  'vacuum', 'vacuum_and_mop', 'vacuum_then_mop', 'mop',
];

/// Available presets of a preset capability, sorted like the web UI and
/// without `custom`.
final presetsProvider = FutureProvider.family<List<String>, String>((
  ref,
  capability,
) async {
  final presets = await _fetch(ref, (c) => c.getPresets(capability));
  final list = presets.where((p) => p != 'custom').toList()
    ..sort((a, b) => presetOrder.indexOf(a).compareTo(presetOrder.indexOf(b)));
  return list;
});

final zonePropertiesProvider = FutureProvider<ZoneProperties>(
  (ref) => _fetch(ref, (c) => c.getZoneProperties()),
);

final segmentationPropertiesProvider =
    FutureProvider<MapSegmentationProperties>(
      (ref) => _fetch(ref, (c) => c.getMapSegmentationProperties()),
    );

final segmentsProvider = FutureProvider.autoDispose<List<Segment>>(
  (ref) => _fetch(ref, (c) => c.getSegments()),
);

final segmentMaterialsProvider = FutureProvider<List<String>>(
  (ref) => _fetch(ref, (c) => c.getSupportedSegmentMaterials()),
);

final restrictedZoneTypesProvider = FutureProvider<List<String>>(
  (ref) => _fetch(ref, (c) => c.getSupportedRestrictedZoneTypes()),
);

final annotationTypesProvider = FutureProvider<List<String>>(
  (ref) => _fetch(ref, (c) => c.getSupportedAnnotationTypes()),
);

// ---------------------------------------------------------------------------
// Generic capability state
// ---------------------------------------------------------------------------

final toggleProvider = FutureProvider.autoDispose.family<bool, String>(
  (ref, capability) => _fetch(ref, (c) => c.getToggle(capability)),
);

/// Single-value capabilities, keyed by `(capability, jsonKey)`.
final valueProvider = FutureProvider.autoDispose
    .family<String, (String, String)>(
      (ref, arg) => _fetch(ref, (c) => c.getValue(arg.$1, arg.$2)),
    );

final capabilityPropertiesProvider = FutureProvider.family<Json, String>(
  (ref, capability) => _fetch(ref, (c) => c.getProperties(capability)),
);

// ---------------------------------------------------------------------------
// Robot
// ---------------------------------------------------------------------------

final consumablesProvider = FutureProvider.autoDispose<List<ConsumableState>>(
  (ref) =>
      _fetch(ref, (c) => c.getConsumables(), poll: const Duration(minutes: 5)),
);

final consumablePropertiesProvider = FutureProvider<List<ConsumableMeta>>(
  (ref) => _fetch(ref, (c) => c.getConsumableProperties()),
);

final currentStatisticsProvider = FutureProvider.autoDispose<List<DataPoint>>(
  (ref) => _fetch(
    ref,
    (c) => c.getStatistics(Cap.currentStatistics),
    poll: const Duration(seconds: 30),
  ),
);

final totalStatisticsProvider = FutureProvider.autoDispose<List<DataPoint>>(
  (ref) => _fetch(
    ref,
    (c) => c.getStatistics(Cap.totalStatistics),
    poll: const Duration(seconds: 60),
  ),
);

final speakerVolumeProvider = FutureProvider.autoDispose<int>(
  (ref) => _fetch(ref, (c) => c.getSpeakerVolume()),
);

final voicePackProvider = FutureProvider.autoDispose<VoicePackStatus>((
  ref,
) async {
  final status = await _fetch(ref, (c) => c.getVoicePackStatus());
  if (status.operationType == 'downloading' ||
      status.operationType == 'installing') {
    final timer = Timer(const Duration(seconds: 1), ref.invalidateSelf);
    ref.onDispose(timer.cancel);
  }
  return status;
});

final audioListProvider = FutureProvider.autoDispose<List<AudioEntry>>(
  (ref) => _fetch(ref, (c) => c.getAudioList()),
);

final dndProvider = FutureProvider.autoDispose<DndConfiguration>(
  (ref) => _fetch(ref, (c) => c.getDnd()),
);

final quirksProvider = FutureProvider.autoDispose<List<Quirk>>(
  (ref) => _fetch(ref, (c) => c.getQuirks()),
);

final obstacleImageDimensionsProvider = FutureProvider<ImageDimensions>(
  (ref) => _fetch(ref, (c) => c.getObstacleImageDimensions()),
);

final duststreamingPropertiesProvider =
    FutureProvider.autoDispose<DuststreamingProperties>(
      (ref) => _fetch(ref, (c) => c.getDuststreamingProperties()),
    );

final duststreamingEnabledProvider = FutureProvider.autoDispose<bool>((ref) {
  if (!ref.watch(capsProvider).has(Cap.duststreaming)) {
    return Future.value(false);
  }
  return _fetch(ref, (c) => c.getDuststreamingEnabled());
});

final manualControlEnabledProvider = FutureProvider.autoDispose<bool>(
  (ref) => _fetch(
    ref,
    (c) => c.getManualControlEnabled(),
    poll: const Duration(seconds: 10),
  ),
);

final movementCommandsProvider = FutureProvider<List<String>>(
  (ref) => _fetch(ref, (c) => c.getSupportedMovementCommands()),
);

final highResManualControlEnabledProvider = FutureProvider.autoDispose<bool>(
  (ref) => _fetch(
    ref,
    (c) => c.getHighResolutionManualControlEnabled(),
    poll: const Duration(seconds: 10),
  ),
);

final robotMapsProvider = FutureProvider.autoDispose<List<RobotMapEntry>>(
  (ref) => _fetch(ref, (c) => c.getMaps(), poll: const Duration(seconds: 30)),
);

final persistentMapProvider = FutureProvider.autoDispose<bool>(
  (ref) => _fetch(ref, (c) => c.getPersistentMapEnabled()),
);

final pendingMapChangeProvider = FutureProvider.autoDispose<bool>(
  (ref) => _fetch(
    ref,
    (c) => c.getPendingMapChange(),
    poll: const Duration(seconds: 30),
  ),
);

// ---------------------------------------------------------------------------
// Events
// ---------------------------------------------------------------------------

final eventsProvider = FutureProvider<List<ValetudoEvent>>(
  (ref) => _fetch(ref, (c) => c.getEvents(), poll: const Duration(seconds: 30)),
);

// ---------------------------------------------------------------------------
// Timers
// ---------------------------------------------------------------------------

final timersProvider = FutureProvider.autoDispose<List<ValetudoTimer>>((
  ref,
) async {
  final timers = await _fetch(ref, (c) => c.getTimers());
  return timers..sort(
    (a, b) => (a.hour * 60 + a.minute).compareTo(b.hour * 60 + b.minute),
  );
});

final timerPropertiesProvider = FutureProvider<TimerProperties>(
  (ref) => _fetch(ref, (c) => c.getTimerProperties()),
);

/// Fork feature; resolves to null on robots without `/delayedstart`.
final delayedStartSupportedProvider = FutureProvider<bool>((ref) async {
  try {
    await _fetch(ref, (c) => c.getDelayedStart());
    return true;
  } on ValetudoApiException {
    return false;
  }
});

final delayedStartProvider = FutureProvider.autoDispose<DelayedStart?>(
  (ref) => _fetch(
    ref,
    (c) => c.getDelayedStart(),
    poll: const Duration(seconds: 30),
  ),
);

// ---------------------------------------------------------------------------
// System & Valetudo
// ---------------------------------------------------------------------------

final hostInfoProvider = FutureProvider.autoDispose<SystemHostInfo>(
  (ref) => _fetch(
    ref,
    (c) => c.getSystemHostInfo(),
    poll: const Duration(seconds: 5),
  ),
);

final runtimeInfoProvider = FutureProvider.autoDispose<SystemRuntimeInfo>(
  (ref) => _fetch(ref, (c) => c.getSystemRuntimeInfo()),
);

final updaterStateProvider = FutureProvider.autoDispose<UpdaterState>(
  (ref) =>
      _fetch(ref, (c) => c.getUpdaterState(), poll: const Duration(seconds: 5)),
);

final updateProviderProvider = FutureProvider.autoDispose<String>(
  (ref) => _fetch(ref, (c) => c.getUpdateProvider()),
);

final logLevelProvider = FutureProvider.autoDispose<LogLevelInfo>(
  (ref) => _fetch(ref, (c) => c.getLogLevel()),
);

// ---------------------------------------------------------------------------
// Connectivity
// ---------------------------------------------------------------------------

final wifiStatusProvider = FutureProvider.autoDispose<WifiStatus>(
  (ref) => _fetch(ref, (c) => c.getWifiStatus()),
);

final wifiReconfigurationSupportedProvider = FutureProvider.autoDispose<bool>(
  (ref) => _fetch(ref, (c) => c.getProvisionedReconfigurationSupported()),
);

final mqttConfigProvider = FutureProvider.autoDispose<Json>(
  (ref) => _fetch(ref, (c) => c.getMqttConfiguration()),
);

final mqttStatusProvider = FutureProvider.autoDispose<MqttStatus>(
  (ref) =>
      _fetch(ref, (c) => c.getMqttStatus(), poll: const Duration(seconds: 5)),
);

final mqttPropertiesProvider = FutureProvider.autoDispose<Json>(
  (ref) => _fetch(ref, (c) => c.getMqttProperties()),
);

final httpAuthProvider = FutureProvider.autoDispose<Json>(
  (ref) => _fetch(ref, (c) => c.getHttpBasicAuth()),
);

final networkAdvertisementProvider = FutureProvider.autoDispose<bool>(
  (ref) => _fetch(ref, (c) => c.getNetworkAdvertisementEnabled()),
);

final networkAdvertisementPropertiesProvider = FutureProvider.autoDispose<Json>(
  (ref) => _fetch(ref, (c) => c.getNetworkAdvertisementProperties()),
);

final ntpStatusProvider = FutureProvider.autoDispose<NtpStatus>(
  (ref) =>
      _fetch(ref, (c) => c.getNtpStatus(), poll: const Duration(seconds: 5)),
);

final ntpConfigProvider = FutureProvider.autoDispose<Json>(
  (ref) => _fetch(ref, (c) => c.getNtpConfiguration()),
);
