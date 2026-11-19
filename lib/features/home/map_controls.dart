import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/valetudo/capabilities.dart';
import '../../core/valetudo/models/models.dart';
import '../../map/editing/shapes.dart';
import '../../map/map_controller.dart';
import '../../state/cleanup.dart';
import '../../state/commands.dart';
import '../../state/data.dart';
import '../../state/session.dart';
import '../../ui/dialogs.dart';
import '../../ui/glass.dart';
import '../../ui/theme.dart';
import '../cleanup/presets_ui.dart';

/// Live-map modes available for the given capabilities.
List<MapMode> supportedLiveModes(Capabilities caps) => [
  if (caps.has(Cap.mapSegmentation)) MapMode.segments,
  if (caps.has(Cap.zoneCleaning)) MapMode.zones,
  if (caps.has(Cap.goToLocation)) MapMode.goTo,
];

String modeLabel(MapMode mode) => switch (mode) {
  MapMode.segments => 'Rooms',
  MapMode.zones => 'Zones',
  MapMode.goTo => 'Go to',
  _ => 'Map',
};

IconData modeIcon(MapMode mode) => switch (mode) {
  MapMode.segments => Icons.grid_view_rounded,
  MapMode.zones => Icons.crop_free_rounded,
  MapMode.goTo => Icons.place_rounded,
  _ => Icons.map_rounded,
};

/// Glass segmented control with a sliding highlight.
class ModeSwitcher extends StatelessWidget {
  const ModeSwitcher({
    super.key,
    required this.modes,
    required this.current,
    required this.onChanged,
    required this.accent,
  });

  final List<MapMode> modes;
  final MapMode current;
  final ValueChanged<MapMode> onChanged;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final index = modes.indexOf(current).clamp(0, modes.length - 1);
    const itemWidth = 82.0;
    return Glass(
      radius: 22,
      padding: const EdgeInsets.all(4),
      child: SizedBox(
        height: 40,
        width: itemWidth * modes.length,
        child: Stack(
          children: [
            AnimatedPositioned(
              duration: const Duration(milliseconds: 320),
              curve: Curves.easeOutBack,
              left: index * itemWidth,
              top: 0,
              bottom: 0,
              width: itemWidth,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: context.isDark ? 0.22 : 0.16),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: accent.withValues(alpha: 0.35)),
                ),
              ),
            ),
            Positioned.fill(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final mode in modes)
                    SizedBox(
                      width: itemWidth,
                      child: Pressable(
                        scale: 0.92,
                        onTap: () => onChanged(mode),
                        semanticLabel: '${modeLabel(mode)} mode',
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              modeIcon(mode),
                              size: 17,
                              color: mode == current
                                  ? accent
                                  : context.colors.textSecondary,
                            ),
                            const SizedBox(width: 5),
                            Text(
                              modeLabel(mode),
                              style: context.text.labelMedium?.copyWith(
                                color: mode == current
                                    ? context.colors.textPrimary
                                    : context.colors.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
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

/// Contextual actions for the current map mode (clean rooms, zones, go to).
class MapActionPill extends ConsumerStatefulWidget {
  const MapActionPill({
    super.key,
    required this.controller,
    required this.accent,
  });

  final MapController controller;
  final Color accent;

  @override
  ConsumerState<MapActionPill> createState() => _MapActionPillState();
}

class _MapActionPillState extends ConsumerState<MapActionPill> {
  int _iterations = 1;
  bool _busy = false;
  MapMode? _lastMode;

  MapController get _map => widget.controller;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _map,
      builder: (context, _) {
        if (_lastMode != _map.mode) {
          _lastMode = _map.mode;
          _iterations = 1;
        }
        final content = _content(context);
        return AnimatedSwitcher(
          duration: const Duration(milliseconds: 280),
          switchInCurve: Curves.easeOutBack,
          switchOutCurve: Curves.easeIn,
          transitionBuilder: (child, anim) => GlassFadeTransition(
            opacity: anim,
            child: ScaleTransition(
              scale: Tween(begin: 0.92, end: 1.0).animate(anim),
              child: child,
            ),
          ),
          child: content ?? const SizedBox.shrink(key: ValueKey('none')),
        );
      },
    );
  }

  Widget? _content(BuildContext context) {
    final robot = ref.watch(robotStateProvider);
    final canStart = robot.canStartAction;
    switch (_map.mode) {
      case MapMode.segments:
        final n = _map.selectedSegments.length;
        if (n == 0) return null;
        final props = ref.watch(segmentationPropertiesProvider).value;
        return _pill(
          key: 'segments',
          label: 'Clean $n ${n == 1 ? 'room' : 'rooms'}',
          enabled: canStart,
          maxIterations: props?.iterationCount.max ?? 1,
          infoHint: _estimate(robot),
          extra: Tooltip(
            message: 'Save as preset',
            child: _roundButton(
              icon: Icons.bookmark_add_rounded,
              onTap: _busy
                  ? null
                  : () => showPresetEditor(
                      context,
                      rooms: [..._map.selectedSegments],
                      iterations: _iterations,
                    ),
            ),
          ),
          onGo: () => _cleanSegments(props),
          onLongPress: () => _showPayload(
            'To start a cleanup of the currently selected segments with the currently configured parameters via MQTT or REST, simply use this payload.',
            {
              'action': 'start_segment_action',
              'segment_ids': _map.selectedSegments,
              'iterations': _iterations,
              'customOrder': props?.customOrderSupport ?? false,
            },
            coordinatesWarning: false,
          ),
          busyHint: 'Cannot start segment cleaning while the robot is busy',
        );
      case MapMode.zones:
        final props = ref.watch(zonePropertiesProvider).value;
        final n = _map.zones.length;
        final max = props?.zoneCount.max ?? 1;
        return _pill(
          key: 'zones',
          label: n == 0
              ? 'Draw a zone'
              : 'Clean $n ${n == 1 ? 'zone' : 'zones'}',
          enabled: canStart && n > 0,
          maxIterations: props?.iterationCount.max ?? 1,
          onGo: _cleanZones,
          onLongPress: n == 0
              ? null
              : () => _showPayload(
                  'To start a cleanup of the currently drawn zones with the currently configured parameters via MQTT or REST, simply use this payload.',
                  {
                    'action': 'clean',
                    'zones': [
                      for (final z in _map.zones) z.toQuad(_pixelSize).toJson(),
                    ],
                    'iterations': _iterations,
                  },
                  coordinatesWarning: true,
                ),
          leading: _roundButton(
            icon: Icons.add_rounded,
            label: '$n/$max',
            onTap: n >= max || _busy
                ? null
                : () => _map.addShape(ShapeKind.zone),
          ),
          showClear: n > 0,
          busyHint: n > 0
              ? 'Cannot start zone cleaning while the robot is busy'
              : null,
        );
      case MapMode.goTo:
        final target = _map.goToTarget;
        if (target == null) {
          return _hint(
            canStart
                ? 'Tap the map to choose a destination'
                : 'Cannot go to point while the robot is busy',
          );
        }
        return _pill(
          key: 'goto',
          label: 'Go to location',
          icon: Icons.near_me_rounded,
          enabled: canStart,
          maxIterations: 1,
          onGo: _goTo,
          onLongPress: () => _showPayload(
            'To trigger a "Go To" to the currently selected location via MQTT or REST, simply use this payload.',
            {'action': 'goto', 'coordinates': _toCm(target).toJson()},
            coordinatesWarning: true,
          ),
          busyHint: 'Cannot go to point while the robot is busy',
        );
      default:
        return null;
    }
  }

  int get _pixelSize => ref.read(liveMapProvider).scene?.data.pixelSize ?? 5;

  /// "≈ 24 min · 15% battery" for the selected rooms.
  String? _estimate(RobotState robot) {
    final data = ref.watch(liveMapProvider).scene?.data;
    final area = _map.selectedSegments.fold(
      0.0,
      (s, id) => s + (data?.segment(id)?.area ?? 0),
    );
    if (area <= 0) return null;
    final estimate = ref
        .watch(estimatorProvider)
        .estimate(
          roomAreaCm2: area,
          iterations: _iterations,
          operationMode: robot.operationMode?.value,
        );
    final battery = robot.battery?.level;
    return battery != null && estimate.batteryPercent > battery - 10
        ? '${estimate.label} · may recharge midway'
        : estimate.label;
  }

  CmPoint _toCm(Offset world) => toCm(world, _pixelSize);

  Widget _hint(String text) {
    return Glass(
      key: ValueKey(text),
      radius: 20,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
      child: Text(
        text,
        style: context.text.labelMedium?.copyWith(
          color: context.colors.textSecondary,
        ),
      ),
    );
  }

  Widget _roundButton({
    required IconData icon,
    String? label,
    required VoidCallback? onTap,
  }) {
    return Pressable(
      onTap: onTap,
      enabled: onTap != null,
      child: Container(
        height: 44,
        padding: EdgeInsets.symmetric(horizontal: label == null ? 0 : 12),
        constraints: const BoxConstraints(minWidth: 44),
        decoration: BoxDecoration(
          color: context.colors.textPrimary.withValues(alpha: 0.07),
          borderRadius: BorderRadius.circular(22),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 20, color: context.colors.textPrimary),
            if (label != null) ...[
              const SizedBox(width: 4),
              Text(label, style: context.text.labelMedium),
            ],
          ],
        ),
      ),
    );
  }

  Widget _pill({
    required String key,
    required String label,
    required bool enabled,
    required int maxIterations,
    required VoidCallback onGo,
    VoidCallback? onLongPress,
    IconData icon = Icons.play_arrow_rounded,
    Widget? leading,
    Widget? extra,
    bool showClear = true,
    String? busyHint,
    String? infoHint,
  }) {
    final robot = ref.watch(robotStateProvider);
    final blocked = !robot.canStartAction && busyHint != null;
    return Column(
      key: ValueKey(key),
      mainAxisSize: MainAxisSize.min,
      children: [
        if (blocked || infoHint != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Glass(
              radius: 14,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              child: Text(
                blocked ? busyHint : infoHint!,
                style: context.text.labelSmall?.copyWith(letterSpacing: 0.2),
              ),
            ),
          ),
        Glass(
          radius: 30,
          tint: widget.accent,
          padding: const EdgeInsets.all(6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (leading != null) ...[leading, const SizedBox(width: 6)],
              Pressable(
                enabled: enabled && !_busy,
                onTap: onGo,
                onLongPress: onLongPress,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 250),
                  height: 48,
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        widget.accent,
                        Color.lerp(widget.accent, Colors.black, 0.18)!,
                      ],
                    ),
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: [
                      BoxShadow(
                        color: widget.accent.withValues(alpha: 0.45),
                        blurRadius: 18,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (_busy)
                        const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.2,
                            color: Colors.white,
                          ),
                        )
                      else
                        Icon(icon, color: Colors.white),
                      const SizedBox(width: 8),
                      Text(
                        label,
                        style: context.text.labelLarge?.copyWith(
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (extra != null) ...[const SizedBox(width: 6), extra],
              if (maxIterations > 1) ...[
                const SizedBox(width: 6),
                Tooltip(
                  message: 'Iteration count',
                  child: _roundButton(
                    icon: Icons.repeat_rounded,
                    label: '×$_iterations',
                    onTap: () => setState(
                      () => _iterations = _iterations % maxIterations + 1,
                    ),
                  ),
                ),
              ],
              if (showClear) ...[
                const SizedBox(width: 6),
                Tooltip(
                  message: 'Clear',
                  child: _roundButton(
                    icon: Icons.close_rounded,
                    onTap: _busy ? null : _map.clearAll,
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _guard(Future<bool> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final ok = await action();
      if (ok) _map.clearAll();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _cleanSegments(MapSegmentationProperties? props) {
    final ids = _map.selectedSegments;
    _guard(
      () => ref
          .read(commandsProvider)
          .run(
            'start the room cleanup',
            (c) => c.cleanSegments(
              ids,
              iterations: _iterations,
              customOrder: props?.customOrderSupport ?? false,
            ),
            refreshState: true,
            haptic: HapticKind.medium,
          ),
    );
  }

  void _cleanZones() {
    final zones = [for (final z in _map.zones) z.toQuad(_pixelSize)];
    _guard(
      () => ref
          .read(commandsProvider)
          .run(
            'start the zone cleanup',
            (c) => c.cleanZones(zones, iterations: _iterations),
            refreshState: true,
            haptic: HapticKind.medium,
          ),
    );
  }

  void _goTo() {
    final target = _map.goToTarget;
    if (target == null) return;
    _guard(
      () => ref
          .read(commandsProvider)
          .run(
            'send the robot to the location',
            (c) => c.goTo(_toCm(target)),
            refreshState: true,
            haptic: HapticKind.medium,
          ),
    );
  }

  void _showPayload(
    String helper,
    Map<String, Object?> payload, {
    required bool coordinatesWarning,
  }) {
    showIntegrationPayload(
      context,
      helper: helper,
      payload: payload,
      coordinatesWarning: coordinatesWarning,
    );
  }
}

/// "Connect with other applications": shows the JSON payload for MQTT/REST.
Future<void> showIntegrationPayload(
  BuildContext context, {
  required String helper,
  required Map<String, Object?> payload,
  bool coordinatesWarning = false,
}) {
  final json = const JsonEncoder.withIndent('  ').convert(payload);
  return showValroveSheet<void>(
    context,
    builder: (context) => SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(22, 14, 22, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Connect with other applications',
              style: context.text.headlineSmall,
            ),
            const SizedBox(height: 8),
            Text(helper, style: context.text.bodyMedium),
            if (coordinatesWarning) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: context.colors.info.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Row(
                  children: [
                    Icon(Icons.campaign_rounded, color: context.colors.info),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Please note that the coordinates displayed here can become invalid if the underlying map changes.',
                        style: context.text.bodySmall,
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFF0A0D12),
                borderRadius: BorderRadius.circular(16),
              ),
              child: SelectableText(
                json,
                style: const TextStyle(
                  fontFamily: AppTheme.monoFamily,
                  fontSize: 12.5,
                  color: Color(0xFFE6EDF7),
                  height: 1.45,
                ),
              ),
            ),
            const SizedBox(height: 14),
            FilledButton.icon(
              onPressed: () {
                Clipboard.setData(ClipboardData(text: json));
                Navigator.pop(context);
              },
              icon: const Icon(Icons.copy_rounded),
              label: const Text('Copy payload'),
            ),
          ],
        ),
      ),
    ),
  );
}
