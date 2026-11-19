import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/util/format.dart';
import '../../core/valetudo/capabilities.dart';
import '../../core/valetudo/models/models.dart';
import '../../state/commands.dart';
import '../../state/session.dart';
import '../../ui/glass.dart';
import '../../ui/theme.dart';

bool hasDockControls(Capabilities caps) => caps.hasAny([
  Cap.autoEmptyDockManualTrigger,
  Cap.mopDockCleanManualTrigger,
  Cap.mopDockDryManualTrigger,
]);

/// Dock status, component health and manual dock actions.
class DockPanel extends ConsumerStatefulWidget {
  const DockPanel({super.key, required this.accent});

  final Color accent;

  @override
  ConsumerState<DockPanel> createState() => _DockPanelState();
}

class _DockPanelState extends ConsumerState<DockPanel> {
  bool _busy = false;

  /// Set after wash/dry was tapped; cleared when the dock state changes or
  /// after 25 s (like the web UI).
  bool _feedbackPending = false;
  String? _feedbackFrom;
  Timer? _feedbackTimer;

  @override
  void dispose() {
    _feedbackTimer?.cancel();
    super.dispose();
  }

  Future<void> _run(
    String what,
    String capability,
    String action, {
    bool feedback = false,
  }) async {
    setState(() => _busy = true);
    final dockState = ref.read(robotStateProvider).dockStatus?.value ?? 'idle';
    final ok = await ref
        .read(commandsProvider)
        .run(
          what,
          (c) => c.trigger(capability, action),
          refreshState: feedback,
        );
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (ok && feedback) {
        _feedbackPending = true;
        _feedbackFrom = dockState;
        _feedbackTimer?.cancel();
        _feedbackTimer = Timer(const Duration(seconds: 25), () {
          if (mounted) setState(() => _feedbackPending = false);
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final caps = ref.watch(capsProvider);
    final state = ref.watch(robotStateProvider);
    final info = ref.watch(robotInfoProvider).value;
    final c = context.colors;
    final dock = state.dockStatus?.value ?? 'idle';
    if (_feedbackPending && _feedbackFrom != null && dock != _feedbackFrom) {
      _feedbackPending = false;
      _feedbackTimer?.cancel();
    }
    final docked = state.status.value == RobotStatus.docked;
    final mopAttached = state.attachment('mop')?.attached == true;
    final components = info?.supportedDockComponents ?? const <String>[];

    final buttons = <Widget>[
      if (caps.has(Cap.mopDockCleanManualTrigger))
        _DockButton(
          icon: dock == 'cleaning' ? Icons.stop_rounded : Icons.water_rounded,
          label: dock == 'cleaning' ? 'Stop wash' : 'Wash mops',
          enabled:
              !_feedbackPending &&
              !_busy &&
              const {'idle', 'cleaning', 'pause'}.contains(dock) &&
              docked &&
              mopAttached,
          onTap: () => _run(
            dock == 'cleaning'
                ? 'stop washing the mops'
                : 'start washing the mops',
            Cap.mopDockCleanManualTrigger,
            dock == 'cleaning' ? 'stop' : 'start',
            feedback: true,
          ),
        ),
      if (caps.has(Cap.mopDockDryManualTrigger))
        _DockButton(
          icon: dock == 'drying'
              ? Icons.stop_rounded
              : Icons.wind_power_rounded,
          label: dock == 'drying' ? 'Stop drying' : 'Dry mops',
          enabled:
              !_feedbackPending &&
              !_busy &&
              const {'idle', 'drying', 'pause'}.contains(dock) &&
              docked &&
              mopAttached,
          onTap: () => _run(
            dock == 'drying' ? 'stop drying the mops' : 'start drying the mops',
            Cap.mopDockDryManualTrigger,
            dock == 'drying' ? 'stop' : 'start',
            feedback: true,
          ),
        ),
      if (caps.has(Cap.autoEmptyDockManualTrigger))
        _DockButton(
          icon: Icons.delete_sweep_rounded,
          label: 'Empty bin',
          enabled: !_busy && const {'idle', 'pause'}.contains(dock) && docked,
          onTap: () => _run(
            'empty the dustbin',
            Cap.autoEmptyDockManualTrigger,
            'trigger',
          ),
        ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Icon(Icons.villa_rounded, size: 18, color: c.textSecondary),
            const SizedBox(width: 8),
            Text('Dock', style: context.text.titleSmall),
            const Spacer(),
            if (_feedbackPending || _busy)
              const Padding(
                padding: EdgeInsets.only(right: 8),
                child: SizedBox.square(
                  dimension: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            _StatusChip(
              text: dockStatusLabel(dock),
              color: dock == 'error'
                  ? c.danger
                  : (dock == 'idle' ? c.textTertiary : widget.accent),
            ),
          ],
        ),
        if (components.isNotEmpty) ...[
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final type in const [
                'water_tank_clean',
                'water_tank_dirty',
                'detergent',
                'dustbag',
              ])
                if (components.contains(type))
                  _ComponentChip(
                    type: type,
                    value:
                        state.dockComponents
                            .where((d) => d.type == type)
                            .firstOrNull
                            ?.value ??
                        'unknown',
                  ),
            ],
          ),
        ],
        if (buttons.isNotEmpty) ...[
          const SizedBox(height: 12),
          Row(
            children: [
              for (var i = 0; i < buttons.length; i++) ...[
                if (i > 0) const SizedBox(width: 8),
                Expanded(child: buttons[i]),
              ],
            ],
          ),
          if (!docked)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                'Dock actions are available while the robot is docked.',
                style: context.text.bodySmall,
              ),
            )
          else if ((caps.has(Cap.mopDockCleanManualTrigger) ||
                  caps.has(Cap.mopDockDryManualTrigger)) &&
              !mopAttached)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                'Attach the mop to wash or dry it.',
                style: context.text.bodySmall,
              ),
            ),
        ],
      ],
    );
  }
}

class _DockButton extends StatelessWidget {
  const _DockButton({
    required this.icon,
    required this.label,
    required this.enabled,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Pressable(
      enabled: enabled,
      onTap: onTap,
      child: Container(
        height: 64,
        decoration: BoxDecoration(
          color: c.textPrimary.withValues(alpha: context.isDark ? 0.06 : 0.045),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 20),
            const SizedBox(height: 4),
            Text(
              label,
              style: context.text.labelSmall?.copyWith(
                color: c.textPrimary,
                letterSpacing: 0,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.text, required this.color});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        text,
        style: context.text.labelMedium?.copyWith(color: color),
      ),
    );
  }
}

class _ComponentChip extends StatelessWidget {
  const _ComponentChip({required this.type, required this.value});

  final String type;
  final String value;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final color = switch (value) {
      'ok' => c.success,
      'empty' || 'full' => c.danger,
      'missing' => c.warning,
      _ => const Color(0xFFA78BFA),
    };
    final icon = switch (type) {
      'water_tank_clean' => Icons.water_drop_rounded,
      'water_tank_dirty' => Icons.water_damage_rounded,
      'detergent' => Icons.science_rounded,
      'dustbag' => Icons.shopping_bag_rounded,
      _ => Icons.help_rounded,
    };
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 6, 10, 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: context.isDark ? 0.12 : 0.09),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: color),
          const SizedBox(width: 6),
          Text(
            dockComponentLabel(type),
            style: context.text.labelMedium?.copyWith(color: c.textPrimary),
          ),
          const SizedBox(width: 6),
          Text(
            dockComponentStateLabel(value),
            style: context.text.labelMedium?.copyWith(
              color: color,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
