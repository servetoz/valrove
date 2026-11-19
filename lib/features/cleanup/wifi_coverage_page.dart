import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/cleanup/wifi_coverage.dart';
import '../../core/valetudo/capabilities.dart';
import '../../state/app_state.dart';
import '../../state/cleanup.dart';
import '../../state/session.dart';
import '../../ui/dialogs.dart';
import '../../ui/theme.dart';
import '../../ui/widgets.dart';
import 'history_page.dart' show MiniMap;

void openWifiCoverage(BuildContext context) => Navigator.of(context)
    .push(MaterialPageRoute<void>(builder: (_) => const WifiCoveragePage()));

Color signalColor(SignalQuality q) => switch (q) {
  SignalQuality.excellent => const Color(0xFF22C55E),
  SignalQuality.good => const Color(0xFF84CC16),
  SignalQuality.fair => const Color(0xFFEAB308),
  SignalQuality.weak => const Color(0xFFF97316),
  SignalQuality.poor => const Color(0xFFEF4444),
};

/// Where the robot's Wi-Fi is strong or weak, from readings taken during
/// cleanups.
class WifiCoveragePage extends ConsumerWidget {
  const WifiCoveragePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final coverage = ref.watch(wifiCoverageProvider);
    final supported = ref.watch(capsProvider).has(Cap.wifiConfiguration);
    final scene = ref.watch(liveMapProvider).scene;
    final pixelSize = scene?.data.pixelSize ?? 5;
    return ValrovePage(
      title: 'Wi-Fi coverage',
      subtitle: 'Signal strength where the robot has been',
      actions: [
        if (coverage.value?.isEmpty == false)
          IconButton(
            tooltip: 'Clear readings',
            icon: const Icon(Icons.delete_sweep_rounded),
            onPressed: () async {
              final ok = await showConfirm(
                context,
                title: 'Clear the Wi-Fi readings?',
                message:
                    'Useful after moving the router or the robot\'s dock. New '
                    'readings are taken during the next cleanups.',
                confirmLabel: 'Clear',
                destructive: true,
              );
              final robot = ref.read(activeProfileProvider);
              if (!ok || robot == null) return;
              final files = await ref.read(robotFilesProvider.future);
              await WifiCoverageStore(files).clear(robot.id);
              ref.invalidate(wifiCoverageProvider);
            },
          ),
      ],
      children: [
        if (!supported)
          const EmptyState(
            icon: Icons.wifi_off_rounded,
            title: 'Not available',
            message: 'This robot does not report its Wi-Fi signal.',
          )
        else
          ...coverage.when(
            data: (c) => c.isEmpty
                ? const [
                    EmptyState(
                      icon: Icons.wifi_find_rounded,
                      title: 'No readings yet',
                      message:
                          'Valrove measures the robot\'s Wi-Fi signal every few '
                          'seconds while it cleans. After a cleanup or two, '
                          'this map shows where the signal is weak.',
                    ),
                  ]
                : _content(context, ref, c, pixelSize),
            loading: () => const [SkeletonCard(rows: 4)],
            error: (e, _) => [ErrorState(message: '$e')],
          ),
      ],
    );
  }

  List<Widget> _content(
    BuildContext context,
    WidgetRef ref,
    WifiCoverage c,
    int pixelSize,
  ) {
    final ps = pixelSize.toDouble();
    final cell = c.cellCm / ps;
    final weakest = c.weakest!;
    final (wx, wy) = c.centreOf(weakest);
    final data = ref.watch(liveMapProvider).scene?.data;
    final weakRoom = data?.segmentAt(wx / ps, wy / ps);
    final roomName = weakRoom == null
        ? null
        : data!.segment(weakRoom)?.displayName;
    final average = c.average!;
    return [
      MiniMap(
        height: 340,
        overlayRects: [
          for (final cellData in c.cells.values)
            (
              rect: Rect.fromLTWH(
                cellData.x * cell + cell * 0.08,
                cellData.y * cell + cell * 0.08,
                cell * 0.84,
                cell * 0.84,
              ),
              color: signalColor(SignalQuality.of(cellData.average))
                  .withValues(alpha: 0.85),
            ),
        ],
        footer: Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
          child: Wrap(
            spacing: 14,
            runSpacing: 6,
            children: [
              for (final q in SignalQuality.values)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: signalColor(q),
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(q.label, style: context.text.bodySmall),
                  ],
                ),
            ],
          ),
        ),
      ),
      const SectionLabel('Summary'),
      ValroveCard(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        child: Column(
          children: [
            InfoRow(
              'Average',
              '${average.round()} dBm · ${SignalQuality.of(average).label}',
            ),
            InfoRow(
              'Weakest spot',
              '${weakest.average.round()} dBm'
                  '${roomName == null ? '' : ' in $roomName'}',
              valueColor: signalColor(SignalQuality.of(weakest.average)),
            ),
            InfoRow(
              'Readings',
              '${c.cells.values.fold(0, (s, x) => s + x.count)} in '
                  '${c.cells.length} spots',
            ),
          ],
        ),
      ),
      const SizedBox(height: 10),
      Text(
        'Readings are taken while the robot cleans, so only the places it '
        'reaches are measured. Below −72 dBm the connection can get '
        'unreliable; below −80 dBm the robot may lose it.',
        style: context.text.bodySmall,
      ),
    ];
  }
}
