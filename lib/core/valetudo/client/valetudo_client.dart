import 'dart:async';
import 'dart:convert';

import '../capabilities.dart';
import '../json_utils.dart';
import '../models/models.dart';
import 'sse.dart';
import 'transport.dart';

export 'sse.dart';
export 'transport.dart';

/// Typed access to the Valetudo REST API (`/api/v2`).
///
/// Every method maps 1:1 to an endpoint used by the official web interface,
/// plus a few endpoints that only exist in community forks (those are only
/// ever called when the robot reports the matching capability).
class ValetudoClient {
  ValetudoClient(this.transport);

  factory ValetudoClient.connect(ValetudoEndpoint endpoint) =>
      ValetudoClient(ValetudoTransport(endpoint));

  final ValetudoTransport transport;
  final Map<String, SseChannel> _channels = {};

  ValetudoEndpoint get endpoint => transport.endpoint;

  static String _cap(String capability, [String suffix = '']) =>
      '/robot/capabilities/$capability$suffix';

  // -------------------------------------------------------------------------
  // Live data
  // -------------------------------------------------------------------------

  SseChannel _channel(String path, String event) => _channels.putIfAbsent(
    '$path@$event',
    () => SseChannel(transport: transport, path: path, eventName: event),
  );

  /// Raw JSON strings of `MapUpdated` events. Parsing happens off the UI
  /// isolate, which is why this stays a string.
  SseChannel get mapChannel => _channel('/robot/state/map/sse', 'MapUpdated');

  SseChannel get attributesChannel =>
      _channel('/robot/state/attributes/sse', 'StateAttributesUpdated');

  SseChannel get logChannel =>
      _channel('/valetudo/log/content/sse', 'LogMessage');

  Iterable<SseChannel> get channels => _channels.values;

  /// Reconnects every active SSE channel (used when the app resumes).
  void reconnectChannels() {
    for (final channel in _channels.values) {
      channel.reconnect();
    }
  }

  // -------------------------------------------------------------------------
  // Robot
  // -------------------------------------------------------------------------

  Future<Capabilities> getCapabilities() async =>
      Capabilities.fromJson(await transport.get('/robot/capabilities'));

  Future<RobotInformation> getRobotInformation() async =>
      RobotInformation.fromJson(await transport.get('/robot'));

  Future<RobotProperties> getRobotProperties() async =>
      RobotProperties.fromJson(await transport.get('/robot/properties'));

  Future<RobotState> getStateAttributes() async =>
      RobotState.fromJson(await transport.get('/robot/state/attributes'));

  /// Raw map JSON. Kept as a string so it can be parsed in an isolate.
  Future<String> getMapJson() async {
    final result = await transport.get(
      '/robot/state/map',
      timeout: const Duration(seconds: 20),
    );
    return result is String ? result : jsonEncode(result);
  }

  // -------------------------------------------------------------------------
  // Basic control & presets
  // -------------------------------------------------------------------------

  /// [action] is one of `start`, `stop`, `pause`, `home`.
  Future<void> basicControl(String action) =>
      transport.put(_cap(Cap.basicControl), {'action': action});

  Future<List<String>> getPresets(String capability) async =>
      asStringList(await transport.get(_cap(capability, '/presets')));

  Future<void> setPreset(String capability, String name) =>
      transport.put(_cap(capability, '/preset'), {'name': name});

  Future<void> locate() =>
      transport.put(_cap(Cap.locate), {'action': 'locate'});

  Future<void> goTo(CmPoint point) => transport.put(_cap(Cap.goToLocation), {
    'action': 'goto',
    'coordinates': point.toJson(),
  });

  // -------------------------------------------------------------------------
  // Zones & segments
  // -------------------------------------------------------------------------

  Future<ZoneProperties> getZoneProperties() async => ZoneProperties.fromJson(
    await transport.get(_cap(Cap.zoneCleaning, '/properties')),
  );

  Future<void> cleanZones(List<CmQuad> zones, {int iterations = 1}) =>
      transport.put(_cap(Cap.zoneCleaning), {
        'action': 'clean',
        'zones': zones.map((z) => z.toJson()).toList(),
        'iterations': iterations,
      });

  Future<List<Segment>> getSegments() async =>
      asJsonList(await transport.get(_cap(Cap.mapSegmentation)))
          .map(Segment.fromJson)
          .toList();

  Future<MapSegmentationProperties> getMapSegmentationProperties() async =>
      MapSegmentationProperties.fromJson(
        await transport.get(_cap(Cap.mapSegmentation, '/properties')),
      );

  Future<void> cleanSegments(
    List<String> segmentIds, {
    int iterations = 1,
    bool customOrder = false,
  }) => transport.put(_cap(Cap.mapSegmentation), {
    'action': 'start_segment_action',
    'segment_ids': segmentIds,
    'iterations': iterations,
    'customOrder': customOrder,
  });

  Future<void> joinSegments(String segmentA, String segmentB) =>
      transport.put(_cap(Cap.mapSegmentEdit), {
        'action': 'join_segments',
        'segment_a_id': segmentA,
        'segment_b_id': segmentB,
      });

  Future<void> splitSegment(String segmentId, CmPoint pA, CmPoint pB) =>
      transport.put(_cap(Cap.mapSegmentEdit), {
        'action': 'split_segment',
        'segment_id': segmentId,
        'pA': pA.toJson(),
        'pB': pB.toJson(),
      });

  Future<void> renameSegment(String segmentId, String name) => transport.put(
    _cap(Cap.mapSegmentRename),
    {'action': 'rename_segment', 'segment_id': segmentId, 'name': name},
  );

  Future<List<String>> getSupportedSegmentMaterials() async => asStringList(
    asJson(
      await transport.get(_cap(Cap.mapSegmentMaterialControl, '/properties')),
    )['supportedMaterials'],
  );

  Future<void> setSegmentMaterial(String segmentId, String material) =>
      transport.put(_cap(Cap.mapSegmentMaterialControl), {
        'action': 'set_material',
        'segment_id': segmentId,
        'material': material,
      });

  /// Fork feature: persist the cleaning order of segments.
  Future<void> orderSegments(List<String> segmentIds) => transport.put(
    _cap(Cap.mapSegmentCleanOrder),
    {'action': 'order_segments', 'segment_ids': segmentIds},
  );

  // -------------------------------------------------------------------------
  // Virtual restrictions & annotations
  // -------------------------------------------------------------------------

  Future<List<String>> getSupportedRestrictedZoneTypes() async => asStringList(
    asJson(
      await transport.get(_cap(Cap.combinedVirtualRestrictions, '/properties')),
    )['supportedRestrictedZoneTypes'],
  );

  Future<void> setVirtualRestrictions(
    List<VirtualWall> walls,
    List<RestrictedZone> zones,
  ) => transport.put(_cap(Cap.combinedVirtualRestrictions), {
    'virtualWalls': walls.map((w) => w.toJson()).toList(),
    'restrictedZones': zones.map((z) => z.toJson()).toList(),
  });

  Future<List<String>> getSupportedAnnotationTypes() async => asStringList(
    asJson(
      await transport.get(_cap(Cap.mapAnnotations, '/properties')),
    )['supportedAnnotationTypes'],
  );

  Future<void> setMapAnnotations(List<MapAnnotation> annotations) =>
      transport.put(
        _cap(Cap.mapAnnotations),
        annotations.map((a) => a.toJson()).toList(),
      );

  // -------------------------------------------------------------------------
  // Map management
  // -------------------------------------------------------------------------

  Future<bool> getPersistentMapEnabled() => getToggle(Cap.persistentMapControl);

  Future<void> resetMap() =>
      transport.put(_cap(Cap.mapReset), {'action': 'reset'});

  Future<void> startMappingPass() =>
      transport.put(_cap(Cap.mappingPass), {'action': 'start_mapping'});

  Future<bool> getPendingMapChange() async => asBool(
    asJson(await transport.get(_cap(Cap.pendingMapChangeHandling)))['pending'],
  );

  /// [action] is `accept` or `reject`.
  Future<void> handlePendingMapChange(String action) =>
      transport.put(_cap(Cap.pendingMapChangeHandling), {'action': action});

  // Fork: multiple maps
  Future<List<RobotMapEntry>> getMaps() async =>
      asJsonList(await transport.get(_cap(Cap.multipleMap)))
          .map(RobotMapEntry.fromJson)
          .toList();

  Future<void> switchMap(String id) =>
      transport.put(_cap(Cap.multipleMap), {'action': 'switch_map', 'id': id});

  Future<void> deleteMap(String id) => transport.put(
    _cap(Cap.multipleMapDelete),
    {'action': 'delete_map', 'id': id},
  );

  Future<void> renameMap(String id, String name) => transport.put(
    _cap(Cap.multipleMapRename),
    {'action': 'rename_map', 'id': id, 'name': name},
  );

  Future<void> rotateMap(String id, double angle) => transport.put(
    _cap(Cap.multipleMapRotate),
    {'action': 'rotate_map', 'id': id, 'angle': angle},
  );

  // -------------------------------------------------------------------------
  // Generic capability helpers
  // -------------------------------------------------------------------------

  /// State of a `SimpleToggleCapability` (`{enabled: bool}`).
  Future<bool> getToggle(String capability) async =>
      asBool(asJson(await transport.get(_cap(capability)))['enabled']);

  Future<void> setToggle(String capability, bool enabled) => transport.put(
    _cap(capability),
    {'action': enabled ? 'enable' : 'disable'},
  );

  /// Reads a single-value capability such as `{mode: "lift"}`.
  Future<String> getValue(String capability, String key) async =>
      asString(asJson(await transport.get(_cap(capability)))[key]);

  Future<void> setValue(String capability, String key, String value) =>
      transport.put(_cap(capability), {key: value});

  Future<Json> getProperties(String capability) async =>
      asJson(await transport.get(_cap(capability, '/properties')));

  /// Sends a fire-and-forget trigger like `{action: "trigger"}`.
  Future<void> trigger(String capability, String action) =>
      transport.put(_cap(capability), {'action': action});

  // -------------------------------------------------------------------------
  // Consumables & statistics
  // -------------------------------------------------------------------------

  Future<List<ConsumableState>> getConsumables() async =>
      asJsonList(await transport.get(_cap(Cap.consumableMonitoring)))
          .map(ConsumableState.fromJson)
          .toList();

  Future<List<ConsumableMeta>> getConsumableProperties() async => asJsonList(
    asJson(
      await transport.get(_cap(Cap.consumableMonitoring, '/properties')),
    )['availableConsumables'],
  ).map(ConsumableMeta.fromJson).toList();

  Future<void> resetConsumable(String type, String? subType) {
    final fragment = (subType == null || subType.isEmpty || subType == 'none')
        ? type
        : '$type/$subType';
    return transport.put(_cap(Cap.consumableMonitoring, '/$fragment'), {
      'action': 'reset',
    });
  }

  Future<List<DataPoint>> getStatistics(String capability) async =>
      asJsonList(await transport.get(_cap(capability)))
          .map(DataPoint.fromJson)
          .toList();

  Future<List<String>> getAvailableStatistics(String capability) async =>
      asStringList(
        asJson(
          await transport.get(_cap(capability, '/properties')),
        )['availableStatistics'],
      );

  // -------------------------------------------------------------------------
  // Manual control
  // -------------------------------------------------------------------------

  Future<bool> getManualControlEnabled() => getToggle(Cap.manualControl);

  Future<List<String>> getSupportedMovementCommands() async => asStringList(
    asJson(
      await transport.get(_cap(Cap.manualControl, '/properties')),
    )['supportedMovementCommands'],
  );

  /// [action] is `enable`, `disable` or `move` (with [movementCommand]).
  Future<void> manualControl(String action, {String? movementCommand}) =>
      transport.put(_cap(Cap.manualControl), {
        'action': action,
        'movementCommand': ?movementCommand,
      });

  Future<bool> getHighResolutionManualControlEnabled() =>
      getToggle(Cap.highResolutionManualControl);

  Future<void> highResolutionManualControl(
    String action, {
    double? velocity,
    double? angle,
  }) => transport.put(_cap(Cap.highResolutionManualControl), {
    'action': action,
    if (velocity != null && angle != null)
      'vector': {'velocity': velocity, 'angle': angle},
  });

  // -------------------------------------------------------------------------
  // Speaker, voice packs, audio
  // -------------------------------------------------------------------------

  Future<int> getSpeakerVolume() async => asInt(
    asJson(await transport.get(_cap(Cap.speakerVolumeControl)))['volume'],
  );

  Future<void> setSpeakerVolume(int volume) => transport.put(
    _cap(Cap.speakerVolumeControl),
    {'action': 'set_volume', 'value': volume},
  );

  Future<void> playTestSound() =>
      transport.put(_cap(Cap.speakerTest), {'action': 'play_test_sound'});

  Future<VoicePackStatus> getVoicePackStatus() async =>
      VoicePackStatus.fromJson(
        await transport.get(_cap(Cap.voicePackManagement)),
      );

  Future<void> downloadVoicePack({
    required String url,
    required String language,
    required String hash,
  }) => transport.put(_cap(Cap.voicePackManagement), {
    'action': 'download',
    'url': url,
    'language': language,
    'hash': hash,
  });

  Future<List<AudioEntry>> getAudioList() async =>
      asJsonList(await transport.get(_cap(Cap.speakerPlayAudio)))
          .map(AudioEntry.fromJson)
          .toList();

  Future<void> playAudio(String id) => transport.put(
    _cap(Cap.speakerPlayAudio),
    {'action': 'play_audio', 'id': id},
  );

  // -------------------------------------------------------------------------
  // Do not disturb, quirks, obstacle images, camera
  // -------------------------------------------------------------------------

  Future<DndConfiguration> getDnd() async =>
      DndConfiguration.fromJson(await transport.get(_cap(Cap.doNotDisturb)));

  Future<void> setDnd(DndConfiguration configuration) =>
      transport.put(_cap(Cap.doNotDisturb), configuration.toJson());

  Future<List<Quirk>> getQuirks() async =>
      asJsonList(await transport.get(_cap(Cap.quirks)))
          .map(Quirk.fromJson)
          .toList();

  Future<void> setQuirk(String id, String value) =>
      transport.put(_cap(Cap.quirks), {'id': id, 'value': value});

  Future<ImageDimensions> getObstacleImageDimensions() async {
    final dims = asJson(
      (await getProperties(Cap.obstacleImages))['dimensions'],
    );
    return ImageDimensions(
      asInt(dims['width'], 640),
      asInt(dims['height'], 480),
    );
  }

  String obstacleImagePath(String id) => _cap(Cap.obstacleImages, '/img/$id');

  Future<List<int>> getObstacleImage(String id) => transport.getBytes(
    obstacleImagePath(id),
    timeout: const Duration(seconds: 20),
  );

  Future<DuststreamingProperties> getDuststreamingProperties() async =>
      DuststreamingProperties.fromJson(
        await transport.get(_cap(Cap.duststreaming, '/properties')),
      );

  Future<bool> getDuststreamingEnabled() async => asBool(
    asJson(await transport.get('/valetudo/config/duststreaming'))['enabled'],
  );

  Future<void> setDuststreamingEnabled(bool enabled) =>
      transport.put('/valetudo/config/duststreaming', {'enabled': enabled});

  String get duststreamPath => _cap(Cap.duststreaming, '/stream');

  // -------------------------------------------------------------------------
  // Wi-Fi
  // -------------------------------------------------------------------------

  Future<WifiStatus> getWifiStatus() async =>
      WifiStatus.fromJson(await transport.get(_cap(Cap.wifiConfiguration)));

  Future<bool> getProvisionedReconfigurationSupported() async => asBool(
    (await getProperties(
      Cap.wifiConfiguration,
    ))['provisionedReconfigurationSupported'],
  );

  Future<void> setWifiConfiguration({
    required String ssid,
    required String password,
  }) => transport.put(_cap(Cap.wifiConfiguration), {
    'ssid': ssid,
    'credentials': {
      'type': 'wpa2_psk',
      'typeSpecificSettings': {'password': password},
    },
  }, const Duration(seconds: 30));

  Future<List<WifiNetwork>> scanWifi() async => asJsonList(
    await transport.get(
      _cap(Cap.wifiScan),
      timeout: const Duration(seconds: 45),
    ),
  ).map(WifiNetwork.fromJson).toList();

  // -------------------------------------------------------------------------
  // Valetudo
  // -------------------------------------------------------------------------

  Future<ValetudoInformation> getValetudoInformation() async =>
      ValetudoInformation.fromJson(await transport.get('/valetudo'));

  Future<ValetudoVersion> getValetudoVersion() async =>
      ValetudoVersion.fromJson(await transport.get('/valetudo/version'));

  Future<void> valetudoAction(String action) =>
      transport.put('/valetudo/action', {'action': action});

  Future<ValetudoCustomizations> getCustomizations() async =>
      ValetudoCustomizations.fromJson(
        await transport.get('/valetudo/config/customizations'),
      );

  Future<void> setCustomizations(ValetudoCustomizations customizations) =>
      transport.put('/valetudo/config/customizations', customizations.toJson());

  Future<String> getLog() async => asString(
    await transport.get(
      '/valetudo/log/content',
      timeout: const Duration(seconds: 30),
    ),
  );

  Future<LogLevelInfo> getLogLevel() async =>
      LogLevelInfo.fromJson(await transport.get('/valetudo/log/level'));

  Future<void> setLogLevel(String level) =>
      transport.put('/valetudo/log/level', {'level': level});

  // -------------------------------------------------------------------------
  // System
  // -------------------------------------------------------------------------

  Future<SystemHostInfo> getSystemHostInfo() async =>
      SystemHostInfo.fromJson(await transport.get('/system/host/info'));

  Future<SystemRuntimeInfo> getSystemRuntimeInfo() async =>
      SystemRuntimeInfo.fromJson(await transport.get('/system/runtime/info'));

  // -------------------------------------------------------------------------
  // Interfaces: MQTT, HTTP auth, network advertisement, NTP
  // -------------------------------------------------------------------------

  Future<Json> getMqttConfiguration() async =>
      asJson(await transport.get('/valetudo/config/interfaces/mqtt'));

  Future<void> setMqttConfiguration(Json configuration) =>
      transport.put('/valetudo/config/interfaces/mqtt', configuration);

  Future<MqttStatus> getMqttStatus() async =>
      MqttStatus.fromJson(await transport.get('/mqtt/status'));

  Future<Json> getMqttProperties() async =>
      asJson(await transport.get('/mqtt/properties'));

  Future<Json> getHttpBasicAuth() async => asJson(
    await transport.get('/valetudo/config/interfaces/http/auth/basic'),
  );

  Future<void> setHttpBasicAuth({
    required bool enabled,
    required String username,
    required String password,
  }) => transport.put('/valetudo/config/interfaces/http/auth/basic', {
    'enabled': enabled,
    'username': username,
    'password': password,
  });

  Future<bool> getNetworkAdvertisementEnabled() async => asBool(
    asJson(await transport.get('/networkadvertisement/config'))['enabled'],
  );

  Future<void> setNetworkAdvertisementEnabled(bool enabled) =>
      transport.put('/networkadvertisement/config', {'enabled': enabled});

  Future<Json> getNetworkAdvertisementProperties() async =>
      asJson(await transport.get('/networkadvertisement/properties'));

  Future<NtpStatus> getNtpStatus() async =>
      NtpStatus.fromJson(await transport.get('/ntpclient/status'));

  Future<Json> getNtpConfiguration() async =>
      asJson(await transport.get('/ntpclient/config'));

  Future<void> setNtpConfiguration(Json configuration) =>
      transport.put('/ntpclient/config', configuration);

  // -------------------------------------------------------------------------
  // Timers & delayed start
  // -------------------------------------------------------------------------

  Future<List<ValetudoTimer>> getTimers() async {
    final json = asJson(await transport.get('/timers'));
    return json.values.map((v) => ValetudoTimer.fromJson(asJson(v))).toList();
  }

  Future<TimerProperties> getTimerProperties() async =>
      TimerProperties.fromJson(await transport.get('/timers/properties'));

  Future<void> createTimer(ValetudoTimer timer) =>
      transport.post('/timers', timer.toJson());

  Future<void> updateTimer(ValetudoTimer timer) =>
      transport.put('/timers/${timer.id}', timer.toJson());

  Future<void> deleteTimer(String id) => transport.delete('/timers/$id');

  Future<void> executeTimer(String id) =>
      transport.put('/timers/$id/action', {'action': 'execute_now'});

  Future<DelayedStart?> getDelayedStart() async =>
      DelayedStart.fromJson(await transport.get('/delayedstart'));

  Future<void> scheduleDelayedStart({
    required int delaySeconds,
    required TimerAction action,
    List<TimerAction> preActions = const [],
  }) => transport.put('/delayedstart', {
    'delay': delaySeconds,
    'action': action.toJson(),
    'pre_actions': preActions.map((p) => p.toJson()).toList(),
  });

  Future<void> cancelDelayedStart() => transport.delete('/delayedstart');

  // -------------------------------------------------------------------------
  // Events
  // -------------------------------------------------------------------------

  Future<List<ValetudoEvent>> getEvents() async =>
      asJsonList(await transport.get('/events'))
          .map(ValetudoEvent.fromJson)
          .toList();

  /// [interaction] is `ok`, `yes`, `no` or `reset`.
  Future<void> interactWithEvent(String id, String interaction) =>
      transport.put('/events/$id/interact', {'interaction': interaction});

  // -------------------------------------------------------------------------
  // Updater
  // -------------------------------------------------------------------------

  Future<String> getUpdateProvider() async => asString(
    asJson(await transport.get('/updater/config'))['updateProvider'],
    'github',
  );

  Future<void> setUpdateProvider(String provider) =>
      transport.put('/updater/config', {'updateProvider': provider});

  Future<UpdaterState> getUpdaterState() async =>
      UpdaterState.fromJson(await transport.get('/updater/state'));

  /// [action] is `check`, `download` or `apply`.
  Future<void> updaterAction(String action) =>
      transport.put('/updater', {'action': action});

  // -------------------------------------------------------------------------

  void close() {
    for (final channel in _channels.values) {
      channel.dispose();
    }
    _channels.clear();
    transport.close();
  }
}
