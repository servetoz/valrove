import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/util/format.dart';
import '../../core/valetudo/json_utils.dart';
import '../../state/commands.dart';
import '../../state/data.dart';
import '../../ui/dialogs.dart';
import '../../ui/theme.dart';
import '../../ui/widgets.dart';

/// Switch bound to a `SimpleToggleCapability`.
class CapabilityToggleTile extends ConsumerStatefulWidget {
  const CapabilityToggleTile({
    super.key,
    required this.capability,
    required this.title,
    this.subtitle,
    required this.icon,
    this.iconColor,
  });

  final String capability;
  final String title;
  final String? subtitle;
  final IconData icon;
  final Color? iconColor;

  @override
  ConsumerState<CapabilityToggleTile> createState() =>
      _CapabilityToggleTileState();
}

class _CapabilityToggleTileState extends ConsumerState<CapabilityToggleTile> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final value = ref.watch(toggleProvider(widget.capability));
    return ToggleTile(
      title: widget.title,
      subtitle: widget.subtitle,
      icon: widget.icon,
      iconColor: widget.iconColor,
      value: value.value,
      error: value.hasError && !value.hasValue,
      busy: _busy || (value.isLoading && !value.hasValue),
      onChanged: (enabled) async {
        setState(() => _busy = true);
        await ref
            .read(commandsProvider)
            .run(
              'change ${widget.title.toLowerCase()}',
              (c) => c.setToggle(widget.capability, enabled),
              invalidate: [toggleProvider(widget.capability)],
              haptic: HapticKind.selection,
            );
        // Wait for the refetch so the switch shows the confirmed value.
        try {
          await ref.read(toggleProvider(widget.capability).future);
        } catch (_) {}
        if (mounted) setState(() => _busy = false);
      },
    );
  }
}

/// Option picker bound to a single-value capability (e.g. `{mode: "lift"}`).
class CapabilitySelectTile extends ConsumerStatefulWidget {
  const CapabilitySelectTile({
    super.key,
    required this.capability,
    required this.valueKey,
    required this.propertiesKey,
    required this.title,
    this.subtitle,
    this.subtitleBuilder,
    required this.icon,
    this.iconColor,
  });

  final String capability;

  /// Key of the value in the GET/PUT payload (`mode`, `interval`, …).
  final String valueKey;

  /// Key of the supported values list in `/properties`.
  final String propertiesKey;
  final String title;
  final String? subtitle;
  final String Function(Json properties)? subtitleBuilder;
  final IconData icon;
  final Color? iconColor;

  @override
  ConsumerState<CapabilitySelectTile> createState() =>
      _CapabilitySelectTileState();
}

class _CapabilitySelectTileState extends ConsumerState<CapabilitySelectTile> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final props = ref.watch(capabilityPropertiesProvider(widget.capability));
    final value = ref.watch(
      valueProvider((widget.capability, widget.valueKey)),
    );
    final options = props
        .whenData(
          (p) => optionsFor(
            widget.capability,
            asStringList(p[widget.propertiesKey]),
          ),
        )
        .value;
    final current = value.value;
    final subtitle = props.hasValue && widget.subtitleBuilder != null
        ? widget.subtitleBuilder!(props.value!)
        : widget.subtitle;

    Widget trailing;
    if (props.hasError) {
      trailing = Text(
        'Error',
        style: context.text.labelMedium?.copyWith(color: context.colors.danger),
      );
    } else if (options == null ||
        (!value.hasValue && value.isLoading) ||
        _busy) {
      trailing = const SizedBox.square(
        dimension: 18,
        child: CircularProgressIndicator(strokeWidth: 2),
      );
    } else {
      trailing = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 120),
            child: Text(
              current == null ? '—' : optionLabel(widget.capability, current),
              style: context.text.labelLarge?.copyWith(
                color: context.scheme.primary,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 2),
          Icon(
            Icons.unfold_more_rounded,
            size: 18,
            color: context.colors.textTertiary,
          ),
        ],
      );
    }

    return ValroveTile(
      title: widget.title,
      subtitle: subtitle,
      icon: widget.icon,
      iconColor: widget.iconColor,
      trailing: trailing,
      onTap: options == null || _busy || value.hasError
          ? null
          : () async {
              final picked = await showChoiceSheet<String>(
                context,
                title: widget.title,
                subtitle: subtitle,
                selected: current,
                options: [
                  for (final (v, label) in options) ChoiceOption(v, label),
                ],
              );
              if (picked == null || picked == current || !mounted) return;
              setState(() => _busy = true);
              await ref
                  .read(commandsProvider)
                  .run(
                    'change ${widget.title.toLowerCase()}',
                    (c) =>
                        c.setValue(widget.capability, widget.valueKey, picked),
                    invalidate: [
                      valueProvider((widget.capability, widget.valueKey)),
                    ],
                    haptic: HapticKind.selection,
                  );
              try {
                await ref.read(
                  valueProvider((widget.capability, widget.valueKey)).future,
                );
              } catch (_) {}
              if (mounted) setState(() => _busy = false);
            },
    );
  }
}
