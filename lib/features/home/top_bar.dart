import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/util/format.dart';
import '../../core/valetudo/models/models.dart';
import '../../state/app_state.dart';
import '../../state/data.dart';
import '../../state/session.dart';
import '../../ui/glass.dart';
import '../../ui/glyphs.dart';
import '../../ui/theme.dart';
import '../../ui/widgets.dart';
import '../events/events_sheet.dart';
import '../navigation.dart';
import '../robots/robots_sheet.dart';
import '../voice/voice_sheet.dart';

/// Display name of the active robot: Valetudo friendly name, saved name or model.
final robotDisplayNameProvider = Provider<String>((ref) {
  final friendly = ref.watch(customizationsProvider).value?.friendlyName.trim();
  if (friendly != null && friendly.isNotEmpty) return friendly;
  final profile = ref.watch(activeProfileProvider);
  return profile?.name ?? 'Robot';
});

class HomeTopBar extends ConsumerWidget {
  const HomeTopBar({super.key, required this.accent});

  final Color accent;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final name = ref.watch(robotDisplayNameProvider);
    final status = ref.watch(robotStatusProvider);
    final known = ref.watch(liveStateProvider).hasValue;
    final health = ref.watch(connectionHealthProvider);
    final events = ref.watch(eventsProvider);
    final unprocessed = events.value?.where((e) => !e.processed).length ?? 0;
    final active = const {
      RobotStatus.cleaning,
      RobotStatus.returning,
      RobotStatus.moving,
      RobotStatus.manualControl,
    }.contains(status.value);

    String subtitle;
    if (health.state == LinkState.unauthorized) {
      subtitle = 'Sign-in required';
    } else if (health.state == LinkState.offline) {
      subtitle = 'Offline';
    } else if (!known) {
      subtitle = 'Connecting…';
    } else {
      subtitle = statusLabel(status.value);
    }

    return Row(
      children: [
        Flexible(
          child: Pressable(
            onTap: () => showRobotsSheet(context),
            semanticLabel: 'Switch robot',
            child: Glass(
              radius: 26,
              padding: const EdgeInsets.fromLTRB(6, 6, 14, 6),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          accent.withValues(alpha: 0.32),
                          accent.withValues(alpha: 0.12),
                        ],
                      ),
                    ),
                    child: Center(
                      child: RobotGlyph(
                        size: 22,
                        color: context.colors.textPrimary,
                        accent: accent,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Flexible(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          name,
                          style: context.text.titleSmall,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            SizedBox(
                              width: 14,
                              height: 14,
                              child: OverflowBox(
                                maxWidth: 30,
                                maxHeight: 30,
                                child: Beacon(
                                  color: accent,
                                  size: 7,
                                  active: active,
                                ),
                              ),
                            ),
                            const SizedBox(width: 4),
                            Flexible(
                              child: Text(
                                subtitle,
                                style: context.text.labelMedium?.copyWith(
                                  color: context.colors.textSecondary,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 6),
                  Icon(
                    Icons.unfold_more_rounded,
                    size: 18,
                    color: context.colors.textTertiary,
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        GlassIconButton(
          icon: Icons.mic_rounded,
          tooltip: 'Voice command',
          onPressed: () => showVoiceSheet(context),
        ),
        const SizedBox(width: 8),
        GlassIconButton(
          icon: Icons.notifications_rounded,
          tooltip: 'Events and notifications',
          onPressed: () => showEventsSheet(context),
          badge: events.hasError && !events.hasValue
              ? const CountBadge('!')
              : (unprocessed > 0 ? CountBadge('$unprocessed') : null),
        ),
        const SizedBox(width: 8),
        GlassIconButton(
          icon: Icons.settings_rounded,
          tooltip: 'Settings',
          onPressed: () => openSettingsHub(context),
        ),
      ],
    );
  }
}

/// Offline / sign-in banner shown below the top bar.
class ConnectionBanner extends ConsumerWidget {
  const ConnectionBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final health = ref.watch(connectionHealthProvider);
    final c = context.colors;
    Widget? content;
    if (health.state == LinkState.offline) {
      content = Row(
        children: [
          SizedBox.square(
            dimension: 16,
            child: CircularProgressIndicator(strokeWidth: 2, color: c.warning),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Robot unreachable — reconnecting',
                  style: context.text.titleSmall,
                ),
                if (health.lastContact != null)
                  Text(
                    'Last contact ${relativeTime(health.lastContact!).toLowerCase()}',
                    style: context.text.bodySmall,
                  ),
              ],
            ),
          ),
          TextButton(
            onPressed: () {
              ref.read(clientProvider)?.reconnectChannels();
              ref.read(liveStateProvider.notifier).refresh();
              ref.read(liveMapProvider.notifier).refresh();
              ref.invalidate(capabilitiesProvider);
            },
            child: const Text('Retry'),
          ),
        ],
      );
    } else if (health.state == LinkState.unauthorized) {
      content = Row(
        children: [
          Icon(Icons.lock_rounded, color: c.warning),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'This robot requires a username and password.',
              style: context.text.titleSmall,
            ),
          ),
          TextButton(
            onPressed: () => editActiveRobot(context, ref),
            child: const Text('Sign in'),
          ),
        ],
      );
    }
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 300),
      transitionBuilder: (child, anim) => SizeTransition(
        sizeFactor: anim,
        alignment: Alignment.topCenter,
        child: GlassFadeTransition(opacity: anim, child: child),
      ),
      child: content == null
          ? const SizedBox(width: double.infinity, key: ValueKey('ok'))
          : Padding(
              key: ValueKey(health.state),
              padding: const EdgeInsets.only(top: 10),
              child: Glass(
                radius: 20,
                tint: c.warning,
                padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
                child: content,
              ),
            ),
    );
  }
}
