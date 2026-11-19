/// Capability names as reported by `GET /api/v2/robot/capabilities`.
///
/// Kept as plain strings so that capabilities added by future Valetudo
/// releases or forks never break parsing; the UI simply ignores what it does
/// not know.
abstract final class Cap {
  static const autoEmptyDockAutoEmptyIntervalControl =
      'AutoEmptyDockAutoEmptyIntervalControlCapability';
  static const autoEmptyDockAutoEmptyDurationControl =
      'AutoEmptyDockAutoEmptyDurationControlCapability';
  static const autoEmptyDockManualTrigger =
      'AutoEmptyDockManualTriggerCapability';
  static const basicControl = 'BasicControlCapability';
  static const carpetModeControl = 'CarpetModeControlCapability';
  static const carpetSensorModeControl = 'CarpetSensorModeControlCapability';
  static const cameraLightControl = 'CameraLightControlCapability';
  static const cleanRouteControl = 'CleanRouteControlCapability';
  static const collisionAvoidantNavigation =
      'CollisionAvoidantNavigationControlCapability';
  static const combinedVirtualRestrictions =
      'CombinedVirtualRestrictionsCapability';
  static const consumableMonitoring = 'ConsumableMonitoringCapability';
  static const currentStatistics = 'CurrentStatisticsCapability';
  static const doNotDisturb = 'DoNotDisturbCapability';
  static const fanSpeedControl = 'FanSpeedControlCapability';
  static const floorMaterialDirectionAwareNavigationControl =
      'FloorMaterialDirectionAwareNavigationControlCapability';
  static const goToLocation = 'GoToLocationCapability';
  static const keyLock = 'KeyLockCapability';
  static const locate = 'LocateCapability';
  static const manualControl = 'ManualControlCapability';
  static const highResolutionManualControl =
      'HighResolutionManualControlCapability';
  static const mapReset = 'MapResetCapability';
  static const mapSegmentEdit = 'MapSegmentEditCapability';
  static const mapSegmentRename = 'MapSegmentRenameCapability';
  static const mapSegmentMaterialControl =
      'MapSegmentMaterialControlCapability';
  static const mapSegmentation = 'MapSegmentationCapability';
  static const mapSnapshot = 'MapSnapshotCapability';
  static const mappingPass = 'MappingPassCapability';
  static const mopDockMopWashTemperatureControl =
      'MopDockMopWashTemperatureControlCapability';
  static const mopDockMopDryingTimeControl =
      'MopDockMopDryingTimeControlCapability';
  static const obstacleAvoidanceControl = 'ObstacleAvoidanceControlCapability';
  static const petObstacleAvoidanceControl =
      'PetObstacleAvoidanceControlCapability';
  static const mopExtensionControl = 'MopExtensionControlCapability';
  static const mopTwistControl = 'MopTwistControlCapability';
  static const mopExtensionFurnitureLegHandlingControl =
      'MopExtensionFurnitureLegHandlingControlCapability';
  static const mopDockCleanManualTrigger =
      'MopDockCleanManualTriggerCapability';
  static const mopDockDryManualTrigger = 'MopDockDryManualTriggerCapability';
  static const mopDockMopAutoDryingControl =
      'MopDockMopAutoDryingControlCapability';
  static const operationModeControl = 'OperationModeControlCapability';
  static const persistentMapControl = 'PersistentMapControlCapability';
  static const pendingMapChangeHandling = 'PendingMapChangeHandlingCapability';
  static const speakerTest = 'SpeakerTestCapability';
  static const speakerVolumeControl = 'SpeakerVolumeControlCapability';
  static const totalStatistics = 'TotalStatisticsCapability';
  static const voicePackManagement = 'VoicePackManagementCapability';
  static const waterUsageControl = 'WaterUsageControlCapability';
  static const wifiConfiguration = 'WifiConfigurationCapability';
  static const wifiScan = 'WifiScanCapability';
  static const zoneCleaning = 'ZoneCleaningCapability';
  static const quirks = 'QuirksCapability';
  static const obstacleImages = 'ObstacleImagesCapability';
  static const mapAnnotations = 'MapAnnotationsCapability';
  static const duststreaming = 'DuststreamingCapability';

  // Capabilities found in community forks (e.g. multi-map support). The app
  // lights up the matching UI only when a robot actually reports them.
  static const mapSegmentCleanOrder = 'MapSegmentCleanOrderCapability';
  static const multipleMap = 'MultipleMapCapability';
  static const multipleMapDelete = 'MultipleMapDeleteCapability';
  static const multipleMapRename = 'MultipleMapRenameCapability';
  static const multipleMapRotate = 'MultipleMapRotateCapability';
  static const speakerPlayAudio = 'SpeakerPlayAudioCapability';
}

/// Immutable set of the capabilities a robot supports.
class Capabilities {
  const Capabilities(this._names);

  factory Capabilities.fromJson(Object? json) => Capabilities(
    Set.unmodifiable((json is List ? json : const []).map((e) => e.toString())),
  );

  static const empty = Capabilities(<String>{});

  final Set<String> _names;

  Set<String> get names => _names;

  bool has(String capability) => _names.contains(capability);

  bool hasAny(Iterable<String> capabilities) => capabilities.any(has);

  bool hasAll(Iterable<String> capabilities) => capabilities.every(has);

  bool operator [](String capability) => has(capability);

  @override
  bool operator ==(Object other) =>
      other is Capabilities &&
      other._names.length == _names.length &&
      other._names.containsAll(_names);

  @override
  int get hashCode => Object.hashAllUnordered(_names);
}
