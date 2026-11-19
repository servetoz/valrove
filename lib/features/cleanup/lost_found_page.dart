import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/cleanup/lost_found.dart';
import '../../core/util/format.dart';
import '../../state/app_state.dart';
import '../../state/cleanup.dart';
import '../../state/session.dart';
import '../../ui/dialogs.dart';
import '../../ui/theme.dart';
import '../../ui/widgets.dart';
import 'history_page.dart' show MiniMap;

void openLostFound(BuildContext context) =>
    Navigator.of(context)
        .push(MaterialPageRoute<void>(builder: (_) => const LostFoundPage()));

/// "today", "yesterday", "Tuesday", "3 Nov".
String foundWhen(DateTime t, {DateTime? now}) {
  final n = now ?? DateTime.now();
  final days = DateTime(
    n.year,
    n.month,
    n.day,
  ).difference(DateTime(t.year, t.month, t.day)).inDays;
  return switch (days) {
    <= 0 => 'today',
    1 => 'yesterday',
    < 7 => DateFormat('EEEE').format(t),
    _ => DateFormat('d MMM').format(t),
  };
}

/// Photos of the obstacles the robot found, kept across cleanups.
class LostFoundPage extends ConsumerWidget {
  const LostFoundPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final found = ref.watch(lostFoundProvider);
    final files = ref.watch(robotFilesProvider).value;
    final robot = ref.watch(activeProfileProvider);
    final store = files == null ? null : LostFoundStore(files);
    return ValrovePage(
      title: 'Lost & found',
      subtitle: 'What the robot spotted on the floor',
      onRefresh: () async => ref.invalidate(lostFoundProvider),
      actions: [
        if (found.value?.isNotEmpty ?? false)
          IconButton(
            tooltip: 'Clear all',
            icon: const Icon(Icons.delete_sweep_rounded),
            onPressed: () async {
              final ok = await showConfirm(
                context,
                title: 'Remove all finds?',
                message: 'The photos are deleted from this phone.',
                confirmLabel: 'Remove',
                destructive: true,
              );
              if (!ok || store == null || robot == null) return;
              await store.clear(robot.id);
              ref.invalidate(lostFoundProvider);
            },
          ),
      ],
      children: [
        ...found.when(
          data: (list) => list.isEmpty
              ? const [
                  EmptyState(
                    icon: Icons.search_rounded,
                    title: 'Nothing found yet',
                    message:
                        'When the robot recognises an obstacle during a '
                        'cleanup (a sock, a cable, toys), Valrove keeps its '
                        'photo here, with the room and the day, long after '
                        'the map has forgotten it.',
                  ),
                ]
              : [
                  GridView.count(
                    crossAxisCount: 2,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    mainAxisSpacing: 10,
                    crossAxisSpacing: 10,
                    childAspectRatio: 0.82,
                    children: [
                      for (final o in list)
                        _FoundCard(
                          item: o,
                          photo: store == null || robot == null || !o.hasPhoto
                              ? null
                              : store.photo(robot.id, o.id),
                          onTap: () => _open(context, ref, o, store),
                        ),
                    ],
                  ),
                ],
          loading: () => const [SkeletonCard(rows: 4)],
          error: (e, _) => [ErrorState(message: '$e')],
        ),
      ],
    );
  }

  void _open(
    BuildContext context,
    WidgetRef ref,
    FoundObstacle o,
    LostFoundStore? store,
  ) {
    final robot = ref.read(activeProfileProvider);
    final ps = ref.read(liveMapProvider).scene?.data.pixelSize ?? 5;
    showValroveSheet<void>(
      context,
      builder: (context) => SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(o.name, style: context.text.headlineSmall),
              const SizedBox(height: 4),
              Text(
                [
                  ?o.roomName,
                  '${foundWhen(o.seenAt)} at '
                      '${timeOfDay(o.seenAt.hour, o.seenAt.minute)}',
                  if (o.label != o.name) o.label.substring(o.name.length + 1),
                ].join(' · '),
                style: context.text.bodyMedium,
              ),
              if (o.hasPhoto && store != null && robot != null) ...[
                const SizedBox(height: 14),
                ClipRRect(
                  borderRadius: BorderRadius.circular(18),
                  child: Image.file(
                    store.photo(robot.id, o.id),
                    fit: BoxFit.contain,
                    errorBuilder: (_, _, _) => const SizedBox.shrink(),
                  ),
                ),
              ],
              const SizedBox(height: 14),
              MiniMap(height: 220, markers: [Offset(o.x / ps, o.y / ps)]),
              const SizedBox(height: 14),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: () async {
                    if (store == null || robot == null) return;
                    await store.delete(robot.id, o.id);
                    ref.invalidate(lostFoundProvider);
                    if (context.mounted) Navigator.pop(context);
                  },
                  icon: const Icon(Icons.check_rounded),
                  label: const Text('Picked it up, remove'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FoundCard extends StatelessWidget {
  const _FoundCard({
    required this.item,
    required this.photo,
    required this.onTap,
  });

  final FoundObstacle item;
  final File? photo;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return ValroveCard(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(22),
              ),
              child: photo == null
                  ? ColoredBox(
                      color: c.textPrimary.withValues(alpha: 0.05),
                      child: Icon(
                        Icons.image_not_supported_outlined,
                        color: c.textTertiary,
                      ),
                    )
                  : Image.file(
                      photo!,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => const SizedBox.shrink(),
                    ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.name,
                  style: context.text.titleSmall,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  [?item.roomName, foundWhen(item.seenAt)].join(' · '),
                  style: context.text.bodySmall,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
