import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/help_texts.dart';
import '../../core/util/format.dart';
import '../../core/valetudo/capabilities.dart';
import '../../core/valetudo/models/models.dart';
import '../../state/commands.dart';
import '../../state/data.dart';
import '../../state/session.dart';
import '../../ui/dialogs.dart';
import '../../ui/theme.dart';
import '../../ui/widgets.dart';

/// Speaker volume, voice packs, audio clips and Do-Not-Disturb.
class SoundPage extends ConsumerWidget {
  const SoundPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final caps = ref.watch(capsProvider);
    return ValrovePage(
      title: 'Sound & quiet hours',
      subtitle: 'Speaker, voice packs and Do Not Disturb',
      children: [
        if (caps.has(Cap.speakerVolumeControl) ||
            caps.has(Cap.speakerTest)) ...[
          const SectionLabel('Speaker', icon: Icons.volume_up_rounded),
          const _SpeakerCard(),
        ],
        if (caps.has(Cap.speakerPlayAudio)) ...[
          const SectionLabel('Sounds', icon: Icons.music_note_rounded),
          const _AudioCard(),
        ],
        if (caps.has(Cap.voicePackManagement)) ...[
          SectionLabel(
            'Voice packs',
            icon: Icons.record_voice_over_rounded,
            trailing: _HelpButton(
              title: 'Voice packs',
              markdown: HelpTexts.voicepackHelp,
            ),
          ),
          const _VoicePackCard(),
        ],
        if (caps.has(Cap.doNotDisturb)) ...[
          SectionLabel(
            'Do not disturb',
            icon: Icons.bedtime_rounded,
            trailing: _HelpButton(
              title: 'Do not disturb',
              markdown: HelpTexts.doNotDisturbHelp,
            ),
          ),
          const _DndCard(),
        ],
      ],
    );
  }
}

class _HelpButton extends StatelessWidget {
  const _HelpButton({required this.title, required this.markdown});

  final String title;
  final String markdown;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 24,
    child: IconButton(
      padding: EdgeInsets.zero,
      iconSize: 18,
      tooltip: 'Help',
      icon: Icon(
        Icons.help_outline_rounded,
        color: context.colors.textTertiary,
      ),
      onPressed: () =>
          showMarkdownSheet(context, title: title, markdown: markdown),
    ),
  );
}

class _SpeakerCard extends ConsumerStatefulWidget {
  const _SpeakerCard();

  @override
  ConsumerState<_SpeakerCard> createState() => _SpeakerCardState();
}

class _SpeakerCardState extends ConsumerState<_SpeakerCard> {
  double? _local;
  bool _testing = false;

  @override
  Widget build(BuildContext context) {
    final caps = ref.watch(capsProvider);
    final volume = caps.has(Cap.speakerVolumeControl)
        ? ref.watch(speakerVolumeProvider)
        : null;
    final server = volume?.value?.toDouble();
    final shown = _local ?? server ?? 0;
    return ValroveCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (volume != null) ...[
            if (volume.hasError && !volume.hasValue)
              Text(
                'Error loading speaker state.',
                style: context.text.bodyMedium?.copyWith(
                  color: context.colors.danger,
                ),
              )
            else ...[
              Row(
                children: [
                  Text('Volume', style: context.text.titleSmall),
                  const Spacer(),
                  Text(
                    '${shown.round()}%',
                    style: context.text.titleSmall?.copyWith(
                      color: context.scheme.primary,
                    ),
                  ),
                ],
              ),
              Row(
                children: [
                  Icon(
                    Icons.volume_down_rounded,
                    color: context.colors.textSecondary,
                  ),
                  Expanded(
                    child: Slider(
                      value: shown.clamp(0, 100),
                      max: 100,
                      divisions: 100,
                      label: '${shown.round()}',
                      onChanged: server == null
                          ? null
                          : (v) => setState(() => _local = v),
                      onChangeEnd: (v) async {
                        final ok = await ref
                            .read(commandsProvider)
                            .run(
                              'change the volume',
                              (c) => c.setSpeakerVolume(v.round()),
                              invalidate: [speakerVolumeProvider],
                              haptic: null,
                            );
                        if (!ok && mounted) setState(() => _local = null);
                        try {
                          await ref.read(speakerVolumeProvider.future);
                        } catch (_) {}
                        if (mounted) setState(() => _local = null);
                      },
                    ),
                  ),
                  Icon(
                    Icons.volume_up_rounded,
                    color: context.colors.textSecondary,
                  ),
                ],
              ),
            ],
          ],
          if (caps.has(Cap.speakerTest)) ...[
            const SizedBox(height: 8),
            OutlinedButton.icon(
              icon: _testing
                  ? const SizedBox.square(
                      dimension: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.campaign_rounded),
              label: const Text('Test sound volume'),
              onPressed: _testing
                  ? null
                  : () async {
                      setState(() => _testing = true);
                      await ref
                          .read(commandsProvider)
                          .run('play the test sound', (c) => c.playTestSound());
                      if (mounted) setState(() => _testing = false);
                    },
            ),
          ],
        ],
      ),
    );
  }
}

class _AudioCard extends ConsumerWidget {
  const _AudioCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final list = ref.watch(audioListProvider);
    return list.when(
      data: (clips) => clips.isEmpty
          ? ValroveCard(
              padding: const EdgeInsets.all(16),
              child: Text(
                'The robot does not offer any sounds to play.',
                style: context.text.bodyMedium,
              ),
            )
          : TileGroup(
              children: [
                for (final clip in clips)
                  ValroveTile(
                    title: clip.name,
                    icon: Icons.play_circle_rounded,
                    onTap: () => ref
                        .read(commandsProvider)
                        .run('play the sound', (c) => c.playAudio(clip.id)),
                  ),
              ],
            ),
      loading: () => const SkeletonCard(rows: 2),
      error: (e, _) => ValroveCard(
        child: InlineError(
          'Error loading sounds',
          onRetry: () => ref.invalidate(audioListProvider),
        ),
      ),
    );
  }
}

class _VoicePackCard extends ConsumerStatefulWidget {
  const _VoicePackCard();

  @override
  ConsumerState<_VoicePackCard> createState() => _VoicePackCardState();
}

class _VoicePackCardState extends ConsumerState<_VoicePackCard> {
  final _url = TextEditingController();
  final _language = TextEditingController();
  final _hash = TextEditingController();
  bool _sending = false;

  @override
  void dispose() {
    _url.dispose();
    _language.dispose();
    _hash.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final status = ref.watch(voicePackProvider);
    final s = status.value;
    final busy =
        s != null &&
        (s.operationType == 'downloading' || s.operationType == 'installing');
    final disabled = s == null || busy;
    if (status.hasError && !status.hasValue) {
      return ValroveCard(
        child: InlineError(
          'Error loading voice pack management state.',
          onRetry: () => ref.invalidate(voicePackProvider),
        ),
      );
    }
    return ValroveCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text('Current language', style: context.text.bodyMedium),
              const Spacer(),
              Text(s?.currentLanguage ?? '…', style: context.text.titleSmall),
            ],
          ),
          if (s?.operationType == 'error') ...[
            const SizedBox(height: 10),
            Text(
              'Error installing voice pack. Check the log for details.',
              style: context.text.bodyMedium?.copyWith(
                color: context.colors.danger,
              ),
            ),
          ],
          AnimatedSize(
            duration: const Duration(milliseconds: 300),
            child: busy
                ? Padding(
                    padding: const EdgeInsets.only(top: 14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          s.operationType == 'downloading'
                              ? 'Downloading…'
                              : 'Installing…',
                          style: context.text.labelLarge,
                        ),
                        const SizedBox(height: 8),
                        ProgressTrack(
                          value: (s.progress == null || s.progress == 0)
                              ? null
                              : s.progress! / 100,
                          color: s.operationType == 'downloading'
                              ? context.colors.success
                              : context.scheme.secondary,
                        ),
                      ],
                    ),
                  )
                : const SizedBox(width: double.infinity),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _url,
            enabled: !disabled,
            keyboardType: TextInputType.url,
            decoration: const InputDecoration(
              labelText: 'URL',
              hintText: 'https://',
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _language,
            enabled: !disabled,
            decoration: const InputDecoration(
              labelText: 'Language code',
              hintText: 'VA',
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _hash,
            enabled: !disabled,
            decoration: const InputDecoration(labelText: 'Hash'),
          ),
          const SizedBox(height: 14),
          FilledButton.tonal(
            onPressed: disabled || _sending
                ? null
                : () async {
                    setState(() => _sending = true);
                    await ref
                        .read(commandsProvider)
                        .run(
                          'set the voice pack',
                          (c) => c.downloadVoicePack(
                            url: _url.text,
                            language: _language.text,
                            hash: _hash.text,
                          ),
                          invalidate: [voicePackProvider],
                        );
                    if (mounted) setState(() => _sending = false);
                  },
            child: _sending
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Set voice pack'),
          ),
        ],
      ),
    );
  }
}

class _DndCard extends ConsumerStatefulWidget {
  const _DndCard();

  @override
  ConsumerState<_DndCard> createState() => _DndCardState();
}

class _DndCardState extends ConsumerState<_DndCard> {
  DndConfiguration? _edit;
  DndConfiguration? _source;
  bool _saving = false;

  /// UTC hour/minute → local [TimeOfDay] using today's offset (like the web UI).
  static TimeOfDay _toLocal(int hour, int minute) {
    final now = DateTime.now().toUtc();
    final utc = DateTime.utc(
      now.year,
      now.month,
      now.day,
      hour,
      minute,
    ).toLocal();
    return TimeOfDay(hour: utc.hour, minute: utc.minute);
  }

  static (int, int) _toUtc(TimeOfDay local) {
    final now = DateTime.now();
    final t = DateTime(
      now.year,
      now.month,
      now.day,
      local.hour,
      local.minute,
    ).toUtc();
    return (t.hour, t.minute);
  }

  @override
  Widget build(BuildContext context) {
    final dnd = ref.watch(dndProvider);
    if (dnd.hasError && !dnd.hasValue) {
      return ValroveCard(
        child: InlineError(
          'Error loading DND configuration.',
          onRetry: () => ref.invalidate(dndProvider),
        ),
      );
    }
    final server = dnd.value;
    if (server != null && !identical(server, _source)) {
      _source = server;
      _edit = server;
    }
    final edit = _edit;
    if (edit == null) return const SkeletonCard(rows: 2);
    final start = _toLocal(edit.startHour, edit.startMinute);
    final end = _toLocal(edit.endHour, edit.endMinute);
    final dirty =
        server != null &&
        (server.enabled != edit.enabled ||
            server.startHour != edit.startHour ||
            server.startMinute != edit.startMinute ||
            server.endHour != edit.endHour ||
            server.endMinute != edit.endMinute);

    Future<void> pick(bool isStart) async {
      final picked = await showTimePicker(
        context: context,
        initialTime: isStart ? start : end,
      );
      if (picked == null) return;
      final (h, m) = _toUtc(picked);
      setState(() {
        _edit = DndConfiguration(
          enabled: edit.enabled,
          startHour: isStart ? h : edit.startHour,
          startMinute: isStart ? m : edit.startMinute,
          endHour: isStart ? edit.endHour : h,
          endMinute: isStart ? edit.endMinute : m,
        );
      });
    }

    return ValroveCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ToggleTile(
            title: 'Enabled',
            subtitle: 'Mute voice prompts and avoid automatic actions during quiet hours',
            icon: Icons.bedtime_rounded,
            iconColor: const Color(0xFFA78BFA),
            value: edit.enabled,
            onChanged: (v) => setState(
              () => _edit = DndConfiguration(
                enabled: v,
                startHour: edit.startHour,
                startMinute: edit.startMinute,
                endHour: edit.endHour,
                endMinute: edit.endMinute,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
            child: Row(
              children: [
                Expanded(
                  child: _TimeBox(
                    label: 'Start time',
                    time: start,
                    enabled: edit.enabled,
                    onTap: () => pick(true),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _TimeBox(
                    label: 'End time',
                    time: end,
                    enabled: edit.enabled,
                    onTap: () => pick(false),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
            child: Text(
              'UTC: ${timeOfDay(edit.startHour, edit.startMinute)} — ${timeOfDay(edit.endHour, edit.endMinute)}',
              style: context.text.bodySmall,
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: FilledButton(
              onPressed: !dirty || _saving
                  ? null
                  : () async {
                      setState(() => _saving = true);
                      await ref
                          .read(commandsProvider)
                          .run(
                            'save Do Not Disturb',
                            (c) => c.setDnd(edit),
                            invalidate: [dndProvider],
                            success: 'Do Not Disturb saved',
                          );
                      if (mounted) setState(() => _saving = false);
                    },
              child: _saving
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Text('Apply'),
            ),
          ),
        ],
      ),
    );
  }
}

class _TimeBox extends StatelessWidget {
  const _TimeBox({
    required this.label,
    required this.time,
    required this.enabled,
    required this.onTap,
  });

  final String label;
  final TimeOfDay time;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: enabled ? 1 : 0.45,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: enabled ? onTap : null,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: context.colors.textPrimary.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: context.text.labelSmall),
              const SizedBox(height: 4),
              Text(
                timeOfDay(time.hour, time.minute),
                style: context.text.headlineSmall?.copyWith(
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
