import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/util/format.dart';
import '../../core/valetudo/capabilities.dart';
import '../../core/valetudo/models/models.dart';
import '../../map/map_controller.dart';
import '../../map/processing/map_processor.dart';
import '../../map/render/map_painter.dart';
import '../../map/widgets/map_canvas.dart';
import '../../state/app_state.dart';
import '../../state/cleanup.dart';
import '../../state/commands.dart';
import '../../state/data.dart';
import '../../state/room_icons.dart';
import '../../state/session.dart';
import '../../ui/dialogs.dart';
import '../../ui/glass.dart';
import '../../ui/theme.dart';
import '../../ui/widgets.dart';
import '../cleanup/cleanup_watcher.dart';
import '../cleanup/launchers.dart';
import '../cleanup/presets_ui.dart';
import '../donate/donate.dart';
import '../navigation.dart';
import '../voice/voice_sheet.dart';
import '../welcome/welcome_sheet.dart';
import 'control_sheet.dart';
import 'map_controls.dart';
import 'top_bar.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  final _map = MapController(mode: MapMode.view);
  final _sheet = DraggableScrollableController();
  String? _robotId;
  bool _welcomeChecked = false;
  Timer? _donateTimer;

  @override
  void initState() {
    super.initState();
    // Opened from the widget, the quick settings tile or a shortcut.
    ref.listenManual<LaunchAction?>(launchActionsProvider, (_, action) {
      if (action == null) return;
      ref.read(launchActionsProvider.notifier).clear();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        performLaunchAction(
          ref,
          action,
          openPresets: () => openPresetsPage(context),
          runCommand: (text) async {
            // The map knows the room names; give it a moment after a cold
            // start.
            for (
              var i = 0;
              i < 20 && ref.read(liveMapProvider).scene == null;
              i++
            ) {
              await Future<void>.delayed(const Duration(milliseconds: 250));
            }
            await runVoiceCommand(ref, parseForRobot(ref, text));
          },
        );
      });
    }, fireImmediately: true);
  }

  @override
  void dispose() {
    _donateTimer?.cancel();
    _map.dispose();
    _sheet.dispose();
    super.dispose();
  }

  String get _modeKey => 'ui.$_robotId.mapMode';

  /// Restores the map mode for the active robot (or picks the first supported).
  void _syncMode(List<MapMode> modes) {
    if (modes.isEmpty) {
      if (_map.mode != MapMode.view) _map.setMode(MapMode.view);
      return;
    }
    if (modes.contains(_map.mode)) return;
    final saved = ref.read(sharedPreferencesProvider).getString(_modeKey);
    final restored =
        modes.where((m) => m.name == saved).firstOrNull ?? modes.first;
    WidgetsBinding.instance.addPostFrameCallback((_) => _map.setMode(restored));
  }

  void _setMode(MapMode mode) {
    _map.setMode(mode);
    ref.read(sharedPreferencesProvider).setString(_modeKey, mode.name);
  }

  void _maybeShowWelcome() {
    if (_welcomeChecked) return;
    final info = ref.read(valetudoInfoProvider).value;
    if (info == null) return;
    _welcomeChecked = true;
    if (!info.welcomeDialogDismissed) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) showWelcomeSheet(context);
      });
    }
  }

  /// Asks for a donation on the openings [DonatePrompt] picks, once the home
  /// screen has shown a connected robot for a moment with nothing over it.
  void _maybeAskForDonation({required bool online}) {
    final opening = ref.watch(appOpeningsProvider);
    if (!DonatePrompt.due(ref.read(sharedPreferencesProvider), opening)) {
      return;
    }
    // Watched, so the screen rebuilds when one of them changes.
    final ready =
        online &&
        ref.watch(appInForegroundProvider) &&
        (ModalRoute.isCurrentOf(context) ?? false);
    if (!ready) {
      _donateTimer?.cancel();
      _donateTimer = null;
      return;
    }
    _donateTimer ??= Timer(DonatePrompt.delay, () {
      _donateTimer = null;
      final prefs = ref.read(sharedPreferencesProvider);
      // Nothing is rebuilt in the background to cancel the timer.
      if (!mounted ||
          !ref.read(appInForegroundProvider) ||
          !DonatePrompt.due(prefs, opening)) {
        return;
      }
      DonatePrompt.markAsked(prefs, opening);
      showDonatePrompt(context, ref);
    });
  }

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(activeProfileProvider);
    if (profile?.id != _robotId) {
      _robotId = profile?.id;
      _welcomeChecked = false;
      _map.setMode(MapMode.view);
    }
    final caps = ref.watch(capsProvider);
    final modes = supportedLiveModes(caps);
    _syncMode(modes);
    ref.watch(valetudoInfoProvider);
    _maybeShowWelcome();
    ref.watch(cleanupWatcherProvider);
    ref.watch(launcherSyncProvider);

    final health = ref.watch(connectionHealthProvider);
    _maybeAskForDonation(online: health.isOnline);
    final robot = ref.watch(robotStateProvider);
    final known = ref.watch(liveStateProvider).hasValue;
    final accent = StateColors.forState(
      robot,
      online: health.isOnline || !known || health.state == LinkState.connecting,
    );
    final mapState = ref.watch(liveMapProvider);
    final dark = ref.watch(isDarkProvider);
    final segProps = caps.has(Cap.mapSegmentation)
        ? ref.watch(segmentationPropertiesProvider).value
        : null;

    final media = MediaQuery.of(context);
    final height = media.size.height;
    final peekPx = sheetPeekHeight + media.padding.bottom;
    final peekFraction = (peekPx / height).clamp(0.15, 0.6);
    final topInset = media.padding.top + 64;
    final insets = EdgeInsets.only(
      top: topInset + 8,
      bottom: peekPx + 72,
      left: 12,
      right: 12,
    );
    final robotActive = const {
      RobotStatus.cleaning,
      RobotStatus.returning,
      RobotStatus.moving,
      RobotStatus.manualControl,
    }.contains(robot.status.value);

    return Scaffold(
      backgroundColor: context.colors.background,
      body: AmbientBackground(
        accent: accent,
        // All glass on this screen shares one backdrop capture and blur pass.
        child: SharedBackdrop(
          child: Stack(
            children: [
              Positioned.fill(
                child: _MapLayer(
                  state: mapState,
                  controller: _map,
                  style: MapStyle.of(
                    dark: dark,
                    accent: accent,
                    background: context.colors.background,
                  ),
                  insets: insets,
                  robotActive: robotActive,
                  job: robot.job,
                  charging: robot.battery?.flag == 'charging',
                  showSelectionOrder: segProps?.customOrderSupport ?? false,
                  showCleanOrder: false,
                  onObstacleTap: (o) => showObstacleSheet(context, ref, o),
                  onSegmentLongPress: caps.has(Cap.mapSegmentation)
                      ? (s) => showRoomSheet(context, ref, s, _map)
                      : null,
                ),
              ),
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: ProgressiveBlurEdge(
                  height: media.padding.top + 84,
                  color: context.colors.background,
                ),
              ),
              Positioned(
                top: media.padding.top + 8,
                left: 12,
                right: 12,
                child: Column(
                  children: [
                    HomeTopBar(accent: accent),
                    const ConnectionBanner(),
                  ],
                ),
              ),
              // Floating map controls ride on top of the sheet.
              AnimatedBuilder(
                animation: _sheet,
                builder: (context, child) {
                  final size = _sheet.isAttached ? _sheet.size : peekFraction;
                  final sheetTop = size * height;
                  final fade = (1 - (size - peekFraction) / 0.18).clamp(
                    0.0,
                    1.0,
                  );
                  return Positioned(
                    left: 12,
                    right: 12,
                    bottom: sheetTop + 10,
                    child: IgnorePointer(
                      ignoring: fade < 0.5,
                      child: GlassOpacity(opacity: fade, child: child!),
                    ),
                  );
                },
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    MapActionPill(controller: _map, accent: accent),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        if (modes.length > 1)
                          ListenableBuilder(
                            listenable: _map,
                            builder: (context, _) => ModeSwitcher(
                              modes: modes,
                              current: _map.mode,
                              onChanged: _setMode,
                              accent: accent,
                            ),
                          ),
                        const Spacer(),
                        if (mapState.hasMap)
                          GlassIconButton(
                            icon: Icons.center_focus_strong_rounded,
                            tooltip: 'Fit map',
                            onPressed: _map.requestFit,
                            size: 48,
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              ControlSheet(
                controller: _sheet,
                mapController: _map,
                accent: accent,
                peekFraction: peekFraction,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MapLayer extends ConsumerWidget {
  const _MapLayer({
    required this.state,
    required this.controller,
    required this.style,
    required this.insets,
    required this.robotActive,
    required this.job,
    required this.charging,
    required this.showSelectionOrder,
    required this.showCleanOrder,
    required this.onObstacleTap,
    required this.onSegmentLongPress,
  });

  final LiveMapState state;
  final MapController controller;
  final MapStyle style;
  final EdgeInsets insets;
  final bool robotActive;
  final JobState job;
  final bool charging;
  final bool showSelectionOrder;
  final bool showCleanOrder;
  final ValueChanged<MapEntity> onObstacleTap;
  final ValueChanged<SegmentInfo>? onSegmentLongPress;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scene = state.scene;
    Widget child;
    if (scene != null && scene.data.hasLayers) {
      child = MapCanvas(
        key: const ValueKey('map'),
        scene: scene,
        controller: controller,
        style: style,
        robotActive: robotActive,
        job: job,
        roomIcons: ref.watch(roomIconsProvider),
        charging: charging,
        insets: insets,
        showSelectionOrder: showSelectionOrder,
        showCleanOrder: showCleanOrder,
        onObstacleTap: onObstacleTap,
        onSegmentLongPress: onSegmentLongPress,
      );
    } else if (scene != null) {
      child = Padding(
        key: const ValueKey('empty'),
        padding: insets,
        child: const Center(child: NoMapView()),
      );
    } else if (state.error != null) {
      child = Padding(
        key: const ValueKey('error'),
        padding: insets,
        child: Center(
          child: ErrorState(
            title: 'Map unavailable',
            message: 'The map could not be loaded.',
            onRetry: () => ref.read(liveMapProvider.notifier).refresh(),
          ),
        ),
      );
    } else {
      child = Padding(
        key: const ValueKey('loading'),
        padding: insets,
        child: const Center(child: RadarLoader(label: 'Loading map…')),
      );
    }
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 500),
      switchInCurve: Curves.easeOutCubic,
      transitionBuilder: (child, anim) => FadeTransition(
        opacity: anim,
        child: ScaleTransition(
          scale: Tween(begin: 0.96, end: 1.0).animate(anim),
          child: child,
        ),
      ),
      child: child,
    );
  }
}

/// Shown when the robot has no map yet.
class NoMapView extends ConsumerWidget {
  const NoMapView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final caps = ref.watch(capsProvider);
    Widget? action;
    if (caps.has(Cap.mappingPass)) {
      action = FilledButton.icon(
        icon: const Icon(Icons.layers_rounded),
        label: const Text('Start mapping pass'),
        onPressed: () async {
          final ok = await showConfirm(
            context,
            title: 'Start mapping pass?',
            message: 'Do you really want to start a mapping pass?',
            confirmLabel: 'Start',
          );
          if (ok) {
            await ref
                .read(commandsProvider)
                .run(
                  'start the mapping pass',
                  (c) => c.startMappingPass(),
                  refreshState: true,
                );
          }
        },
      );
    } else if (caps.has(Cap.basicControl)) {
      action = FilledButton.icon(
        icon: const Icon(Icons.play_arrow_rounded),
        label: const Text('Start full cleanup'),
        onPressed: () async {
          final ok = await showConfirm(
            context,
            title: 'Start full cleanup?',
            message: "The robot needs to return to the dock on its own to save the newly created map. Do not interfere with the cleanup or else it won't be saved.",
            confirmLabel: 'Start',
          );
          if (ok) {
            await ref
                .read(commandsProvider)
                .run(
                  'start the cleanup',
                  (c) => c.basicControl('start'),
                  refreshState: true,
                );
          }
        },
      );
    }
    return EmptyState(
      icon: Icons.map_outlined,
      title: 'No map yet',
      message: 'Let the robot explore your home to create a map. Make sure doors are open and cables are out of the way.',
      action: action,
    );
  }
}

/// Animated radar sweep used while connecting/loading.
class RadarLoader extends StatefulWidget {
  const RadarLoader({super.key, this.label});

  final String? label;

  @override
  State<RadarLoader> createState() => _RadarLoaderState();
}

class _RadarLoaderState extends State<RadarLoader>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2400),
  )..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final accent = context.scheme.primary;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox.square(
          dimension: 140,
          child: AnimatedBuilder(
            animation: _c,
            builder: (context, _) => CustomPaint(
              painter: _RadarPainter(
                _c.value,
                accent,
                context.colors.textTertiary,
              ),
            ),
          ),
        ),
        if (widget.label != null) ...[
          const SizedBox(height: 18),
          Text(
            widget.label!,
            style: context.text.titleSmall?.copyWith(
              color: context.colors.textSecondary,
            ),
          ),
        ],
      ],
    );
  }
}

class _RadarPainter extends CustomPainter {
  _RadarPainter(this.t, this.color, this.grid);

  final double t;
  final Color color;
  final Color grid;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.width / 2;
    final ring = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = grid.withValues(alpha: 0.25);
    for (var i = 1; i <= 3; i++) {
      canvas.drawCircle(c, r * i / 3, ring);
    }
    final angle = t * 2 * math.pi;
    final sweep = Paint()
      ..shader = SweepGradient(
        startAngle: 0,
        endAngle: 2 * math.pi,
        colors: [color.withValues(alpha: 0), color.withValues(alpha: 0.5)],
        stops: const [0.75, 1],
        transform: GradientRotation(angle - 2 * math.pi),
      ).createShader(Rect.fromCircle(center: c, radius: r));
    canvas.drawCircle(c, r, sweep);
    for (var i = 0; i < 3; i++) {
      final phase = (t + i / 3) % 1;
      canvas.drawCircle(
        c,
        r * phase,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = color.withValues(alpha: (1 - phase) * 0.35),
      );
    }
    canvas.drawCircle(c, 6, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_RadarPainter old) => old.t != t;
}

/// Obstacle details, including the photo if the robot took one.
Future<void> showObstacleSheet(
  BuildContext context,
  WidgetRef ref,
  MapEntity obstacle,
) {
  final caps = ref.read(capsProvider);
  final id = obstacle.id;
  return showValroveSheet<void>(
    context,
    builder: (context) => SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Obstacle', style: context.text.headlineSmall),
            const SizedBox(height: 4),
            Text(
              obstacle.label ?? 'Unlabeled obstacle',
              style: context.text.bodyMedium,
            ),
            if (id != null && caps.has(Cap.obstacleImages)) ...[
              const SizedBox(height: 16),
              ObstacleImage(id: id),
            ],
          ],
        ),
      ),
    ),
  );
}

final _obstacleImageProvider = FutureProvider.autoDispose
    .family<Uint8List, String>((ref, id) async {
      final client = requireClient(ref);
      return Uint8List.fromList(await client.getObstacleImage(id));
    });

class ObstacleImage extends ConsumerWidget {
  const ObstacleImage({super.key, required this.id});

  final String id;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dims =
        ref.watch(obstacleImageDimensionsProvider).value ??
        const ImageDimensions(4, 3);
    final image = ref.watch(_obstacleImageProvider(id));
    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: AspectRatio(
        aspectRatio: dims.aspectRatio,
        child: image.when(
          data: (bytes) => Image.memory(
            bytes,
            fit: BoxFit.contain,
            gaplessPlayback: true,
            errorBuilder: (_, _, _) => const _NoPhoto(),
          ),
          loading: () => const Skeleton(radius: 0),
          error: (_, _) => const _NoPhoto(),
        ),
      ),
    );
  }
}

class _NoPhoto extends StatelessWidget {
  const _NoPhoto();

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: context.colors.textPrimary.withValues(alpha: 0.05),
    child: Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.image_not_supported_rounded,
            color: context.colors.textTertiary,
            size: 36,
          ),
          const SizedBox(height: 8),
          Text('Photo unavailable', style: context.text.bodySmall),
        ],
      ),
    ),
  );
}

/// Quick actions for a room (long-press on the live map).
Future<void> showRoomSheet(
  BuildContext context,
  WidgetRef ref,
  SegmentInfo segment,
  MapController map,
) {
  final caps = ref.read(capsProvider);
  return showValroveSheet<void>(
    context,
    builder: (context) => Consumer(
      builder: (context, ref, _) {
        final robot = ref.watch(robotStateProvider);
        final docked = robot.status.value == RobotStatus.docked;
        final props = ref.watch(segmentationPropertiesProvider).value;
        return SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    if (ref.watch(roomIconsProvider)[segment.id]
                        case final icon?) ...[
                      Icon(icon, size: 26, color: context.colors.textSecondary),
                      const SizedBox(width: 10),
                    ],
                    Expanded(
                      child: Text(
                        segment.displayName,
                        style: context.text.headlineSmall,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  [
                    areaFromCm2(segment.area),
                    if (segment.material != null &&
                        segment.material != 'generic')
                      SegmentMaterial.label(segment.material!),
                    'ID ${segment.id}',
                  ].join(' · '),
                  style: context.text.bodyMedium,
                ),
                if (ref.watch(lastCleanedProvider)[segment.id] case final last?)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      'Last cleaned ${lastCleanedLabel(last)}',
                      style: context.text.bodySmall,
                    ),
                  ),
                const SizedBox(height: 18),
                FilledButton.icon(
                  icon: const Icon(Icons.play_arrow_rounded),
                  label: Text('Clean ${segment.displayName}'),
                  onPressed: robot.canStartAction
                      ? () {
                          Navigator.pop(context);
                          ref
                              .read(commandsProvider)
                              .run(
                                'start the room cleanup',
                                (c) => c.cleanSegments(
                                  [segment.id],
                                  customOrder:
                                      props?.customOrderSupport ?? false,
                                ),
                                refreshState: true,
                              );
                        }
                      : null,
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  icon: const Icon(Icons.add_task_rounded),
                  label: const Text('Add to selection'),
                  onPressed: () {
                    Navigator.pop(context);
                    if (map.mode != MapMode.segments) {
                      map.setMode(MapMode.segments);
                    }
                    if (!map.selectedSegments.contains(segment.id)) {
                      map.toggleSegment(segment.id);
                    }
                  },
                ),
                if (caps.hasAny([
                  Cap.mapSegmentRename,
                  Cap.mapSegmentEdit,
                  Cap.mapSegmentMaterialControl,
                ])) ...[
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.edit_rounded),
                    label: Text(
                      docked
                          ? 'Edit rooms'
                          : 'Edit rooms (requires docked robot)',
                    ),
                    onPressed: () {
                      Navigator.pop(context);
                      openMapEditor(context, MapMode.editSegments);
                    },
                  ),
                ],
              ],
            ),
          ),
        );
      },
    ),
  );
}
