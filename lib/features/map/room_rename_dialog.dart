import 'package:material_ui/material_ui.dart';

import '../../ui/room_kinds.dart';
import '../../ui/theme.dart';
import '../../ui/haptics.dart';

/// New name of a room, and the icon picked for it (null: recognised from the
/// name).
typedef RoomRename = ({String name, RoomKind? kind});

/// Asks for a room's name, suggesting common ones, and lets the user pick
/// the room's icon.
Future<RoomRename?> showRoomRenameDialog(
  BuildContext context, {
  required String roomLabel,
  required String currentName,
  RoomKind? pickedKind,
  Iterable<String> takenNames = const [],
}) => showDialog<RoomRename>(
  context: context,
  builder: (_) => RoomRenameDialog(
    roomLabel: roomLabel,
    currentName: currentName,
    pickedKind: pickedKind,
    takenNames: takenNames.toList(),
  ),
);

class RoomRenameDialog extends StatefulWidget {
  const RoomRenameDialog({
    super.key,
    required this.roomLabel,
    required this.currentName,
    this.pickedKind,
    this.takenNames = const [],
  });

  /// How the room is shown now ("Room 4" for unnamed rooms).
  final String roomLabel;
  final String currentName;

  /// Icon picked for the room before, if any.
  final RoomKind? pickedKind;

  /// Names of the other rooms; suggestions avoid them.
  final List<String> takenNames;

  @override
  State<RoomRenameDialog> createState() => _RoomRenameDialogState();
}

class _RoomRenameDialogState extends State<RoomRenameDialog> {
  late final _controller = TextEditingController(text: widget.currentName);
  late RoomKind? _picked = widget.pickedKind;

  /// What the user typed; suggestions are narrowed to it.
  String _query = '';

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _suggest(RoomSuggestion s) {
    Haptics.selection();
    setState(() {
      _controller.value = TextEditingValue(
        text: s.name,
        selection: TextSelection.collapsed(offset: s.name.length),
      );
      _picked = null;
      _query = '';
    });
  }

  void _pick(RoomKind? kind) {
    Haptics.selection();
    setState(() => _picked = kind);
  }

  void _submit() =>
      Navigator.pop(context, (name: _controller.text.trim(), kind: _picked));

  @override
  Widget build(BuildContext context) {
    final text = _controller.text.trim();
    final recognised = RoomKind.match(text);
    final icon = (_picked ?? recognised)?.icon ?? RoomKind.genericIcon;
    final suggestions = [
      for (final s in roomNameSuggestions(
        takenNames: widget.takenNames,
        query: _query,
      ))
        if (s.name != text) s,
    ];
    final label = context.text.labelSmall;
    return AlertDialog(
      title: const Text('Rename room'),
      content: SizedBox(
        width: double.maxFinite,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                "How should '${widget.roomLabel}' be called?",
                style: context.text.bodyMedium,
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _controller,
                autofocus: true,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(
                  labelText: 'Room name',
                  prefixIcon: Icon(icon),
                ),
                onChanged: (v) => setState(() => _query = v),
                onSubmitted: (_) => _submit(),
              ),
              if (suggestions.isNotEmpty) ...[
                const SizedBox(height: 18),
                Text('SUGGESTIONS', style: label),
                const SizedBox(height: 8),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 148),
                  child: SingleChildScrollView(
                    child: Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        for (final s in suggestions)
                          ActionChip(
                            avatar: Icon(s.kind.icon, size: 18),
                            label: Text(s.name),
                            onPressed: () => _suggest(s),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 18),
              Row(
                children: [
                  Text('ICON', style: label),
                  const Spacer(),
                  Text(
                    _picked?.label ??
                        (recognised == null
                            ? 'None recognised'
                            : 'From the name: ${recognised.label}'),
                    style: context.text.bodySmall,
                  ),
                ],
              ),
              const SizedBox(height: 8),
              SizedBox(
                height: 44,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: [
                    _IconChoice(
                      icon: Icons.auto_awesome_rounded,
                      tooltip: 'From the name',
                      selected: _picked == null,
                      onTap: () => _pick(null),
                    ),
                    for (final kind in RoomKind.all)
                      _IconChoice(
                        icon: kind.icon,
                        tooltip: kind.label,
                        selected: _picked == kind,
                        onTap: () => _pick(kind),
                      ),
                  ],
                ),
              ),
              if (_picked != null) ...[
                const SizedBox(height: 8),
                Text(
                  'Picked icons are kept on this phone; Valetudo only stores '
                  'the name.',
                  style: context.text.bodySmall,
                ),
              ],
            ],
          ),
        ),
      ),
      actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Rename')),
      ],
    );
  }
}

class _IconChoice extends StatelessWidget {
  const _IconChoice({
    required this.icon,
    required this.tooltip,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = context.scheme;
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: Tooltip(
        message: tooltip,
        child: Semantics(
          button: true,
          selected: selected,
          label: tooltip,
          child: Material(
            color: selected
                ? scheme.primary
                : context.colors.textPrimary.withValues(alpha: 0.07),
            shape: const CircleBorder(),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: onTap,
              child: SizedBox.square(
                dimension: 44,
                child: Icon(
                  icon,
                  size: 22,
                  color: selected ? Colors.white : context.colors.textPrimary,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
