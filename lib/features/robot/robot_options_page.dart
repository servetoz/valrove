import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/util/format.dart';
import '../../core/valetudo/capabilities.dart';
import '../../core/valetudo/json_utils.dart';
import '../../state/commands.dart';
import '../../state/session.dart';
import '../../ui/widgets.dart';
import '../navigation.dart';
import 'capability_tiles.dart';

/// Tunables and actions provided by the robot's firmware.
class RobotOptionsPage extends ConsumerStatefulWidget {
  const RobotOptionsPage({super.key});

  @override
  ConsumerState<RobotOptionsPage> createState() => _RobotOptionsPageState();
}

class _RobotOptionsPageState extends ConsumerState<RobotOptionsPage> {
  bool _locating = false;

  @override
  Widget build(BuildContext context) {
    final caps = ref.watch(capsProvider);

    final general = <Widget>[
      if (caps.has(Cap.locate))
        ActionTile(
          title: 'Locate robot',
          subtitle: 'The robot will play a sound to announce its location',
          icon: Icons.not_listed_location_rounded,
          actionLabel: 'Locate',
          busy: _locating,
          onAction: () async {
            setState(() => _locating = true);
            await ref
                .read(commandsProvider)
                .run('locate the robot', (c) => c.locate());
            if (mounted) setState(() => _locating = false);
          },
        ),
      if (caps.has(Cap.keyLock))
        const CapabilityToggleTile(
          capability: Cap.keyLock,
          title: 'Lock keys',
          subtitle: 'Prevents the robot from being operated using its physical buttons.',
          icon: Icons.lock_rounded,
        ),
    ];

    final navigation = <Widget>[
      if (caps.has(Cap.collisionAvoidantNavigation))
        const CapabilityToggleTile(
          capability: Cap.collisionAvoidantNavigation,
          title: 'Collision-avoidant navigation',
          subtitle: 'Drive a more conservative route to reduce collisions. May cause missed spots.',
          icon: Icons.roundabout_right_rounded,
        ),
      if (caps.has(Cap.floorMaterialDirectionAwareNavigationControl))
        const CapabilityToggleTile(
          capability: Cap.floorMaterialDirectionAwareNavigationControl,
          title: 'Material-aligned navigation',
          subtitle: 'Clean along the direction of the configured/detected floor material (if applicable).',
          icon: Icons.explore_rounded,
        ),
      if (caps.has(Cap.cleanRouteControl))
        CapabilitySelectTile(
          capability: Cap.cleanRouteControl,
          valueKey: 'route',
          propertiesKey: 'supportedRoutes',
          title: 'Clean route',
          icon: Icons.route_rounded,
          subtitleBuilder: _cleanRouteSubtitle,
        ),
    ];

    final carpet = <Widget>[
      if (caps.has(Cap.carpetModeControl))
        const CapabilityToggleTile(
          capability: Cap.carpetModeControl,
          title: 'Carpet mode',
          subtitle: 'When enabled, the vacuum will recognize carpets automatically and increase the suction.',
          icon: Icons.keyboard_double_arrow_up_rounded,
        ),
      if (caps.has(Cap.carpetSensorModeControl))
        const CapabilitySelectTile(
          capability: Cap.carpetSensorModeControl,
          valueKey: 'mode',
          propertiesKey: 'supportedModes',
          title: 'Carpet sensor',
          subtitle: 'Select what action the robot should take if it detects carpet while mopping.',
          icon: Icons.troubleshoot_rounded,
        ),
    ];

    final mop = <Widget>[
      if (caps.has(Cap.mopExtensionControl))
        const CapabilityToggleTile(
          capability: Cap.mopExtensionControl,
          title: 'Mop extension',
          subtitle:
              'Extend the mop outwards to reach closer to walls and furniture.',
          icon: Icons.open_in_full_rounded,
        ),
      if (caps.has(Cap.mopTwistControl))
        CapabilityToggleTile(
          capability: Cap.mopTwistControl,
          title: 'Mop twist',
          subtitle: caps.has(Cap.mopExtensionControl)
              ? 'With the mop extended, twist the robot to further reach below furniture and other overhangs.'
              : 'Twist the robot to mop closer to walls and furniture. Will increase the cleanup duration.',
          icon: Icons.rotate_90_degrees_cw_rounded,
        ),
      if (caps.has(Cap.mopExtensionFurnitureLegHandlingControl))
        const CapabilityToggleTile(
          capability: Cap.mopExtensionFurnitureLegHandlingControl,
          title: 'Mop extension for furniture legs',
          subtitle: 'Use the extending mop to mop up close to legs of chairs and tables.',
          icon: Icons.table_bar_rounded,
        ),
    ];

    final perception = <Widget>[
      if (caps.has(Cap.obstacleAvoidanceControl))
        const CapabilityToggleTile(
          capability: Cap.obstacleAvoidanceControl,
          title: 'Obstacle avoidance',
          subtitle: 'Avoid obstacles using sensors such as lasers or cameras. May suffer from false positives.',
          icon: Icons.cable_rounded,
        ),
      if (caps.has(Cap.petObstacleAvoidanceControl))
        const CapabilityToggleTile(
          capability: Cap.petObstacleAvoidanceControl,
          title: 'Pet obstacle avoidance',
          subtitle: 'Fine-tune obstacle avoidance to avoid obstacles left by pets. Will increase the general false positive rate.',
          icon: Icons.pets_rounded,
        ),
      if (caps.has(Cap.obstacleImages))
        const CapabilityToggleTile(
          capability: Cap.obstacleImages,
          title: 'Obstacle images',
          subtitle: 'Take pictures of all encountered obstacles.',
          icon: Icons.photo_rounded,
        ),
      if (caps.has(Cap.cameraLightControl))
        const CapabilityToggleTile(
          capability: Cap.cameraLightControl,
          title: 'Camera light',
          subtitle: 'Illuminate the dark to improve the AI image recognition obstacle avoidance.',
          icon: Icons.flashlight_on_rounded,
        ),
    ];

    final emptying = <Widget>[
      if (caps.has(Cap.autoEmptyDockAutoEmptyIntervalControl))
        const CapabilitySelectTile(
          capability: Cap.autoEmptyDockAutoEmptyIntervalControl,
          valueKey: 'interval',
          propertiesKey: 'supportedIntervals',
          title: 'Dock auto-empty',
          subtitle: 'Select if and/or how often the dock should auto-empty the robot.',
          icon: Icons.auto_delete_rounded,
        ),
      if (caps.has(Cap.autoEmptyDockAutoEmptyDurationControl))
        const CapabilitySelectTile(
          capability: Cap.autoEmptyDockAutoEmptyDurationControl,
          valueKey: 'duration',
          propertiesKey: 'supportedDurations',
          title: 'Auto-empty duration',
          subtitle: 'Configure the duration of the auto-empty cycle.',
          icon: Icons.av_timer_rounded,
        ),
    ];

    final mopDock = <Widget>[
      if (caps.has(Cap.mopDockMopWashTemperatureControl))
        const CapabilitySelectTile(
          capability: Cap.mopDockMopWashTemperatureControl,
          valueKey: 'temperature',
          propertiesKey: 'supportedTemperatures',
          title: 'Mop wash temperature',
          subtitle: 'Select if and/or how much the dock should heat the water used to rinse the mop pads.',
          icon: Icons.device_thermostat_rounded,
        ),
      if (caps.has(Cap.mopDockMopAutoDryingControl))
        const CapabilityToggleTile(
          capability: Cap.mopDockMopAutoDryingControl,
          title: 'Mop auto-drying',
          subtitle: 'Automatically dry the mop pads after a cleanup.',
          icon: Icons.air_rounded,
        ),
      if (caps.has(Cap.mopDockMopDryingTimeControl))
        CapabilitySelectTile(
          capability: Cap.mopDockMopDryingTimeControl,
          valueKey: 'duration',
          propertiesKey: 'supportedDurations',
          title: 'Mop drying time',
          icon: Icons.av_timer_rounded,
          subtitleBuilder: (p) {
            const base =
                'Select how long the mop should be dried with hot air after a cleanup.';
            return asStringList(p['supportedDurations']).contains('cold')
                ? '$base "Cold" disables the heater and compensates with far longer runtimes.'
                : base;
          },
        ),
    ];

    final soundParts = [
      if (caps.has(Cap.voicePackManagement)) 'Voice packs',
      if (caps.has(Cap.doNotDisturb)) 'Do not disturb',
      if (caps.has(Cap.speakerVolumeControl) && caps.has(Cap.speakerTest))
        'Speaker settings',
    ];
    final misc = <Widget>[
      if (caps.hasAny([
        Cap.speakerVolumeControl,
        Cap.speakerTest,
        Cap.voicePackManagement,
        Cap.doNotDisturb,
      ]))
        NavTile(
          title: 'System options',
          subtitle: soundParts.join(', '),
          icon: Icons.miscellaneous_services_rounded,
          onTap: () => openSoundOptions(context),
        ),
      if (caps.has(Cap.quirks))
        NavTile(
          title: 'Quirks',
          subtitle: 'Configure firmware-specific quirks',
          icon: Icons.star_rounded,
          onTap: () => openQuirks(context),
        ),
    ];

    final groups = <(String, IconData, List<Widget>)>[
      ('General', Icons.settings_rounded, general),
      ('Behavior', Icons.schema_rounded, [...navigation, ...carpet, ...mop]),
      ('Perception', Icons.satellite_alt_rounded, perception),
      ('Dock', Icons.villa_rounded, [...emptying, ...mopDock]),
      ('Misc', Icons.tune_rounded, misc),
    ];
    final visible = groups.where((g) => g.$3.isNotEmpty).toList();

    return ValrovePage(
      title: 'Robot options',
      subtitle: "Tunables and actions provided by the robot's firmware",
      children: [
        if (visible.isEmpty)
          const EmptyState(
            icon: Icons.tune_rounded,
            title: 'Nothing to configure',
            message: 'This robot does not expose any firmware options.',
          ),
        for (final (title, icon, tiles) in visible) ...[
          SectionLabel(title, icon: icon),
          TileGroup(children: tiles),
        ],
      ],
    );
  }

  static String _cleanRouteSubtitle(Json p) {
    final supported = asStringList(p['supportedRoutes']);
    String labels(List<String> values) => values
        .map(
          (v) =>
              '"${supported.contains(v) ? optionLabel(Cap.cleanRouteControl, v) : 'unknown'}"',
        )
        .join(', ');
    final mopOnly = asStringList(p['mopOnly']);
    final oneTime = asStringList(p['oneTime']);
    final buffer = StringBuffer('Trade speed for thoroughness and vice-versa.');
    if (mopOnly.isNotEmpty) {
      buffer.write(
        ' ${labels(mopOnly)} ${mopOnly.length == 1 ? 'only applies' : 'only apply'} when mopping.',
      );
    }
    if (oneTime.isNotEmpty) {
      buffer.write(
        ' ${labels(oneTime)} ${oneTime.length == 1 ? 'is' : 'are'} one-time only.',
      );
    }
    return buffer.toString();
  }
}
