import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/help_texts.dart';
import '../../core/util/format.dart';
import '../../core/valetudo/capabilities.dart';
import '../../core/valetudo/json_utils.dart';
import '../../core/valetudo/models/models.dart';
import '../../state/commands.dart';
import '../../state/data.dart';
import '../../state/room_icons.dart';
import '../../state/session.dart';
import '../../ui/dialogs.dart';
import '../../ui/theme.dart';
import '../../ui/widgets.dart';

/// Shifts a timer's time (and days, on day rollover) by [offsetMinutes].
/// Positive offsets convert UTC → local east of Greenwich.
ValetudoTimer shiftTimer(ValetudoTimer t, int offsetMinutes) {
  var m = t.hour * 60 + t.minute + offsetMinutes;
  var dow = t.dow;
  if (m >= 1440) {
    dow = dow.map((d) => (d + 1) % 7).toList();
    m -= 1440;
  } else if (m < 0) {
    dow = dow.map((d) => (d + 6) % 7).toList();
    m += 1440;
  }
  return t.copyWith(hour: m ~/ 60, minute: m % 60, dow: dow);
}

int get _localOffset => DateTime.now().timeZoneOffset.inMinutes;

const _dayLabels = {
  1: 'Mon',
  2: 'Tue',
  3: 'Wed',
  4: 'Thu',
  5: 'Fri',
  6: 'Sat',
  0: 'Sun',
};

String actionLabel(String type) => switch (type) {
  TimerActionType.fullCleanup => 'Full cleanup',
  TimerActionType.segmentCleanup => 'Room cleanup',
  _ => humanize(type),
};

class TimersPage extends ConsumerWidget {
  const TimersPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final timers = ref.watch(timersProvider);
    final props = ref.watch(timerPropertiesProvider);
    final delayedSupported =
        ref.watch(delayedStartSupportedProvider).value ?? false;
    return ValrovePage(
      title: 'Schedules',
      subtitle: 'Timers run in UTC on the robot',
      onRefresh: () async {
        ref.invalidate(delayedStartProvider);
        ref.invalidate(timersProvider);
        await ref.read(timersProvider.future);
      },
      actions: [
        IconButton(
          tooltip: 'Help',
          icon: const Icon(Icons.help_outline_rounded),
          onPressed: () => showMarkdownSheet(
            context,
            title: 'Timers',
            markdown: HelpTexts.timersHelp,
          ),
        ),
      ],
      floating: props.hasValue && props.value!.supportedActions.isNotEmpty
          ? FilledButton.icon(
              onPressed: () => _create(context, ref, props.value!),
              icon: const Icon(Icons.add_rounded),
              label: const Text('Add timer'),
            )
          : null,
      children: [
        if (delayedSupported) ...[
          const SectionLabel('Start later', icon: Icons.timer_rounded),
          const _DelayedStartCard(),
        ],
        const SectionLabel('Timers', icon: Icons.schedule_rounded),
        ...timers.when(
          data: (list) => list.isEmpty
              ? [
                  const EmptyState(
                    icon: Icons.event_available_rounded,
                    title: 'No timers yet',
                    message: "You currently don't have any timers configured in Valetudo.",
                  ),
                ]
              : [
                  for (final t in list) ...[
                    _TimerCard(timer: t),
                    const SizedBox(height: 12),
                  ],
                ],
          loading: () => [const SkeletonCard(rows: 2)],
          error: (e, _) => [
            ErrorState(
              message: 'Error loading timers',
              onRetry: () => ref.invalidate(timersProvider),
            ),
          ],
        ),
      ],
    );
  }

  Future<void> _create(
    BuildContext context,
    WidgetRef ref,
    TimerProperties props,
  ) async {
    const template = ValetudoTimer(
      id: '',
      enabled: true,
      label: null,
      dow: [1, 2, 3, 4, 5],
      hour: 6,
      minute: 0,
      action: TimerAction(type: TimerActionType.fullCleanup),
      preActions: [],
    );
    final initial = props.supportedActions.contains(TimerActionType.fullCleanup)
        ? template
        : template.copyWith(
            action: TimerAction(type: props.supportedActions.first),
          );
    final edited = await showTimerEditor(context, initial, props);
    if (edited == null) return;
    await ref
        .read(commandsProvider)
        .run(
          'create the timer',
          (c) => c.createTimer(shiftTimer(edited, -_localOffset)),
          invalidate: [timersProvider],
          success: 'Timer created',
        );
  }
}

class _TimerCard extends ConsumerWidget {
  const _TimerCard({required this.timer});

  final ValetudoTimer timer;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final local = shiftTimer(timer, _localOffset);
    final c = context.colors;
    final name = timer.label?.isNotEmpty == true
        ? '"${timer.label}"'
        : 'this timer';
    final props = ref.watch(timerPropertiesProvider).value;
    return ValroveCard(
      padding: const EdgeInsets.fromLTRB(18, 14, 8, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  timer.label?.isNotEmpty == true ? timer.label! : 'Timer',
                  style: context.text.titleMedium,
                ),
              ),
              Switch(
                value: timer.enabled,
                onChanged: (v) => ref
                    .read(commandsProvider)
                    .run(
                      v ? 'enable the timer' : 'disable the timer',
                      (cl) => cl.updateTimer(timer.copyWith(enabled: v)),
                      invalidate: [timersProvider],
                      haptic: HapticKind.selection,
                    ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                timeOfDay(local.hour, local.minute),
                style: context.text.displaySmall?.copyWith(
                  color: timer.enabled ? c.textPrimary : c.textTertiary,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              const SizedBox(width: 10),
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(
                  '${timeOfDay(timer.hour, timer.minute)} UTC',
                  style: context.text.bodySmall,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              for (final d in const [1, 2, 3, 4, 5, 6, 0])
                Expanded(
                  child: Container(
                    margin: const EdgeInsets.only(right: 4),
                    padding: const EdgeInsets.symmetric(vertical: 5),
                    decoration: BoxDecoration(
                      color: local.dow.contains(d)
                          ? context.scheme.primary.withValues(alpha: 0.14)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      _dayLabels[d]!,
                      style: context.text.labelSmall?.copyWith(
                        letterSpacing: 0,
                        color: local.dow.contains(d)
                            ? context.scheme.primary
                            : c.textTertiary,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Icon(
                timer.action.type == TimerActionType.segmentCleanup
                    ? Icons.grid_view_rounded
                    : Icons.cleaning_services_rounded,
                size: 16,
                color: c.textSecondary,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  [
                    actionLabel(timer.action.type),
                    if (timer.action.type == TimerActionType.segmentCleanup)
                      '${asStringList(timer.action.params['segment_ids']).length} rooms',
                    if (timer.preActions.isNotEmpty)
                      '${timer.preActions.length} ${timer.preActions.length == 1 ? 'pre-action' : 'pre-actions'}',
                  ].join(' · '),
                  style: context.text.bodySmall,
                ),
              ),
              IconButton(
                tooltip: 'Run now',
                icon: Icon(Icons.play_arrow_rounded, color: c.success),
                onPressed: () async {
                  final ok = await showConfirm(
                    context,
                    title: 'Execute timer?',
                    message: 'Do you really want to execute $name right now?',
                    confirmLabel: 'Execute',
                  );
                  if (ok) {
                    await ref
                        .read(commandsProvider)
                        .run(
                          'execute the timer',
                          (cl) => cl.executeTimer(timer.id),
                          refreshState: true,
                          invalidate: [timersProvider],
                        );
                  }
                },
              ),
              IconButton(
                tooltip: 'Edit',
                icon: Icon(Icons.edit_rounded, color: c.warning),
                onPressed: props == null
                    ? null
                    : () async {
                        final edited = await showTimerEditor(
                          context,
                          local,
                          props,
                        );
                        if (edited == null) return;
                        await ref
                            .read(commandsProvider)
                            .run(
                              'save the timer',
                              (cl) => cl.updateTimer(
                                shiftTimer(edited, -_localOffset),
                              ),
                              invalidate: [timersProvider],
                            );
                      },
              ),
              IconButton(
                tooltip: 'Delete',
                icon: Icon(Icons.delete_outline_rounded, color: c.danger),
                onPressed: () async {
                  final ok = await showConfirm(
                    context,
                    title: 'Delete timer?',
                    message: 'Do you really want to delete $name?',
                    confirmLabel: 'Delete',
                    destructive: true,
                  );
                  if (ok) {
                    await ref
                        .read(commandsProvider)
                        .run(
                          'delete the timer',
                          (cl) => cl.deleteTimer(timer.id),
                          invalidate: [timersProvider],
                        );
                  }
                },
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Opens the timer editor; resolves to the edited timer in local time.
Future<ValetudoTimer?> showTimerEditor(
  BuildContext context,
  ValetudoTimer local,
  TimerProperties props,
) {
  return Navigator.of(context).push<ValetudoTimer>(
    MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => _TimerEditor(initial: local, props: props),
    ),
  );
}

class _TimerEditor extends ConsumerStatefulWidget {
  const _TimerEditor({required this.initial, required this.props});

  final ValetudoTimer initial;
  final TimerProperties props;

  @override
  ConsumerState<_TimerEditor> createState() => _TimerEditorState();
}

class _TimerEditorState extends ConsumerState<_TimerEditor> {
  late ValetudoTimer _t = widget.initial;
  late final TextEditingController _label = TextEditingController(
    text: widget.initial.label ?? '',
  );

  @override
  void dispose() {
    _label.dispose();
    super.dispose();
  }

  bool get _valid {
    switch (_t.action.type) {
      case TimerActionType.fullCleanup:
        return true;
      case TimerActionType.segmentCleanup:
        return asStringList(_t.action.params['segment_ids']).isNotEmpty;
      default:
        return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final utcNow = DateTime.now();
    final utc = DateTime(
      utcNow.year,
      utcNow.month,
      utcNow.day,
      _t.hour,
      _t.minute,
    ).toUtc();
    return Scaffold(
      appBar: AppBar(
        title: Text(_t.id.isEmpty ? 'Add timer' : 'Edit timer'),
        leading: IconButton(
          icon: const Icon(Icons.close_rounded),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: FilledButton(
              onPressed: _valid
                  ? () {
                      final label = _label.text.trim();
                      Navigator.pop(
                        context,
                        ValetudoTimer(
                          id: _t.id,
                          enabled: _t.enabled,
                          label: label.isEmpty ? null : label,
                          dow: _t.dow,
                          hour: _t.hour,
                          minute: _t.minute,
                          action: _t.action,
                          preActions: _t.preActions,
                        ),
                      );
                    }
                  : null,
              child: const Text('Save'),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: EdgeInsets.fromLTRB(
          16,
          8,
          16,
          32 + MediaQuery.paddingOf(context).bottom,
        ),
        children: [
          TileGroup(
            children: [
              ToggleTile(
                title: 'Enabled',
                icon: Icons.power_settings_new_rounded,
                value: _t.enabled,
                onChanged: (v) => setState(() => _t = _t.copyWith(enabled: v)),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                child: TextField(
                  controller: _label,
                  maxLength: 24,
                  decoration: const InputDecoration(
                    labelText: 'Custom label',
                    counterText: '',
                  ),
                ),
              ),
            ],
          ),
          const SectionLabel('Schedule'),
          ValroveCard(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                InkWell(
                  borderRadius: BorderRadius.circular(16),
                  onTap: () async {
                    final picked = await showTimePicker(
                      context: context,
                      initialTime: TimeOfDay(hour: _t.hour, minute: _t.minute),
                    );
                    if (picked != null) {
                      setState(
                        () => _t = _t.copyWith(
                          hour: picked.hour,
                          minute: picked.minute,
                        ),
                      );
                    }
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Row(
                      children: [
                        Text(
                          timeOfDay(_t.hour, _t.minute),
                          style: context.text.displayMedium?.copyWith(
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                        const Spacer(),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text('Local time', style: context.text.labelSmall),
                            Text(
                              'UTC ${timeOfDay(utc.hour, utc.minute)}',
                              style: context.text.bodySmall,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final d in const [1, 2, 3, 4, 5, 6, 0])
                      FilterChip(
                        label: Text(_dayLabels[d]!),
                        selected: _t.dow.contains(d),
                        showCheckmark: false,
                        onSelected: (sel) {
                          final next = [..._t.dow];
                          if (sel) {
                            if (!next.contains(d)) next.add(d);
                          } else {
                            if (next.length == 1) {
                              return; // keep at least one day
                            }
                            next.remove(d);
                          }
                          setState(() => _t = _t.copyWith(dow: next));
                        },
                      ),
                  ],
                ),
              ],
            ),
          ),
          if (widget.props.supportedPreActions.isNotEmpty) ...[
            const SectionLabel('Before starting'),
            TileGroup(
              children: [
                for (final type in widget.props.supportedPreActions)
                  _PreActionRow(
                    type: type,
                    current: _t.preActions
                        .where((p) => p.type == type)
                        .firstOrNull,
                    onChanged: (value) {
                      final next = _t.preActions
                          .where((p) => p.type != type)
                          .toList();
                      if (value != null) {
                        next.add(
                          TimerAction(type: type, params: {'value': value}),
                        );
                      }
                      setState(() => _t = _t.copyWith(preActions: next));
                    },
                  ),
              ],
            ),
          ],
          const SectionLabel('Action'),
          ActionEditor(
            supported: widget.props.supportedActions,
            action: _t.action,
            onChanged: (a) => setState(() => _t = _t.copyWith(action: a)),
          ),
          if (!_valid)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text(
                'Select at least one room.',
                style: context.text.bodySmall?.copyWith(color: c.warning),
              ),
            ),
        ],
      ),
    );
  }
}

class _PreActionRow extends ConsumerWidget {
  const _PreActionRow({
    required this.type,
    required this.current,
    required this.onChanged,
  });

  final String type;
  final TimerAction? current;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final (cap, title, icon) = switch (type) {
      TimerPreActionType.fanSpeedControl => (
        Cap.fanSpeedControl,
        'Set suction to',
        Icons.air_rounded,
      ),
      TimerPreActionType.waterUsageControl => (
        Cap.waterUsageControl,
        'Set water to',
        Icons.water_drop_rounded,
      ),
      _ => (Cap.operationModeControl, 'Set mode to', Icons.tune_rounded),
    };
    final presets = ref.watch(presetsProvider(cap));
    final value = current == null
        ? null
        : asStringOrNull(current!.params['value']);
    return ValroveTile(
      title: title,
      icon: icon,
      trailing: presets.when(
        data: (list) => DropdownButton<String?>(
          value: list.contains(value) ? value : null,
          underline: const SizedBox.shrink(),
          borderRadius: BorderRadius.circular(16),
          hint: const Text("Don't change"),
          items: [
            const DropdownMenuItem<String?>(
              value: null,
              child: Text("Don't change"),
            ),
            for (final p in list)
              DropdownMenuItem<String?>(value: p, child: Text(presetLabel(p))),
          ],
          onChanged: onChanged,
        ),
        loading: () => const SizedBox.square(
          dimension: 18,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
        error: (e, _) => Text(
          'Error',
          style: context.text.labelMedium?.copyWith(
            color: context.colors.danger,
          ),
        ),
      ),
    );
  }
}

/// Picks a timer/delayed-start action: full cleanup or ordered room cleanup.
class ActionEditor extends ConsumerWidget {
  const ActionEditor({
    super.key,
    required this.supported,
    required this.action,
    required this.onChanged,
  });

  final List<String> supported;
  final TimerAction action;
  final ValueChanged<TimerAction> onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    return ValroveCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (supported.length > 1)
            SegmentedButton<String>(
              segments: [
                for (final s in supported)
                  ButtonSegment(value: s, label: Text(actionLabel(s))),
              ],
              selected: {action.type},
              showSelectedIcon: false,
              onSelectionChanged: (s) => onChanged(TimerAction(type: s.first)),
            )
          else
            Text(actionLabel(action.type), style: context.text.titleMedium),
          if (!supported.contains(action.type))
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text(
                'The currently configured action does not exist. Please select a different action.',
                style: context.text.bodySmall?.copyWith(color: c.danger),
              ),
            ),
          if (action.type == TimerActionType.segmentCleanup) ...[
            const SizedBox(height: 16),
            _SegmentParams(action: action, onChanged: onChanged),
          ],
        ],
      ),
    );
  }
}

class _SegmentParams extends ConsumerWidget {
  const _SegmentParams({required this.action, required this.onChanged});

  final TimerAction action;
  final ValueChanged<TimerAction> onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final segments = ref.watch(segmentsProvider);
    final props = ref.watch(segmentationPropertiesProvider);
    if (segments.isLoading || props.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (!segments.hasValue || !props.hasValue) {
      return Text(
        'Error loading MapSegmentationCapability',
        style: context.text.bodySmall?.copyWith(color: context.colors.danger),
      );
    }
    final all = segments.value!;
    final p = props.value!;
    final selected = asStringList(action.params['segment_ids']);
    final iterations = asInt(action.params['iterations'], 1);
    final customOrder = asBool(action.params['custom_order']);
    String name(String id) =>
        all.where((s) => s.id == id).firstOrNull?.displayName ??
        'Unnamed segment: $id';
    String? nameOf(String id) => all.where((s) => s.id == id).firstOrNull?.name;
    final choices = ref.watch(roomIconChoicesProvider);

    void update(Map<String, Object?> changes) => onChanged(
      TimerAction(type: action.type, params: {...action.params, ...changes}),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Text('Iterations', style: context.text.titleSmall),
            const Spacer(),
            DropdownButton<int>(
              value: iterations.clamp(
                p.iterationCount.min,
                p.iterationCount.max,
              ),
              underline: const SizedBox.shrink(),
              items: [
                for (
                  var i = p.iterationCount.min;
                  i <= p.iterationCount.max;
                  i++
                )
                  DropdownMenuItem(
                    value: i,
                    child: Text('$i ${i == 1 ? 'iteration' : 'iterations'}'),
                  ),
              ],
              onChanged: (v) => update({'iterations': v}),
            ),
          ],
        ),
        if (p.customOrderSupport)
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            title: Text('Use custom order', style: context.text.titleSmall),
            subtitle: Text(
              'Clean rooms in the order listed below',
              style: context.text.bodySmall,
            ),
            value: customOrder,
            onChanged: (v) => update({'custom_order': v}),
          ),
        const SizedBox(height: 8),
        if (selected.isNotEmpty) ...[
          Text('SELECTED', style: context.text.labelSmall),
          const SizedBox(height: 6),
          ReorderableListView(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            buildDefaultDragHandles: false,
            onReorderItem: (from, to) {
              final next = [...selected];
              next.insert(to, next.removeAt(from));
              update({'segment_ids': next});
            },
            children: [
              for (var i = 0; i < selected.length; i++)
                ListTile(
                  key: ValueKey(selected[i]),
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  leading: CircleAvatar(
                    radius: 13,
                    backgroundColor: context.scheme.primary,
                    child: Text(
                      '${i + 1}',
                      style: const TextStyle(color: Colors.white, fontSize: 12),
                    ),
                  ),
                  title: Row(
                    children: [
                      if (roomKindOf(choices, selected[i], nameOf(selected[i]))
                          case final kind?) ...[
                        Icon(
                          kind.icon,
                          size: 18,
                          color: context.colors.textSecondary,
                        ),
                        const SizedBox(width: 8),
                      ],
                      Expanded(child: Text(name(selected[i]))),
                    ],
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.remove_circle_outline_rounded),
                        onPressed: () => update({
                          'segment_ids': [...selected]..removeAt(i),
                        }),
                      ),
                      ReorderableDragStartListener(
                        index: i,
                        child: const Icon(Icons.drag_handle_rounded),
                      ),
                    ],
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
        ],
        Text('AVAILABLE ROOMS', style: context.text.labelSmall),
        const SizedBox(height: 6),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final s in all.where((s) => !selected.contains(s.id)))
              ActionChip(
                avatar: const Icon(Icons.add_rounded, size: 18),
                label: Text(s.displayName),
                onPressed: () => update({
                  'segment_ids': [...selected, s.id],
                }),
              ),
          ],
        ),
      ],
    );
  }
}

/// Fork feature: schedule a one-off cleanup after a delay.
class _DelayedStartCard extends ConsumerStatefulWidget {
  const _DelayedStartCard();

  @override
  ConsumerState<_DelayedStartCard> createState() => _DelayedStartCardState();
}

class _DelayedStartCardState extends ConsumerState<_DelayedStartCard> {
  Duration _delay = const Duration(minutes: 30);
  TimerAction _action = const TimerAction(type: TimerActionType.fullCleanup);
  bool _busy = false;

  static const _presets = [
    Duration(minutes: 15),
    Duration(minutes: 30),
    Duration(hours: 1),
    Duration(hours: 2),
    Duration(hours: 4),
    Duration(hours: 8),
  ];

  @override
  Widget build(BuildContext context) {
    final pending = ref.watch(delayedStartProvider);
    final caps = ref.watch(capsProvider);
    final supported = [
      if (caps.has(Cap.basicControl)) TimerActionType.fullCleanup,
      if (caps.has(Cap.mapSegmentation)) TimerActionType.segmentCleanup,
    ];
    final p = pending.value;
    if (p != null) {
      return ValroveCard(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            TileIcon(
              Icons.timer_rounded,
              color: context.scheme.primary,
              size: 44,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: StreamBuilder<int>(
                stream: Stream.periodic(const Duration(seconds: 1), (i) => i),
                builder: (context, _) {
                  final left = p.startsAt.difference(DateTime.now());
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        actionLabel(p.action.type),
                        style: context.text.titleMedium,
                      ),
                      Text(
                        left.isNegative
                            ? 'Starting…'
                            : 'Starts in ${compactDuration(left.inSeconds.toDouble())}',
                        style: context.text.bodyMedium,
                      ),
                    ],
                  );
                },
              ),
            ),
            TextButton(
              onPressed: () => ref
                  .read(commandsProvider)
                  .run(
                    'cancel the delayed start',
                    (c) => c.cancelDelayedStart(),
                    invalidate: [delayedStartProvider],
                  ),
              child: const Text('Cancel'),
            ),
          ],
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ValroveCard(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Delay', style: context.text.titleSmall),
              const SizedBox(height: 10),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final d in _presets)
                    ChoiceChip(
                      label: Text(compactDuration(d.inSeconds.toDouble())),
                      selected: _delay == d,
                      showCheckmark: false,
                      onSelected: (_) => setState(() => _delay = d),
                    ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        if (supported.isNotEmpty)
          ActionEditor(
            supported: supported,
            action: _action,
            onChanged: (a) => setState(() => _action = a),
          ),
        const SizedBox(height: 10),
        FilledButton.tonalIcon(
          icon: _busy
              ? const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.timer_rounded),
          label: Text(
            'Schedule in ${compactDuration(_delay.inSeconds.toDouble())}',
          ),
          onPressed:
              _busy ||
                  (_action.type == TimerActionType.segmentCleanup &&
                      asStringList(_action.params['segment_ids']).isEmpty)
              ? null
              : () async {
                  setState(() => _busy = true);
                  await ref
                      .read(commandsProvider)
                      .run(
                        'schedule the delayed start',
                        (c) => c.scheduleDelayedStart(
                          delaySeconds: _delay.inSeconds,
                          action: _action,
                        ),
                        invalidate: [delayedStartProvider],
                        success: 'Cleanup scheduled',
                      );
                  if (mounted) setState(() => _busy = false);
                },
        ),
      ],
    );
  }
}
