import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/util/format.dart';
import '../../core/valetudo/capabilities.dart';
import '../../core/valetudo/models/models.dart';
import '../../map/map_controller.dart';
import '../../state/commands.dart';
import '../../state/data.dart';
import '../../state/session.dart';
import '../../ui/dialogs.dart';
import '../../ui/glass.dart';
import '../../ui/theme.dart';
import '../../ui/widgets.dart';
import '../cleanup/history_page.dart';
import '../cleanup/presets_ui.dart';
import '../navigation.dart';
import 'dock_panel.dart';
import 'presets.dart';

/// Height of the collapsed sheet content (without the bottom safe area).
const double sheetPeekHeight = 166;

/// Draggable control center at the bottom of the home screen.
class ControlSheet extends ConsumerWidget {
  const ControlSheet({
    super.key,
    required this.controller,
    required this.mapController,
    required this.accent,
    required this.peekFraction,
  });

  final DraggableScrollableController controller;
  final MapController mapController;
  final Color accent;
  final double peekFraction;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final caps = ref.watch(capsProvider);
    final mid = (peekFraction + 0.3).clamp(peekFraction + 0.05, 0.9);
    return DraggableScrollableSheet(
      controller: controller,
      initialChildSize: peekFraction,
      minChildSize: peekFraction,
      maxChildSize: 0.94,
      snap: true,
      snapSizes: [mid],
      builder: (context, scroll) {
        return Glass(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
          tint: accent,
          child: ListView(
            controller: scroll,
            padding: EdgeInsets.fromLTRB(
              16,
              0,
              16,
              MediaQuery.paddingOf(context).bottom + 24,
            ),
            physics: const ClampingScrollPhysics(),
            children: [
              const _Handle(),
              _StatusHeader(accent: accent),
              const SizedBox(height: 14),
              if (caps.has(Cap.basicControl))
                _BasicControls(mapController: mapController, accent: accent),
              const _DelayedStartBanner(),
              // Keeps the next section out of the collapsed sheet, also below
              // the system gesture area.
              SizedBox(height: 20 + MediaQuery.paddingOf(context).bottom),
              if (caps.hasAny([Cap.basicControl, Cap.mapSegmentation]))
                Padding(
                  padding: const EdgeInsets.only(bottom: 18),
                  child: PresetsStrip(accent: accent),
                ),
              for (final (cap, type, title, icon) in presetCapabilities)
                if (caps.has(cap))
                  Padding(
                    padding: const EdgeInsets.only(bottom: 18),
                    child: PresetSelector(
                      capability: cap,
                      type: type,
                      title: title,
                      icon: icon,
                      accent: accent,
                    ),
                  ),
              if (hasDockControls(caps)) ...[
                _SheetCard(child: DockPanel(accent: accent)),
                const SizedBox(height: 12),
              ],
              const _AttachmentsCard(),
              if (caps.has(Cap.currentStatistics)) ...[
                const _CurrentStatsCard(),
                const SizedBox(height: 12),
              ],
              _QuickLinks(accent: accent),
            ],
          ),
        );
      },
    );
  }
}

class _Handle extends StatelessWidget {
  const _Handle();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        margin: const EdgeInsets.only(top: 10, bottom: 12),
        width: 40,
        height: 5,
        decoration: BoxDecoration(
          color: context.colors.textTertiary.withValues(alpha: 0.45),
          borderRadius: BorderRadius.circular(3),
        ),
      ),
    );
  }
}

class _SheetCard extends StatelessWidget {
  const _SheetCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.colors.textPrimary.withValues(
          alpha: context.isDark ? 0.045 : 0.035,
        ),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: context.colors.tileBorder),
      ),
      child: child,
    );
  }
}

class _StatusHeader extends ConsumerWidget {
  const _StatusHeader({required this.accent});

  final Color accent;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final live = ref.watch(liveStateProvider);
    final state = live.value;
    final c = context.colors;
    if (state == null) {
      return Row(
        children: [
          Expanded(child: Skeleton(height: 24, width: 160)),
          const SizedBox(width: 12),
          const Skeleton(height: 18, width: 60),
        ],
      );
    }
    final status = state.status;
    final flag = flagLabel(status.flag);
    final active = const {
      RobotStatus.cleaning,
      RobotStatus.returning,
      RobotStatus.moving,
      RobotStatus.manualControl,
    }.contains(status.value);
    final battery = state.battery;
    final dock = state.dockStatus;
    String? detail;
    if (status.value == RobotStatus.error) {
      detail = status.error?.message.isNotEmpty == true
          ? status.error!.message
          : 'The robot reported an error';
    } else if (status.value == RobotStatus.docked &&
        dock != null &&
        dock.value != 'idle') {
      detail = 'Dock: ${dockStatusLabel(dock.value)}';
    } else if (battery?.flag == 'charging') {
      detail = 'Charging';
    } else if (battery?.flag == 'charged') {
      detail = 'Fully charged';
    }
    return Row(
      children: [
        Beacon(color: accent, size: 10, active: active),
        const SizedBox(width: 6),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 300),
                transitionBuilder: (child, anim) => FadeTransition(
                  opacity: anim,
                  child: SlideTransition(
                    position: Tween(
                      begin: const Offset(0, 0.3),
                      end: Offset.zero,
                    ).animate(anim),
                    child: child,
                  ),
                ),
                child: Text(
                  flag == null
                      ? statusLabel(status.value)
                      : '${statusLabel(status.value)} · $flag',
                  key: ValueKey('${status.value}${status.flag}'),
                  style: context.text.headlineSmall,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (detail != null)
                Text(
                  detail,
                  style: context.text.bodySmall?.copyWith(
                    color: status.value == RobotStatus.error
                        ? c.danger
                        : c.textSecondary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
            ],
          ),
        ),
        if (battery != null)
          BatteryPill(level: battery.level, flag: battery.flag),
      ],
    );
  }
}

class _BasicControls extends ConsumerStatefulWidget {
  const _BasicControls({required this.mapController, required this.accent});

  final MapController mapController;
  final Color accent;

  @override
  ConsumerState<_BasicControls> createState() => _BasicControlsState();
}

class _BasicControlsState extends ConsumerState<_BasicControls> {
  String? _inFlight;

  Future<void> _send(String action) async {
    if (action == 'start' && widget.mapController.hasPendingAction) {
      final ok = await showConfirm(
        context,
        title: 'Start a full cleanup?',
        message: 'You currently have a pending map action.\n\nHint: you might instead be looking for the button above the control sheet.',
        confirmLabel: 'Start full cleanup',
      );
      if (!ok) return;
    }
    setState(() => _inFlight = action);
    final what = switch (action) {
      'start' => 'start the robot',
      'pause' => 'pause the robot',
      'stop' => 'stop the robot',
      _ => 'send the robot home',
    };
    await ref
        .read(commandsProvider)
        .run(
          what,
          (c) => c.basicControl(action),
          refreshState: true,
          haptic: HapticKind.medium,
        );
    if (mounted) setState(() => _inFlight = null);
  }

  @override
  Widget build(BuildContext context) {
    final status = ref.watch(robotStatusProvider);
    final known = ref.watch(liveStateProvider).hasValue;
    final v = status.value;
    final resumable = status.flag == StatusFlag.resumable;
    final busy = _inFlight != null || !known;
    final startEnabled = const {
      RobotStatus.idle,
      RobotStatus.docked,
      RobotStatus.paused,
      RobotStatus.error,
    }.contains(v);
    final pauseEnabled = const {
      RobotStatus.cleaning,
      RobotStatus.returning,
      RobotStatus.moving,
    }.contains(v);
    final stopEnabled =
        resumable || !const {RobotStatus.idle, RobotStatus.docked}.contains(v);
    final homeEnabled = const {
      RobotStatus.idle,
      RobotStatus.error,
      RobotStatus.paused,
    }.contains(v);

    return Row(
      children: [
        Expanded(
          flex: 5,
          child: _ControlButton(
            icon: Icons.play_arrow_rounded,
            label: resumable ? 'Resume' : 'Start',
            primary: true,
            accent: widget.accent,
            enabled: startEnabled && !busy,
            loading: _inFlight == 'start',
            onTap: () => _send('start'),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          flex: 3,
          child: _ControlButton(
            icon: Icons.pause_rounded,
            label: 'Pause',
            accent: widget.accent,
            enabled: pauseEnabled && !busy,
            loading: _inFlight == 'pause',
            onTap: () => _send('pause'),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          flex: 3,
          child: _ControlButton(
            icon: Icons.stop_rounded,
            label: 'Stop',
            accent: widget.accent,
            enabled: stopEnabled && !busy,
            loading: _inFlight == 'stop',
            onTap: () => _send('stop'),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          flex: 3,
          child: _ControlButton(
            icon: Icons.home_rounded,
            label: 'Dock',
            accent: widget.accent,
            enabled: homeEnabled && !busy,
            loading: _inFlight == 'home',
            onTap: () => _send('home'),
          ),
        ),
      ],
    );
  }
}

class _ControlButton extends StatelessWidget {
  const _ControlButton({
    required this.icon,
    required this.label,
    required this.enabled,
    required this.onTap,
    required this.accent,
    this.primary = false,
    this.loading = false,
  });

  final IconData icon;
  final String label;
  final bool enabled;
  final bool primary;
  final bool loading;
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final fg = primary ? Colors.white : c.textPrimary;
    return Pressable(
      enabled: enabled,
      onTap: onTap,
      semanticLabel: label,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        height: 64,
        decoration: BoxDecoration(
          gradient: primary
              ? LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [accent, Color.lerp(accent, Colors.black, 0.22)!],
                )
              : null,
          color: primary
              ? null
              : c.textPrimary.withValues(alpha: context.isDark ? 0.07 : 0.05),
          borderRadius: BorderRadius.circular(20),
          boxShadow: primary && enabled
              ? [
                  BoxShadow(
                    color: accent.withValues(alpha: 0.4),
                    blurRadius: 18,
                    offset: const Offset(0, 6),
                  ),
                ]
              : null,
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (loading)
              SizedBox.square(
                dimension: 22,
                child: CircularProgressIndicator(strokeWidth: 2.4, color: fg),
              )
            else
              Icon(icon, color: fg, size: primary ? 28 : 24),
            const SizedBox(height: 2),
            Text(label, style: context.text.labelMedium?.copyWith(color: fg)),
          ],
        ),
      ),
    );
  }
}

class _DelayedStartBanner extends ConsumerWidget {
  const _DelayedStartBanner();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final supported = ref.watch(delayedStartSupportedProvider).value ?? false;
    if (!supported) return const SizedBox.shrink();
    final pending = ref.watch(delayedStartProvider).value;
    if (pending == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: _SheetCard(
        child: Row(
          children: [
            Icon(Icons.timer_rounded, color: context.scheme.primary),
            const SizedBox(width: 12),
            Expanded(
              child: StreamBuilder<int>(
                stream: Stream.periodic(const Duration(seconds: 1), (i) => i),
                builder: (context, _) {
                  final left = pending.startsAt.difference(DateTime.now());
                  return Text(
                    left.isNegative
                        ? 'Delayed start is due'
                        : 'Cleanup starts in ${compactDuration(left.inSeconds.toDouble())}',
                    style: context.text.titleSmall,
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
      ),
    );
  }
}

class _AttachmentsCard extends ConsumerWidget {
  const _AttachmentsCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final supported =
        ref.watch(robotInfoProvider).value?.supportedAttachments ?? const [];
    if (supported.isEmpty) return const SizedBox.shrink();
    final attachments = ref.watch(
      robotStateProvider.select((s) => s.attachments),
    );
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: _SheetCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.extension_rounded, size: 18, color: c.textSecondary),
                const SizedBox(width: 8),
                Text('Attachments', style: context.text.titleSmall),
              ],
            ),
            const SizedBox(height: 12),
            if (attachments.isEmpty)
              Text('No attachments found', style: context.text.bodySmall)
            else
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final a in attachments)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: (a.attached ? c.success : c.textTertiary)
                            .withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            a.attached
                                ? Icons.check_circle_rounded
                                : Icons.radio_button_unchecked_rounded,
                            size: 16,
                            color: a.attached ? c.success : c.textTertiary,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            attachmentLabel(a.type),
                            style: context.text.labelMedium?.copyWith(
                              color: c.textPrimary,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            a.attached ? 'Attached' : 'Detached',
                            style: context.text.labelMedium?.copyWith(
                              color: c.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

class _CurrentStatsCard extends ConsumerWidget {
  const _CurrentStatsCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stats = ref.watch(currentStatisticsProvider);
    final c = context.colors;
    return _SheetCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.insights_rounded, size: 18, color: c.textSecondary),
              const SizedBox(width: 8),
              Text('Current cleanup', style: context.text.titleSmall),
            ],
          ),
          const SizedBox(height: 12),
          stats.when(
            skipLoadingOnRefresh: true,
            data: (points) => Row(
              children: [
                for (final p in points)
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          switch (p.type) {
                            'area' => areaFromCm2(p.value, decimals: 2),
                            'time' => compactDuration(p.value),
                            _ => p.value.round().toString(),
                          },
                          style: context.text.headlineSmall?.copyWith(
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                        Text(switch (p.type) {
                          'area' => 'Area',
                          'time' => 'Time',
                          'count' => 'Count',
                          _ => humanize(p.type),
                        }, style: context.text.bodySmall),
                      ],
                    ),
                  ),
              ],
            ),
            loading: () => const Skeleton(height: 44),
            error: (e, _) => Text(
              'Error loading current statistics',
              style: context.text.bodySmall?.copyWith(color: c.danger),
            ),
          ),
        ],
      ),
    );
  }
}

class _QuickLinks extends ConsumerWidget {
  const _QuickLinks({required this.accent});

  final Color accent;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final caps = ref.watch(capsProvider);
    final cameraEnabled =
        caps.has(Cap.duststreaming) &&
        (ref.watch(duststreamingEnabledProvider).value ?? false);
    final links = <(IconData, String, VoidCallback)>[
      if (caps.has(Cap.consumableMonitoring))
        (
          Icons.pending_actions_rounded,
          'Consumables',
          () => openConsumables(context),
        ),
      if (caps.has(Cap.totalStatistics))
        (
          Icons.emoji_events_rounded,
          'Statistics',
          () => openStatistics(context),
        ),
      if (caps.hasAny([Cap.manualControl, Cap.highResolutionManualControl]))
        (
          Icons.sports_esports_rounded,
          'Drive',
          () => openManualControl(context),
        ),
      (Icons.schedule_rounded, 'Schedules', () => openTimers(context)),
      (Icons.history_rounded, 'History', () => openHistory(context)),
      (Icons.bookmarks_rounded, 'Presets', () => openPresetsPage(context)),
      if (hasMapManagement(caps))
        (Icons.map_rounded, 'Map', () => openMapManagement(context)),
      if (cameraEnabled)
        (Icons.videocam_rounded, 'Camera', () => openCamera(context)),
      (Icons.tune_rounded, 'Robot', () => openRobotOptions(context)),
      (Icons.settings_rounded, 'Settings', () => openSettingsHub(context)),
    ];
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: GridView.count(
        crossAxisCount: 4,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
        childAspectRatio: 0.92,
        children: [
          for (final (icon, label, onTap) in links)
            Pressable(
              onTap: onTap,
              semanticLabel: label,
              child: Container(
                decoration: BoxDecoration(
                  color: context.colors.textPrimary.withValues(
                    alpha: context.isDark ? 0.05 : 0.04,
                  ),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: context.colors.tileBorder),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(icon, color: accent, size: 24),
                    const SizedBox(height: 8),
                    Text(
                      label,
                      style: context.text.labelMedium,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
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
