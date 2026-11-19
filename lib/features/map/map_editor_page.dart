import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/help_texts.dart';
import '../../core/util/format.dart';
import '../../core/valetudo/capabilities.dart';
import '../../core/valetudo/client/valetudo_client.dart';
import '../../core/valetudo/models/models.dart';
import '../../map/editing/shapes.dart';
import '../../map/map_controller.dart';
import '../../map/processing/map_processor.dart';
import '../../map/render/map_painter.dart';
import '../../map/widgets/map_canvas.dart';
import '../../state/app_state.dart';
import '../../state/commands.dart';
import '../../state/data.dart';
import '../../state/room_icons.dart';
import '../../state/session.dart';
import '../../state/toasts.dart';
import '../../ui/dialogs.dart';
import '../../ui/glass.dart';
import '../../ui/theme.dart';
import '../../ui/widgets.dart';
import '../home/home_screen.dart' show RadarLoader;
import 'room_rename_dialog.dart';

class MapEditorPage extends ConsumerStatefulWidget {
  const MapEditorPage({super.key, required this.mode});

  final MapMode mode;

  @override
  ConsumerState<MapEditorPage> createState() => _MapEditorPageState();
}

class _MapEditorPageState extends ConsumerState<MapEditorPage> {
  late final MapController _map = MapController(mode: widget.mode);
  bool _loadedShapes = false;
  bool _reloadOnNextMap = false;
  int _savedRevision = 0;
  String? _sceneNonce;
  bool _busy = false;
  bool _orderMode = false;

  bool get _isShapeEditor =>
      widget.mode == MapMode.editRestrictions ||
      widget.mode == MapMode.editAnnotations;

  bool get _dirty =>
      _isShapeEditor && _loadedShapes && _map.revision != _savedRevision;

  String get _title => switch (widget.mode) {
    MapMode.editSegments => 'Rooms',
    MapMode.editRestrictions => 'Virtual restrictions',
    _ => 'Annotations',
  };

  String get _help => switch (widget.mode) {
    MapMode.editSegments => HelpTexts.segmentEditHelp,
    MapMode.editRestrictions => HelpTexts.virtualRestrictionEditHelp,
    _ => HelpTexts.mapAnnotationsHelp,
  };

  @override
  void dispose() {
    _map.dispose();
    super.dispose();
  }

  void _loadShapes(ValetudoMap map) {
    final shapes = widget.mode == MapMode.editRestrictions
        ? restrictionShapesFromMap(map)
        : annotationShapesFromMap(map);
    _map.replaceShapes(shapes);
    _savedRevision = _map.revision;
    _loadedShapes = true;
  }

  Future<bool> _confirmDiscard() async {
    if (!_dirty) return true;
    return showConfirm(
      context,
      title: 'Discard changes?',
      message: 'You have unsaved changes on the map.',
      confirmLabel: 'Discard',
      destructive: true,
    );
  }

  @override
  Widget build(BuildContext context) {
    final mapState = ref.watch(liveMapProvider);
    final scene = mapState.scene;
    final status = ref.watch(robotStatusProvider);
    final docked = status.value == RobotStatus.docked;
    final dark = ref.watch(isDarkProvider);
    final caps = ref.watch(capsProvider);
    final accent = context.scheme.primary;

    if (scene != null && _isShapeEditor) {
      if (!_loadedShapes) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && !_loadedShapes) {
            setState(() => _loadShapes(scene.data.map));
          }
        });
      } else if (_reloadOnNextMap && scene.data.map.nonce != _sceneNonce) {
        _reloadOnNextMap = false;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) setState(() => _loadShapes(scene.data.map));
        });
      }
    }
    _sceneNonce = scene?.data.map.nonce;

    final media = MediaQuery.of(context);
    final insets = EdgeInsets.only(
      top: media.padding.top + 70,
      bottom: 210 + media.padding.bottom,
      left: 12,
      right: 12,
    );

    return PopScope(
      canPop: !_dirty,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (await _confirmDiscard() && context.mounted) {
          _savedRevision = _map.revision;
          Navigator.of(context).pop();
        }
      },
      child: Scaffold(
        body: AmbientBackground(
          accent: accent,
          intensity: 0.6,
          child: SharedBackdrop(
            child: Stack(
              children: [
                Positioned.fill(
                  child: scene == null || !scene.data.hasLayers
                      ? Center(
                          child: mapState.loading
                              ? const RadarLoader(label: 'Loading map…')
                              : const EmptyState(
                                  icon: Icons.map_outlined,
                                  title: 'No map',
                                  message: 'The robot has no map to edit yet.',
                                ),
                        )
                      : ListenableBuilder(
                          listenable: _map,
                          builder: (context, _) => MapCanvas(
                            scene: scene,
                            controller: _map,
                            style: MapStyle.of(
                              dark: dark,
                              accent: accent,
                              background: context.colors.background,
                            ),
                            insets: insets,
                            roomIcons: ref.watch(roomIconsProvider),
                            editingAllowed: docked,
                            maxSegmentSelection: _orderMode ? null : 2,
                            showSelectionOrder: _orderMode,
                            showCleanOrder:
                                caps.has(Cap.mapSegmentCleanOrder) &&
                                !_orderMode,
                            onBlockedInteraction: () => ref
                                .read(toastProvider)
                                .show(
                                  'Editing requires the robot to be docked',
                                ),
                            onSelectionLimit: () => ref
                                .read(toastProvider)
                                .show(
                                  'Select at most two rooms (to join them)',
                                ),
                          ),
                        ),
                ),
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: ProgressiveBlurEdge(height: media.padding.top + 76),
                ),
                Positioned(
                  top: media.padding.top + 8,
                  left: 12,
                  right: 12,
                  child: Row(
                    children: [
                      GlassIconButton(
                        icon: Icons.arrow_back_ios_new_rounded,
                        iconSize: 18,
                        tooltip: 'Back',
                        onPressed: () async {
                          if (await _confirmDiscard() && context.mounted) {
                            _savedRevision = _map.revision;
                            Navigator.of(context).pop();
                          }
                        },
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Glass(
                          radius: 24,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 13,
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  _title,
                                  style: context.text.titleMedium,
                                ),
                              ),
                              if (_dirty)
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 3,
                                  ),
                                  decoration: BoxDecoration(
                                    color: context.colors.warning.withValues(
                                      alpha: 0.18,
                                    ),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    'Unsaved',
                                    style: context.text.labelSmall?.copyWith(
                                      color: context.colors.warning,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      GlassIconButton(
                        icon: Icons.help_outline_rounded,
                        tooltip: 'Help',
                        onPressed: () => showMarkdownSheet(
                          context,
                          title: _title,
                          markdown: _help,
                        ),
                      ),
                    ],
                  ),
                ),
                Positioned(
                  left: 12,
                  right: 12,
                  bottom: media.padding.bottom + 12,
                  child: Glass(
                    radius: 28,
                    padding: const EdgeInsets.all(14),
                    child: ListenableBuilder(
                      listenable: _map,
                      builder: (context, _) => AnimatedSize(
                        duration: const Duration(milliseconds: 250),
                        curve: Curves.easeOutCubic,
                        child: !docked
                            ? _hint(
                                context,
                                Icons.lock_clock_rounded,
                                'Editing ${_title.toLowerCase()} requires the robot to be docked',
                              )
                            : switch (widget.mode) {
                                MapMode.editSegments => _segmentPanel(
                                  context,
                                  scene?.data,
                                ),
                                MapMode.editRestrictions => _restrictionPanel(
                                  context,
                                ),
                                _ => _annotationPanel(context),
                              },
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _hint(BuildContext context, IconData icon, String text) {
    return Row(
      children: [
        Icon(icon, color: context.colors.textSecondary),
        const SizedBox(width: 12),
        Expanded(child: Text(text, style: context.text.bodyMedium)),
      ],
    );
  }

  Future<bool> _command(
    String what,
    Future<void> Function(ValetudoClient c) action,
  ) async {
    setState(() => _busy = true);
    final ok = await ref
        .read(commandsProvider)
        .run(what, action, refreshState: true, invalidate: [segmentsProvider]);
    if (ok) {
      _map.clearSelection();
      await ref.read(liveMapProvider.notifier).refresh();
    }
    if (mounted) setState(() => _busy = false);
    return ok;
  }

  // -------------------------------------------------------------------------
  // Rooms
  // -------------------------------------------------------------------------

  Widget _segmentPanel(BuildContext context, ProcessedMap? data) {
    final caps = ref.watch(capsProvider);
    final selected = _map.selectedSegments;
    final line = _map.cuttingLine;
    String name(String id) => data?.segment(id)?.displayName ?? 'Room $id';

    if (_orderMode) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Clean order', style: context.text.titleMedium),
          const SizedBox(height: 4),
          Text(
            selected.isEmpty
                ? 'Tap the rooms in the order they should be cleaned.'
                : selected
                      .map(name)
                      .toList()
                      .asMap()
                      .entries
                      .map((e) => '${e.key + 1}. ${e.value}')
                      .join('  '),
            style: context.text.bodySmall,
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () {
                    _map.clearSelection();
                    setState(() => _orderMode = false);
                  },
                  child: const Text('Cancel'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton(
                  onPressed: selected.isEmpty || _busy
                      ? null
                      : () async {
                          await _command(
                            'save the clean order',
                            (c) => c.orderSegments(selected),
                          );
                          if (mounted) setState(() => _orderMode = false);
                        },
                  child: const Text('Save order'),
                ),
              ),
            ],
          ),
        ],
      );
    }

    if (selected.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _hint(
            context,
            Icons.touch_app_rounded,
            'Select a room to start editing. Select two rooms to join them.',
          ),
          if (caps.has(Cap.mapSegmentCleanOrder)) ...[
            const SizedBox(height: 12),
            OutlinedButton.icon(
              icon: const Icon(Icons.format_list_numbered_rounded),
              label: const Text('Edit clean order'),
              onPressed: () => setState(() => _orderMode = true),
            ),
          ],
        ],
      );
    }

    final buttons = <Widget>[];
    if (selected.length == 2 && line == null && caps.has(Cap.mapSegmentEdit)) {
      buttons.add(
        _PanelButton(
          icon: Icons.join_full_rounded,
          label: 'Join ${name(selected[0])} and ${name(selected[1])}',
          primary: true,
          busy: _busy,
          onTap: () => _command(
            'join the rooms',
            (c) => c.joinSegments(selected[0], selected[1]),
          ),
        ),
      );
    }
    if (selected.length == 1 && line != null && caps.has(Cap.mapSegmentEdit)) {
      buttons.add(
        _PanelButton(
          icon: Icons.content_cut_rounded,
          label: 'Split ${name(selected[0])}',
          primary: true,
          busy: _busy,
          onTap: () {
            final ps = data?.pixelSize ?? 5;
            _command(
              'split the room',
              (c) => c.splitSegment(
                selected[0],
                toCm(line.p0, ps),
                toCm(line.p1, ps),
              ),
            );
          },
        ),
      );
    }
    if (selected.length == 1 && line == null) {
      if (caps.has(Cap.mapSegmentRename)) {
        buttons.add(
          _PanelButton(
            icon: Icons.drive_file_rename_outline_rounded,
            label: 'Rename',
            busy: _busy,
            onTap: () async {
              final id = selected[0];
              final current = (data?.segment(id)?.name ?? '').trim();
              final result = await showRoomRenameDialog(
                context,
                roomLabel: name(id),
                currentName: current,
                pickedKind: pickedRoomKind(
                  ref.read(roomIconChoicesProvider),
                  id,
                  current,
                ),
                takenNames: [
                  for (final s in data?.segments ?? const <SegmentInfo>[])
                    if (s.id != id && s.name != null) s.name!,
                ],
              );
              if (result == null) return;
              final renamed =
                  result.name == current ||
                  await _command(
                    'rename the room',
                    (c) => c.renameSegment(id, result.name),
                  );
              if (renamed) {
                ref
                    .read(roomIconChoicesProvider.notifier)
                    .set(id, name: result.name, kind: result.kind);
              }
            },
          ),
        );
      }
      if (caps.has(Cap.mapSegmentMaterialControl)) {
        buttons.add(
          _PanelButton(
            icon: Icons.texture_rounded,
            label: 'Material',
            busy: _busy,
            onTap: () async {
              final materials = await ref
                  .read(segmentMaterialsProvider.future)
                  .catchError((_) => <String>[]);
              if (!context.mounted || materials.isEmpty) return;
              final current =
                  data?.segment(selected[0])?.material ??
                  SegmentMaterial.generic;
              final picked = await showChoiceSheet<String>(
                context,
                title: 'Floor material',
                subtitle:
                    "What material is the floor of '${name(selected[0])}' made of?",
                selected: current,
                options: [
                  for (final m in materials)
                    ChoiceOption(m, SegmentMaterial.label(m)),
                ],
              );
              if (picked != null && picked != current) {
                await _command(
                  'set the floor material',
                  (c) => c.setSegmentMaterial(selected[0], picked),
                );
              }
            },
          ),
        );
      }
      if (caps.has(Cap.mapSegmentEdit)) {
        buttons.add(
          _PanelButton(
            icon: Icons.design_services_rounded,
            label: 'Cutting line',
            onTap: () => _map.addShape(ShapeKind.cuttingLine),
          ),
        );
      }
    }
    buttons.add(
      _PanelButton(
        icon: Icons.close_rounded,
        label: 'Clear',
        onTap: _map.clearSelection,
      ),
    );

    final info = selected.length == 1 ? data?.segment(selected[0]) : null;
    final icon = info == null ? null : ref.watch(roomIconsProvider)[info.id];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            if (icon != null) ...[
              Icon(icon, size: 20, color: context.colors.textSecondary),
              const SizedBox(width: 8),
            ],
            Expanded(
              child: Text(
                selected.length == 1
                    ? name(selected[0])
                    : '${name(selected[0])} + ${name(selected[1])}',
                style: context.text.titleMedium,
              ),
            ),
          ],
        ),
        if (info != null)
          Text(
            [
              areaFromCm2(info.area),
              if (info.material != null) SegmentMaterial.label(info.material!),
              if (line != null) 'Drag the cutting line across the room',
            ].join(' · '),
            style: context.text.bodySmall,
          ),
        if (selected.length == 1 &&
            line == null &&
            caps.has(Cap.mapSegmentEdit))
          Text(
            'Select a second room to join, or add a cutting line to split.',
            style: context.text.bodySmall,
          ),
        const SizedBox(height: 12),
        Wrap(spacing: 8, runSpacing: 8, children: buttons),
      ],
    );
  }

  // -------------------------------------------------------------------------
  // Restrictions & annotations
  // -------------------------------------------------------------------------

  Widget _restrictionPanel(BuildContext context) {
    final types = ref.watch(restrictedZoneTypesProvider);
    return types.when(
      data: (supported) => _shapePanel(
        context,
        kinds: [
          ShapeKind.virtualWall,
          if (supported.contains('regular')) ShapeKind.noGoArea,
          if (supported.contains('mop')) ShapeKind.noMopArea,
        ],
        onSave: () async {
          final ps = ref.read(liveMapProvider).scene?.data.pixelSize ?? 5;
          return ref
              .read(commandsProvider)
              .run(
                'save the virtual restrictions',
                (c) => c.setVirtualRestrictions(
                  virtualWallsFromShapes(_map.shapes, ps),
                  restrictedZonesFromShapes(_map.shapes, ps),
                ),
                success: 'Saved successfully',
              );
        },
      ),
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => InlineError(
        'Error loading CombinedVirtualRestrictionsCapability properties',
        onRetry: () => ref.invalidate(restrictedZoneTypesProvider),
      ),
    );
  }

  Widget _annotationPanel(BuildContext context) {
    final types = ref.watch(annotationTypesProvider);
    return types.when(
      data: (supported) => _shapePanel(
        context,
        kinds: [
          if (supported.contains('threshold')) ShapeKind.threshold,
          if (supported.contains('curtain')) ShapeKind.curtain,
          if (supported.contains('ramp')) ShapeKind.ramp,
        ],
        onSave: () async {
          final ps = ref.read(liveMapProvider).scene?.data.pixelSize ?? 5;
          return ref
              .read(commandsProvider)
              .run(
                'save the map annotations',
                (c) =>
                    c.setMapAnnotations(annotationsFromShapes(_map.shapes, ps)),
                success: 'Saved successfully',
              );
        },
      ),
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => InlineError(
        'Error loading MapAnnotationsCapability properties',
        onRetry: () => ref.invalidate(annotationTypesProvider),
      ),
    );
  }

  Widget _shapePanel(
    BuildContext context, {
    required List<ShapeKind> kinds,
    required Future<bool> Function() onSave,
  }) {
    IconData icon(ShapeKind k) => switch (k) {
      ShapeKind.virtualWall => Icons.fence_rounded,
      ShapeKind.noGoArea => Icons.do_not_disturb_on_rounded,
      ShapeKind.noMopArea => Icons.format_color_reset_rounded,
      ShapeKind.threshold => Icons.horizontal_rule_rounded,
      ShapeKind.curtain => Icons.curtains_rounded,
      ShapeKind.ramp => Icons.trending_up_rounded,
      _ => Icons.add_rounded,
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            for (final k in kinds)
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 3),
                  child: Pressable(
                    onTap: () => _map.addShape(k),
                    semanticLabel: 'Add ${k.label}',
                    child: Container(
                      height: 62,
                      decoration: BoxDecoration(
                        color: context.colors.textPrimary.withValues(
                          alpha: 0.06,
                        ),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(icon(k), size: 18),
                              const SizedBox(width: 4),
                              Icon(
                                Icons.add_rounded,
                                size: 14,
                                color: context.colors.textSecondary,
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${k.label} (${_map.countOf(k)})',
                            style: context.text.labelSmall?.copyWith(
                              letterSpacing: 0,
                              color: context.colors.textPrimary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            IconButton.filledTonal(
              tooltip: 'Remove all',
              onPressed: _map.shapes.isEmpty
                  ? null
                  : () => _map.removeShapesWhere((_) => true),
              icon: const Icon(Icons.delete_sweep_rounded),
            ),
            const SizedBox(width: 6),
            IconButton.filledTonal(
              tooltip: 'Reload from robot',
              onPressed: () {
                final map = ref.read(liveMapProvider).scene?.data.map;
                if (map != null) setState(() => _loadShapes(map));
              },
              icon: const Icon(Icons.refresh_rounded),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: FilledButton.icon(
                onPressed: _busy || !_dirty
                    ? null
                    : () async {
                        setState(() => _busy = true);
                        final ok = await onSave();
                        if (ok) {
                          _savedRevision = _map.revision;
                          _reloadOnNextMap = true;
                          await ref.read(liveMapProvider.notifier).refresh();
                        }
                        if (mounted) setState(() => _busy = false);
                      },
                icon: _busy
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.save_rounded),
                label: const Text('Save'),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _PanelButton extends StatelessWidget {
  const _PanelButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.primary = false,
    this.busy = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool primary;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final child = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (busy && primary)
          const SizedBox.square(
            dimension: 16,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: Colors.white,
            ),
          )
        else
          Icon(icon, size: 18),
        const SizedBox(width: 6),
        Flexible(child: Text(label, overflow: TextOverflow.ellipsis)),
      ],
    );
    return primary
        ? FilledButton(onPressed: busy ? null : onTap, child: child)
        : FilledButton.tonal(onPressed: busy ? null : onTap, child: child);
  }
}
