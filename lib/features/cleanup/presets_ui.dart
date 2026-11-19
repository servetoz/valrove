import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/cleanup/cleanup_tracker.dart' show joinNames;
import '../../core/cleanup/estimator.dart';
import '../../core/cleanup/presets.dart';
import '../../core/util/format.dart';
import '../../core/valetudo/models/models.dart';
import '../../map/processing/map_processor.dart';
import '../../state/cleanup.dart';
import '../../state/data.dart';
import '../../state/room_icons.dart';
import '../../state/session.dart';
import '../../ui/dialogs.dart';
import '../../ui/glass.dart';
import '../../ui/room_kinds.dart';
import '../../ui/theme.dart';
import '../../ui/widgets.dart';
import '../home/presets.dart' show presetCapabilities;
import 'launchers.dart';

/// Rooms of the live map, by id.
Map<String, SegmentInfo> _rooms(WidgetRef ref) => {
  for (final s
      in ref.watch(liveMapProvider).scene?.data.segments ??
          const <SegmentInfo>[])
    s.id: s,
};

/// "Kitchen, Hallway" or "Whole home".
String presetWhere(CleanupPreset p, Map<String, SegmentInfo> rooms) =>
    p.wholeHome
    ? 'Whole home'
    : joinNames([
        for (final id in p.rooms) rooms[id]?.displayName ?? 'Room $id',
      ]);

/// Estimate for [p] on the current map, if its rooms are known.
CleanupEstimate? presetEstimate(
  WidgetRef ref,
  CleanupPreset p,
  Map<String, SegmentInfo> rooms,
) {
  final estimator = ref.watch(estimatorProvider);
  final currentMode = ref.watch(robotStateProvider).operationMode?.value;
  var minutes = 0;
  var battery = 0;
  var basedOn = 0;
  for (final step in p.steps) {
    final area = step.rooms.isEmpty
        ? rooms.values.fold(0.0, (s, r) => s + r.area)
        : step.rooms.fold(0.0, (s, id) => s + (rooms[id]?.area ?? 0));
    if (area <= 0) continue;
    final e = estimator.estimate(
      roomAreaCm2: area,
      iterations: step.iterations,
      operationMode: step.operationMode ?? currentMode,
    );
    minutes += e.duration.inMinutes;
    battery += e.batteryPercent;
    basedOn = e.basedOn;
  }
  if (minutes == 0) return null;
  return CleanupEstimate(
    duration: Duration(minutes: minutes),
    batteryPercent: battery.clamp(1, 100),
    basedOn: basedOn,
  );
}

/// One-tap presets on the home sheet.
class PresetsStrip extends ConsumerWidget {
  const PresetsStrip({super.key, required this.accent});

  final Color accent;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final presets = ref.watch(cleanupPresetsProvider);
    final rooms = _rooms(ref);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              Icons.bookmarks_rounded,
              size: 18,
              color: context.colors.textSecondary,
            ),
            const SizedBox(width: 8),
            Text('Presets', style: context.text.titleSmall),
            const Spacer(),
            if (presets.isNotEmpty)
              TextButton(
                onPressed: () => openPresetsPage(context),
                child: const Text('Manage'),
              ),
          ],
        ),
        const SizedBox(height: 6),
        SizedBox(
          height: 66,
          child: ListView(
            scrollDirection: Axis.horizontal,
            clipBehavior: Clip.none,
            children: [
              for (final p in presets)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: _PresetChip(
                    title: p.name,
                    subtitle: _chipSubtitle(ref, p, rooms),
                    icon: Icons.play_arrow_rounded,
                    accent: accent,
                    onTap: () => runCleanupPreset(ref, p),
                    onLongPress: () => showPresetEditor(context, preset: p),
                  ),
                ),
              _PresetChip(
                title: presets.isEmpty ? 'Save a preset' : 'New',
                subtitle: presets.isEmpty ? 'Rooms + settings' : 'Preset',
                icon: Icons.add_rounded,
                accent: accent,
                outlined: true,
                onTap: () => showPresetEditor(context),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

String _chipSubtitle(
  WidgetRef ref,
  CleanupPreset p,
  Map<String, SegmentInfo> rooms,
) {
  final minutes = presetEstimate(ref, p, rooms)?.duration.inMinutes;
  final steps = p.steps.length;
  return [
    presetWhere(p, rooms),
    if (steps > 1) '$steps steps',
    if (minutes != null) '≈ $minutes min',
  ].join(' · ');
}

class _PresetChip extends StatelessWidget {
  const _PresetChip({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.accent,
    required this.onTap,
    this.onLongPress,
    this.outlined = false,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final Color accent;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final bool outlined;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Pressable(
      onTap: onTap,
      onLongPress: onLongPress,
      semanticLabel: title,
      child: Container(
        constraints: const BoxConstraints(minWidth: 120, maxWidth: 230),
        padding: const EdgeInsets.fromLTRB(10, 10, 16, 10),
        decoration: BoxDecoration(
          color: outlined
              ? Colors.transparent
              : c.textPrimary.withValues(alpha: context.isDark ? 0.06 : 0.045),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: outlined ? c.tileBorder : accent.withValues(alpha: 0.25),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: outlined
                    ? c.textPrimary.withValues(alpha: 0.07)
                    : accent,
              ),
              child: Icon(
                icon,
                size: 20,
                color: outlined ? c.textPrimary : Colors.white,
              ),
            ),
            const SizedBox(width: 10),
            Flexible(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: context.text.labelLarge,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    subtitle,
                    style: context.text.bodySmall,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Creates a preset (from [rooms] and [iterations], e.g. the selected rooms)
/// or edits [preset].
Future<void> showPresetEditor(
  BuildContext context, {
  CleanupPreset? preset,
  List<String> rooms = const [],
  int iterations = 1,
}) => showValroveSheet<void>(
  context,
  builder: (_) => _PresetEditor(
    preset:
        preset ??
        CleanupPreset(
          id: CleanupPresets.newId(),
          name: '',
          rooms: rooms,
          iterations: iterations,
        ),
    isNew: preset == null,
  ),
);

class _PresetEditor extends ConsumerStatefulWidget {
  const _PresetEditor({required this.preset, required this.isNew});

  final CleanupPreset preset;
  final bool isNew;

  @override
  ConsumerState<_PresetEditor> createState() => _PresetEditorState();
}

class _PresetEditorState extends ConsumerState<_PresetEditor> {
  late CleanupPreset _p = widget.preset;
  late final _name = TextEditingController(text: widget.preset.name);
  bool _seeded = false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _set(CleanupPreset p) => setState(() => _p = p);

  Widget? _roomSettingsLabel(RoomSettings? s) {
    if (s == null || s.isEmpty) return null;
    return Text(
      [
        for (final v in [s.operationMode, s.fanSpeed, s.waterGrade])
          if (v != null) presetLabel(v),
      ].join(' · '),
      style: context.text.bodySmall?.copyWith(color: context.scheme.primary),
    );
  }

  Future<void> _editRoom(String id, String name) async {
    final result = await showValroveSheet<RoomSettings>(
      context,
      builder: (_) =>
          _RoomSettingsSheet(name: name, initial: _p.roomSettings[id]),
    );
    if (result == null) return;
    _set(
      _p.copyWith(
        roomSettings: {
          for (final MapEntry(:key, :value) in _p.roomSettings.entries)
            if (key != id) key: value,
          if (!result.isEmpty) id: result,
        },
      ),
    );
  }

  void _save(Map<String, SegmentInfo> rooms) {
    final name = _name.text.trim();
    ref
        .read(cleanupPresetsProvider.notifier)
        .save(_p.copyWith(name: name.isEmpty ? presetWhere(_p, rooms) : name));
    Navigator.pop(context);
  }

  Future<void> _delete() async {
    final ok = await showConfirm(
      context,
      title: 'Delete "${_p.name}"?',
      confirmLabel: 'Delete',
      destructive: true,
    );
    if (!ok || !mounted) return;
    ref.read(cleanupPresetsProvider.notifier).delete(_p.id);
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final caps = ref.watch(capsProvider);
    final rooms = _rooms(ref);
    final icons = ref.watch(roomIconsProvider);
    final robot = ref.watch(robotStateProvider);
    final maxIterations =
        ref.watch(segmentationPropertiesProvider).value?.iterationCount.max ??
        1;
    // New presets start with the robot's current settings.
    if (widget.isNew && !_seeded && robot.hasStatus) {
      _seeded = true;
      _p = _p.copyWith(
        operationMode: () => robot.operationMode?.value,
        fanSpeed: () => robot.fanSpeed?.value,
        waterGrade: () => robot.waterGrade?.value,
      );
    }
    final estimate = presetEstimate(ref, _p, rooms);
    final available = [
      for (final r in rooms.values)
        if (!_p.rooms.contains(r.id)) r,
    ];
    final values = {
      PresetType.operationMode: _p.operationMode,
      PresetType.fanSpeed: _p.fanSpeed,
      PresetType.waterGrade: _p.waterGrade,
    };
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SheetHeader(
            title: widget.isNew ? 'New preset' : 'Edit preset',
            subtitle:
                'Starts with one tap from the home screen, the widget, '
                'the app shortcuts or the quick settings tile.',
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: _name,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: InputDecoration(
                    labelText: 'Name',
                    hintText: presetWhere(_p, rooms),
                  ),
                ),
                const SizedBox(height: 18),
                Text(
                  _p.rooms.length > 1 ? 'ROOMS, IN ORDER' : 'ROOMS',
                  style: context.text.labelSmall,
                ),
                const SizedBox(height: 6),
                if (_p.wholeHome)
                  const ValroveTile(
                    title: 'Whole home',
                    subtitle: 'Add rooms to clean only those',
                    icon: Icons.home_rounded,
                    dense: true,
                  )
                else
                  ReorderableListView(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    buildDefaultDragHandles: false,
                    onReorderItem: (from, to) {
                      final next = [..._p.rooms];
                      next.insert(to, next.removeAt(from));
                      _set(_p.copyWith(rooms: next));
                    },
                    children: [
                      for (var i = 0; i < _p.rooms.length; i++)
                        ListTile(
                          key: ValueKey(_p.rooms[i]),
                          contentPadding: EdgeInsets.zero,
                          dense: true,
                          leading: Icon(
                            icons[_p.rooms[i]] ?? RoomKind.genericIcon,
                            color: context.colors.textSecondary,
                          ),
                          title: Text(
                            rooms[_p.rooms[i]]?.displayName ??
                                'Room ${_p.rooms[i]} (not on the map)',
                          ),
                          subtitle: _roomSettingsLabel(
                            _p.roomSettings[_p.rooms[i]],
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                tooltip: 'Settings for this room',
                                icon: Icon(
                                  Icons.tune_rounded,
                                  color:
                                      _p.roomSettings[_p.rooms[i]]?.isEmpty ==
                                          false
                                      ? context.scheme.primary
                                      : null,
                                ),
                                onPressed: () => _editRoom(
                                  _p.rooms[i],
                                  rooms[_p.rooms[i]]?.displayName ??
                                      'Room ${_p.rooms[i]}',
                                ),
                              ),
                              IconButton(
                                tooltip: 'Remove',
                                icon: const Icon(
                                  Icons.remove_circle_outline_rounded,
                                ),
                                onPressed: () => _set(
                                  _p.copyWith(
                                    rooms: [..._p.rooms]..removeAt(i),
                                  ),
                                ),
                              ),
                              ReorderableDragStartListener(
                                index: i,
                                child: const Padding(
                                  padding: EdgeInsets.all(8),
                                  child: Icon(Icons.drag_handle_rounded),
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                if (_p.steps.length > 1) ...[
                  const SizedBox(height: 6),
                  _StepsNote(
                    steps: [
                      for (final s in _p.steps)
                        [
                          joinNames([
                            for (final id in s.rooms)
                              rooms[id]?.displayName ?? 'Room $id',
                          ]),
                          for (final v in [
                            s.operationMode,
                            s.fanSpeed,
                            s.waterGrade,
                          ])
                            if (v != null) presetLabel(v),
                        ].join(' · '),
                    ],
                  ),
                ],
                if (available.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final r in available)
                        ActionChip(
                          avatar: Icon(
                            icons[r.id] ?? Icons.add_rounded,
                            size: 18,
                          ),
                          label: Text(r.displayName),
                          onPressed: () =>
                              _set(_p.copyWith(rooms: [..._p.rooms, r.id])),
                        ),
                    ],
                  ),
                ],
                if (!_p.wholeHome && maxIterations > 1) ...[
                  const SizedBox(height: 18),
                  Row(
                    children: [
                      Text('Passes', style: context.text.titleSmall),
                      const Spacer(),
                      SegmentedButton<int>(
                        segments: [
                          for (var i = 1; i <= maxIterations; i++)
                            ButtonSegment(value: i, label: Text('×$i')),
                        ],
                        selected: {_p.iterations.clamp(1, maxIterations)},
                        showSelectedIcon: false,
                        onSelectionChanged: (s) =>
                            _set(_p.copyWith(iterations: s.first)),
                      ),
                    ],
                  ),
                ],
                for (final (cap, type, title, icon) in presetCapabilities)
                  if (caps.has(cap)) ...[
                    const SizedBox(height: 14),
                    _SettingField(
                      capability: cap,
                      title: title,
                      icon: icon,
                      value: values[type],
                      onChanged: (v) => _set(switch (type) {
                        PresetType.operationMode => _p.copyWith(
                          operationMode: () => v,
                        ),
                        PresetType.fanSpeed => _p.copyWith(fanSpeed: () => v),
                        _ => _p.copyWith(waterGrade: () => v),
                      }),
                    ),
                  ],
                if (estimate != null) ...[
                  const SizedBox(height: 18),
                  Row(
                    children: [
                      Icon(
                        Icons.timer_outlined,
                        size: 18,
                        color: context.colors.textSecondary,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          estimate.basedOn == 0
                              ? '${estimate.label} (typical robot)'
                              : '${estimate.label} (from ${estimate.basedOn} '
                                    'cleanups)',
                          style: context.text.bodySmall,
                        ),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 22),
                Row(
                  children: [
                    if (!widget.isNew)
                      TextButton.icon(
                        onPressed: _delete,
                        icon: const Icon(Icons.delete_outline_rounded),
                        label: const Text('Delete'),
                        style: TextButton.styleFrom(
                          foregroundColor: context.colors.danger,
                        ),
                      ),
                    const Spacer(),
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Cancel'),
                    ),
                    const SizedBox(width: 8),
                    FilledButton(
                      onPressed: () => _save(rooms),
                      child: const Text('Save'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A robot setting the preset applies, or "Keep current".
class _SettingField extends ConsumerWidget {
  const _SettingField({
    required this.capability,
    required this.title,
    required this.icon,
    required this.value,
    required this.onChanged,
    this.unsetLabel = 'Keep current',
  });

  final String capability;
  final String title;
  final IconData icon;
  final String? value;
  final ValueChanged<String?> onChanged;
  final String unsetLabel;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final options = ref.watch(presetsProvider(capability)).value ?? const [];
    return DropdownButtonFormField<String?>(
      initialValue: options.contains(value) ? value : null,
      decoration: InputDecoration(labelText: title, prefixIcon: Icon(icon)),
      items: [
        DropdownMenuItem(value: null, child: Text(unsetLabel)),
        for (final o in options)
          DropdownMenuItem(value: o, child: Text(presetLabel(o))),
      ],
      onChanged: onChanged,
    );
  }
}

void openPresetsPage(BuildContext context) =>
    Navigator.of(context)
        .push(MaterialPageRoute<void>(builder: (_) => const PresetsPage()));

/// All presets: edit, reorder, delete.
class PresetsPage extends ConsumerWidget {
  const PresetsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final presets = ref.watch(cleanupPresetsProvider);
    final rooms = _rooms(ref);
    return ValrovePage(
      title: 'Presets',
      subtitle: 'Saved cleanups for one tap',
      floating: FilledButton.icon(
        onPressed: () => showPresetEditor(context),
        icon: const Icon(Icons.add_rounded),
        label: const Text('New preset'),
      ),
      children: [
        if (presets.isEmpty)
          const EmptyState(
            icon: Icons.bookmarks_rounded,
            title: 'No presets yet',
            message:
                'Save rooms, passes and robot settings as a preset, or select '
                'rooms on the map and tap the bookmark next to "Clean".',
          )
        else ...[
          ValroveCard(
            child: ReorderableListView(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              buildDefaultDragHandles: false,
              onReorderItem: (from, to) =>
                  ref.read(cleanupPresetsProvider.notifier).move(from, to),
              children: [
                for (var i = 0; i < presets.length; i++)
                  ListTile(
                    key: ValueKey(presets[i].id),
                    onTap: () => showPresetEditor(context, preset: presets[i]),
                    leading: CircleAvatar(
                      radius: 16,
                      backgroundColor: context.scheme.primary,
                      child: const Icon(
                        Icons.play_arrow_rounded,
                        color: Colors.white,
                        size: 20,
                      ),
                    ),
                    title: Text(presets[i].name),
                    subtitle: Text(
                      [
                        presetWhere(presets[i], rooms),
                        if (!presets[i].wholeHome && presets[i].iterations > 1)
                          '×${presets[i].iterations}',
                        for (final s in [
                          presets[i].operationMode,
                          presets[i].fanSpeed,
                          presets[i].waterGrade,
                        ])
                          if (s != null) presetLabel(s),
                      ].join(' · '),
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          tooltip: 'Start',
                          icon: const Icon(Icons.play_circle_outline_rounded),
                          onPressed: () => runCleanupPreset(ref, presets[i]),
                        ),
                        ReorderableDragStartListener(
                          index: i,
                          child: const Padding(
                            padding: EdgeInsets.all(8),
                            child: Icon(Icons.drag_handle_rounded),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Glass(
            radius: 18,
            padding: const EdgeInsets.all(14),
            child: Text(
              'The first $launcherSlots presets appear in the home screen '
              'widget and when you long-press the app icon. The quick '
              'settings tile starts the first one.',
              style: context.text.bodySmall,
            ),
          ),
        ],
      ],
    );
  }
}

/// Explains that a preset runs as several cleanups.
class _StepsNote extends StatelessWidget {
  const _StepsNote({required this.steps});

  final List<String> steps;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: context.scheme.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Runs as ${steps.length} cleanups in a row',
            style: context.text.titleSmall,
          ),
          const SizedBox(height: 4),
          for (var i = 0; i < steps.length; i++)
            Text('${i + 1}. ${steps[i]}', style: context.text.bodySmall),
          const SizedBox(height: 6),
          Text(
            'Each step starts when the robot finished the one before. Valrove '
            'has to see that: on Android its cleaning notifications do it in '
            'the background, otherwise keep the app open.',
            style: context.text.bodySmall,
          ),
        ],
      ),
    );
  }
}

/// Mode, suction and water for one room of a preset.
class _RoomSettingsSheet extends ConsumerStatefulWidget {
  const _RoomSettingsSheet({required this.name, this.initial});

  final String name;
  final RoomSettings? initial;

  @override
  ConsumerState<_RoomSettingsSheet> createState() => _RoomSettingsSheetState();
}

class _RoomSettingsSheetState extends ConsumerState<_RoomSettingsSheet> {
  late String? _mode = widget.initial?.operationMode;
  late String? _fan = widget.initial?.fanSpeed;
  late String? _water = widget.initial?.waterGrade;

  @override
  Widget build(BuildContext context) {
    final caps = ref.watch(capsProvider);
    final values = {
      PresetType.operationMode: _mode,
      PresetType.fanSpeed: _fan,
      PresetType.waterGrade: _water,
    };
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SheetHeader(
            title: widget.name,
            subtitle:
                'Settings for this room only. Rooms with other '
                'settings than the ones next to them are cleaned in a '
                'separate step.',
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final (cap, type, title, icon) in presetCapabilities)
                  if (caps.has(cap))
                    Padding(
                      padding: const EdgeInsets.only(bottom: 14),
                      child: _SettingField(
                        capability: cap,
                        title: title,
                        icon: icon,
                        value: values[type],
                        unsetLabel: 'Same as the preset',
                        onChanged: (v) => setState(() {
                          switch (type) {
                            case PresetType.operationMode:
                              _mode = v;
                            case PresetType.fanSpeed:
                              _fan = v;
                            default:
                              _water = v;
                          }
                        }),
                      ),
                    ),
                Row(
                  children: [
                    TextButton(
                      onPressed: () =>
                          Navigator.pop(context, const RoomSettings()),
                      child: const Text('Reset'),
                    ),
                    const Spacer(),
                    FilledButton(
                      onPressed: () => Navigator.pop(
                        context,
                        RoomSettings(
                          operationMode: _mode,
                          fanSpeed: _fan,
                          waterGrade: _water,
                        ),
                      ),
                      child: const Text('Done'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
