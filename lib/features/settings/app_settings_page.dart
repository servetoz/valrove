import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../state/app_state.dart';
import '../../ui/theme.dart';
import '../../ui/widgets.dart';
import '../cleanup/cleanup_service.dart';
import '../robots/robots_sheet.dart';

class AppSettingsPage extends ConsumerWidget {
  const AppSettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final robots = ref.watch(robotsProvider);
    return ValrovePage(
      title: 'Appearance & robots',
      children: [
        const SectionLabel('Theme'),
        ValroveCard(
          padding: const EdgeInsets.all(14),
          child: SegmentedButton<AppThemeMode>(
            segments: const [
              ButtonSegment(
                value: AppThemeMode.system,
                label: Text('System'),
                icon: Icon(Icons.brightness_auto_rounded),
              ),
              ButtonSegment(
                value: AppThemeMode.light,
                label: Text('Light'),
                icon: Icon(Icons.light_mode_rounded),
              ),
              ButtonSegment(
                value: AppThemeMode.dark,
                label: Text('Dark'),
                icon: Icon(Icons.dark_mode_rounded),
              ),
            ],
            selected: {settings.themeMode},
            showSelectedIcon: false,
            onSelectionChanged: (s) =>
                ref.read(settingsProvider.notifier).setThemeMode(s.first),
          ),
        ),
        const SectionLabel('Feedback'),
        TileGroup(
          children: [
            ToggleTile(
              title: 'Haptic feedback',
              subtitle: 'Subtle vibrations when controlling the robot',
              icon: Icons.vibration_rounded,
              value: settings.haptics,
              onChanged: (v) =>
                  ref.read(settingsProvider.notifier).setHaptics(v),
            ),
            if (CleanupService.supported)
              ToggleTile(
                title: 'Cleaning notifications',
                subtitle:
                    'A live notification with Pause and Dock while the robot '
                    'cleans, alerts when it finishes or needs help, and the '
                    'history also while Valrove is closed',
                icon: Icons.notifications_active_rounded,
                value: settings.cleanupNotifications,
                onChanged: (v) => ref
                    .read(settingsProvider.notifier)
                    .setCleanupNotifications(v),
              ),
          ],
        ),
        SectionLabel('Robots (${robots.profiles.length})'),
        TileGroup(
          children: [
            for (final p in robots.profiles)
              ValroveTile(
                title: p.name,
                subtitle: p.subtitle,
                icon: Icons.cleaning_services_rounded,
                iconColor: p.id == robots.active?.id
                    ? context.scheme.primary
                    : context.colors.textTertiary,
                trailing: p.id == robots.active?.id
                    ? Icon(
                        Icons.check_circle_rounded,
                        color: context.scheme.primary,
                      )
                    : null,
                onTap: () => ref.read(robotsProvider.notifier).activate(p.id),
              ),
          ],
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: () => showRobotsSheet(context),
          icon: const Icon(Icons.tune_rounded),
          label: const Text('Manage robots'),
        ),
      ],
    );
  }
}
