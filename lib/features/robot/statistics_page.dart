import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/util/format.dart';
import '../../core/valetudo/capabilities.dart';
import '../../core/valetudo/models/models.dart';
import '../../state/data.dart';
import '../../state/session.dart';
import '../../ui/dialogs.dart';
import '../../ui/theme.dart';
import '../../ui/widgets.dart';

class Achievement {
  const Achievement(this.threshold, this.title, this.description);

  final double threshold;
  final String title;
  final String description;
}

/// Valetudo's statistics achievements, ascending by threshold.
const achievements = <String, List<Achievement>>{
  'area': [
    Achievement(
      10000,
      'Metric',
      "You've cleaned more than the area of an entire A0 paper",
    ),
    Achievement(
      700000,
      'Breathe',
      "You've cleaned more than the approximate surface area of a human lung",
    ),
    Achievement(
      1620000,
      'Sports',
      "You've cleaned more than an entire volleyball court",
    ),
    Achievement(
      100000000,
      'bcc',
      "You've cleaned more than the whole CCCongress: bcc Berlin Congress Center",
    ),
    Achievement(
      240000000,
      'CCH',
      "You've cleaned more than the whole CCCongress: Congress Center Hamburg (pre 2021)",
    ),
    Achievement(
      360000000,
      'CCH (Again)',
      "You've cleaned more than the whole CCCongress: Congress Center Hamburg (post 2022)",
    ),
    Achievement(
      8192 * 2.54 * 8192 * 2.54,
      'GoldSrc Map',
      "You've cleaned more than the maximum playable area of a full GoldSrc (Half-Life 1) map",
    ),
    Achievement(
      500000000,
      'Leipziger Messe',
      "You've cleaned more than the whole CCCongress: Leipziger Messe",
    ),
    Achievement(
      32768 * 2.54 * 32768 * 2.54,
      'Source Map',
      "You've cleaned more than the maximum playable area of a full Source Engine (Half-Life 2) map",
    ),
    Achievement(25690000000000, 'Saarland', 'Ei jo.'),
  ],
  'time': [
    Achievement(
      3600,
      'An hour',
      'More than an entire hour of continuous cleaning',
    ),
    Achievement(
      86400,
      'A day',
      'More than an entire day of continuous cleaning',
    ),
    Achievement(
      393840,
      'Desolation',
      'More than the time it took the Apollo 11 mission from liftoff to man setting foot on the moon',
    ),
    Achievement(
      604800,
      'A week',
      'More than an entire week of continuous cleaning',
    ),
    Achievement(
      2592000,
      'Subscription',
      'One entire month of continuous cleaning',
    ),
    Achievement(
      1.67e34 * 365.25 * 86400,
      'Proton Decay',
      "50% of all matter in the universe might've already decayed into energy",
    ),
  ],
  'count': [
    Achievement(10, 'Baby steps', 'Your robot has done its first 10 cleanups'),
    Achievement(
      64,
      'Y2K38 Compliant',
      'Enough bits to survive the next extinction event',
    ),
    Achievement(
      256,
      '1 byte',
      'The cleanup count has exceeded the limit of what can be stored in a single byte',
    ),
    Achievement(365, 'Daily Driver', 'One year of daily cleanups'),
    Achievement(512, '1 Block', 'Make sure to align your partitions'),
    Achievement(1000, '1k', '1000 cleanups'),
    Achievement(1024, '2^10', 'The true size of 1k'),
    Achievement(1337, '1337', 'r0b0t v4cuum h4x0r'),
    Achievement(
      6.02214076e23,
      '1 Mole',
      'The SI base unit for "amount of substance"',
    ),
  ],
};

String statName(String type) => switch (type) {
  'time' => 'Time',
  'area' => 'Area',
  'count' => 'Count',
  _ => humanize(type),
};

String formatStat(String type, double value) => switch (type) {
  'area' => areaFromCm2(value, decimals: 2),
  'time' => secondsToHuman(value, showDays: false),
  _ => value.round().toString(),
};

class StatisticsPage extends ConsumerWidget {
  const StatisticsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final caps = ref.watch(capsProvider);
    if (!caps.has(Cap.totalStatistics)) {
      return const ValrovePage(
        title: 'Statistics',
        children: [
          EmptyState(
            icon: Icons.bar_chart_rounded,
            title: 'Not supported',
            message: 'This robot does not support total statistics.',
          ),
        ],
      );
    }
    final stats = ref.watch(totalStatisticsProvider);
    const order = ['time', 'area', 'count'];
    return ValrovePage(
      title: 'Statistics',
      subtitle: 'Lifetime totals and achievements',
      onRefresh: () async => ref.refresh(totalStatisticsProvider.future),
      children: [
        ...stats.when(
          data: (points) {
            final sorted = [...points]
              ..sort((a, b) {
                int r(String t) => order.contains(t) ? order.indexOf(t) : 99;
                return r(a.type).compareTo(r(b.type));
              });
            return [
              for (final p in sorted) ...[
                _StatCard(point: p),
                const SizedBox(height: 12),
              ],
            ];
          },
          loading: () => [const SkeletonCard(rows: 3)],
          error: (e, _) => [
            ErrorState(
              message: 'Error loading statistics',
              onRetry: () => ref.invalidate(totalStatisticsProvider),
            ),
          ],
        ),
      ],
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({required this.point});

  final DataPoint point;

  @override
  Widget build(BuildContext context) {
    final list = achievements[point.type] ?? const <Achievement>[];
    final earned = list.where((a) => point.value >= a.threshold).toList();
    final latest = earned.lastOrNull;
    final next = list.where((a) => point.value < a.threshold).firstOrNull;
    final c = context.colors;
    return ValroveCard(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _Badge(title: latest?.title, achieved: latest != null, size: 64),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Total ${statName(point.type)}',
                      style: context.text.labelSmall,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      formatStat(point.type, point.value),
                      style: context.text.headlineMedium?.copyWith(
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Achievement overview',
                icon: const Icon(Icons.history_rounded),
                onPressed: () => _showOverview(context, point, list),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            latest?.description ?? 'No achievement yet',
            style: context.text.bodyMedium?.copyWith(color: c.textPrimary),
          ),
          if (next != null && next.threshold < 1e15) ...[
            const SizedBox(height: 12),
            ProgressTrack(
              value: point.value / next.threshold,
              color: const Color(0xFFF2B020),
            ),
            const SizedBox(height: 6),
            Text(
              'Next: ${next.title} at ${formatStat(point.type, next.threshold)}',
              style: context.text.bodySmall,
            ),
          ],
        ],
      ),
    );
  }

  void _showOverview(
    BuildContext context,
    DataPoint point,
    List<Achievement> list,
  ) {
    showValroveSheet<void>(
      context,
      builder: (context) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.8,
        maxChildSize: 0.95,
        builder: (context, scroll) => ListView(
          controller: scroll,
          padding: EdgeInsets.fromLTRB(
            16,
            8,
            16,
            24 + MediaQuery.paddingOf(context).bottom,
          ),
          children: [
            SheetHeader(title: '${statName(point.type)} achievements'),
            for (final a in list) ...[
              ValroveCard(
                padding: const EdgeInsets.all(14),
                child: Row(
                  children: [
                    _Badge(
                      title: point.value >= a.threshold ? a.title : '?',
                      achieved: point.value >= a.threshold,
                      size: 52,
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            point.value >= a.threshold ? a.title : 'Locked',
                            style: context.text.titleSmall,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            point.value >= a.threshold
                                ? a.description
                                : 'Not yet achieved',
                            style: context.text.bodySmall,
                          ),
                          if (point.value >= a.threshold) ...[
                            const SizedBox(height: 4),
                            Text(
                              'Achieved at ${formatStat(point.type, a.threshold)}',
                              style: context.text.labelSmall,
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
            ],
          ],
        ),
      ),
    );
  }
}

/// Medal-style achievement badge.
class _Badge extends StatelessWidget {
  const _Badge({
    required this.title,
    required this.achieved,
    required this.size,
  });

  final String? title;
  final bool achieved;
  final double size;

  @override
  Widget build(BuildContext context) {
    final gold = context.isDark
        ? const Color(0xFFF2B020)
        : const Color(0xFFFFB922);
    final seal = context.isDark
        ? const Color(0xFF002173)
        : const Color(0xFF002990);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: achieved
            ? RadialGradient(colors: [seal, const Color(0xFF000B67)])
            : LinearGradient(
                colors: [const Color(0xFF333333), const Color(0xFF191919)],
              ),
        border: Border.all(
          color: achieved ? gold : const Color(0xFF444444),
          width: 3,
        ),
        boxShadow: achieved
            ? [BoxShadow(color: gold.withValues(alpha: 0.35), blurRadius: 14)]
            : null,
      ),
      padding: const EdgeInsets.all(6),
      child: Center(
        child: achieved
            ? FittedBox(
                child: Text(
                  title ?? '',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: AppTheme.fontFamily,
                    fontWeight: FontWeight.w800,
                    color: gold,
                    fontSize: 13,
                  ),
                ),
              )
            : Icon(
                Icons.lock_rounded,
                color: const Color(0xFF666666),
                size: size * 0.38,
              ),
      ),
    );
  }
}
