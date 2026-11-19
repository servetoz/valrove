import '../util/format.dart';
import '../valetudo/models/models.dart';
import 'cleanup_record.dart';
import 'map_summary.dart';

/// Buttons of the ongoing cleanup notification.
enum CleanupAction { pause, resume, dock }

/// A notification worth showing even when the app is closed.
class CleanupAlert {
  const CleanupAlert(this.key, this.title, this.body);

  /// Identifies the alert; a newer alert with the same key replaces it.
  final String key;
  final String title;
  final String body;
}

/// What the ongoing notification shows.
class OngoingCleanup {
  const OngoingCleanup({
    required this.title,
    required this.text,
    required this.actions,
  });

  final String title;
  final String text;
  final List<CleanupAction> actions;
}

/// What the robot looked like at one moment.
class CleanupSample {
  const CleanupSample({
    required this.at,
    required this.state,
    this.areaCm2,
    this.seconds,
    this.map,
    this.events,
  });

  final DateTime at;
  final RobotState state;

  /// Current statistics of the running job, when fetched.
  final double? areaCm2;
  final int? seconds;

  /// A fresh map, when fetched.
  final MapSummary? map;

  /// Valetudo's events, when fetched.
  final List<ValetudoEvent>? events;
}

class TrackerUpdate {
  const TrackerUpdate({
    this.ongoing,
    this.alerts = const [],
    this.ended = false,
  });

  /// Null while no cleanup is tracked.
  final OngoingCleanup? ongoing;
  final List<CleanupAlert> alerts;

  /// The cleanup just ended: call [CleanupTracker.finish].
  final bool ended;
}

/// Follows one cleanup from start to end through [CleanupSample]s and turns
/// it into notifications and a [CleanupRecord]. Knows nothing about where the
/// samples come from, so the background service and the app share it.
class CleanupTracker {
  CleanupTracker({
    required this.robotId,
    this.pauseTimeout = const Duration(hours: 6),
  });

  final String robotId;

  /// A cleanup paused (or waiting at the dock to resume) this long counts as
  /// stopped; recharging in between usually takes a few hours.
  final Duration pauseTimeout;

  DateTime? _startedAt;
  DateTime? _endedAt;
  String _kind = CleanupKind.full;
  String? _outcome;
  final _activeRooms = <String>{};
  MapSummary? _map;
  double? _area;
  int? _seconds;
  int? _batteryStart;
  int? _battery;
  bool _recharged = false;
  String? _mode;
  String? _fan;
  String? _error;
  String? _alertedError;
  String? _lastMove;
  DateTime? _pausedSince;
  Set<String>? _seenEvents;

  bool get tracking => _startedAt != null;

  TrackerUpdate add(CleanupSample s) {
    final alerts = <CleanupAlert>[];
    if (s.map != null) _map = s.map;
    if (s.events != null) alerts.addAll(_newEvents(s.events!));
    if (_endedAt != null) return TrackerUpdate(alerts: alerts, ended: true);
    final status = s.state.status;
    final job = s.state.job;
    if (!tracking) {
      if (job == JobState.none) return TrackerUpdate(alerts: alerts);
      _begin(s);
    }

    if (s.areaCm2 != null) _area = s.areaCm2;
    if (s.seconds != null) _seconds = s.seconds;
    final level = s.state.battery?.level.round();
    if (level != null) {
      if (_battery != null && level > _battery! + 3) _recharged = true;
      _battery = level;
      _batteryStart ??= level;
    }
    if (status.value == RobotStatus.docked && job != JobState.none) {
      _recharged = true;
    }
    if (status.value == RobotStatus.cleaning) {
      _kind = CleanupKind.fromStatusFlag(status.flag);
    }
    for (final room in _map?.rooms ?? const <SummaryRoom>[]) {
      if (room.active) _activeRooms.add(room.id);
    }

    if (status.value == RobotStatus.error) {
      final message = status.error?.message;
      _error = message?.isNotEmpty == true ? message : 'The robot is stuck';
      if (_alertedError != _error) {
        _alertedError = _error;
        alerts.add(CleanupAlert('error', 'Robot needs help', _error!));
      }
    } else {
      _alertedError = null;
    }
    if (const {
      RobotStatus.cleaning,
      RobotStatus.returning,
      RobotStatus.paused,
      RobotStatus.error,
      RobotStatus.moving,
    }.contains(status.value)) {
      _lastMove = status.value;
    }
    final waiting =
        status.value == RobotStatus.paused ||
        (status.value == RobotStatus.docked && job != JobState.none);
    _pausedSince = waiting ? (_pausedSince ?? s.at) : null;

    final atRest = const {
      RobotStatus.docked,
      RobotStatus.idle,
    }.contains(status.value);
    final pausedTooLong =
        _pausedSince != null && s.at.difference(_pausedSince!) >= pauseTimeout;
    if ((job == JobState.none && atRest) || pausedTooLong) {
      _endedAt = s.at;
      _outcome = pausedTooLong
          ? CleanupOutcome.stopped
          : switch (_lastMove) {
              RobotStatus.returning => CleanupOutcome.finished,
              RobotStatus.error => CleanupOutcome.error,
              _ => CleanupOutcome.stopped,
            };
      return TrackerUpdate(alerts: alerts, ended: true);
    }
    return TrackerUpdate(ongoing: _ongoing(s.state), alerts: alerts);
  }

  void _begin(CleanupSample s) {
    // Joining a cleanup that is already running: count back its time.
    _startedAt = s.seconds != null && s.seconds! > 0
        ? s.at.subtract(Duration(seconds: s.seconds!))
        : s.at;
    _kind = CleanupKind.fromStatusFlag(s.state.status.flag);
    _mode = s.state.operationMode?.value;
    _fan = s.state.fanSpeed?.value;
  }

  /// Finishes the ended cleanup, preferably with a [map] fetched after it
  /// ended (for the complete path), and resets the tracker.
  CleanupRecord? finish({MapSummary? map}) {
    final startedAt = _startedAt;
    final endedAt = _endedAt;
    if (startedAt == null || endedAt == null) return null;
    final m = map ?? _map;
    final rooms = _roomsOf(m);
    final record = CleanupRecord(
      robotId: robotId,
      startedAt: startedAt,
      endedAt: endedAt,
      kind: _kind,
      outcome: _outcome ?? CleanupOutcome.stopped,
      cleaningSeconds: _seconds,
      areaCm2: _area,
      rooms: [for (final r in rooms) (id: r.id, name: r.displayName)],
      roomAreaCm2: rooms.fold(0.0, (sum, r) => sum + r.areaCm2),
      batteryStart: _batteryStart,
      batteryEnd: _battery,
      recharged: _recharged,
      operationMode: _mode,
      fanSpeed: _fan,
      error: _error,
      pixelSize: m?.pixelSize ?? 5,
      path: m == null ? const [] : thinPath(m.path),
      obstacles: m?.obstacles ?? const [],
    );
    final seen = _seenEvents;
    _reset();
    _seenEvents = seen;
    return record;
  }

  void _reset() {
    _startedAt = null;
    _endedAt = null;
    _outcome = null;
    _kind = CleanupKind.full;
    _activeRooms.clear();
    _area = null;
    _seconds = null;
    _batteryStart = null;
    _battery = null;
    _recharged = false;
    _mode = null;
    _fan = null;
    _error = null;
    _alertedError = null;
    _lastMove = null;
    _pausedSince = null;
  }

  List<SummaryRoom> _roomsOf(MapSummary? map) {
    if (map == null) return const [];
    switch (_kind) {
      case CleanupKind.full:
        return map.rooms;
      case CleanupKind.rooms when _activeRooms.isNotEmpty:
        return [
          for (final r in map.rooms)
            if (_activeRooms.contains(r.id)) r,
        ];
      default:
        // Zones and spots: the rooms the robot spent its time in, not the
        // ones it only drove through.
        final counts = map.pathPointsPerRoom();
        final total = counts.values.fold(0, (a, b) => a + b);
        if (total == 0) return const [];
        return [
          for (final r in map.rooms)
            if ((counts[r.id] ?? 0) >= total * 0.2) r,
        ];
    }
  }

  /// Where the robot cleans, for titles.
  String _where() {
    switch (_kind) {
      case CleanupKind.full:
        return 'Whole home';
      case CleanupKind.zones:
        return 'Zones';
      case CleanupKind.spot:
        return 'Spot';
      case CleanupKind.mapping:
        return 'Mapping';
    }
    final names = [
      for (final r in _map?.rooms ?? const <SummaryRoom>[])
        if (_activeRooms.contains(r.id)) r.displayName,
    ];
    return names.isEmpty ? 'Rooms' : joinNames(names);
  }

  OngoingCleanup _ongoing(RobotState state) {
    final status = state.status;
    final job = state.job;
    final where = _where();
    final (title, actions) = switch (status.value) {
      RobotStatus.cleaning => (
        'Cleaning · $where',
        const [CleanupAction.pause, CleanupAction.dock],
      ),
      RobotStatus.returning when job != JobState.none => (
        'Returning to recharge',
        const [CleanupAction.pause],
      ),
      RobotStatus.returning => (
        'Returning to the dock',
        const [CleanupAction.pause],
      ),
      RobotStatus.docked => (
        'Charging · resumes when charged',
        const [CleanupAction.resume],
      ),
      RobotStatus.error => ('Robot needs help', const [CleanupAction.dock]),
      RobotStatus.paused || RobotStatus.idle => (
        'Paused · $where',
        const [CleanupAction.resume, CleanupAction.dock],
      ),
      _ => (
        '${statusLabel(status.value)} · $where',
        const [CleanupAction.pause, CleanupAction.dock],
      ),
    };
    final parts = [
      if (status.value == RobotStatus.error && _error != null) _error!,
      if (_area != null && _area! > 0) areaFromCm2(_area!),
      if (_seconds != null && _seconds! > 0) compactDuration(_seconds! * 1.0),
      if (_battery != null) 'Battery $_battery%',
    ];
    return OngoingCleanup(
      title: title,
      text: parts.isEmpty
          ? 'Valrove is following the cleanup'
          : parts.join(' · '),
      actions: actions,
    );
  }

  List<CleanupAlert> _newEvents(List<ValetudoEvent> events) {
    String key(ValetudoEvent e) =>
        '${e.id}@${e.timestamp?.millisecondsSinceEpoch}';
    final open = events.where((e) => !e.processed).toList();
    final seen = _seenEvents;
    if (seen == null) {
      // Events that were already there when tracking started are old news.
      _seenEvents = {for (final e in open) key(e)};
      return const [];
    }
    return [
      for (final e in open)
        if (seen.add(key(e))) ?eventAlert(e),
    ];
  }

  /// The notification for one of Valetudo's events, if it deserves one.
  static CleanupAlert? eventAlert(ValetudoEvent e) => switch (e.className) {
    'DustBinFullValetudoEvent' => const CleanupAlert(
      'event-dustbin',
      'Dust bin full',
      'Empty the dust bin so the robot can keep cleaning.',
    ),
    'ConsumableDepletedValetudoEvent' when e.type != null => CleanupAlert(
      'event-consumable-${e.type}-${e.subType}',
      'Replace the ${consumableName(e.type!, e.subType).toLowerCase()}',
      'It has reached the end of its life.',
    ),
    'MopAttachmentReminderValetudoEvent' => const CleanupAlert(
      'event-mop',
      'Mop still attached',
      'The mop is still attached to the robot.',
    ),
    'MissingResourceValetudoEvent' => CleanupAlert(
      'event-resource',
      'Something is missing',
      e.message ?? 'The robot is missing a resource.',
    ),
    _ => null,
  };

  /// The notification for a finished cleanup.
  static CleanupAlert finishedAlert(CleanupRecord r) {
    final title = switch (r.outcome) {
      CleanupOutcome.finished => 'Cleaning finished',
      CleanupOutcome.error => 'Cleaning ended with an error',
      _ => 'Cleaning stopped',
    };
    final where = r.kind == CleanupKind.full
        ? 'Whole home'
        : r.rooms.isEmpty
        ? null
        : joinNames([for (final room in r.rooms) room.name]);
    final parts = [
      ?where,
      if (r.areaCm2 != null && r.areaCm2! > 0) areaFromCm2(r.areaCm2!),
      'in ${compactDuration(r.duration.inSeconds * 1.0)}',
    ];
    return CleanupAlert('finished', title, parts.join(' · '));
  }
}

/// "Kitchen, Hallway +2".
String joinNames(List<String> names, {int max = 3}) => names.length <= max
    ? names.join(', ')
    : '${names.take(max - 1).join(', ')} +${names.length - max + 1}';
