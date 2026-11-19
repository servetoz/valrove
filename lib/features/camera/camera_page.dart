import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/valetudo/models/models.dart';
import '../../map/map_controller.dart';
import '../../map/render/map_painter.dart';
import '../../map/widgets/map_canvas.dart';
import '../../state/app_state.dart';
import '../../state/room_icons.dart';
import '../../state/session.dart';
import '../../ui/glass.dart';
import '../../ui/theme.dart';
import 'camera_view.dart';

/// Spectator view: the robot camera above a read-only live map.
class CameraPage extends ConsumerStatefulWidget {
  const CameraPage({super.key});

  @override
  ConsumerState<CameraPage> createState() => _CameraPageState();
}

class _CameraPageState extends ConsumerState<CameraPage> {
  final _map = MapController(mode: MapMode.view);

  @override
  void dispose() {
    _map.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final scene = ref.watch(liveMapProvider).scene;
    final robot = ref.watch(robotStateProvider);
    final dark = ref.watch(isDarkProvider);
    final accent = StateColors.forState(robot);
    return Scaffold(
      body: AmbientBackground(
        accent: accent,
        child: SharedBackdrop(
          child: Column(
            children: [
              SizedBox(height: media.padding.top + 8),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Row(
                  children: [
                    GlassIconButton(
                      icon: Icons.arrow_back_ios_new_rounded,
                      iconSize: 18,
                      tooltip: 'Back',
                      onPressed: () => Navigator.pop(context),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Glass(
                        radius: 24,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 13,
                        ),
                        child: Text('Camera', style: context.text.titleMedium),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 12),
                child: ClipRRect(
                  borderRadius: BorderRadius.all(Radius.circular(24)),
                  child: CameraView(),
                ),
              ),
              Expanded(
                child: scene == null || !scene.data.hasLayers
                    ? const SizedBox.shrink()
                    : MapCanvas(
                        scene: scene,
                        controller: _map,
                        style: MapStyle.of(
                          dark: dark,
                          accent: accent,
                          background: context.colors.background,
                        ),
                        robotActive: const {
                          RobotStatus.cleaning,
                          RobotStatus.returning,
                          RobotStatus.moving,
                          RobotStatus.manualControl,
                        }.contains(robot.status.value),
                        job: robot.job,
                        roomIcons: ref.watch(roomIconsProvider),
                        insets: EdgeInsets.only(
                          bottom: media.padding.bottom + 8,
                          left: 8,
                          right: 8,
                          top: 8,
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
