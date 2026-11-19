import '../json_utils.dart';

/// Values of `StatusStateAttribute.value`.
abstract final class RobotStatus {
  static const error = 'error';
  static const docked = 'docked';
  static const idle = 'idle';
  static const returning = 'returning';
  static const cleaning = 'cleaning';
  static const paused = 'paused';
  static const manualControl = 'manual_control';
  static const moving = 'moving';
}

/// Values of `StatusStateAttribute.flag`.
abstract final class StatusFlag {
  static const none = 'none';
  static const zone = 'zone';
  static const segment = 'segment';
  static const spot = 'spot';
  static const target = 'target';
  static const resumable = 'resumable';
  static const mapping = 'mapping';
}

/// Whether a cleanup job is in progress (see [RobotState.job]).
enum JobState {
  /// No job. Rooms that the map still marks as `active` are left over from
  /// the last one: firmwares keep the flag, e.g. after a cancelled cleanup.
  none,

  /// A job is unfinished, but the robot isn't cleaning right now (paused, or
  /// at the dock in the middle of a job, e.g. to wash its mops).
  interrupted,

  /// The robot is cleaning.
  running,
}

class RobotError {
  const RobotError({
    required this.severityKind,
    required this.severityLevel,
    required this.subsystem,
    required this.message,
    this.vendorErrorCode,
  });

  factory RobotError.fromJson(Json json) {
    final severity = asJson(json['severity']);
    return RobotError(
      severityKind: asString(severity['kind'], 'unknown'),
      severityLevel: asString(severity['level'], 'unknown'),
      subsystem: asString(json['subsystem'], 'unknown'),
      message: asString(json['message']),
      vendorErrorCode: asStringOrNull(json['vendorErrorCode']),
    );
  }

  final String severityKind;
  final String severityLevel;
  final String subsystem;
  final String message;
  final String? vendorErrorCode;
}

sealed class RobotAttribute {
  const RobotAttribute();

  static RobotAttribute fromJson(Json json) {
    switch (asString(json['__class'])) {
      case 'StatusStateAttribute':
        final errorJson = json['error'];
        return StatusAttribute(
          value: asString(json['value'], RobotStatus.error),
          flag: asString(json['flag'], StatusFlag.none),
          error: errorJson is Map
              ? RobotError.fromJson(asJson(errorJson))
              : null,
        );
      case 'BatteryStateAttribute':
        return BatteryAttribute(
          level: asDouble(json['level']),
          flag: asString(json['flag'], 'none'),
        );
      case 'PresetSelectionStateAttribute':
        return PresetAttribute(
          type: asString(json['type']),
          value: asString(json['value']),
          customValue: asNumOrNull(json['customValue']),
        );
      case 'AttachmentStateAttribute':
        return AttachmentAttribute(
          type: asString(json['type']),
          attached: asBool(json['attached']),
        );
      case 'DockStatusStateAttribute':
        return DockStatusAttribute(value: asString(json['value'], 'idle'));
      case 'DockComponentStateAttribute':
        return DockComponentAttribute(
          type: asString(json['type']),
          value: asString(json['value'], 'unknown'),
        );
      default:
        return UnknownAttribute(json);
    }
  }
}

class StatusAttribute extends RobotAttribute {
  const StatusAttribute({required this.value, required this.flag, this.error});

  /// Fallback used while no status is known (mirrors the web UI behavior).
  static const unknown = StatusAttribute(
    value: RobotStatus.error,
    flag: StatusFlag.none,
  );

  final String value;
  final String flag;
  final RobotError? error;
}

class BatteryAttribute extends RobotAttribute {
  const BatteryAttribute({required this.level, required this.flag});

  final double level;

  /// `none`, `charged`, `charging` or `discharging`.
  final String flag;
}

/// Preset types reported by `PresetSelectionStateAttribute.type`.
abstract final class PresetType {
  static const fanSpeed = 'fan_speed';
  static const waterGrade = 'water_grade';
  static const operationMode = 'operation_mode';
}

class PresetAttribute extends RobotAttribute {
  const PresetAttribute({
    required this.type,
    required this.value,
    this.customValue,
  });

  final String type;
  final String value;
  final num? customValue;
}

class AttachmentAttribute extends RobotAttribute {
  const AttachmentAttribute({required this.type, required this.attached});

  /// `dustbin`, `watertank` or `mop`.
  final String type;
  final bool attached;
}

class DockStatusAttribute extends RobotAttribute {
  const DockStatusAttribute({required this.value});

  /// `error`, `idle`, `pause`, `emptying`, `cleaning` or `drying`.
  final String value;
}

class DockComponentAttribute extends RobotAttribute {
  const DockComponentAttribute({required this.type, required this.value});

  /// `water_tank_clean`, `water_tank_dirty`, `dustbag` or `detergent`.
  final String type;

  /// `ok`, `missing`, `empty`, `full` or `unknown`.
  final String value;
}

class UnknownAttribute extends RobotAttribute {
  const UnknownAttribute(this.json);

  final Json json;
}

/// Convenience view over the list returned by `/robot/state/attributes`.
class RobotState {
  const RobotState(this.attributes);

  factory RobotState.fromJson(Object? json) => RobotState(
    List.unmodifiable(asJsonList(json).map(RobotAttribute.fromJson)),
  );

  static const empty = RobotState([]);

  final List<RobotAttribute> attributes;

  StatusAttribute get status =>
      attributes.whereType<StatusAttribute>().firstOrNull ??
      StatusAttribute.unknown;

  bool get hasStatus => attributes.whereType<StatusAttribute>().isNotEmpty;

  BatteryAttribute? get battery =>
      attributes.whereType<BatteryAttribute>().firstOrNull;

  PresetAttribute? preset(String type) => attributes
      .whereType<PresetAttribute>()
      .where((p) => p.type == type)
      .firstOrNull;

  PresetAttribute? get fanSpeed => preset(PresetType.fanSpeed);

  PresetAttribute? get waterGrade => preset(PresetType.waterGrade);

  PresetAttribute? get operationMode => preset(PresetType.operationMode);

  List<AttachmentAttribute> get attachments =>
      attributes.whereType<AttachmentAttribute>().toList();

  AttachmentAttribute? attachment(String type) =>
      attachments.where((a) => a.type == type).firstOrNull;

  DockStatusAttribute? get dockStatus =>
      attributes.whereType<DockStatusAttribute>().firstOrNull;

  List<DockComponentAttribute> get dockComponents =>
      attributes.whereType<DockComponentAttribute>().toList();

  /// Valetudo reports unfinished jobs as `paused` or with the `resumable`
  /// flag (also while docked mid-job).
  JobState get job {
    final s = status;
    if (s.value == RobotStatus.cleaning) return JobState.running;
    if (s.value == RobotStatus.paused || s.flag == StatusFlag.resumable) {
      return JobState.interrupted;
    }
    return JobState.none;
  }

  /// Whether a new cleanup (segment/zone/go-to) may be started right now.
  ///
  /// Matches the web interface, which allows starting actions while idle,
  /// docked, paused, returning or in an error state.
  bool get canStartAction => const {
    RobotStatus.idle,
    RobotStatus.docked,
    RobotStatus.paused,
    RobotStatus.returning,
    RobotStatus.error,
  }.contains(status.value);
}
