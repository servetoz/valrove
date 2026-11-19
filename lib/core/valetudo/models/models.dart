import '../json_utils.dart';

export 'map_data.dart';
export 'robot_state.dart';

// ---------------------------------------------------------------------------
// Geometry
// ---------------------------------------------------------------------------

/// A point in centimeters (robot coordinate space).
class CmPoint {
  const CmPoint(this.x, this.y);

  factory CmPoint.fromJson(Json json) =>
      CmPoint(asDouble(json['x']), asDouble(json['y']));

  final double x;
  final double y;

  /// Valetudo expects integer coordinates; the web interface floors them.
  Json toJson() => {'x': x.floor(), 'y': y.floor()};

  @override
  String toString() => '($x, $y)';
}

/// A rectangle defined by its four corners (clockwise, starting top-left).
class CmQuad {
  const CmQuad(this.pA, this.pB, this.pC, this.pD);

  factory CmQuad.fromJson(Json json) {
    final points = asJson(json['points']);
    return CmQuad(
      CmPoint.fromJson(asJson(points['pA'])),
      CmPoint.fromJson(asJson(points['pB'])),
      CmPoint.fromJson(asJson(points['pC'])),
      CmPoint.fromJson(asJson(points['pD'])),
    );
  }

  final CmPoint pA;
  final CmPoint pB;
  final CmPoint pC;
  final CmPoint pD;

  Json toJson() => {
    'points': {
      'pA': pA.toJson(),
      'pB': pB.toJson(),
      'pC': pC.toJson(),
      'pD': pD.toJson(),
    },
  };
}

class MinMax {
  const MinMax(this.min, this.max);

  factory MinMax.fromJson(Object? json, {int min = 1, int max = 1}) {
    final j = asJson(json);
    return MinMax(asInt(j['min'], min), asInt(j['max'], max));
  }

  final int min;
  final int max;
}

// ---------------------------------------------------------------------------
// Robot & Valetudo information
// ---------------------------------------------------------------------------

class RobotInformation {
  const RobotInformation({
    required this.manufacturer,
    required this.modelName,
    required this.implementation,
    required this.supportedAttachments,
    required this.supportedDockComponents,
  });

  factory RobotInformation.fromJson(Object? json) {
    final j = asJson(json);
    final details = asJson(j['modelDetails']);
    return RobotInformation(
      manufacturer: asString(j['manufacturer'], 'Unknown'),
      modelName: asString(j['modelName'], 'Robot'),
      implementation: asString(j['implementation']),
      supportedAttachments: asStringList(details['supportedAttachments']),
      supportedDockComponents: asStringList(details['supportedDockComponents']),
    );
  }

  final String manufacturer;
  final String modelName;
  final String implementation;
  final List<String> supportedAttachments;
  final List<String> supportedDockComponents;
}

class RobotProperties {
  const RobotProperties({this.firmwareVersion});

  factory RobotProperties.fromJson(Object? json) => RobotProperties(
    firmwareVersion: asStringOrNull(asJson(json)['firmwareVersion']),
  );

  final String? firmwareVersion;
}

class ValetudoInformation {
  const ValetudoInformation({
    required this.embedded,
    required this.systemId,
    required this.welcomeDialogDismissed,
  });

  factory ValetudoInformation.fromJson(Object? json) {
    final j = asJson(json);
    return ValetudoInformation(
      embedded: asBool(j['embedded']),
      systemId: asString(j['systemId']),
      welcomeDialogDismissed: asBool(j['welcomeDialogDismissed'], true),
    );
  }

  final bool embedded;
  final String systemId;
  final bool welcomeDialogDismissed;
}

class ValetudoVersion {
  const ValetudoVersion({required this.release, required this.commit});

  factory ValetudoVersion.fromJson(Object? json) {
    final j = asJson(json);
    return ValetudoVersion(
      release: asString(j['release'], '?'),
      commit: asString(j['commit'], '?'),
    );
  }

  final String release;
  final String commit;
}

class ValetudoCustomizations {
  const ValetudoCustomizations({required this.friendlyName});

  factory ValetudoCustomizations.fromJson(Object? json) =>
      ValetudoCustomizations(
        friendlyName: asString(asJson(json)['friendlyName']),
      );

  final String friendlyName;

  Json toJson() => {'friendlyName': friendlyName};
}

// ---------------------------------------------------------------------------
// System
// ---------------------------------------------------------------------------

class CpuUsage {
  const CpuUsage({
    required this.user,
    required this.nice,
    required this.sys,
    required this.idle,
    required this.irq,
  });

  factory CpuUsage.fromJson(Json json) {
    final u = asJson(json['usage']);
    return CpuUsage(
      user: asDouble(u['user']),
      nice: asDouble(u['nice']),
      sys: asDouble(u['sys']),
      idle: asDouble(u['idle']),
      irq: asDouble(u['irq']),
    );
  }

  final double user;
  final double nice;
  final double sys;
  final double idle;
  final double irq;
}

class SystemHostInfo {
  const SystemHostInfo({
    required this.hostname,
    required this.arch,
    required this.memTotal,
    required this.memFree,
    required this.memValetudoCurrent,
    required this.memValetudoMax,
    required this.uptime,
    required this.load1,
    required this.load5,
    required this.load15,
    required this.cpus,
  });

  factory SystemHostInfo.fromJson(Object? json) {
    final j = asJson(json);
    final mem = asJson(j['mem']);
    final load = asJson(j['load']);
    return SystemHostInfo(
      hostname: asString(j['hostname']),
      arch: asString(j['arch']),
      memTotal: asDouble(mem['total']),
      memFree: asDouble(mem['free']),
      memValetudoCurrent: asDouble(mem['valetudo_current']),
      memValetudoMax: asDouble(mem['valetudo_max']),
      uptime: asDouble(j['uptime']),
      load1: asDouble(load['1']),
      load5: asDouble(load['5']),
      load15: asDouble(load['15']),
      cpus: asJsonList(j['cpus']).map(CpuUsage.fromJson).toList(),
    );
  }

  final String hostname;
  final String arch;
  final double memTotal;
  final double memFree;
  final double memValetudoCurrent;
  final double memValetudoMax;

  /// Seconds.
  final double uptime;
  final double load1;
  final double load5;
  final double load15;
  final List<CpuUsage> cpus;
}

class SystemRuntimeInfo {
  const SystemRuntimeInfo(this.json);

  factory SystemRuntimeInfo.fromJson(Object? json) =>
      SystemRuntimeInfo(asJson(json));

  final Json json;

  double get uptime => asDouble(json['uptime']);
  List<String> get argv => asStringList(json['argv']);
  List<String> get execArgv => asStringList(json['execArgv']);
  String get execPath => asString(json['execPath']);
  int get uid => asInt(json['uid']);
  int get gid => asInt(json['gid']);
  int get pid => asInt(json['pid']);
  Map<String, String> get versions =>
      asJson(json['versions']).map((k, v) => MapEntry(k, asString(v)));
  Map<String, String> get env =>
      asJson(json['env']).map((k, v) => MapEntry(k, asString(v)));
  bool get canReincarnate => asBool(asJson(json['phoenix'])['canReincarnate']);
  int get generation => asInt(asJson(json['phoenix'])['generation']);
}

// ---------------------------------------------------------------------------
// Cleaning
// ---------------------------------------------------------------------------

class ZoneProperties {
  const ZoneProperties({required this.zoneCount, required this.iterationCount});

  factory ZoneProperties.fromJson(Object? json) {
    final j = asJson(json);
    return ZoneProperties(
      zoneCount: MinMax.fromJson(j['zoneCount'], max: 1),
      iterationCount: MinMax.fromJson(j['iterationCount']),
    );
  }

  final MinMax zoneCount;
  final MinMax iterationCount;
}

class MapSegmentationProperties {
  const MapSegmentationProperties({
    required this.iterationCount,
    required this.customOrderSupport,
  });

  factory MapSegmentationProperties.fromJson(Object? json) {
    final j = asJson(json);
    return MapSegmentationProperties(
      iterationCount: MinMax.fromJson(j['iterationCount']),
      customOrderSupport: asBool(j['customOrderSupport']),
    );
  }

  final MinMax iterationCount;
  final bool customOrderSupport;
}

class Segment {
  const Segment({required this.id, this.name, this.material});

  factory Segment.fromJson(Json json) => Segment(
    id: asString(json['id']),
    name: asStringOrNull(json['name']),
    material: asStringOrNull(json['material']),
  );

  final String id;
  final String? name;
  final String? material;

  String get displayName =>
      (name == null || name!.isEmpty) ? 'Segment $id' : name!;
}

// ---------------------------------------------------------------------------
// Consumables
// ---------------------------------------------------------------------------

class ConsumableState {
  const ConsumableState({
    required this.type,
    required this.subType,
    required this.value,
    required this.unit,
  });

  factory ConsumableState.fromJson(Json json) {
    final remaining = asJson(json['remaining']);
    return ConsumableState(
      type: asString(json['type']),
      subType: asString(json['subType'], 'none'),
      value: asDouble(remaining['value']),
      unit: asString(remaining['unit'], 'percent'),
    );
  }

  final String type;
  final String subType;
  final double value;

  /// `minutes` or `percent`.
  final String unit;

  String get key => '$type.$subType';
}

class ConsumableMeta {
  const ConsumableMeta({
    required this.type,
    required this.subType,
    required this.unit,
    this.maxValue,
  });

  factory ConsumableMeta.fromJson(Json json) => ConsumableMeta(
    type: asString(json['type']),
    subType: asString(json['subType'], 'none'),
    unit: asString(json['unit'], 'percent'),
    maxValue: asNumOrNull(json['maxValue'])?.toDouble(),
  );

  final String type;
  final String subType;
  final String unit;
  final double? maxValue;

  String get key => '$type.$subType';
}

// ---------------------------------------------------------------------------
// Statistics
// ---------------------------------------------------------------------------

class DataPoint {
  const DataPoint({required this.type, required this.value, this.timestamp});

  factory DataPoint.fromJson(Json json) => DataPoint(
    type: asString(json['type']),
    value: asDouble(json['value']),
    timestamp: asDateTime(json['timestamp']),
  );

  /// `count`, `time` (seconds) or `area` (cm²).
  final String type;
  final double value;
  final DateTime? timestamp;
}

// ---------------------------------------------------------------------------
// Timers & delayed start
// ---------------------------------------------------------------------------

abstract final class TimerActionType {
  static const fullCleanup = 'full_cleanup';
  static const segmentCleanup = 'segment_cleanup';
}

abstract final class TimerPreActionType {
  static const fanSpeedControl = 'fan_speed_control';
  static const waterUsageControl = 'water_usage_control';
  static const operationModeControl = 'operation_mode_control';
}

class TimerAction {
  const TimerAction({required this.type, this.params = const {}});

  factory TimerAction.fromJson(Object? json) {
    final j = asJson(json);
    return TimerAction(
      type: asString(j['type']),
      params: Map.of(asJson(j['params'])),
    );
  }

  final String type;
  final Json params;

  Json toJson() => {'type': type, 'params': params};
}

class ValetudoTimer {
  const ValetudoTimer({
    required this.id,
    required this.enabled,
    required this.label,
    required this.dow,
    required this.hour,
    required this.minute,
    required this.action,
    required this.preActions,
  });

  factory ValetudoTimer.fromJson(Json json) => ValetudoTimer(
    id: asString(json['id']),
    enabled: asBool(json['enabled']),
    label: asStringOrNull(json['label']),
    dow: asList(json['dow']).map((e) => asInt(e)).toList()..sort(),
    hour: asInt(json['hour']),
    minute: asInt(json['minute']),
    action: TimerAction.fromJson(json['action']),
    preActions: asList(json['pre_actions']).map(TimerAction.fromJson).toList(),
  );

  final String id;
  final bool enabled;
  final String? label;

  /// Days of week in UTC, 0 = Sunday … 6 = Saturday.
  final List<int> dow;

  /// UTC hour.
  final int hour;

  /// UTC minute.
  final int minute;
  final TimerAction action;
  final List<TimerAction> preActions;

  ValetudoTimer copyWith({
    String? id,
    bool? enabled,
    String? label,
    List<int>? dow,
    int? hour,
    int? minute,
    TimerAction? action,
    List<TimerAction>? preActions,
  }) => ValetudoTimer(
    id: id ?? this.id,
    enabled: enabled ?? this.enabled,
    label: label ?? this.label,
    dow: dow ?? this.dow,
    hour: hour ?? this.hour,
    minute: minute ?? this.minute,
    action: action ?? this.action,
    preActions: preActions ?? this.preActions,
  );

  Json toJson() => {
    'id': id,
    'enabled': enabled,
    if (label != null && label!.isNotEmpty) 'label': label,
    'dow': dow,
    'hour': hour,
    'minute': minute,
    'action': action.toJson(),
    'pre_actions': preActions.map((p) => p.toJson()).toList(),
  };
}

class TimerProperties {
  const TimerProperties({
    required this.supportedActions,
    required this.supportedPreActions,
  });

  factory TimerProperties.fromJson(Object? json) {
    final j = asJson(json);
    return TimerProperties(
      supportedActions: asStringList(j['supportedActions']),
      supportedPreActions: asStringList(j['supportedPreActions']),
    );
  }

  final List<String> supportedActions;
  final List<String> supportedPreActions;
}

/// A pending one-off delayed cleanup (fork feature: `/api/v2/delayedstart`).
class DelayedStart {
  const DelayedStart({
    required this.remaining,
    required this.action,
    required this.preActions,
    required this.fetchedAt,
  });

  static DelayedStart? fromJson(Object? json) {
    final pending = asJson(json)['pending'];
    if (pending is! Map) return null;
    final p = asJson(pending);
    return DelayedStart(
      remaining: asDouble(p['remaining']),
      action: TimerAction.fromJson(p['action']),
      preActions: asList(p['pre_actions']).map(TimerAction.fromJson).toList(),
      fetchedAt: DateTime.now(),
    );
  }

  /// Seconds until the cleanup starts at the time of [fetchedAt].
  final double remaining;
  final TimerAction action;
  final List<TimerAction> preActions;
  final DateTime fetchedAt;

  DateTime get startsAt =>
      fetchedAt.add(Duration(milliseconds: (remaining * 1000).round()));
}

// ---------------------------------------------------------------------------
// Events
// ---------------------------------------------------------------------------

class ValetudoEvent {
  const ValetudoEvent(this.json);

  factory ValetudoEvent.fromJson(Json json) => ValetudoEvent(json);

  final Json json;

  String get className => asString(json['__class']);
  String get id => asString(json['id']);
  DateTime? get timestamp => asDateTime(json['timestamp']);
  bool get processed => asBool(json['processed']);
  String? get type => asStringOrNull(json['type']);
  String? get subType => asStringOrNull(json['subType']);
  String? get message => asStringOrNull(json['message']);
  String? get reason => asStringOrNull(json['reason']);
  String? get description => asStringOrNull(json['description']);
  String? get previousVersion => asStringOrNull(json['previousVersion']);
  String? get newVersion => asStringOrNull(json['newVersion']);
  int? get generation => asIntOrNull(json['generation']);
}

// ---------------------------------------------------------------------------
// Logging
// ---------------------------------------------------------------------------

class LogLevelInfo {
  const LogLevelInfo({required this.current, required this.presets});

  factory LogLevelInfo.fromJson(Object? json) {
    final j = asJson(json);
    return LogLevelInfo(
      current: asString(j['current'], 'info'),
      presets: asStringList(j['presets']),
    );
  }

  final String current;
  final List<String> presets;
}

// ---------------------------------------------------------------------------
// Speaker / voice
// ---------------------------------------------------------------------------

class VoicePackStatus {
  const VoicePackStatus({
    required this.currentLanguage,
    required this.operationType,
    this.progress,
  });

  factory VoicePackStatus.fromJson(Object? json) {
    final j = asJson(json);
    final op = asJson(j['operationStatus']);
    return VoicePackStatus(
      currentLanguage: asString(j['currentLanguage'], '?'),
      operationType: asString(op['type'], 'idle'),
      progress: asNumOrNull(op['progress'])?.toDouble(),
    );
  }

  final String currentLanguage;

  /// `idle`, `downloading`, `installing` or `error`.
  final String operationType;
  final double? progress;
}

/// An audio clip that can be played by forks supporting `SpeakerPlayAudioCapability`.
class AudioEntry {
  const AudioEntry({required this.id, required this.name});

  factory AudioEntry.fromJson(Json json) => AudioEntry(
    id: asString(json['id']),
    name: asString(json['name'], asString(json['id'])),
  );

  final String id;
  final String name;
}

// ---------------------------------------------------------------------------
// Do not disturb
// ---------------------------------------------------------------------------

class DndConfiguration {
  const DndConfiguration({
    required this.enabled,
    required this.startHour,
    required this.startMinute,
    required this.endHour,
    required this.endMinute,
  });

  factory DndConfiguration.fromJson(Object? json) {
    final j = asJson(json);
    final start = asJson(j['start']);
    final end = asJson(j['end']);
    return DndConfiguration(
      enabled: asBool(j['enabled']),
      startHour: asInt(start['hour']),
      startMinute: asInt(start['minute']),
      endHour: asInt(end['hour']),
      endMinute: asInt(end['minute']),
    );
  }

  final bool enabled;

  /// All times are UTC.
  final int startHour;
  final int startMinute;
  final int endHour;
  final int endMinute;

  Json toJson() => {
    'enabled': enabled,
    'start': {'hour': startHour, 'minute': startMinute},
    'end': {'hour': endHour, 'minute': endMinute},
  };
}

// ---------------------------------------------------------------------------
// Wi-Fi
// ---------------------------------------------------------------------------

class WifiStatus {
  const WifiStatus({
    required this.state,
    this.ssid,
    this.bssid,
    this.downspeed,
    this.upspeed,
    this.signal,
    this.ips = const [],
    this.frequency,
  });

  factory WifiStatus.fromJson(Object? json) {
    final j = asJson(json);
    final d = asJson(j['details']);
    return WifiStatus(
      state: asString(j['state'], 'unknown'),
      ssid: asStringOrNull(d['ssid']),
      bssid: asStringOrNull(d['bssid']),
      downspeed: asNumOrNull(d['downspeed'])?.toDouble(),
      upspeed: asNumOrNull(d['upspeed'])?.toDouble(),
      signal: asNumOrNull(d['signal'])?.toDouble(),
      ips: asStringList(d['ips']),
      frequency: asStringOrNull(d['frequency']),
    );
  }

  /// `connected`, `not_connected` or `unknown`.
  final String state;
  final String? ssid;
  final String? bssid;
  final double? downspeed;
  final double? upspeed;

  /// dBm.
  final double? signal;
  final List<String> ips;

  /// `2.4ghz` or `5ghz`.
  final String? frequency;
}

class WifiNetwork {
  const WifiNetwork({required this.bssid, this.ssid, this.signal});

  factory WifiNetwork.fromJson(Json json) {
    final d = asJson(json['details']);
    return WifiNetwork(
      bssid: asString(json['bssid']),
      ssid: asStringOrNull(d['ssid']),
      signal: asNumOrNull(d['signal'])?.toDouble(),
    );
  }

  final String bssid;
  final String? ssid;
  final double? signal;
}

// ---------------------------------------------------------------------------
// Virtual restrictions & annotations
// ---------------------------------------------------------------------------

class VirtualWall {
  const VirtualWall(this.pA, this.pB);

  final CmPoint pA;
  final CmPoint pB;

  Json toJson() => {
    'points': {'pA': pA.toJson(), 'pB': pB.toJson()},
  };
}

class RestrictedZone {
  const RestrictedZone({required this.type, required this.quad});

  /// `regular` (no-go) or `mop` (no-mop).
  final String type;
  final CmQuad quad;

  Json toJson() => {'type': type, ...quad.toJson()};
}

class MapAnnotation {
  const MapAnnotation({required this.type, required this.points});

  /// `threshold`, `curtain` or `ramp`.
  final String type;
  final List<CmPoint> points;

  Json toJson() => {
    'type': type,
    'points': points.map((p) => p.toJson()).toList(),
  };
}

// ---------------------------------------------------------------------------
// Updater
// ---------------------------------------------------------------------------

class UpdaterState {
  const UpdaterState(this.json);

  factory UpdaterState.fromJson(Object? json) => UpdaterState(asJson(json));

  final Json json;

  String get className => asString(json['__class'], 'ValetudoUpdaterIdleState');
  bool get busy => asBool(json['busy']);
  DateTime? get timestamp => asDateTime(json['timestamp']);
  double? get progress =>
      asNumOrNull(asJson(json['metaData'])['progress'])?.toDouble();
  String? get type => asStringOrNull(json['type']);
  String? get message => asStringOrNull(json['message']);
  String? get currentVersion => asStringOrNull(json['currentVersion']);
  String? get version => asStringOrNull(json['version']);
  DateTime? get releaseTimestamp => asDateTime(json['releaseTimestamp']);
  String? get changelog => asStringOrNull(json['changelog']);
  String? get downloadUrl => asStringOrNull(json['downloadUrl']);
  String? get expectedHash => asStringOrNull(json['expectedHash']);
  String? get downloadPath => asStringOrNull(json['downloadPath']);
}

// ---------------------------------------------------------------------------
// NTP
// ---------------------------------------------------------------------------

class NtpStatus {
  const NtpStatus(this.json);

  factory NtpStatus.fromJson(Object? json) => NtpStatus(asJson(json));

  final Json json;

  Json get _state => asJson(json['state']);
  String get stateClass => asString(_state['__class']);
  DateTime? get stateTimestamp => asDateTime(_state['timestamp']);
  String? get errorType => asStringOrNull(_state['type']);
  String? get message => asStringOrNull(_state['message']);
  double? get offset => asNumOrNull(_state['offset'])?.toDouble();
  DateTime? get robotTime => asDateTime(json['robotTime']);
}

// ---------------------------------------------------------------------------
// Quirks
// ---------------------------------------------------------------------------

class Quirk {
  const Quirk({
    required this.id,
    required this.options,
    required this.title,
    required this.description,
    required this.value,
  });

  factory Quirk.fromJson(Json json) => Quirk(
    id: asString(json['id']),
    options: asStringList(json['options']),
    title: asString(json['title']),
    description: asString(json['description']),
    value: asString(json['value']),
  );

  final String id;
  final List<String> options;
  final String title;
  final String description;
  final String value;
}

// ---------------------------------------------------------------------------
// Multiple maps (fork feature)
// ---------------------------------------------------------------------------

class RobotMapEntry {
  const RobotMapEntry({
    required this.id,
    required this.name,
    required this.active,
  });

  factory RobotMapEntry.fromJson(Json json) => RobotMapEntry(
    id: asString(json['id']),
    name: asString(json['name'], 'Map ${asString(json['id'])}'),
    active: asBool(json['active']),
  );

  final String id;
  final String name;
  final bool active;
}

// ---------------------------------------------------------------------------
// Misc capability properties
// ---------------------------------------------------------------------------

class CleanRouteProperties {
  const CleanRouteProperties({
    required this.supportedRoutes,
    required this.mopOnly,
    required this.oneTime,
  });

  factory CleanRouteProperties.fromJson(Object? json) {
    final j = asJson(json);
    return CleanRouteProperties(
      supportedRoutes: asStringList(j['supportedRoutes']),
      mopOnly: asStringList(j['mopOnly']),
      oneTime: asStringList(j['oneTime']),
    );
  }

  final List<String> supportedRoutes;
  final List<String> mopOnly;
  final List<String> oneTime;
}

class ImageDimensions {
  const ImageDimensions(this.width, this.height);

  final int width;
  final int height;

  double get aspectRatio => height == 0 ? 4 / 3 : width / height;
}

class DuststreamingProperties {
  const DuststreamingProperties({
    required this.dimensions,
    required this.duststreamerInstalled,
  });

  factory DuststreamingProperties.fromJson(Object? json) {
    final j = asJson(json);
    return DuststreamingProperties(
      dimensions: ImageDimensions(
        asInt(j['width'], 640),
        asInt(j['height'], 480),
      ),
      duststreamerInstalled: asBool(j['duststreamerInstalled']),
    );
  }

  final ImageDimensions dimensions;
  final bool duststreamerInstalled;
}

class MqttStatus {
  const MqttStatus(this.json);

  factory MqttStatus.fromJson(Object? json) => MqttStatus(asJson(json));

  final Json json;

  /// `init`, `ready`, `disconnected`, `lost` or `alert`.
  String get state => asString(json['state'], 'disconnected');
  Json get _stats => asJson(json['stats']);
  int get messagesReceived =>
      asInt(asJson(asJson(_stats['messages'])['count'])['received']);
  int get messagesSent =>
      asInt(asJson(asJson(_stats['messages'])['count'])['sent']);
  int get bytesReceived =>
      asInt(asJson(asJson(_stats['messages'])['bytes'])['received']);
  int get bytesSent =>
      asInt(asJson(asJson(_stats['messages'])['bytes'])['sent']);
  int get connects => asInt(asJson(_stats['connection'])['connects']);
  int get disconnects => asInt(asJson(_stats['connection'])['disconnects']);
  int get reconnects => asInt(asJson(_stats['connection'])['reconnects']);
  int get errors => asInt(asJson(_stats['connection'])['errors']);
}
