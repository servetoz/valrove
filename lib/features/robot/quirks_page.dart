import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/help_texts.dart';
import '../../core/valetudo/models/models.dart';
import '../../state/commands.dart';
import '../../state/data.dart';
import '../../ui/dialogs.dart';
import '../../ui/theme.dart';
import '../../ui/widgets.dart';

class QuirksPage extends ConsumerWidget {
  const QuirksPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final quirks = ref.watch(quirksProvider);
    return ValrovePage(
      title: 'Quirks',
      subtitle: 'Firmware-specific tweaks',
      onRefresh: () async => ref.refresh(quirksProvider.future),
      actions: [
        IconButton(
          tooltip: 'Help',
          icon: const Icon(Icons.help_outline_rounded),
          onPressed: () => showMarkdownSheet(
            context,
            title: 'Quirks',
            markdown: HelpTexts.quirksHelp,
          ),
        ),
      ],
      children: [
        ...quirks.when(
          data: (list) {
            if (list.isEmpty) {
              return [
                const EmptyState(
                  icon: Icons.star_outline_rounded,
                  title: 'No quirks',
                  message: 'You might want to reload.',
                ),
              ];
            }
            final sorted = [...list]
              ..sort(
                (a, b) =>
                    a.title.toLowerCase().compareTo(b.title.toLowerCase()),
              );
            return [
              for (final q in sorted) ...[
                _QuirkCard(quirk: q),
                const SizedBox(height: 12),
              ],
            ];
          },
          loading: () => [
            const SkeletonCard(rows: 2),
            const SizedBox(height: 12),
            const SkeletonCard(rows: 2),
          ],
          error: (e, _) => [
            ErrorState(
              message: 'Error loading quirks.',
              onRetry: () => ref.invalidate(quirksProvider),
            ),
          ],
        ),
      ],
    );
  }
}

class _QuirkCard extends ConsumerStatefulWidget {
  const _QuirkCard({required this.quirk});

  final Quirk quirk;

  @override
  ConsumerState<_QuirkCard> createState() => _QuirkCardState();
}

class _QuirkCardState extends ConsumerState<_QuirkCard> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final q = widget.quirk;
    return ValroveCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(q.title, style: context.text.titleMedium),
          const SizedBox(height: 6),
          Text(q.description, style: context.text.bodyMedium),
          const SizedBox(height: 14),
          InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: _busy
                ? null
                : () async {
                    final picked = await showChoiceSheet<String>(
                      context,
                      title: q.title,
                      selected: q.value,
                      options: [for (final o in q.options) ChoiceOption(o, o)],
                    );
                    if (picked == null || picked == q.value || !mounted) return;
                    setState(() => _busy = true);
                    await ref
                        .read(commandsProvider)
                        .run(
                          'change the quirk',
                          (c) => c.setQuirk(q.id, picked),
                          invalidate: [quirksProvider],
                        );
                    try {
                      await ref.read(quirksProvider.future);
                    } catch (_) {}
                    if (mounted) setState(() => _busy = false);
                  },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: context.colors.textPrimary.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      q.value,
                      style: context.text.titleSmall?.copyWith(
                        color: context.scheme.primary,
                      ),
                    ),
                  ),
                  if (_busy)
                    const SizedBox.square(
                      dimension: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  else
                    Icon(
                      Icons.unfold_more_rounded,
                      color: context.colors.textTertiary,
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
