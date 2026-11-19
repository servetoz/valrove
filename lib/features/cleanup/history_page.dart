import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/cleanup/cleanup_record.dart';
import '../../core/cleanup/cleanup_tracker.dart' show joinNames;
import '../../core/util/format.dart';
import '../../map/map_controller.dart';
import '../../map/render/map_painter.dart';
import '../../map/widgets/map_canvas.dart';
import '../../state/app_state.dart';
import '../../state/cleanup.dart';
import '../../state/room_icons.dart';
import '../../state/session.dart';
import '../../ui/dialogs.dart';
import '../../ui/theme.dart';
import '../../ui/widgets.dart';
import 'lost_found_page.dart';
import 'wifi_coverage_page.dart';

void openHistory(BuildContext context) =>
    Navigator.of(context)
        .push(MaterialPageRoute<void>(builder: (_) => const HistoryPage()));

/// Colour of a room by how long ago it was cleaned.
Color freshnessColor(DateTime? last, DateTime now) {
  if (last == null) return const Color(0xFF94A3B8);
  final days = _daysBetween(last, now);
  if (days <= 1) return const Color(0xFF22C55E);
  if (days <= 3) return const Color(0xFFEAB308);
  if (days <= 7) return const Color(0xFFF97316);
  return const Color(0xFFEF4444);
}

/// "today", "1 d", "never".
String freshnessNote(DateTime? last, DateTime now) {
  if (last == null) return 'never';
  final days = _daysBetween(last, now);
  return days == 0 ? 'today' : '$days d';
}

int _daysBetween(DateTime a, DateTime b) {
  final da = DateTime(a.year, a.month, a.day);
  final db = DateTime(b.year, b.month, b.day);
  return db.difference(da).inDays;
}

/// "Kitchen, Hallway", "Whole home", "Zones" …
String recordTitle(CleanupRecord r) => switch (r.kind) {
  CleanupKind.full => 'Whole home',
  CleanupKind.zones =>
    r.rooms.isEmpty
        ? 'Zones'
        : 'Zones in ${joinNames([for (final x in r.rooms) x.name])}',
  CleanupKind.spot => 'Spot',
  CleanupKind.mapping => 'Mapping run',
  _ => r.rooms.isEmpty ? 'Rooms' : joinNames([for (final x in r.rooms) x.name]),
};

IconData recordIcon(CleanupRecord r) => switch (r.kind) {
  CleanupKind.full => Icons.home_rounded,
  CleanupKind.zones => Icons.crop_free_rounded,
  CleanupKind.spot => Icons.adjust_rounded,
  CleanupKind.mapping => Icons.map_rounded,
  _ => Icons.grid_view_rounded,
};

String _recordFacts(CleanupRecord r) => [
  DateFormat.Hm().format(r.startedAt),
  if (r.areaCm2 != null && r.areaCm2! > 0) areaFromCm2(r.areaCm2!),
  compactDuration(r.duration.inSeconds * 1.0),
].join(' · ');

class HistoryPage extends ConsumerWidget {
  const HistoryPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final history = ref.watch(historyProvider);
    return ValrovePage(
      title: 'History',
      subtitle: 'Cleanups recorded on this phone',
      onRefresh: () async => ref.invalidate(historyProvider),
      actions: [
        if (history.value?.isNotEmpty ?? false)
          IconButton(
            tooltip: 'Clear history',
            icon: const Icon(Icons.delete_sweep_rounded),
            onPressed: () async {
              final ok = await showConfirm(
                context,
                title: 'Clear the history?',
                message:
                    'All recorded cleanups of this robot are removed from '
                    'this phone. Estimates start over with typical values.',
                confirmLabel: 'Clear',
                destructive: true,
              );
              final robot = ref.read(activeProfileProvider);
              if (!ok || robot == null) return;
              await (await ref.read(historyStoreProvider.future))
                  .clear(robot.id);
              ref.invalidate(historyProvider);
            },
          ),
      ],
      children: [
        const _FreshnessMap(),
        const SizedBox(height: 12),
        TileGroup(
          children: [
            NavTile(
              title: 'Lost & found',
              subtitle: _foundSubtitle(ref),
              icon: Icons.search_rounded,
              onTap: () => openLostFound(context),
            ),
            NavTile(
              title: 'Wi-Fi coverage',
              subtitle: 'Signal strength around your home',
              icon: Icons.wifi_rounded,
              onTap: () => openWifiCoverage(context),
            ),
          ],
        ),
        ...history.when(
          data: (list) => list.isEmpty
              ? const [
                  EmptyState(
                    icon: Icons.history_rounded,
                    title: 'No cleanups yet',
                    message:
                        'Valrove records the cleanups it sees. With cleaning '
                        'notifications on (Android), it also records them '
                        'while the app is closed.',
                  ),
                ]
              : _list(context, list),
          loading: () => const [SkeletonCard(rows: 4)],
          error: (e, _) => [
            ErrorState(
              title: 'History unavailable',
              message: '$e',
              onRetry: () => ref.invalidate(historyProvider),
            ),
          ],
        ),
      ],
    );
  }

  static String _foundSubtitle(WidgetRef ref) {
    final n = ref.watch(lostFoundProvider).value?.length ?? 0;
    return n == 0
        ? 'Photos of what the robot found on the floor'
        : '$n ${n == 1 ? 'find' : 'finds'} with photos';
  }

  List<Widget> _list(BuildContext context, List<CleanupRecord> list) {
    final now = DateTime.now();
    final week = [
      for (final r in list)
        if (now.difference(r.startedAt) < const Duration(days: 7)) r,
    ];
    final weekArea = week.fold(0.0, (s, r) => s + (r.areaCm2 ?? 0));
    final weekTime = week.fold(0, (s, r) => s + r.duration.inSeconds);
    final groups = <String, List<CleanupRecord>>{};
    for (final r in list) {
      final days = _daysBetween(r.startedAt, now);
      final label = switch (days) {
        0 => 'Today',
        1 => 'Yesterday',
        _ => DateFormat('EEEE, d MMMM').format(r.startedAt),
      };
      (groups[label] ??= []).add(r);
    }
    return [
      const SizedBox(height: 12),
      ValroveCard(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            _Stat('${week.length}', week.length == 1 ? 'cleanup' : 'cleanups'),
            _Stat(areaFromCm2(weekArea, decimals: 0), 'cleaned'),
            _Stat(compactDuration(weekTime * 1.0), 'cleaning'),
          ],
        ),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(6, 6, 6, 0),
        child: Text('Last 7 days', style: context.text.bodySmall),
      ),
      for (final MapEntry(key: label, value: records) in groups.entries) ...[
        SectionLabel(label),
        TileGroup(
          children: [
            for (final r in records)
              ValroveTile(
                title: recordTitle(r),
                subtitle: _recordFacts(r),
                icon: recordIcon(r),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (r.outcome != CleanupOutcome.finished)
                      _OutcomeBadge(r.outcome),
                    const Icon(Icons.chevron_right_rounded),
                  ],
                ),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => CleanupDetailPage(record: r),
                  ),
                ),
              ),
          ],
        ),
      ],
    ];
  }
}

class _Stat extends StatelessWidget {
  const _Stat(this.value, this.label);

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) => Expanded(
    child: Column(
      children: [
        Text(value, style: context.text.titleLarge),
        Text(label, style: context.text.bodySmall),
      ],
    ),
  );
}

class _OutcomeBadge extends StatelessWidget {
  const _OutcomeBadge(this.outcome);

  final String outcome;

  @override
  Widget build(BuildContext context) {
    final error = outcome == CleanupOutcome.error;
    final color = error ? context.colors.danger : context.colors.warning;
    return Container(
      margin: const EdgeInsets.only(right: 6),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        error ? 'Error' : 'Stopped',
        style: context.text.labelSmall?.copyWith(color: color),
      ),
    );
  }
}

/// A small read-only map of the live map's rooms.
class MiniMap extends ConsumerStatefulWidget {
  const MiniMap({
    super.key,
    this.roomTints = const {},
    this.roomNotes = const {},
    this.overlayPath,
    this.overlayRects = const [],
    this.markers = const [],
    this.footer,
    this.height = 300,
  });

  final Map<String, Color> roomTints;
  final Map<String, String> roomNotes;
  final Path? overlayPath;
  final List<({Rect rect, Color color})> overlayRects;
  final List<Offset> markers;
  final Widget? footer;
  final double height;

  @override
  ConsumerState<MiniMap> createState() => MiniMapState();
}

class MiniMapState extends ConsumerState<MiniMap> {
  final _map = MapController(mode: MapMode.view);

  @override
  void dispose() {
    _map.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scene = ref.watch(liveMapProvider).scene;
    if (scene == null || !scene.data.hasLayers) return const SizedBox.shrink();
    return ValroveCard(
      child: Column(
        children: [
          SizedBox(
            height: widget.height,
            child: IgnorePointer(
              child: ClipRRect(
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(22),
                ),
                child: MapCanvas(
                  scene: scene,
                  controller: _map,
                  style: MapStyle.of(
                    dark: ref.watch(isDarkProvider),
                    accent: context.scheme.primary,
                    background: context.colors.tile,
                  ),
                  roomIcons: ref.watch(roomIconsProvider),
                  roomTints: widget.roomTints,
                  roomNotes: widget.roomNotes,
                  overlayPath: widget.overlayPath,
                  overlayRects: widget.overlayRects,
                  markers: widget.markers,
                  showLivePath: false,
                  alwaysShowLabels: true,
                  insets: const EdgeInsets.all(14),
                ),
              ),
            ),
          ),
          ?widget.footer,
        ],
      ),
    );
  }
}

/// The map coloured by when each room was cleaned last.
class _FreshnessMap extends ConsumerWidget {
  const _FreshnessMap();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final segments = ref.watch(
      liveMapProvider.select((s) => s.scene?.data.segments),
    );
    if (segments == null || segments.isEmpty) return const SizedBox.shrink();
    final last = ref.watch(lastCleanedProvider);
    final now = DateTime.now();
    return MiniMap(
      roomTints: {
        for (final s in segments)
          s.id: freshnessColor(last[s.id], now).withValues(alpha: 0.5),
      },
      roomNotes: {
        for (final s in segments) s.id: freshnessNote(last[s.id], now),
      },
      footer: Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
        child: Wrap(
          spacing: 14,
          runSpacing: 6,
          children: [
            for (final (days, label) in [
              (0, 'Last day'),
              (3, '2–3 days'),
              (6, '4–7 days'),
              (30, 'Longer'),
              (null, 'Not yet'),
            ])
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: freshnessColor(
                        days == null
                            ? null
                            : now.subtract(Duration(days: days)),
                        now,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(label, style: context.text.bodySmall),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

/// One recorded cleanup.
class CleanupDetailPage extends ConsumerStatefulWidget {
  const CleanupDetailPage({super.key, required this.record});

  final CleanupRecord record;

  @override
  ConsumerState<CleanupDetailPage> createState() => _CleanupDetailPageState();
}

class _CleanupDetailPageState extends ConsumerState<CleanupDetailPage> {
  late final Path? _path = _pathOf(widget.record);

  static Path? _pathOf(CleanupRecord r) {
    if (r.path.length < 4) return null;
    final ps = r.pixelSize.toDouble();
    final path = Path()..moveTo(r.path[0] / ps, r.path[1] / ps);
    for (var i = 2; i + 1 < r.path.length; i += 2) {
      path.lineTo(r.path[i] / ps, r.path[i + 1] / ps);
    }
    return path;
  }

  Future<void> _delete() async {
    final r = widget.record;
    final ok = await showConfirm(
      context,
      title: 'Delete this cleanup?',
      confirmLabel: 'Delete',
      destructive: true,
    );
    if (!ok) return;
    await (await ref.read(historyStoreProvider.future)).delete(r.robotId, r.id);
    ref.invalidate(historyProvider);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.record;
    final day = DateFormat('EEEE, d MMMM').format(r.startedAt);
    final time =
        '${DateFormat.Hm().format(r.startedAt)}–'
        '${DateFormat.Hm().format(r.endedAt)}';
    final accent = context.scheme.primary;
    return ValrovePage(
      title: recordTitle(r),
      subtitle: '$day · $time',
      actions: [
        IconButton(
          tooltip: 'Delete',
          icon: const Icon(Icons.delete_outline_rounded),
          onPressed: _delete,
        ),
      ],
      children: [
        MiniMap(
          overlayPath: _path,
          roomTints: {
            for (final room in r.rooms) room.id: accent.withValues(alpha: 0.28),
          },
          footer: _path == null
              ? Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(
                    'No path was recorded for this cleanup.',
                    style: context.text.bodySmall,
                  ),
                )
              : null,
        ),
        const SectionLabel('Details'),
        ValroveCard(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          child: Column(
            children: [
              InfoRow('Result', switch (r.outcome) {
                CleanupOutcome.finished => 'Finished at the dock',
                CleanupOutcome.error => 'Ended with an error',
                _ => 'Stopped',
              }),
              if (r.error != null) InfoRow('Last error', r.error!),
              InfoRow(
                'Cleaning time',
                compactDuration(r.duration.inSeconds * 1.0),
              ),
              if (r.wallTime.inMinutes > r.duration.inMinutes + 1)
                InfoRow(
                  'Start to end',
                  compactDuration(r.wallTime.inSeconds * 1.0),
                ),
              if (r.areaCm2 != null && r.areaCm2! > 0)
                InfoRow('Area cleaned', areaFromCm2(r.areaCm2!)),
              if (r.rooms.isNotEmpty)
                InfoRow(
                  r.rooms.length == 1 ? 'Room' : 'Rooms',
                  [for (final x in r.rooms) x.name].join(', '),
                ),
              if (r.batteryStart != null && r.batteryEnd != null)
                InfoRow(
                  'Battery',
                  '${r.batteryStart}% → ${r.batteryEnd}%'
                      '${r.recharged ? ' (charged in between)' : ''}',
                ),
              if (r.operationMode != null)
                InfoRow('Mode', presetLabel(r.operationMode!)),
              if (r.fanSpeed != null)
                InfoRow('Suction', presetLabel(r.fanSpeed!)),
            ],
          ),
        ),
        if (r.obstacles.isNotEmpty) ...[
          SectionLabel('Obstacles seen (${r.obstacles.length})'),
          ValroveCard(
            padding: const EdgeInsets.all(14),
            child: Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final o in r.obstacles)
                  Chip(
                    avatar: const Icon(Icons.warning_amber_rounded, size: 16),
                    label: Text(o),
                  ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}
