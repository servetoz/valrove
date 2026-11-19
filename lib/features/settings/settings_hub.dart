import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/valetudo/capabilities.dart';
import '../../state/data.dart';
import '../../state/session.dart';
import '../../ui/theme.dart';
import '../../ui/widgets.dart';
import '../home/top_bar.dart';
import '../navigation.dart';

/// All deeper configuration, grouped by topic and filtered by capabilities.
class SettingsHubPage extends ConsumerWidget {
  const SettingsHubPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final caps = ref.watch(capsProvider);
    final name = ref.watch(robotDisplayNameProvider);
    final info = ref.watch(robotInfoProvider).value;
    final version = ref.watch(valetudoVersionProvider).value;
    final cameraEnabled =
        caps.has(Cap.duststreaming) &&
        (ref.watch(duststreamingEnabledProvider).value ?? false);
    final c = context.colors;

    final soundParts = [
      if (caps.has(Cap.speakerVolumeControl) || caps.has(Cap.speakerTest))
        'Speaker',
      if (caps.has(Cap.voicePackManagement)) 'Voice packs',
      if (caps.has(Cap.doNotDisturb)) 'Do not disturb',
    ];

    return ValrovePage(
      title: 'Settings',
      subtitle: info == null
          ? name
          : '$name · ${info.manufacturer} ${info.modelName}${version == null ? '' : ' · Valetudo ${version.release}'}',
      children: [
        const SectionLabel('Robot'),
        TileGroup(
          children: [
            if (caps.has(Cap.consumableMonitoring))
              NavTile(
                title: 'Consumables',
                subtitle: 'Brushes, filters and more',
                icon: Icons.pending_actions_rounded,
                iconColor: c.warning,
                onTap: () => openConsumables(context),
              ),
            if (caps.has(Cap.totalStatistics))
              NavTile(
                title: 'Statistics',
                subtitle: 'Lifetime totals and achievements',
                icon: Icons.emoji_events_rounded,
                iconColor: const Color(0xFFF59E0B),
                onTap: () => openStatistics(context),
              ),
            if (caps.hasAny([
              Cap.manualControl,
              Cap.highResolutionManualControl,
            ]))
              NavTile(
                title: 'Manual control',
                subtitle: 'Drive the robot remotely',
                icon: Icons.sports_esports_rounded,
                iconColor: const Color(0xFF38BDF8),
                onTap: () => openManualControl(context),
              ),
            if (cameraEnabled)
              NavTile(
                title: 'Camera',
                subtitle: 'Live view from the robot',
                icon: Icons.videocam_rounded,
                iconColor: c.danger,
                onTap: () => openCamera(context),
              ),
            NavTile(
              title: 'Robot options',
              subtitle: 'Cleaning behavior, perception and dock',
              icon: Icons.tune_rounded,
              onTap: () => openRobotOptions(context),
            ),
            if (soundParts.isNotEmpty)
              NavTile(
                title: 'Sound & quiet hours',
                subtitle: soundParts.join(', '),
                icon: Icons.volume_up_rounded,
                iconColor: const Color(0xFFA78BFA),
                onTap: () => openSoundOptions(context),
              ),
            if (caps.has(Cap.quirks))
              NavTile(
                title: 'Quirks',
                subtitle: 'Configure firmware-specific quirks',
                icon: Icons.star_rounded,
                iconColor: const Color(0xFFF472B6),
                onTap: () => openQuirks(context),
              ),
          ],
        ),
        const SectionLabel('Cleaning'),
        TileGroup(
          children: [
            NavTile(
              title: 'Schedules',
              subtitle: 'Timers and delayed starts',
              icon: Icons.schedule_rounded,
              iconColor: const Color(0xFF2DD4BF),
              onTap: () => openTimers(context),
            ),
            if (hasMapManagement(caps))
              NavTile(
                title: 'Map',
                subtitle: 'Rooms, restrictions, annotations and maps',
                icon: Icons.map_rounded,
                iconColor: const Color(0xFF60A5FA),
                onTap: () => openMapManagement(context),
              ),
          ],
        ),
        const SectionLabel('Network'),
        TileGroup(
          children: [
            NavTile(
              title: 'Connectivity',
              subtitle: 'Wi-Fi, MQTT, NTP, access and discovery',
              icon: Icons.hub_rounded,
              iconColor: const Color(0xFF34D399),
              onTap: () => openConnectivity(context),
            ),
          ],
        ),
        const SectionLabel('Valetudo'),
        TileGroup(
          children: [
            NavTile(
              title: 'Valetudo options',
              subtitle: 'Name, camera streaming and defaults',
              icon: Icons.settings_suggest_rounded,
              onTap: () => openValetudoOptions(context),
            ),
            NavTile(
              title: 'Updater',
              subtitle: 'Check for Valetudo updates',
              icon: Icons.system_update_alt_rounded,
              iconColor: const Color(0xFF22D3EE),
              onTap: () => openUpdater(context),
            ),
            NavTile(
              title: 'Log',
              subtitle: 'Live Valetudo log',
              icon: Icons.article_rounded,
              iconColor: const Color(0xFF94A3B8),
              onTap: () => openLog(context),
            ),
            NavTile(
              title: 'System information',
              subtitle: 'Memory, CPU and runtime',
              icon: Icons.memory_rounded,
              iconColor: const Color(0xFFFB923C),
              onTap: () => openSystemInfo(context),
            ),
          ],
        ),
        const SectionLabel('App'),
        TileGroup(
          children: [
            NavTile(
              title: 'Appearance & robots',
              subtitle: 'Theme, haptics and saved robots',
              icon: Icons.palette_rounded,
              iconColor: const Color(0xFFE879F9),
              onTap: () => openAppSettings(context),
            ),
            NavTile(
              title: 'Help',
              subtitle: 'Getting started with Valetudo',
              icon: Icons.help_rounded,
              onTap: () => openHelp(context),
            ),
            NavTile(
              title: 'About',
              subtitle: 'Versions, licenses and credits',
              icon: Icons.info_rounded,
              onTap: () => openAbout(context),
            ),
          ],
        ),
      ],
    );
  }
}
