import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/persistence/robot_profile.dart';
import '../../state/app_state.dart';
import '../../ui/dialogs.dart';
import '../../ui/glyphs.dart';
import '../../ui/theme.dart';
import '../../ui/widgets.dart';
import 'robot_setup.dart';

/// Switch between saved robots, add or remove robots.
Future<void> showRobotsSheet(BuildContext context) {
  return showValroveSheet<void>(
    context,
    builder: (context) => const _RobotsSheet(),
  );
}

class _RobotsSheet extends ConsumerWidget {
  const _RobotsSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final robots = ref.watch(robotsProvider);
    return SafeArea(
      top: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SheetHeader(
            title: 'Robots',
            subtitle: 'Switch between your Valetudo robots',
          ),
          Flexible(
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
              children: [
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
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (p.id == robots.active?.id)
                              Icon(
                                Icons.check_circle_rounded,
                                color: context.scheme.primary,
                              ),
                            IconButton(
                              tooltip: 'Edit',
                              icon: const Icon(Icons.more_horiz_rounded),
                              onPressed: () => _editRobot(context, ref, p),
                            ),
                          ],
                        ),
                        onTap: () {
                          ref.read(robotsProvider.notifier).activate(p.id);
                          Navigator.pop(context);
                        },
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  icon: const Icon(Icons.add_rounded),
                  label: const Text('Add robot'),
                  onPressed: () {
                    Navigator.pop(context);
                    showAddRobotSheet(context);
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _editRobot(
    BuildContext context,
    WidgetRef ref,
    RobotProfile profile,
  ) async {
    final action = await showChoiceSheet<String>(
      context,
      title: profile.name,
      subtitle: profile.subtitle,
      options: const [
        ChoiceOption(
          'rename',
          'Rename',
          icon: Icons.drive_file_rename_outline_rounded,
        ),
        ChoiceOption(
          'connection',
          'Connection & password',
          icon: Icons.lan_rounded,
        ),
        ChoiceOption(
          'remove',
          'Remove from this phone',
          icon: Icons.delete_outline_rounded,
        ),
      ],
    );
    if (!context.mounted || action == null) return;
    switch (action) {
      case 'rename':
        final name = await showTextPrompt(
          context,
          title: 'Rename robot',
          initial: profile.name,
          label: 'Name',
          validator: (v) => v.trim().isEmpty ? 'Enter a name' : null,
        );
        if (name != null) {
          await ref
              .read(robotsProvider.notifier)
              .upsert(profile.copyWith(name: name.trim()), activate: false);
        }
      case 'connection':
        if (context.mounted) await showEditRobotSheet(context, profile);
      case 'remove':
        final ok = await showConfirm(
          context,
          title: 'Remove ${profile.name}?',
          message: 'The robot itself is not changed. You can add it again at any time.',
          confirmLabel: 'Remove',
          destructive: true,
        );
        if (ok) await ref.read(robotsProvider.notifier).remove(profile.id);
    }
  }
}

Future<void> showAddRobotSheet(BuildContext context) {
  return showValroveSheet<void>(
    context,
    builder: (context) => SafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SheetHeader(title: 'Add robot'),
            RobotSetupView(onDone: (_) => Navigator.pop(context)),
          ],
        ),
      ),
    ),
  );
}

Future<void> showEditRobotSheet(
  BuildContext context,
  RobotProfile profile, {
  bool authRequired = false,
}) {
  return showValroveSheet<void>(
    context,
    builder: (context) => SafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SheetHeader(title: profile.name, subtitle: 'Connection settings'),
            RobotSetupView(
              existing: profile,
              showDiscovery: false,
              initialAuthRequired: authRequired,
              onDone: (_) => Navigator.pop(context),
            ),
          ],
        ),
      ),
    ),
  );
}

/// Small robot avatar used in lists.
class RobotAvatar extends StatelessWidget {
  const RobotAvatar({super.key, this.color});

  final Color? color;

  @override
  Widget build(BuildContext context) =>
      RobotGlyph(size: 22, color: color ?? context.colors.textPrimary);
}
