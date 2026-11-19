import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:app_links/app_links.dart';
import 'package:home_widget/home_widget.dart';
import 'package:quick_actions/quick_actions.dart';

import '../../core/cleanup/presets.dart';
import '../../core/persistence/robot_profile.dart';
import '../../state/app_state.dart';
import '../../state/cleanup.dart';
import '../../state/commands.dart';
import '../../state/session.dart';
import '../../state/toasts.dart';
import 'cleanup_watcher.dart';
import 'preset_start.dart';

/// Something to do because Valrove was opened from its widget, the quick
/// settings tile or an app shortcut.
sealed class LaunchAction {
  const LaunchAction(this.robotId);

  final String? robotId;

  /// `valrove://preset?robot=…&id=…`, `valrove://dock?robot=…`,
  /// `valrove://presets`, `valrove://command?text=clean+the+kitchen`.
  static LaunchAction? fromUri(Uri? uri) {
    if (uri == null || uri.scheme != 'valrove') return null;
    final robot = uri.queryParameters['robot'];
    return switch (uri.host) {
      'command' when (uri.queryParameters['text'] ?? '').trim().isNotEmpty =>
        CommandAction(robot, uri.queryParameters['text']!),
      'preset' when uri.queryParameters['id'] != null => RunPresetAction(
        robot,
        uri.queryParameters['id']!,
      ),
      'dock' => DockAction(robot),
      'presets' => OpenPresetsAction(robot),
      _ => null,
    };
  }

  static Uri presetUri(String robotId, String presetId) => Uri(
    scheme: 'valrove',
    host: 'preset',
    queryParameters: {'robot': robotId, 'id': presetId},
  );

  static Uri dockUri(String robotId) =>
      Uri(scheme: 'valrove', host: 'dock', queryParameters: {'robot': robotId});

  static final presetsUri = Uri(scheme: 'valrove', host: 'presets');
}

class RunPresetAction extends LaunchAction {
  const RunPresetAction(super.robotId, this.presetId);

  final String presetId;
}

class DockAction extends LaunchAction {
  const DockAction(super.robotId);
}

class OpenPresetsAction extends LaunchAction {
  const OpenPresetsAction(super.robotId);
}

/// A command in words, as spoken ("clean the kitchen"), from a link that
/// Siri Shortcuts or an automation app opened.
class CommandAction extends LaunchAction {
  const CommandAction(super.robotId, this.text);

  final String text;
}

/// The launch action waiting to be handled by the home screen.
class LaunchActions extends Notifier<LaunchAction?> {
  @override
  LaunchAction? build() {
    if (ref.watch(integrationsEnabledProvider)) unawaited(_listen());
    return null;
  }

  Future<void> _listen() async {
    try {
      QuickActions().initialize((type) => receive(Uri.tryParse(type)));
      // Links from the widget, the tile and other apps; the link that opened
      // the app comes first.
      final sub = AppLinks().uriLinkStream.listen(receive);
      ref.onDispose(sub.cancel);
    } catch (e) {
      debugPrint('Launch sources unavailable: $e');
    }
  }

  void receive(Uri? uri) {
    final action = LaunchAction.fromUri(uri);
    if (action != null) state = action;
  }

  void clear() => state = null;
}

final launchActionsProvider = NotifierProvider<LaunchActions, LaunchAction?>(
  LaunchActions.new,
);

/// Shortcuts and widget slots show the first presets.
const launcherSlots = 3;

/// Keeps the app shortcuts and the home screen widget (Android) in sync with
/// the active robot's presets. The quick settings tile reads the widget data.
final launcherSyncProvider = Provider<void>((ref) {
  if (!ref.watch(integrationsEnabledProvider)) return;
  final robot = ref.watch(activeProfileProvider);
  final presets = ref.watch(cleanupPresetsProvider);
  unawaited(_sync(robot, presets.take(launcherSlots).toList()));
});

Future<void> _sync(RobotProfile? robot, List<CleanupPreset> presets) async {
  try {
    await QuickActions().setShortcutItems([
      if (robot != null) ...[
        for (final p in presets)
          ShortcutItem(
            type: LaunchAction.presetUri(robot.id, p.id).toString(),
            localizedTitle: p.name,
            icon: 'ic_shortcut_play',
          ),
        ShortcutItem(
          type: LaunchAction.dockUri(robot.id).toString(),
          localizedTitle: 'Return to dock',
          icon: 'ic_shortcut_dock',
        ),
      ],
    ]);
    if (!Platform.isAndroid) return;
    await HomeWidget.saveWidgetData<String>('robot_name', robot?.name);
    for (var i = 0; i < launcherSlots; i++) {
      final p = i < presets.length && robot != null ? presets[i] : null;
      await HomeWidget.saveWidgetData<String>('preset_${i}_name', p?.name);
      await HomeWidget.saveWidgetData<String>(
        'preset_${i}_uri',
        p == null ? null : LaunchAction.presetUri(robot!.id, p.id).toString(),
      );
    }
    await HomeWidget.saveWidgetData<String>(
      'dock_uri',
      robot == null ? null : LaunchAction.dockUri(robot.id).toString(),
    );
    await HomeWidget.saveWidgetData<String>(
      'presets_uri',
      LaunchAction.presetsUri.toString(),
    );
    await HomeWidget.updateWidget(
      qualifiedAndroidName: 'dev.valroveapp.valrove.PresetWidgetProvider',
    );
  } catch (e) {
    debugPrint('Could not update shortcuts and widget: $e');
  }
}

/// Starts [preset] on the active robot, with feedback.
Future<bool> runCleanupPreset(WidgetRef ref, CleanupPreset preset) async {
  final state = ref.read(robotStateProvider);
  if (state.hasStatus && !state.canStartAction) {
    ref
        .read(toastProvider)
        .error(
          'Couldn\'t start "${preset.name}"',
          detail: 'The robot is busy. Pause or stop the current job first.',
        );
    return false;
  }
  return ref
      .read(commandsProvider)
      .run(
        'start "${preset.name}"',
        (c) async {
          final robotId = ref.read(activeProfileProvider)?.id;
          if (robotId == null) return;
          await startPresetWithSteps(
            c,
            preset,
            robotId: robotId,
            files: await ref.read(robotFilesProvider.future),
          );
        },
        refreshState: true,
        haptic: HapticKind.medium,
        success: 'Started "${preset.name}"',
      );
}

/// Carries out [action]; switches to its robot first when needed.
Future<void> performLaunchAction(
  WidgetRef ref,
  LaunchAction action, {
  required void Function() openPresets,
  required Future<void> Function(String text) runCommand,
}) async {
  final robots = ref.read(robotsProvider);
  final robotId = action.robotId;
  if (robotId != null &&
      robotId != robots.activeId &&
      robots.profiles.any((p) => p.id == robotId)) {
    await ref.read(robotsProvider.notifier).activate(robotId);
  }
  switch (action) {
    case RunPresetAction(:final presetId):
      final preset = ref
          .read(cleanupPresetsProvider)
          .where((p) => p.id == presetId)
          .firstOrNull;
      if (preset == null) {
        ref.read(toastProvider).error('This preset no longer exists');
        return;
      }
      await runCleanupPreset(ref, preset);
    case DockAction():
      await ref
          .read(commandsProvider)
          .run(
            'send the robot to its dock',
            (c) => c.basicControl('home'),
            refreshState: true,
            success: 'The robot returns to its dock',
          );
    case OpenPresetsAction():
      openPresets();
    case CommandAction(:final text):
      await runCommand(text);
  }
}
