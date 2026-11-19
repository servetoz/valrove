import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/util/format.dart';
import '../../core/valetudo/capabilities.dart';
import '../../core/valetudo/models/models.dart';
import '../../state/commands.dart';
import '../../state/data.dart';
import '../../state/session.dart';
import '../../ui/glass.dart';
import '../../ui/glyphs.dart';
import '../../ui/theme.dart';
import '../../ui/widgets.dart';

/// Preset capabilities shown on the home sheet, in display order.
const presetCapabilities = [
  (
    Cap.operationModeControl,
    PresetType.operationMode,
    'Mode',
    Icons.tune_rounded,
  ),
  (Cap.fanSpeedControl, PresetType.fanSpeed, 'Suction', Icons.air_rounded),
  (
    Cap.waterUsageControl,
    PresetType.waterGrade,
    'Water',
    Icons.water_drop_rounded,
  ),
];

/// Segmented selector for one preset capability (fan speed, water, mode).
class PresetSelector extends ConsumerStatefulWidget {
  const PresetSelector({
    super.key,
    required this.capability,
    required this.type,
    required this.title,
    required this.icon,
    required this.accent,
  });

  final String capability;
  final String type;
  final String title;
  final IconData icon;
  final Color accent;

  @override
  ConsumerState<PresetSelector> createState() => _PresetSelectorState();
}

class _PresetSelectorState extends ConsumerState<PresetSelector> {
  String? _pending;
  Timer? _revert;

  @override
  void dispose() {
    _revert?.cancel();
    super.dispose();
  }

  Future<void> _select(String value, String? current) async {
    if (value == current || _pending != null) return;
    setState(() => _pending = value);
    _revert?.cancel();
    // Snap back if the robot never reports the new value (web UI: 5 s).
    _revert = Timer(const Duration(seconds: 5), () {
      if (mounted) setState(() => _pending = null);
    });
    final ok = await ref
        .read(commandsProvider)
        .run(
          'change ${widget.title.toLowerCase()}',
          (c) => c.setPreset(widget.capability, value),
          refreshState: true,
          haptic: HapticKind.selection,
        );
    if (!ok && mounted) setState(() => _pending = null);
  }

  @override
  Widget build(BuildContext context) {
    final current = ref.watch(
      robotStateProvider.select((s) => s.preset(widget.type)?.value),
    );
    if (_pending != null && current == _pending) {
      _revert?.cancel();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _pending = null);
      });
    }
    final presets = ref.watch(presetsProvider(widget.capability));
    final shown = _pending ?? current;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(widget.icon, size: 18, color: context.colors.textSecondary),
            const SizedBox(width: 8),
            Text(widget.title, style: context.text.titleSmall),
            const Spacer(),
            if (_pending != null)
              const SizedBox.square(
                dimension: 14,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            else if (current != null)
              Text(
                presetLabel(current),
                style: context.text.labelMedium?.copyWith(
                  color: context.colors.textSecondary,
                ),
              ),
          ],
        ),
        const SizedBox(height: 10),
        presets.when(
          data: (list) => list.isEmpty
              ? Text('No presets reported', style: context.text.bodySmall)
              : _Segments(
                  values: list,
                  selected: shown,
                  type: widget.type,
                  accent: widget.accent,
                  onSelect: (v) => _select(v, current),
                ),
          loading: () => const Skeleton(height: 48, radius: 16),
          error: (e, _) => InlineError(
            'Error loading ${widget.capability}',
            onRetry: () => ref.invalidate(presetsProvider(widget.capability)),
          ),
        ),
      ],
    );
  }
}

class _Segments extends StatelessWidget {
  const _Segments({
    required this.values,
    required this.selected,
    required this.type,
    required this.accent,
    required this.onSelect,
  });

  final List<String> values;
  final String? selected;
  final String type;
  final Color accent;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final isMode = type == PresetType.operationMode;
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: c.textPrimary.withValues(alpha: context.isDark ? 0.06 : 0.045),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          for (final v in values)
            Expanded(
              child: Pressable(
                scale: 0.93,
                haptic: false,
                onTap: () => onSelect(v),
                semanticLabel: presetLabel(v),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 260),
                  curve: Curves.easeOutCubic,
                  height: isMode ? 58 : 48,
                  margin: const EdgeInsets.symmetric(horizontal: 2),
                  decoration: BoxDecoration(
                    color: v == selected
                        ? (context.isDark
                              ? const Color(0xFF242B37)
                              : Colors.white)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: v == selected && !context.isDark
                        ? [
                            BoxShadow(
                              color: c.shadow.withValues(alpha: 0.12),
                              blurRadius: 10,
                              offset: const Offset(0, 3),
                            ),
                          ]
                        : null,
                    border: v == selected
                        ? Border.all(
                            color: accent.withValues(alpha: 0.55),
                            width: 1.2,
                          )
                        : null,
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (isMode)
                        Icon(
                          presetIcon(type, v),
                          size: 18,
                          color: v == selected ? accent : c.textSecondary,
                        )
                      else
                        LevelBars(
                          level: presetLevel(v),
                          color: v == selected ? accent : c.textSecondary,
                          height: 12,
                        ),
                      const SizedBox(height: 4),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 2),
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            presetLabel(v),
                            maxLines: 1,
                            style: context.text.labelSmall?.copyWith(
                              letterSpacing: 0,
                              fontSize: 11.5,
                              color: v == selected
                                  ? c.textPrimary
                                  : c.textSecondary,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
