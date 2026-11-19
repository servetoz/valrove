import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart';

import '../../core/cleanup/cleanup_tracker.dart' show joinNames;
import '../../core/valetudo/capabilities.dart';
import '../../core/valetudo/models/models.dart';
import '../../map/processing/map_processor.dart';
import '../../state/cleanup.dart';
import '../../state/commands.dart';
import '../../state/data.dart';
import '../../state/session.dart';
import '../../state/toasts.dart';
import '../../ui/dialogs.dart';
import '../../ui/theme.dart';
import '../cleanup/launchers.dart';
import 'voice_commands.dart';

/// Rooms of the live map, for matching spoken names.
List<SegmentInfo> _rooms(WidgetRef ref) =>
    ref.read(liveMapProvider).scene?.data.segments ?? const [];

/// Reads [text] as a command for the active robot.
VoiceCommand parseForRobot(WidgetRef ref, String text) => parseVoiceCommand(
  text,
  rooms: [for (final s in _rooms(ref)) (id: s.id, name: s.displayName)],
  presets: [
    for (final p in ref.read(cleanupPresetsProvider)) (id: p.id, name: p.name),
  ],
);

/// Carries out [command]. Returns false when it wasn't understood.
Future<bool> runVoiceCommand(WidgetRef ref, VoiceCommand command) async {
  final commands = ref.read(commandsProvider);
  final names = {for (final s in _rooms(ref)) s.id: s.displayName};
  switch (command) {
    case CleanRoomsCommand(:final roomIds, :final iterations):
      MapSegmentationProperties? props;
      try {
        props = await ref.read(segmentationPropertiesProvider.future);
      } catch (_) {}
      final passes = iterations.clamp(1, props?.iterationCount.max ?? 1);
      final where = joinNames([for (final id in roomIds) names[id] ?? id]);
      await commands.run(
        'clean $where',
        (c) => c.cleanSegments(
          roomIds,
          iterations: passes,
          customOrder:
              (props?.customOrderSupport ?? false) && roomIds.length > 1,
        ),
        refreshState: true,
        haptic: HapticKind.medium,
        success: 'Cleaning $where${passes > 1 ? ' ×$passes' : ''}',
      );
    case CleanHomeCommand():
      await commands.run(
        'start cleaning',
        (c) => c.basicControl('start'),
        refreshState: true,
        haptic: HapticKind.medium,
        success: 'Cleaning the whole home',
      );
    case RunPresetCommand(:final presetId):
      final preset = ref
          .read(cleanupPresetsProvider)
          .where((p) => p.id == presetId)
          .firstOrNull;
      if (preset != null) await runCleanupPreset(ref, preset);
    case DockCommand():
      await commands.run(
        'send the robot to its dock',
        (c) => c.basicControl('home'),
        refreshState: true,
        success: 'Going back to the dock',
      );
    case PauseCommand():
      await commands.run(
        'pause',
        (c) => c.basicControl('pause'),
        refreshState: true,
        success: 'Paused',
      );
    case ResumeCommand():
      await commands.run(
        'resume',
        (c) => c.basicControl('start'),
        refreshState: true,
        success: 'Carrying on',
      );
    case StopCommand():
      await commands.run(
        'stop',
        (c) => c.basicControl('stop'),
        refreshState: true,
        success: 'Stopped',
      );
    case LocateCommand():
      if (!ref.read(capsProvider).has(Cap.locate)) return false;
      await commands.run(
        'locate the robot',
        (c) => c.locate(),
        success: 'The robot plays a sound',
      );
    case UnknownCommand(:final text):
      ref
          .read(toastProvider)
          .error(
            "Didn't understand \"$text\"",
            detail: 'Try "clean the kitchen" or "go back to the dock".',
          );
      return false;
  }
  return true;
}

/// Listens for a spoken command (or takes a typed one) and carries it out.
Future<void> showVoiceSheet(BuildContext context) =>
    showValroveSheet<void>(context, builder: (_) => const _VoiceSheet());

class _VoiceSheet extends ConsumerStatefulWidget {
  const _VoiceSheet();

  @override
  ConsumerState<_VoiceSheet> createState() => _VoiceSheetState();
}

enum _Phase { starting, listening, unavailable, notUnderstood }

class _VoiceSheetState extends ConsumerState<_VoiceSheet> {
  final _speech = SpeechToText();
  final _typed = TextEditingController();
  _Phase _phase = _Phase.starting;
  String _heard = '';
  bool _onDevice = true;
  bool _done = false;

  @override
  void initState() {
    super.initState();
    unawaited(_start());
  }

  @override
  void dispose() {
    unawaited(_speech.cancel());
    _typed.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    setState(() {
      _phase = _Phase.starting;
      _heard = '';
    });
    var ok = false;
    try {
      ok = await _speech.initialize(onError: (e) => _onError(e.errorMsg));
    } catch (e) {
      debugPrint('Speech recognition unavailable: $e');
    }
    if (!mounted) return;
    if (!ok) {
      setState(() => _phase = _Phase.unavailable);
      return;
    }
    await _listen();
  }

  Future<void> _listen() async {
    final phrases = [
      for (final s in _rooms(ref)) s.displayName,
      for (final p in ref.read(cleanupPresetsProvider)) p.name,
    ];
    setState(() => _phase = _Phase.listening);
    await _speech.listen(
      onResult: _onResult,
      listenOptions: SpeechListenOptions(
        // Speech stays on the phone where the phone can do that.
        onDevice: _onDevice,
        listenMode: ListenMode.confirmation,
        contextualPhrases: phrases,
        pauseFor: const Duration(seconds: 3),
        listenFor: const Duration(seconds: 12),
      ),
    );
  }

  void _onError(String message) {
    if (!mounted || _done) return;
    // No on-device recognizer for this language: use the phone's default.
    if (_onDevice && message.contains('language')) {
      _onDevice = false;
      unawaited(_listen());
      return;
    }
    if (_phase == _Phase.listening) {
      setState(() => _phase = _heard.isEmpty ? _Phase.notUnderstood : _phase);
    }
  }

  void _onResult(SpeechRecognitionResult result) {
    if (!mounted || _done) return;
    setState(() => _heard = result.recognizedWords);
    if (result.finalResult) unawaited(_handle(result.recognizedWords));
  }

  Future<void> _handle(String text) async {
    if (text.trim().isEmpty) {
      setState(() => _phase = _Phase.notUnderstood);
      return;
    }
    final command = parseForRobot(ref, text);
    if (command is UnknownCommand) {
      setState(() {
        _heard = text;
        _phase = _Phase.notUnderstood;
      });
      return;
    }
    _done = true;
    await _speech.stop();
    if (mounted) Navigator.pop(context);
    await runVoiceCommand(ref, command);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final rooms = _rooms(ref);
    final presets = ref.watch(cleanupPresetsProvider);
    final examples = [
      if (rooms.isNotEmpty) 'Clean the ${rooms.first.displayName}',
      if (rooms.length > 1)
        'Clean ${rooms[0].displayName} and ${rooms[1].displayName} twice',
      if (presets.isNotEmpty) 'Start ${presets.first.name}',
      'Go back to the dock',
    ];
    final (title, hint) = switch (_phase) {
      _Phase.starting => ('Getting ready…', null),
      _Phase.listening => (
        _heard.isEmpty ? 'Listening…' : '“$_heard”',
        'Say what the robot should do',
      ),
      _Phase.unavailable => (
        'Speech recognition is not available',
        'Type the command instead.',
      ),
      _Phase.notUnderstood => (
        _heard.isEmpty ? "Didn't hear anything" : '“$_heard”',
        "That didn't sound like a command. Try again or type it.",
      ),
    };
    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: _MicButton(
                active: _phase == _Phase.listening,
                onTap: _phase == _Phase.unavailable
                    ? null
                    : () => _phase == _Phase.listening
                          ? _speech.stop()
                          : _listen(),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              title,
              textAlign: TextAlign.center,
              style: context.text.titleLarge,
            ),
            if (hint != null) ...[
              const SizedBox(height: 4),
              Text(
                hint,
                textAlign: TextAlign.center,
                style: context.text.bodyMedium,
              ),
            ],
            const SizedBox(height: 18),
            TextField(
              controller: _typed,
              textInputAction: TextInputAction.go,
              decoration: const InputDecoration(
                labelText: 'Or type a command',
                prefixIcon: Icon(Icons.keyboard_rounded),
              ),
              onSubmitted: _handle,
            ),
            const SizedBox(height: 16),
            Text('FOR EXAMPLE', style: context.text.labelSmall),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final e in examples)
                  ActionChip(label: Text(e), onPressed: () => _handle(e)),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              _onDevice
                  ? 'Speech is recognised on this phone when it can do that.'
                  : "Speech is recognised by your phone's speech service.",
              style: context.text.bodySmall?.copyWith(color: c.textTertiary),
            ),
          ],
        ),
      ),
    );
  }
}

class _MicButton extends StatelessWidget {
  const _MicButton({required this.active, required this.onTap});

  final bool active;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final accent = context.scheme.primary;
    return Semantics(
      button: true,
      label: active ? 'Stop listening' : 'Listen',
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          width: 84,
          height: 84,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: active ? accent : accent.withValues(alpha: 0.12),
            boxShadow: [
              if (active)
                BoxShadow(
                  color: accent.withValues(alpha: 0.45),
                  blurRadius: 28,
                  spreadRadius: 4,
                ),
            ],
          ),
          child: Icon(
            Icons.mic_rounded,
            size: 38,
            color: active ? Colors.white : accent,
          ),
        ),
      ),
    );
  }
}
