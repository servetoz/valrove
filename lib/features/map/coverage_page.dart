import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/help_texts.dart';
import '../../core/valetudo/models/models.dart';
import '../../map/map_controller.dart';
import '../../map/render/map_painter.dart';
import '../../map/widgets/map_canvas.dart';
import '../../state/app_state.dart';
import '../../state/room_icons.dart';
import '../../state/session.dart';
import '../../ui/dialogs.dart';
import '../../ui/glass.dart';
import '../../ui/theme.dart';
import '../../ui/widgets.dart';
import '../home/home_screen.dart' show RadarLoader;

/// Live map with a thick path so unreached areas stand out.
class CoverageMapPage extends ConsumerStatefulWidget {
  const CoverageMapPage({super.key});

  @override
  ConsumerState<CoverageMapPage> createState() => _CoverageMapPageState();
}

class _CoverageMapPageState extends ConsumerState<CoverageMapPage> {
  final _map = MapController(mode: MapMode.coverage);

  @override
  void dispose() {
    _map.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final mapState = ref.watch(liveMapProvider);
    final scene = mapState.scene;
    final robot = ref.watch(robotStateProvider);
    final dark = ref.watch(isDarkProvider);
    final accent = StateColors.forState(robot);
    final media = MediaQuery.of(context);
    return Scaffold(
      body: AmbientBackground(
        accent: accent,
        child: SharedBackdrop(
          child: Stack(
            children: [
              Positioned.fill(
                child: scene == null || !scene.data.hasLayers
                    ? Center(
                        child: mapState.loading
                            ? const RadarLoader(label: 'Loading map…')
                            : const EmptyState(
                                icon: Icons.map_outlined,
                                title: 'No map data',
                              ),
                      )
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
                        }.contains(robot.status.value),
                        job: robot.job,
                        roomIcons: ref.watch(roomIconsProvider),
                        insets: EdgeInsets.only(
                          top: media.padding.top + 70,
                          bottom: media.padding.bottom + 90,
                          left: 12,
                          right: 12,
                        ),
                      ),
              ),
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: ProgressiveBlurEdge(height: media.padding.top + 76),
              ),
              Positioned(
                top: media.padding.top + 8,
                left: 12,
                right: 12,
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
                        child: Text(
                          'Coverage map',
                          style: context.text.titleMedium,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    GlassIconButton(
                      icon: Icons.help_outline_rounded,
                      tooltip: 'Help',
                      onPressed: () => showMarkdownSheet(
                        context,
                        title: 'Coverage map',
                        markdown: HelpTexts.robotCoverageMapHelp,
                      ),
                    ),
                  ],
                ),
              ),
              Positioned(
                left: 12,
                right: 12,
                bottom: media.padding.bottom + 16,
                child: Glass(
                  radius: 22,
                  padding: const EdgeInsets.all(14),
                  child: Row(
                    children: [
                      Icon(Icons.brush_rounded, color: accent),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'The robot path is drawn as wide as the robot. Uncovered spots stand out.',
                          style: context.text.bodySmall,
                        ),
                      ),
                    ],
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
