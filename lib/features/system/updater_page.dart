import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/help_texts.dart';
import '../../core/valetudo/models/models.dart';
import '../../state/commands.dart';
import '../../state/data.dart';
import '../../ui/dialogs.dart';
import '../../ui/markdown.dart';
import '../../ui/theme.dart';
import '../../ui/widgets.dart';

class UpdaterPage extends ConsumerStatefulWidget {
  const UpdaterPage({super.key});

  @override
  ConsumerState<UpdaterPage> createState() => _UpdaterPageState();
}

class _UpdaterPageState extends ConsumerState<UpdaterPage> {
  bool _sending = false;

  Future<void> _send(String action) async {
    if (action == 'download') {
      final ok = await showConfirm(
        context,
        title: 'Download update?',
        message: 'Do you want to download the displayed Valetudo update?\nPlease make sure to fully read the provided changelog as it may contain breaking changes as well as other relevant information.',
        confirmLabel: 'Download',
      );
      if (!ok) return;
    } else if (action == 'apply') {
      final ok = await showConfirm(
        context,
        title: 'Apply update?',
        message: 'Do you want to apply the downloaded update? The robot may reboot during this procedure.',
        confirmLabel: 'Apply',
      );
      if (!ok) return;
    }
    setState(() => _sending = true);
    await ref
        .read(commandsProvider)
        .run(
          'send the updater command',
          (c) => c.updaterAction(action),
          invalidate: [updaterStateProvider],
        );
    if (mounted) setState(() => _sending = false);
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(updaterStateProvider);
    final provider = ref.watch(updateProviderProvider);
    return ValrovePage(
      title: 'Updater',
      subtitle: 'Keep Valetudo up to date',
      onRefresh: () async => ref.refresh(updaterStateProvider.future),
      actions: [
        IconButton(
          tooltip: 'Help',
          icon: const Icon(Icons.help_outline_rounded),
          onPressed: () => showMarkdownSheet(
            context,
            title: 'Updater',
            markdown: HelpTexts.updaterHelp,
          ),
        ),
      ],
      children: [
        if (!state.hasValue)
          state.hasError
              ? ErrorState(
                  message: 'Error loading updater state',
                  onRetry: () => ref.invalidate(updaterStateProvider),
                )
              : const SkeletonCard(rows: 3)
        else
          _StateCard(
            state: state.value!,
            sending: _sending,
            onAction: _send,
            stale: state.hasError,
          ),
        const SectionLabel('Update channel'),
        TileGroup(
          children: [
            ValroveTile(
              title: 'Channel',
              subtitle: 'Select the channel used by the inbuilt updater',
              icon: Icons.system_update_alt_rounded,
              trailing: provider.when(
                data: (p) => SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: 'github', label: Text('Release')),
                    ButtonSegment(
                      value: 'github_nightly',
                      label: Text('Nightly'),
                    ),
                  ],
                  selected: {p},
                  showSelectedIcon: false,
                  onSelectionChanged: (s) => ref
                      .read(commandsProvider)
                      .run(
                        'change the update channel',
                        (c) => c.setUpdateProvider(s.first),
                        invalidate: [updateProviderProvider],
                      ),
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
      ],
    );
  }
}

class _StateCard extends StatelessWidget {
  const _StateCard({
    required this.state,
    required this.sending,
    required this.onAction,
    required this.stale,
  });

  final UpdaterState state;
  final bool sending;
  final bool stale;
  final ValueChanged<String> onAction;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final busy =
        state.busy && state.className != 'ValetudoUpdaterDownloadingState';
    IconData icon;
    Color color;
    Widget body;
    String? action;
    String? actionLabel;

    switch (state.className) {
      case 'ValetudoUpdaterIdleState':
        icon = Icons.info_rounded;
        color = c.info;
        body = Text(
          'You are currently running Valetudo ${state.currentVersion ?? '?'}.\nThere may be newer versions of Valetudo available.',
          textAlign: TextAlign.center,
          style: context.text.bodyMedium?.copyWith(color: c.textPrimary),
        );
        action = 'check';
        actionLabel = 'Check for updates';
      case 'ValetudoUpdaterErrorState':
        icon = Icons.warning_rounded;
        color = c.danger;
        body = Text(
          state.message ?? 'Unknown error',
          textAlign: TextAlign.center,
          style: context.text.bodyMedium?.copyWith(color: c.danger),
        );
        action = 'check';
        actionLabel = 'Check for updates';
      case 'ValetudoUpdaterNoUpdateRequiredState':
        icon = Icons.check_circle_rounded;
        color = c.success;
        body = Column(
          children: [
            Text(
              'You are already running the latest version of Valetudo (${state.currentVersion ?? '?'})',
              textAlign: TextAlign.center,
              style: context.text.bodyMedium?.copyWith(color: c.textPrimary),
            ),
            if (state.changelog?.isNotEmpty == true)
              _Changelog(
                title: 'Changelog for Valetudo ${state.currentVersion}',
                markdown: state.changelog!,
                initiallyExpanded: false,
              ),
          ],
        );
        action = 'check';
        actionLabel = 'Check for updates';
      case 'ValetudoUpdaterApprovalPendingState':
        icon = Icons.pending_actions_rounded;
        color = c.warning;
        body = _Changelog(
          title: 'Changelog for Valetudo ${state.version ?? ''}',
          markdown: state.changelog ?? '',
          initiallyExpanded: true,
        );
        action = 'download';
        actionLabel = 'Download update';
      case 'ValetudoUpdaterDownloadingState':
        icon = Icons.download_rounded;
        color = c.info;
        body = Column(
          children: [
            Text(
              'The updater is currently downloading version',
              style: context.text.bodyMedium?.copyWith(color: c.textPrimary),
            ),
            const SizedBox(height: 4),
            Text(
              state.version ?? '?',
              style: const TextStyle(fontFamily: AppTheme.monoFamily),
            ),
            const SizedBox(height: 14),
            ProgressTrack(
              value: state.progress == null ? null : state.progress! / 100,
            ),
          ],
        );
      case 'ValetudoUpdaterApplyPendingState':
        icon = Icons.restart_alt_rounded;
        color = c.success;
        body = Column(
          children: [
            Text(
              'Successfully downloaded ${state.version ?? ''}',
              style: context.text.titleSmall,
            ),
            if (!state.busy) ...[
              const SizedBox(height: 10),
              Text(
                "Please keep in mind that each update can require troubleshooting post-update.\nMake sure that you've thoroughly read the changelog to be aware of possible breaking changes.",
                textAlign: TextAlign.center,
                style: context.text.bodySmall?.copyWith(color: c.danger),
              ),
            ],
          ],
        );
        action = 'apply';
        actionLabel = 'Apply update';
      case 'ValetudoUpdaterDisabledState':
        icon = Icons.update_disabled_rounded;
        color = c.textTertiary;
        body = Text(
          'The updater was disabled in the Valetudo config.',
          style: context.text.bodyMedium,
        );
      default:
        icon = Icons.help_rounded;
        color = c.textTertiary;
        body = Text(state.className, style: context.text.bodyMedium);
    }
    if (busy) {
      icon = Icons.hourglass_top_rounded;
      color = c.info;
      body = Text(
        'The updater is currently busy',
        style: context.text.bodyMedium?.copyWith(color: c.textPrimary),
      );
    }

    return ValroveCard(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          TileIcon(icon, color: color, size: 56),
          const SizedBox(height: 14),
          if (stale)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                'Error loading updater state',
                style: context.text.bodySmall?.copyWith(color: c.danger),
              ),
            ),
          body,
          if (action != null) ...[
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: state.busy || sending
                    ? null
                    : () => onAction(action!),
                child: sending
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : Text(actionLabel!),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _Changelog extends StatelessWidget {
  const _Changelog({
    required this.title,
    required this.markdown,
    required this.initiallyExpanded,
  });

  final String title;
  final String markdown;
  final bool initiallyExpanded;

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        initiallyExpanded: initiallyExpanded,
        tilePadding: EdgeInsets.zero,
        title: Text(title, style: context.text.titleSmall),
        childrenPadding: const EdgeInsets.only(bottom: 8),
        children: [MarkdownText(markdown, selectable: true)],
      ),
    );
  }
}
