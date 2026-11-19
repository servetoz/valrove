import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../ui/room_kinds.dart';
import 'app_state.dart';
import 'session.dart';

/// An icon picked on this phone for a room, valid while the room keeps the
/// name it was picked for (rooms get new ids and names when the map changes).
typedef RoomIconChoice = ({String name, String kind});

/// Icons picked for rooms, per robot. Valetudo has nowhere to store them.
class RoomIconChoices extends Notifier<Map<String, RoomIconChoice>> {
  String? get _key {
    final id = ref.read(activeProfileProvider)?.id;
    return id == null ? null : 'rooms.icons.$id';
  }

  @override
  Map<String, RoomIconChoice> build() {
    ref.watch(activeProfileProvider.select((p) => p?.id));
    final raw = _key == null
        ? null
        : ref.read(sharedPreferencesProvider).getString(_key!);
    if (raw == null) return const {};
    try {
      final json = jsonDecode(raw) as Map<String, dynamic>;
      return {
        for (final MapEntry(:key, :value) in json.entries)
          if (value case {'name': String name, 'kind': String kind})
            key: (name: name, kind: kind),
      };
    } catch (_) {
      return const {};
    }
  }

  /// Remembers [kind] for the room [segmentId] named [name]; null (or the
  /// kind the name already implies) goes back to recognising it by name.
  void set(String segmentId, {required String name, RoomKind? kind}) {
    final next = {...state};
    if (kind == null || kind == RoomKind.match(name)) {
      next.remove(segmentId);
    } else {
      next[segmentId] = (name: name.trim(), kind: kind.id);
    }
    state = next;
    final key = _key;
    if (key == null) return;
    ref
        .read(sharedPreferencesProvider)
        .setString(
          key,
          jsonEncode({
            for (final MapEntry(:key, :value) in next.entries)
              key: {'name': value.name, 'kind': value.kind},
          }),
        );
  }
}

final roomIconChoicesProvider =
    NotifierProvider<RoomIconChoices, Map<String, RoomIconChoice>>(
      RoomIconChoices.new,
    );

/// The icon picked for room [segmentId] with [name], if it still applies.
RoomKind? pickedRoomKind(
  Map<String, RoomIconChoice> choices,
  String segmentId,
  String? name,
) {
  final choice = choices[segmentId];
  if (choice == null || choice.name != (name ?? '').trim()) return null;
  return RoomKind.byId(choice.kind);
}

/// Kind of room [segmentId]: the picked icon, else recognised from [name].
RoomKind? roomKindOf(
  Map<String, RoomIconChoice> choices,
  String segmentId,
  String? name,
) => pickedRoomKind(choices, segmentId, name) ?? RoomKind.match(name);

/// Icons of the rooms on the live map that have a known kind.
final roomIconsProvider = Provider<Map<String, IconData>>((ref) {
  final segments =
      ref.watch(liveMapProvider.select((s) => s.scene?.data.segments)) ??
      const [];
  final choices = ref.watch(roomIconChoicesProvider);
  return {
    for (final s in segments)
      if (roomKindOf(choices, s.id, s.name) case final kind?) s.id: kind.icon,
  };
});
