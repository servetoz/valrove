import '../../core/cleanup/presets.dart';
import '../../core/cleanup/robot_files.dart';
import '../../core/cleanup/sequence.dart';
import '../../core/valetudo/capabilities.dart';
import '../../core/valetudo/client/valetudo_client.dart';

/// What starting a preset did: its first step and how many steps it has.
typedef PresetStarted = ({CleanupStep first, int stepCount});

/// Starts [preset] on [client] and remembers its later steps for robot
/// [robotId]; they start when the robot finished the step before. Used by
/// the app, its widget and shortcuts, and by assistants.
Future<PresetStarted> startPresetWithSteps(
  ValetudoClient client,
  CleanupPreset preset, {
  required String robotId,
  required RobotFiles files,
}) async {
  final caps = await client.getCapabilities();
  final rooms = preset.wholeHome
      ? const <String>{}
      : {for (final s in await client.getSegments()) s.id};
  final customOrder =
      preset.rooms.length > 1 &&
      caps.has(Cap.mapSegmentation) &&
      (await client.getMapSegmentationProperties()).customOrderSupport;
  final started = await startPreset(
    client,
    preset,
    caps: caps,
    existingRooms: rooms,
    customOrder: customOrder,
  );
  await SequenceStore(files).save(
    robotId,
    started.rest.isEmpty
        ? null
        : PendingSequence(
            presetName: preset.name,
            currentRooms: started.first.rooms,
            remaining: started.rest,
            stepNumber: 1,
            stepCount: started.rest.length + 1,
            startedAt: DateTime.now(),
            customOrder: customOrder,
          ),
  );
  return (first: started.first, stepCount: started.rest.length + 1);
}
