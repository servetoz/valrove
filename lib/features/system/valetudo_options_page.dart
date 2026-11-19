import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/help_texts.dart';
import '../../core/valetudo/capabilities.dart';
import '../../core/valetudo/models/models.dart';
import '../../state/commands.dart';
import '../../state/data.dart';
import '../../state/session.dart';
import '../../ui/dialogs.dart';
import '../../ui/markdown.dart';
import '../../ui/theme.dart';
import '../../ui/widgets.dart';
import '../connectivity/connectivity_pages.dart' show InfoNote;
import '../../ui/haptics.dart';

class ValetudoOptionsPage extends ConsumerStatefulWidget {
  const ValetudoOptionsPage({super.key});

  @override
  ConsumerState<ValetudoOptionsPage> createState() =>
      _ValetudoOptionsPageState();
}

class _ValetudoOptionsPageState extends ConsumerState<ValetudoOptionsPage> {
  bool _restoring = false;
  bool _renaming = false;

  @override
  Widget build(BuildContext context) {
    final caps = ref.watch(capsProvider);
    final custom = ref.watch(customizationsProvider);
    final provider = ref.watch(updateProviderProvider);
    final friendly = custom.value?.friendlyName ?? '';
    return ValrovePage(
      title: 'Valetudo options',
      subtitle: 'Tunables and actions provided by Valetudo',
      children: [
        TileGroup(
          children: [
            ActionTile(
              title: 'Friendly name',
              subtitle: friendly.isNotEmpty ? friendly : 'Set a custom friendly name for Network Advertisement, MQTT etc.',
              icon: Icons.badge_rounded,
              actionLabel: 'Edit',
              busy: _renaming || custom.isLoading,
              onAction: () async {
                final value = await showTextPrompt(
                  context,
                  title: 'Custom friendly name',
                  description: 'Set a custom friendly name for Network Advertisement, MQTT etc.',
                  initial: friendly,
                  label: 'Name',
                  transform: (v) {
                    final cleaned = v.replaceAll(RegExp(r'[^a-zA-Z0-9 -]'), '');
                    return cleaned.length > 24
                        ? cleaned.substring(0, 24)
                        : cleaned;
                  },
                );
                if (value == null) return;
                setState(() => _renaming = true);
                await ref
                    .read(commandsProvider)
                    .run(
                      'save the friendly name',
                      (c) => c.setCustomizations(
                        ValetudoCustomizations(friendlyName: value),
                      ),
                      invalidate: [customizationsProvider],
                    );
                if (mounted) setState(() => _renaming = false);
              },
            ),
            ValroveTile(
              title: 'Update channel',
              subtitle: 'Select the channel used by the inbuilt updater',
              icon: Icons.system_update_alt_rounded,
              trailing: provider.when(
                data: (p) => DropdownButton<String>(
                  value: p == 'github' || p == 'github_nightly' ? p : null,
                  underline: const SizedBox.shrink(),
                  borderRadius: BorderRadius.circular(16),
                  items: const [
                    DropdownMenuItem(value: 'github', child: Text('Release')),
                    DropdownMenuItem(
                      value: 'github_nightly',
                      child: Text('Nightly'),
                    ),
                  ],
                  onChanged: (v) {
                    if (v != null) {
                      ref
                          .read(commandsProvider)
                          .run(
                            'change the update channel',
                            (c) => c.setUpdateProvider(v),
                            invalidate: [updateProviderProvider],
                          );
                    }
                  },
                ),
                loading: () => const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                error: (e, _) => Text(
                  'Error',
                  style: context.text.labelMedium?.copyWith(
                    color: context.colors.danger,
                  ),
                ),
              ),
            ),
          ],
        ),
        if (caps.has(Cap.duststreaming)) ...[
          const SectionLabel('Camera'),
          const TileGroup(children: [_CameraStreamingTile()]),
        ],
        const SectionLabel('Danger zone'),
        TileGroup(
          children: [
            ActionTile(
              title: 'Restore default configuration',
              subtitle: 'This will only affect Valetudo',
              icon: Icons.restart_alt_rounded,
              actionLabel: 'Restore',
              danger: true,
              busy: _restoring,
              onAction: () async {
                final ok = await showConfirm(
                  context,
                  title: 'Restore default Valetudo configuration?',
                  message: 'Are you sure that you want to restore the default configuration? This will not affect Wi-Fi settings, Map data etc.',
                  confirmLabel: 'Restore',
                  destructive: true,
                );
                if (!ok) return;
                setState(() => _restoring = true);
                final done = await ref
                    .read(commandsProvider)
                    .run(
                      'restore the default configuration',
                      (c) => c.valetudoAction('restoreDefaultConfiguration'),
                    );
                if (done) ref.invalidate(clientProvider);
                if (mounted) setState(() => _restoring = false);
              },
            ),
          ],
        ),
      ],
    );
  }
}

/// Enable/disable camera streaming with Valetudo's mandatory privacy lecture.
class _CameraStreamingTile extends ConsumerStatefulWidget {
  const _CameraStreamingTile();

  @override
  ConsumerState<_CameraStreamingTile> createState() =>
      _CameraStreamingTileState();
}

class _CameraStreamingTileState extends ConsumerState<_CameraStreamingTile> {
  bool _busy = false;

  Future<void> _set(bool enabled) async {
    setState(() => _busy = true);
    await ref
        .read(commandsProvider)
        .run(
          enabled ? 'enable camera streaming' : 'disable camera streaming',
          (c) => c.setDuststreamingEnabled(enabled),
          invalidate: [
            duststreamingEnabledProvider,
            duststreamingPropertiesProvider,
          ],
        );
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _instructions() async {
    String path = 'undefined';
    try {
      final runtime = await ref.read(runtimeInfoProvider.future);
      final exec = runtime.execPath;
      final sep = exec.contains('/') ? '/' : '\\';
      path = '${exec.substring(0, exec.lastIndexOf(sep) + 1)}duststreamer';
    } catch (_) {}
    if (!mounted) return;
    await showValroveSheet<void>(
      context,
      builder: (context) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.8,
        builder: (context, scroll) => ListView(
          controller: scroll,
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          children: [
            Text("You're not done yet!", style: context.text.headlineSmall),
            const SizedBox(height: 12),
            MarkdownText(
              'The video capture, processing and encoding part of the camera streaming feature lives in the gstreamer-based '
              '[duststreamer](https://github.com/hypfer/duststreamer).\n'
              'That is yet again another statically linked single binary to be dropped onto the robot - and also to be yeeted away to make camera streaming technically impossible again.\n\n'
              'To complete the setup, place an executable `duststreamer` binary at `$path` and refresh.',
            ),
            const SizedBox(height: 16),
            const InfoNote(
              '**Note**: The slight clunkiness of this feature is not an oversight but by-design.\n'
              'Valetudo could easily be doing all this for you, but then it would be a one-button, no-thinking, no-skillcheck spycam.\n\n'
              'For more information and additional thoughts, check out the [2026.08.0 release notes](https://github.com/Hypfer/Valetudo/releases/tag/2026.08.0), featuring the first release of this functionality.',
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Understood'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final enabled = ref.watch(duststreamingEnabledProvider);
    final props = ref.watch(duststreamingPropertiesProvider);
    final on = enabled.value ?? false;
    final installed = props.value?.duststreamerInstalled ?? false;
    final error = enabled.hasError || props.hasError;

    Widget? subtitleWidget;
    String subtitle;
    if (!on) {
      subtitle = 'See what your robot sees';
    } else if (!installed) {
      subtitle = '';
      subtitleWidget = GestureDetector(
        onTap: _instructions,
        child: Text(
          'Setup incomplete',
          style: context.text.bodySmall?.copyWith(
            color: context.colors.warning,
            decoration: TextDecoration.underline,
          ),
        ),
      );
    } else {
      subtitle = "Rockwell - Somebody's Watching Me ♫";
    }

    return ValroveTile(
      title: 'Camera streaming',
      subtitle: subtitle,
      subtitleWidget: subtitleWidget,
      icon: Icons.videocam_rounded,
      iconColor: context.colors.danger,
      trailing: error
          ? Text(
              'Error',
              style: context.text.labelMedium?.copyWith(
                color: context.colors.danger,
              ),
            )
          : FilledButton.tonal(
              onPressed: _busy || !props.hasValue || !enabled.hasValue
                  ? null
                  : () async {
                      if (on) {
                        final ok = await showConfirm(
                          context,
                          title: 'Disable camera streaming?',
                          message: 'This will also delete the duststreamer, so that it cannot be re-enabled with HTTP access alone.',
                          confirmLabel: 'Disable',
                          destructive: true,
                        );
                        if (ok) await _set(false);
                      } else {
                        final ok = await showDialog<bool>(
                          context: context,
                          builder: (_) => const _LectureDialog(),
                        );
                        if (ok == true) {
                          await _set(true);
                          if (!installed && mounted) await _instructions();
                        }
                      }
                    },
              child: _busy
                  ? const SizedBox.square(
                      dimension: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(on ? 'Disable' : 'Enable'),
            ),
    );
  }
}

/// Privacy lecture with a 60 second countdown (pauses while the app is in
/// the background). Typing "skip" on a hardware keyboard skips it.
class _LectureDialog extends StatefulWidget {
  const _LectureDialog();

  @override
  State<_LectureDialog> createState() => _LectureDialogState();
}

class _LectureDialogState extends State<_LectureDialog>
    with WidgetsBindingObserver {
  int _remaining = 60;
  Timer? _timer;
  bool _focused = true;
  String _typed = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_focused && _remaining > 0) setState(() => _remaining--);
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) =>
      _focused = state == AppLifecycleState.resumed;

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      autofocus: true,
      onKeyEvent: (node, event) {
        final ch = event.character;
        if (event is KeyDownEvent && ch != null && ch.length == 1) {
          _typed = (_typed + ch);
          if (_typed.length > 4) _typed = _typed.substring(_typed.length - 4);
          if (_typed == 'skip') setState(() => _remaining = 0);
        }
        return KeyEventResult.ignored;
      },
      child: AlertDialog(
        title: const Text('Are you sure you want to enable camera streaming?'),
        content: SizedBox(
          width: 560,
          child: SingleChildScrollView(
            child: MarkdownText(HelpTexts.duststreamingLecture),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: _remaining > 0
                ? null
                : () {
                    Haptics.medium();
                    Navigator.pop(context, true);
                  },
            child: Text(
              _remaining > 0 ? 'I understand (${_remaining}s)' : 'I understand',
            ),
          ),
        ],
      ),
    );
  }
}
