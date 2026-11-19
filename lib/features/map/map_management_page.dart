import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/help_texts.dart';
import '../../core/valetudo/capabilities.dart';
import '../../core/valetudo/client/valetudo_client.dart';
import '../../core/valetudo/models/models.dart';
import '../../map/map_controller.dart';
import '../../state/commands.dart';
import '../../state/data.dart';
import '../../state/session.dart';
import '../../ui/dialogs.dart';
import '../../ui/theme.dart';
import '../../ui/widgets.dart';
import '../navigation.dart';

class MapManagementPage extends ConsumerStatefulWidget {
  const MapManagementPage({super.key});

  @override
  ConsumerState<MapManagementPage> createState() => _MapManagementPageState();
}

class _MapManagementPageState extends ConsumerState<MapManagementPage> {
  String? _busy;

  Future<void> _run(
    String key,
    String what,
    Future<void> Function(ValetudoClient c) action,
  ) async {
    setState(() => _busy = key);
    await ref.read(commandsProvider).run(what, action, refreshState: true);
    if (mounted) setState(() => _busy = null);
  }

  Future<void> _export() async {
    final raw = ref.read(liveMapProvider).rawJson;
    if (raw == null) return;
    final systemId = ref.read(valetudoInfoProvider).value?.systemId ?? 'robot';
    final ts = DateTime.now()
        .toUtc()
        .toIso8601String()
        .replaceAll(':', '-')
        .split('.')
        .first;
    final pretty = const JsonEncoder.withIndent('  ').convert(jsonDecode(raw));
    final name = 'ValetudoMapExport-$systemId-$ts.json';
    await SharePlus.instance.share(
      ShareParams(
        files: [
          XFile.fromData(
            utf8.encode(pretty),
            mimeType: 'application/json',
            name: name,
          ),
        ],
        fileNameOverrides: [name],
        subject: name,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final caps = ref.watch(capsProvider);
    final cameraEnabled =
        caps.has(Cap.duststreaming) &&
        (ref.watch(duststreamingEnabledProvider).value ?? false);
    final hasMap = ref.watch(liveMapProvider.select((s) => s.rawJson != null));
    final c = context.colors;

    return ValrovePage(
      title: 'Map',
      subtitle: 'Rooms, restrictions and map tools',
      actions: [
        IconButton(
          tooltip: 'Help',
          icon: const Icon(Icons.help_outline_rounded),
          onPressed: () => showMarkdownSheet(
            context,
            title: 'Map management',
            markdown:
                '${HelpTexts.mapManagementHelp}\n\n${HelpTexts.mapUtilitiesHelp}',
          ),
        ),
      ],
      children: [
        if (caps.has(Cap.pendingMapChangeHandling))
          const _PendingMapChangeCard(),
        if (caps.has(Cap.multipleMap)) ...[
          const SectionLabel('Maps', icon: Icons.layers_rounded),
          const _MultiMapCard(),
        ],
        if (caps.hasAny([
          Cap.mapSegmentEdit,
          Cap.mapSegmentRename,
          Cap.combinedVirtualRestrictions,
          Cap.mapAnnotations,
          Cap.mapSegmentMaterialControl,
        ])) ...[
          const SectionLabel('Edit', icon: Icons.edit_rounded),
          TileGroup(
            children: [
              if (caps.hasAny([Cap.mapSegmentEdit, Cap.mapSegmentRename]))
                NavTile(
                  title: 'Rooms',
                  subtitle: 'Join, split, rename and set floor materials',
                  icon: Icons.dashboard_rounded,
                  iconColor: const Color(0xFF2DD4BF),
                  onTap: () => openMapEditor(context, MapMode.editSegments),
                ),
              if (caps.has(Cap.combinedVirtualRestrictions))
                NavTile(
                  title: 'Virtual restrictions',
                  subtitle:
                      'Create, modify and delete walls, no-go and no-mop areas',
                  icon: Icons.block_rounded,
                  iconColor: c.danger,
                  onTap: () => openMapEditor(context, MapMode.editRestrictions),
                ),
              if (caps.has(Cap.mapAnnotations))
                NavTile(
                  title: 'Annotations',
                  subtitle: 'Thresholds, curtains and ramps',
                  icon: Icons.edit_note_rounded,
                  iconColor: const Color(0xFF06B6D4),
                  onTap: () => openMapEditor(context, MapMode.editAnnotations),
                ),
            ],
          ),
        ],
        if (caps.hasAny([
          Cap.persistentMapControl,
          Cap.mappingPass,
          Cap.mapReset,
        ])) ...[
          const SectionLabel('Robot-managed', icon: Icons.memory_rounded),
          TileGroup(
            children: [
              if (caps.has(Cap.persistentMapControl))
                const _PersistentMapToggle(),
              if (caps.has(Cap.mappingPass))
                ActionTile(
                  title: 'Mapping pass',
                  subtitle: 'Create a new map',
                  icon: Icons.layers_rounded,
                  actionLabel: 'Start',
                  busy: _busy == 'mapping',
                  onAction: () async {
                    final ok = await showConfirm(
                      context,
                      title: 'Start mapping pass?',
                      message: 'Do you really want to start a mapping pass?',
                      confirmLabel: 'Start',
                    );
                    if (ok) {
                      await _run(
                        'mapping',
                        'start the mapping pass',
                        (c) => c.startMappingPass(),
                      );
                    }
                  },
                ),
              if (caps.has(Cap.mapReset))
                ActionTile(
                  title: 'Map reset',
                  subtitle: 'Delete the current map',
                  icon: Icons.layers_clear_rounded,
                  actionLabel: 'Reset',
                  danger: true,
                  busy: _busy == 'reset',
                  onAction: () async {
                    final ok = await showConfirm(
                      context,
                      title: 'Reset map?',
                      message: 'Do you really want to reset the map?',
                      confirmLabel: 'Reset',
                      destructive: true,
                    );
                    if (ok) {
                      await _run('reset', 'reset the map', (c) => c.resetMap());
                    }
                  },
                ),
            ],
          ),
        ],
        const SectionLabel('Utilities', icon: Icons.auto_awesome_rounded),
        TileGroup(
          children: [
            NavTile(
              title: 'Coverage map',
              subtitle: "Check the robot's coverage",
              icon: Icons.crop_rounded,
              iconColor: const Color(0xFFA78BFA),
              onTap: () => openCoverageMap(context),
            ),
            if (cameraEnabled)
              NavTile(
                title: 'Spectator view',
                subtitle: 'Watch it clean: live map and camera',
                icon: Icons.videocam_rounded,
                iconColor: c.danger,
                onTap: () => openCamera(context),
              ),
            ActionTile(
              title: 'Export ValetudoMap',
              subtitle:
                  'Share a ValetudoMap data export to use with other tools',
              icon: Icons.ios_share_rounded,
              actionLabel: 'Share',
              onAction: hasMap ? _export : null,
            ),
          ],
        ),
      ],
    );
  }
}

class _PersistentMapToggle extends ConsumerStatefulWidget {
  const _PersistentMapToggle();

  @override
  ConsumerState<_PersistentMapToggle> createState() =>
      _PersistentMapToggleState();
}

class _PersistentMapToggleState extends ConsumerState<_PersistentMapToggle> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final value = ref.watch(persistentMapProvider);
    return ToggleTile(
      title: 'Persistent maps',
      subtitle: 'Store a persistent map',
      icon: Icons.save_rounded,
      value: value.value,
      error: value.hasError && !value.hasValue,
      busy: _busy,
      onChanged: (enable) async {
        if (!enable) {
          final ok = await showConfirm(
            context,
            title: 'Disable persistent maps?',
            message: 'Do you really want to disable persistent maps?\nThis will delete the currently stored map.',
            confirmLabel: 'Disable',
            destructive: true,
          );
          if (!ok) return;
        }
        setState(() => _busy = true);
        await ref
            .read(commandsProvider)
            .run(
              enable ? 'enable persistent maps' : 'disable persistent maps',
              (c) => c.setToggle(Cap.persistentMapControl, enable),
              invalidate: [persistentMapProvider],
            );
        if (mounted) setState(() => _busy = false);
      },
    );
  }
}

/// Shown while the robot waits for a decision about a newly detected map.
class _PendingMapChangeCard extends ConsumerWidget {
  const _PendingMapChangeCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pending = ref.watch(pendingMapChangeProvider).value ?? false;
    if (!pending) return const SizedBox.shrink();
    Future<void> decide(String action) => ref
        .read(commandsProvider)
        .run(
          action == 'accept' ? 'accept the new map' : 'reject the new map',
          (c) => c.handlePendingMapChange(action),
          invalidate: [pendingMapChangeProvider, eventsProvider],
          refreshState: true,
        );
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: ValroveCard(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                TileIcon(Icons.map_rounded, color: context.colors.warning),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'A map change is pending. Do you want to accept the new map?',
                    style: context.text.titleSmall,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => decide('reject'),
                    child: const Text('Keep old map'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton(
                    onPressed: () => decide('accept'),
                    child: const Text('Accept new map'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Fork feature: multiple stored maps.
class _MultiMapCard extends ConsumerWidget {
  const _MultiMapCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final caps = ref.watch(capsProvider);
    final maps = ref.watch(robotMapsProvider);
    final rotation = ref.watch(
      liveMapProvider.select((s) => s.scene?.data.map.rotation ?? 0),
    );
    return maps.when(
      data: (list) => TileGroup(
        children: [
          for (final m in list)
            ValroveTile(
              title: m.name,
              subtitle: m.active ? 'Active map' : 'Tap to switch to this map',
              icon: m.active ? Icons.check_circle_rounded : Icons.map_outlined,
              iconColor: m.active
                  ? context.colors.success
                  : context.colors.textTertiary,
              onTap: m.active
                  ? null
                  : () async {
                      final ok = await showConfirm(
                        context,
                        title: 'Switch map?',
                        message: 'Switch the robot to "${m.name}"?',
                        confirmLabel: 'Switch',
                      );
                      if (ok) {
                        await ref
                            .read(commandsProvider)
                            .run(
                              'switch the map',
                              (c) => c.switchMap(m.id),
                              invalidate: [robotMapsProvider],
                            );
                        await ref.read(liveMapProvider.notifier).refresh();
                      }
                    },
              trailing: PopupMenuButton<String>(
                icon: const Icon(Icons.more_horiz_rounded),
                onSelected: (action) =>
                    _onAction(context, ref, m, action, rotation),
                itemBuilder: (context) => [
                  if (caps.has(Cap.multipleMapRename))
                    const PopupMenuItem(
                      value: 'rename',
                      child: Text('Rename map'),
                    ),
                  if (caps.has(Cap.multipleMapRotate) && m.active)
                    const PopupMenuItem(
                      value: 'rotate',
                      child: Text('Rotate map'),
                    ),
                  if (caps.has(Cap.multipleMapDelete))
                    const PopupMenuItem(
                      value: 'delete',
                      child: Text('Delete map'),
                    ),
                ],
              ),
            ),
        ],
      ),
      loading: () => const SkeletonCard(rows: 1),
      error: (e, _) => ValroveCard(
        child: InlineError(
          'Error loading maps',
          onRetry: () => ref.invalidate(robotMapsProvider),
        ),
      ),
    );
  }

  Future<void> _onAction(
    BuildContext context,
    WidgetRef ref,
    RobotMapEntry m,
    String action,
    double rotation,
  ) async {
    switch (action) {
      case 'rename':
        final name = await showTextPrompt(
          context,
          title: 'Rename map',
          initial: m.name,
          label: 'Map name',
          validator: (v) => v.trim().isEmpty ? 'Enter a name' : null,
        );
        if (name != null) {
          await ref
              .read(commandsProvider)
              .run(
                'rename the map',
                (c) => c.renameMap(m.id, name.trim()),
                invalidate: [robotMapsProvider],
              );
        }
      case 'rotate':
        if (!context.mounted) return;
        final angle = await showChoiceSheet<double>(
          context,
          title: 'Rotate map',
          subtitle: 'Rotate the current map',
          selected: rotation % 360,
          options: const [
            ChoiceOption(0, '0°', icon: Icons.north_rounded),
            ChoiceOption(90, '90°', icon: Icons.east_rounded),
            ChoiceOption(180, '180°', icon: Icons.south_rounded),
            ChoiceOption(270, '270°', icon: Icons.west_rounded),
          ],
        );
        if (angle != null) {
          await ref
              .read(commandsProvider)
              .run(
                'rotate the map',
                (c) => c.rotateMap(m.id, angle),
                refreshState: true,
              );
          await ref.read(liveMapProvider.notifier).refresh();
        }
      case 'delete':
        final ok = await showConfirm(
          context,
          title: 'Delete map?',
          message: 'Do you really want to delete "${m.name}"?',
          confirmLabel: 'Delete',
          destructive: true,
        );
        if (ok) {
          await ref
              .read(commandsProvider)
              .run(
                'delete the map',
                (c) => c.deleteMap(m.id),
                invalidate: [robotMapsProvider],
              );
        }
    }
  }
}
