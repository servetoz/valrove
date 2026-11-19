import 'package:material_ui/material_ui.dart';

import 'markdown.dart';
import 'theme.dart';
import 'haptics.dart';

/// Shows a styled modal bottom sheet with a grab handle.
Future<T?> showValroveSheet<T>(
  BuildContext context, {
  required WidgetBuilder builder,
  bool scrollControlled = true,
  bool dismissible = true,
}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: scrollControlled,
    isDismissible: dismissible,
    enableDrag: dismissible,
    useSafeArea: true,
    builder: (context) => _SheetFrame(child: builder(context)),
  );
}

class _SheetFrame extends StatelessWidget {
  const _SheetFrame({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 10),
          Container(
            width: 38,
            height: 5,
            decoration: BoxDecoration(
              color: context.colors.textTertiary.withValues(alpha: 0.4),
              borderRadius: BorderRadius.circular(3),
            ),
          ),
          Flexible(child: child),
        ],
      ),
    );
  }
}

/// Header used at the top of sheets.
class SheetHeader extends StatelessWidget {
  const SheetHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.trailing,
  });

  final String title;
  final String? subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 16, 14, 8),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: context.text.headlineSmall),
                if (subtitle != null) ...[
                  const SizedBox(height: 4),
                  Text(subtitle!, style: context.text.bodyMedium),
                ],
              ],
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}

/// Asks the user to confirm an action. Resolves to true when confirmed.
Future<bool> showConfirm(
  BuildContext context, {
  required String title,
  String? message,
  String confirmLabel = 'Confirm',
  String cancelLabel = 'Cancel',
  bool destructive = false,
  Widget? content,
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (context) {
      final c = context.colors;
      return AlertDialog(
        title: Text(title),
        content:
            content ??
            (message == null
                ? null
                : Text(message, style: context.text.bodyMedium)),
        actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(cancelLabel),
          ),
          FilledButton(
            autofocus: true,
            style: destructive
                ? FilledButton.styleFrom(
                    backgroundColor: c.danger,
                    foregroundColor: Colors.white,
                  )
                : null,
            onPressed: () {
              Haptics.medium();
              Navigator.pop(context, true);
            },
            child: Text(confirmLabel),
          ),
        ],
      );
    },
  );
  return result ?? false;
}

/// Asks for a single line of text.
Future<String?> showTextPrompt(
  BuildContext context, {
  required String title,
  String? description,
  String? initial,
  String? label,
  String? hint,
  String confirmLabel = 'Save',
  bool obscure = false,
  TextInputType? keyboardType,
  String? Function(String)? validator,
  String Function(String)? transform,
}) {
  return showDialog<String>(
    context: context,
    builder: (context) => _TextPromptDialog(
      title: title,
      description: description,
      initial: initial,
      label: label,
      hint: hint,
      confirmLabel: confirmLabel,
      obscure: obscure,
      keyboardType: keyboardType,
      validator: validator,
      transform: transform,
    ),
  );
}

class _TextPromptDialog extends StatefulWidget {
  const _TextPromptDialog({
    required this.title,
    this.description,
    this.initial,
    this.label,
    this.hint,
    required this.confirmLabel,
    required this.obscure,
    this.keyboardType,
    this.validator,
    this.transform,
  });

  final String title;
  final String? description;
  final String? initial;
  final String? label;
  final String? hint;
  final String confirmLabel;
  final bool obscure;
  final TextInputType? keyboardType;
  final String? Function(String)? validator;
  final String Function(String)? transform;

  @override
  State<_TextPromptDialog> createState() => _TextPromptDialogState();
}

class _TextPromptDialogState extends State<_TextPromptDialog> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initial ?? '',
  );
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final value = _controller.text;
    final error = widget.validator?.call(value);
    if (error != null) {
      setState(() => _error = error);
      return;
    }
    Navigator.pop(context, value);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (widget.description != null) ...[
            Text(widget.description!, style: context.text.bodyMedium),
            const SizedBox(height: 16),
          ],
          TextField(
            controller: _controller,
            autofocus: true,
            obscureText: widget.obscure,
            keyboardType: widget.keyboardType,
            decoration: InputDecoration(
              labelText: widget.label,
              hintText: widget.hint,
              errorText: _error,
            ),
            onChanged: (v) {
              if (widget.transform != null) {
                final next = widget.transform!(v);
                if (next != v) {
                  _controller.value = TextEditingValue(
                    text: next,
                    selection: TextSelection.collapsed(offset: next.length),
                  );
                }
              }
              if (_error != null) setState(() => _error = null);
            },
            onSubmitted: (_) => _submit(),
          ),
        ],
      ),
      actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _submit, child: Text(widget.confirmLabel)),
      ],
    );
  }
}

class ChoiceOption<T> {
  const ChoiceOption(this.value, this.label, {this.subtitle, this.icon});

  final T value;
  final String label;
  final String? subtitle;
  final IconData? icon;
}

/// Lets the user pick one option from a sheet.
Future<T?> showChoiceSheet<T>(
  BuildContext context, {
  required String title,
  String? subtitle,
  required List<ChoiceOption<T>> options,
  T? selected,
}) {
  return showValroveSheet<T>(
    context,
    builder: (context) => SafeArea(
      top: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SheetHeader(title: title, subtitle: subtitle),
          Flexible(
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 16),
              children: [
                for (final o in options)
                  _ChoiceRow(
                    label: o.label,
                    subtitle: o.subtitle,
                    icon: o.icon,
                    selected: o.value == selected,
                    onTap: () => Navigator.pop(context, o.value),
                  ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

class _ChoiceRow extends StatelessWidget {
  const _ChoiceRow({
    required this.label,
    this.subtitle,
    this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final String? subtitle;
  final IconData? icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final primary = context.scheme.primary;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Material(
        color: selected
            ? primary.withValues(alpha: context.isDark ? 0.18 : 0.10)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () {
            Haptics.selection();
            onTap();
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                if (icon != null) ...[
                  Icon(
                    icon,
                    color: selected ? primary : context.colors.textSecondary,
                  ),
                  const SizedBox(width: 14),
                ],
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        label,
                        style: context.text.titleSmall?.copyWith(
                          color: selected ? primary : null,
                        ),
                      ),
                      if (subtitle != null) ...[
                        const SizedBox(height: 2),
                        Text(subtitle!, style: context.text.bodySmall),
                      ],
                    ],
                  ),
                ),
                AnimatedScale(
                  scale: selected ? 1 : 0,
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeOutBack,
                  child: Icon(Icons.check_circle_rounded, color: primary),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Shows a Markdown help/info text in a sheet.
Future<void> showMarkdownSheet(
  BuildContext context, {
  required String title,
  required String markdown,
}) {
  return showValroveSheet<void>(
    context,
    builder: (context) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.75,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      builder: (context, controller) => ListView(
        controller: controller,
        padding: EdgeInsets.fromLTRB(
          22,
          12,
          22,
          24 + MediaQuery.paddingOf(context).bottom,
        ),
        children: [
          Text(title, style: context.text.headlineSmall),
          const SizedBox(height: 14),
          MarkdownText(markdown),
        ],
      ),
    ),
  );
}
