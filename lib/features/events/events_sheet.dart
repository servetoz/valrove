import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/util/format.dart';
import '../../core/valetudo/models/models.dart';
import '../../state/commands.dart';
import '../../state/data.dart';
import '../../ui/dialogs.dart';
import '../../ui/theme.dart';
import '../../ui/widgets.dart';

Future<void> showEventsSheet(BuildContext context) {
  return showValroveSheet<void>(
    context,
    builder: (context) => const _EventsSheet(),
  );
}

class _EventsSheet extends ConsumerWidget {
  const _EventsSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final events = ref.watch(eventsProvider);
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.6,
      minChildSize: 0.35,
      maxChildSize: 0.92,
      builder: (context, scroll) => Column(
        children: [
          SheetHeader(
            title: 'Events',
            subtitle: 'Notifications from your robot',
            trailing: IconButton(
              tooltip: 'Refresh',
              onPressed: () => ref.invalidate(eventsProvider),
              icon: events.isLoading
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.refresh_rounded),
            ),
          ),
          Expanded(
            child: events.when(
              skipLoadingOnRefresh: true,
              data: (list) => list.isEmpty
                  ? ListView(
                      controller: scroll,
                      children: const [
                        EmptyState(
                          icon: Icons.notifications_none_rounded,
                          title: 'No events',
                          message: 'Everything is running smoothly.',
                        ),
                      ],
                    )
                  : ListView.separated(
                      controller: scroll,
                      padding: EdgeInsets.fromLTRB(
                        16,
                        4,
                        16,
                        16 + MediaQuery.paddingOf(context).bottom,
                      ),
                      itemCount: list.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 10),
                      itemBuilder: (context, i) => _EventCard(event: list[i]),
                    ),
              loading: () => ListView(
                controller: scroll,
                padding: const EdgeInsets.all(16),
                children: const [SkeletonCard(rows: 3)],
              ),
              error: (e, _) => ListView(
                controller: scroll,
                children: [
                  ErrorState(
                    message: describeError(e),
                    onRetry: () => ref.invalidate(eventsProvider),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _EventCard extends ConsumerStatefulWidget {
  const _EventCard({required this.event});

  final ValetudoEvent event;

  @override
  ConsumerState<_EventCard> createState() => _EventCardState();
}

class _EventCardState extends ConsumerState<_EventCard> {
  bool _busy = false;

  Future<void> _interact(String interaction) async {
    setState(() => _busy = true);
    await ref
        .read(commandsProvider)
        .run(
          'update the event',
          (c) => c.interactWithEvent(widget.event.id, interaction),
          invalidate: [eventsProvider],
        );
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final e = widget.event;
    final c = context.colors;
    final (icon, color, message, actions) = _describe(context, e);
    final processed = e.processed;
    return ValroveCard(
      padding: const EdgeInsets.all(14),
      child: Opacity(
        opacity: processed ? 0.55 : 1,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TileIcon(icon, color: color),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        message,
                        style: context.text.bodyMedium?.copyWith(
                          color: c.textPrimary,
                          decoration: processed
                              ? TextDecoration.lineThrough
                              : null,
                        ),
                      ),
                      if (e.timestamp != null) ...[
                        const SizedBox(height: 4),
                        Tooltip(
                          message: dateTime(e.timestamp!),
                          child: Text(
                            relativeTime(e.timestamp!),
                            style: context.text.bodySmall,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
            if (actions.isNotEmpty) ...[
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  if (_busy)
                    const Padding(
                      padding: EdgeInsets.only(right: 12),
                      child: SizedBox.square(
                        dimension: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                  for (final (label, interaction, tone) in actions) ...[
                    const SizedBox(width: 8),
                    FilledButton.tonal(
                      style: FilledButton.styleFrom(
                        minimumSize: const Size(64, 38),
                        backgroundColor: tone.withValues(alpha: 0.14),
                        foregroundColor: tone,
                      ),
                      onPressed: processed || _busy
                          ? null
                          : () => _interact(interaction),
                      child: Text(label),
                    ),
                  ],
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  (IconData, Color, String, List<(String, String, Color)>) _describe(
    BuildContext context,
    ValetudoEvent e,
  ) {
    final c = context.colors;
    switch (e.className) {
      case 'ConsumableDepletedValetudoEvent':
        if (e.type == null || e.subType == null) {
          return (
            Icons.error_rounded,
            c.danger,
            'Consumable without type/subType depleted',
            const [],
          );
        }
        return (
          Icons.pending_actions_rounded,
          c.warning,
          'The consumable ${consumableName(e.type!, e.subType)} is depleted',
          [('Reset', 'reset', c.warning)],
        );
      case 'ErrorStateValetudoEvent':
        return (
          Icons.report_rounded,
          c.danger,
          'An error occurred: ${e.message ?? 'Unknown error'}',
          [('Dismiss', 'ok', c.danger)],
        );
      case 'PendingMapChangeValetudoEvent':
        return (
          Icons.map_rounded,
          c.info,
          'A map change is pending. Do you want to accept the new map?',
          [('No', 'no', c.danger), ('Yes', 'yes', c.success)],
        );
      case 'DustBinFullValetudoEvent':
        return (
          Icons.delete_rounded,
          c.info,
          'The dust bin is full. Please empty it.',
          [('Dismiss', 'ok', c.info)],
        );
      case 'MopAttachmentReminderValetudoEvent':
        return (
          Icons.water_drop_rounded,
          c.info,
          'The mop is still attached to the robot.',
          [('Dismiss', 'ok', c.info)],
        );
      case 'MissingResourceValetudoEvent':
        return (
          Icons.inventory_2_rounded,
          c.warning,
          e.message ?? 'A resource is missing.',
          [('Dismiss', 'ok', c.warning)],
        );
      case 'ValetudoUpdatedValetudoEvent':
        return (
          Icons.system_update_rounded,
          c.success,
          "Valetudo was successfully updated from '${e.previousVersion ?? 'unknown'}' to '${e.newVersion ?? 'unknown'}'.",
          [('Dismiss', 'ok', c.info)],
        );
      case 'ValetudoRuntimeErrorValetudoEvent':
        return (
          Icons.bug_report_rounded,
          c.danger,
          'Valetudo ran into a problem and reincarnated itself. This should never happen.\n\n${e.description ?? 'Reason: ${e.reason}'}',
          [('Dismiss', 'ok', c.danger)],
        );
      default:
        return (
          Icons.help_rounded,
          c.danger,
          'Unknown event type: ${e.className}',
          const [],
        );
    }
  }
}
