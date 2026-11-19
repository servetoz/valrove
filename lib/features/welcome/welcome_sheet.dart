import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/store.dart';
import '../../core/support_copy.dart';
import '../../core/valetudo/capabilities.dart';
import '../../state/commands.dart';
import '../../state/data.dart';
import '../../state/session.dart';
import '../../ui/dialogs.dart';
import '../../ui/markdown.dart';
import '../../ui/theme.dart';
import '../../ui/widgets.dart';

Future<void> showWelcomeSheet(BuildContext context) {
  return showValroveSheet<void>(
    context,
    dismissible: false,
    builder: (context) => const _WelcomeSheet(),
  );
}

const _intro = '''
It looks like it might be the first time that you're using Valetudo on this robot.

The first step is usually to let the robot create a new map of your home. Depending on your firmware, the map will allow you to clean specific rooms, add virtual walls and more.

There are some variations in the map creation process based on the model of robot. For example, some robots might require you to enable map persistence first, whereas others might offer a dedicated Mapping Pass.

For the initial mapping, please ensure that:

- the robot is docked
- all relevant doors are open
- there are no loose cables lying around
- all areas you don't want it to go are blocked off

With that done, here's what you'll need to let your robot create a new map:
''';

final _outro = [
  // Left out of the Play build, like the other support links.
  if (!playStoreBuild)
    'While watching your robot zip around, you might want to [${SupportCopy.valetudoWelcomeLinkLabel}](${SupportCopy.valetudoUrl}) to the Valetudo project.',
  'Now, please enjoy your cloud-free robot :)',
].join('\n\n');

class _WelcomeSheet extends ConsumerStatefulWidget {
  const _WelcomeSheet();

  @override
  ConsumerState<_WelcomeSheet> createState() => _WelcomeSheetState();
}

class _WelcomeSheetState extends ConsumerState<_WelcomeSheet> {
  bool _dismissing = false;

  @override
  Widget build(BuildContext context) {
    final caps = ref.watch(capsProvider);
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.85,
      maxChildSize: 0.95,
      minChildSize: 0.5,
      builder: (context, scroll) => ListView(
        controller: scroll,
        padding: EdgeInsets.fromLTRB(
          20,
          14,
          20,
          20 + MediaQuery.paddingOf(context).bottom,
        ),
        children: [
          Text('Welcome to Valetudo', style: context.text.headlineMedium),
          const SizedBox(height: 14),
          const MarkdownText(_intro),
          if (caps.has(Cap.persistentMapControl)) const _PersistentMapTile(),
          if (caps.has(Cap.mappingPass))
            _ActionCard(
              icon: Icons.layers_rounded,
              title: 'Mapping Pass',
              subtitle: 'Create a new map',
              onTap: () async {
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
            )
          else if (caps.has(Cap.basicControl))
            _ActionCard(
              icon: Icons.layers_rounded,
              title: 'Full Cleanup',
              subtitle: 'Create a new map',
              onTap: () async {
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
            ),
          const SizedBox(height: 16),
          MarkdownText(_outro),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Hide'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton(
                  onPressed: _dismissing
                      ? null
                      : () async {
                          setState(() => _dismissing = true);
                          final ok = await ref
                              .read(commandsProvider)
                              .run(
                                'update the welcome dialog setting',
                                (c) => c.valetudoAction('dismissWelcomeDialog'),
                                invalidate: [valetudoInfoProvider],
                              );
                          if (!context.mounted) return;
                          if (ok) {
                            Navigator.pop(context);
                          } else {
                            setState(() => _dismissing = false);
                          }
                        },
                  child: const Text('Do not show again'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ActionCard extends StatelessWidget {
  const _ActionCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: ValroveCard(
        child: ActionTile(
          title: title,
          subtitle: subtitle,
          icon: icon,
          actionLabel: 'Go',
          onAction: onTap,
        ),
      ),
    );
  }
}

class _PersistentMapTile extends ConsumerStatefulWidget {
  const _PersistentMapTile();

  @override
  ConsumerState<_PersistentMapTile> createState() => _PersistentMapTileState();
}

class _PersistentMapTileState extends ConsumerState<_PersistentMapTile> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final value = ref.watch(persistentMapProvider);
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: ValroveCard(
        child: ToggleTile(
          title: 'Persistent maps',
          subtitle: 'Store a persistent map',
          icon: Icons.save_rounded,
          value: value.value,
          error: value.hasError,
          busy: _busy || value.isLoading,
          onChanged: (enable) async {
            if (!enable) {
              final ok = await showConfirm(
                context,
                title: 'Disable persistent maps?',
                message: 'Do you really want to disable persistent maps?\nThis will delete the currently stored map.',
                confirmLabel: 'Disable',
                destructive: true,
              );
              if (!ok) return;
            }
            setState(() => _busy = true);
            await ref
                .read(commandsProvider)
                .run(
                  enable ? 'enable persistent maps' : 'disable persistent maps',
                  (c) => c.setToggle(Cap.persistentMapControl, enable),
                  invalidate: [persistentMapProvider],
                );
            if (mounted) setState(() => _busy = false);
          },
        ),
      ),
    );
  }
}
