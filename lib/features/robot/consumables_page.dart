import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/help_texts.dart';
import '../../core/util/format.dart';
import '../../core/valetudo/models/models.dart';
import '../../state/commands.dart';
import '../../state/data.dart';
import '../../ui/dialogs.dart';
import '../../ui/theme.dart';
import '../../ui/widgets.dart';

import 'package:intl/intl.dart';

import '../../state/cleanup.dart';
import '../cleanup/cleanup_extras.dart' show forecastLabel;

class ConsumablesPage extends ConsumerWidget {
  const ConsumablesPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final props = ref.watch(consumablePropertiesProvider);
    final states = ref.watch(consumablesProvider);
    return ValrovePage(
      title: 'Consumables',
      subtitle: 'Monitor and reset consumable states',
      onRefresh: () async {
        ref.invalidate(consumablePropertiesProvider);
        ref.invalidate(consumablesProvider);
        await ref.read(consumablesProvider.future);
      },
      actions: [
        IconButton(
          tooltip: 'Help',
          icon: const Icon(Icons.help_outline_rounded),
          onPressed: () => showMarkdownSheet(
            context,
            title: 'Consumables',
            markdown: HelpTexts.consumablesHelp,
          ),
        ),
      ],
      children: [
        if (props.hasValue && states.hasValue)
          for (final meta in props.value!) ...[
            _ConsumableCard(
              meta: meta,
              state: states.value!
                  .where(
                    (s) => s.type == meta.type && s.subType == meta.subType,
                  )
                  .firstOrNull,
            ),
            const SizedBox(height: 12),
          ]
        else if (props.hasError || states.hasError)
          ErrorState(
            message: describeError(props.error ?? states.error!),
            onRetry: () {
              ref.invalidate(consumablePropertiesProvider);
              ref.invalidate(consumablesProvider);
            },
          )
        else ...[
          const SkeletonCard(rows: 2),
          const SizedBox(height: 12),
          const SkeletonCard(rows: 2),
        ],
      ],
    );
  }
}

class _ConsumableCard extends ConsumerStatefulWidget {
  const _ConsumableCard({required this.meta, required this.state});

  final ConsumableMeta meta;
  final ConsumableState? state;

  @override
  ConsumerState<_ConsumableCard> createState() => _ConsumableCardState();
}

class _ConsumableCardState extends ConsumerState<_ConsumableCard> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final meta = widget.meta;
    final state = widget.state;
    final c = context.colors;
    final name = consumableName(meta.type, meta.subType);
    final depleted = state != null && state.value <= 0;

    double? fraction;
    if (state != null) {
      if (meta.unit == 'percent') {
        fraction = state.value / 100;
      } else if (meta.maxValue != null && meta.maxValue! > 0) {
        fraction = state.value / meta.maxValue!;
      }
      fraction = fraction?.clamp(0, 1);
    }
    final color = fraction == null
        ? context.scheme.primary
        : (fraction > 0.5
              ? c.success
              : (fraction > 0.2 ? c.warning : c.danger));

    String remaining;
    if (state == null) {
      remaining = 'No data';
    } else if (depleted) {
      remaining = 'Depleted';
    } else if (state.unit == 'minutes') {
      remaining =
          'Remaining: ${secondsToHuman(state.value * 60, showSeconds: false)}';
    } else {
      remaining = 'Remaining: ${state.value.round()} %';
    }
    final left = state == null || depleted
        ? null
        : ref
              .watch(consumableForecastsProvider)
              .value
              ?.remaining(
                state.key,
                cleaningMinutesPerDay: ref.watch(cleaningMinutesPerDayProvider),
              );

    return ValroveCard(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          SizedBox.square(
            dimension: 58,
            child: TweenAnimationBuilder<double>(
              tween: Tween(end: fraction ?? 0),
              duration: const Duration(milliseconds: 900),
              curve: Curves.easeOutCubic,
              builder: (context, v, _) => CustomPaint(
                painter: _RingPainter(
                  v,
                  color,
                  c.textPrimary.withValues(alpha: 0.08),
                ),
                child: Center(
                  child: Text(
                    fraction == null ? '–' : '${(fraction * 100).round()}%',
                    style: context.text.labelMedium?.copyWith(
                      color: c.textPrimary,
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name, style: context.text.titleMedium),
                const SizedBox(height: 4),
                Text(
                  remaining,
                  style: context.text.bodyMedium?.copyWith(
                    color: depleted ? c.danger : c.textSecondary,
                  ),
                ),
                if (left != null)
                  Text(
                    '${forecastLabel(left)} · around '
                    '${DateFormat('d MMM').format(DateTime.now().add(left))}',
                    style: context.text.bodySmall?.copyWith(
                      color: left <= const Duration(days: 7)
                          ? c.warning
                          : c.textTertiary,
                    ),
                  ),
              ],
            ),
          ),
          FilledButton.tonal(
            style: FilledButton.styleFrom(
              minimumSize: const Size(64, 40),
              backgroundColor: (depleted ? c.warning : context.scheme.primary)
                  .withValues(alpha: 0.14),
              foregroundColor: depleted ? c.warning : context.scheme.primary,
            ),
            onPressed: _busy
                ? null
                : () async {
                    final ok = await showConfirm(
                      context,
                      title: 'Reset consumable?',
                      message:
                          'Do you really want to reset the $name consumable?',
                      confirmLabel: 'Reset',
                    );
                    if (!ok) return;
                    setState(() => _busy = true);
                    await ref
                        .read(commandsProvider)
                        .run(
                          'reset the consumable',
                          (c) => c.resetConsumable(meta.type, meta.subType),
                          invalidate: [consumablesProvider],
                          success: '$name reset',
                        );
                    if (mounted) setState(() => _busy = false);
                  },
            child: _busy
                ? const SizedBox.square(
                    dimension: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Reset'),
          ),
        ],
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter(this.value, this.color, this.track);

  final double value;
  final Color color;
  final Color track;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = (Offset.zero & size).deflate(4);
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(rect, 0, 2 * math.pi, false, stroke..color = track);
    if (value > 0) {
      canvas.drawArc(
        rect,
        -math.pi / 2,
        2 * math.pi * value,
        false,
        stroke..color = color,
      );
    }
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.value != value || old.color != color;
}
