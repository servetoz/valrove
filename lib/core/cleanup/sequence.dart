import '../valetudo/json_utils.dart';
import 'cleanup_record.dart';
import 'presets.dart';
import 'robot_files.dart';

/// The rest of a preset that runs in several steps: the step the robot is
/// on and the ones still to start.
class PendingSequence {
  const PendingSequence({
    required this.presetName,
    required this.currentRooms,
    required this.remaining,
    required this.stepNumber,
    required this.stepCount,
    required this.startedAt,
    this.customOrder = false,
  });

  factory PendingSequence.fromJson(Object? json) {
    final j = asJson(json);
    return PendingSequence(
      presetName: asString(j['presetName']),
      currentRooms: asStringList(j['currentRooms']),
      remaining: [
        for (final s in asList(j['remaining'])) CleanupStep.fromJson(s),
      ],
      stepNumber: asInt(j['stepNumber'], 1),
      stepCount: asInt(j['stepCount'], 1),
      startedAt: DateTime.fromMillisecondsSinceEpoch(asInt(j['startedAt'])),
      customOrder: asBool(j['customOrder']),
    );
  }

  final String presetName;

  /// Rooms of the step that is running.
  final List<String> currentRooms;
  final List<CleanupStep> remaining;

  /// 1-based number of the running step.
  final int stepNumber;
  final int stepCount;
  final DateTime startedAt;

  /// The robot accepts a room order.
  final bool customOrder;

  /// A sequence nobody finished in this time is dropped.
  static const maxAge = Duration(hours: 12);

  Json toJson() => {
    'presetName': presetName,
    'currentRooms': currentRooms,
    'remaining': [for (final s in remaining) s.toJson()],
    'stepNumber': stepNumber,
    'stepCount': stepCount,
    'startedAt': startedAt.millisecondsSinceEpoch,
    'customOrder': customOrder,
  };
}

/// What to do after a cleanup ended.
sealed class SequenceDecision {
  const SequenceDecision();
}

/// Nothing is pending (or it was dropped quietly).
class SequenceIdle extends SequenceDecision {
  const SequenceIdle();
}

/// The step did not finish, so the rest is cancelled.
class SequenceStopped extends SequenceDecision {
  const SequenceStopped(this.sequence);

  final PendingSequence sequence;
}

/// Start [step]; [next] is what remains pending afterwards (null when it was
/// the last step).
class SequenceContinue extends SequenceDecision {
  const SequenceContinue(this.step, this.next, this.stepNumber, this.stepCount);

  final CleanupStep step;
  final PendingSequence? next;
  final int stepNumber;
  final int stepCount;
}

/// Decides how [sequence] goes on after the cleanup [ended].
SequenceDecision decideNextStep(
  PendingSequence? sequence,
  CleanupRecord ended,
  DateTime now,
) {
  if (sequence == null || sequence.remaining.isEmpty) {
    return const SequenceIdle();
  }
  if (now.difference(sequence.startedAt) > PendingSequence.maxAge) {
    return const SequenceIdle();
  }
  // Another cleanup ran in between: don't continue someone else's job.
  final rooms = {for (final r in ended.rooms) r.id};
  if (rooms.isNotEmpty && !_sameSet(rooms, sequence.currentRooms.toSet())) {
    return const SequenceIdle();
  }
  if (ended.outcome != CleanupOutcome.finished) {
    return SequenceStopped(sequence);
  }
  final step = sequence.remaining.first;
  final rest = sequence.remaining.skip(1).toList();
  final number = sequence.stepNumber + 1;
  return SequenceContinue(
    step,
    rest.isEmpty
        ? null
        : PendingSequence(
            presetName: sequence.presetName,
            currentRooms: step.rooms,
            remaining: rest,
            stepNumber: number,
            stepCount: sequence.stepCount,
            startedAt: sequence.startedAt,
            customOrder: sequence.customOrder,
          ),
    number,
    sequence.stepCount,
  );
}

bool _sameSet(Set<String> a, Set<String> b) =>
    a.length == b.length && a.containsAll(b);

class SequenceStore {
  SequenceStore(this.files);

  final RobotFiles files;
  static const _name = 'sequence';

  Future<PendingSequence?> load(String robotId) async {
    final json = await files.read(robotId, _name);
    return json == null ? null : PendingSequence.fromJson(json);
  }

  Future<void> save(String robotId, PendingSequence? sequence) =>
      sequence == null
      ? files.delete(robotId, _name)
      : files.write(robotId, _name, sequence.toJson());
}
