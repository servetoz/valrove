import '../../ui/room_kinds.dart';

/// Something the user asked for by voice (or a `valrove://command` link).
sealed class VoiceCommand {
  const VoiceCommand();
}

class CleanRoomsCommand extends VoiceCommand {
  const CleanRoomsCommand(this.roomIds, {this.iterations = 1});

  /// In the order they were said.
  final List<String> roomIds;
  final int iterations;
}

class CleanHomeCommand extends VoiceCommand {
  const CleanHomeCommand();
}

class RunPresetCommand extends VoiceCommand {
  const RunPresetCommand(this.presetId);

  final String presetId;
}

class DockCommand extends VoiceCommand {
  const DockCommand();
}

class PauseCommand extends VoiceCommand {
  const PauseCommand();
}

class ResumeCommand extends VoiceCommand {
  const ResumeCommand();
}

class StopCommand extends VoiceCommand {
  const StopCommand();
}

class LocateCommand extends VoiceCommand {
  const LocateCommand();
}

class UnknownCommand extends VoiceCommand {
  const UnknownCommand(this.text);

  final String text;
}

typedef Named = ({String id, String name});

const _numbers = {
  'one': '1', 'two': '2', 'three': '3', 'four': '4', 'five': '5', //
  'six': '6', 'seven': '7', 'eight': '8', 'nine': '9', 'ten': '10',
  'zwei': '2', 'drei': '3', 'vier': '4', 'funf': '5', 'sechs': '6',
  'sieben': '7', 'acht': '8', 'neun': '9', 'zehn': '10',
};

/// Lower case, no accents or punctuation, number words as digits, padded
/// with spaces so whole words can be found with `' word '`.
String normalizeSpeech(String text) {
  final words = RoomKind.fold(text)
      .replaceAll(RegExp(r"[^a-z0-9']+"), ' ')
      .replaceAll("'", '')
      .split(' ')
      .where((w) => w.isNotEmpty)
      .map((w) => _numbers[w] ?? w);
  return ' ${words.join(' ')} ';
}

bool _hasAny(String t, List<String> phrases) =>
    phrases.any((p) => t.contains(' $p '));

/// Understands commands such as "clean the kitchen and the hallway twice",
/// "start after dinner", "go back to the dock" or "pause" (English and
/// German). Rooms are matched by name, or by kind ("kitchen" finds a room
/// named "Küche").
VoiceCommand parseVoiceCommand(
  String text, {
  List<Named> rooms = const [],
  List<Named> presets = const [],
}) {
  final t = normalizeSpeech(text);
  if (t.trim().isEmpty) return UnknownCommand(text);

  // Presets by name, the longest first ("after dinner" before "after").
  final byLength = [...presets]
    ..sort((a, b) => b.name.length.compareTo(a.name.length));
  for (final p in byLength) {
    final name = normalizeSpeech(p.name).trim();
    if (name.isNotEmpty && t.contains(' $name ')) return RunPresetCommand(p.id);
  }

  if (_hasAny(t, [
    'where are you',
    'locate',
    'find yourself',
    'wo bist du',
    'finde dich',
  ])) {
    return const LocateCommand();
  }
  if (_hasAny(t, [
    'stop',
    'cancel',
    'abort',
    'stopp',
    'abbrechen',
    'beenden',
  ])) {
    return const StopCommand();
  }
  if (_hasAny(t, ['pause', 'hold on', 'wait', 'anhalten', 'warte'])) {
    return const PauseCommand();
  }
  if (_hasAny(t, [
    'resume',
    'continue',
    'carry on',
    'keep going',
    'weiter',
    'fortsetzen',
    'fortfahren',
  ])) {
    return const ResumeCommand();
  }
  if (_hasAny(t, [
    'everything',
    'everywhere',
    'whole home',
    'whole house',
    'whole flat',
    'whole apartment',
    'entire home',
    'entire house',
    'all rooms',
    'alles',
    'uberall',
    'ganze wohnung',
    'ganzes haus',
    'alle raume',
    'alle zimmer',
  ])) {
    return const CleanHomeCommand();
  }

  final found = _findRooms(t, rooms);
  if (found.isNotEmpty) {
    return CleanRoomsCommand(found, iterations: _iterations(t));
  }
  if (_hasAny(t, [
    'dock',
    'home',
    'base',
    'charge',
    'charger',
    'charging',
    'go back',
    'return',
    'ladestation',
    'zuruck',
    'heim',
    'nach hause',
    'basis',
    'laden',
  ])) {
    return const DockCommand();
  }
  if (_hasAny(t, [
    'clean',
    'cleaning',
    'vacuum',
    'mop',
    'hoover',
    'sweep',
    'start',
    'go',
    'saugen',
    'staubsaugen',
    'putzen',
    'wischen',
    'reinigen',
    'starte',
    'los',
  ])) {
    return const CleanHomeCommand();
  }
  return UnknownCommand(text);
}

int _iterations(String t) {
  if (_hasAny(t, ['twice', 'double', 'zweimal', 'doppelt'])) return 2;
  if (_hasAny(t, ['thrice', 'dreimal'])) return 3;
  final m = RegExp(r' (\d+) (times|mal|passes|durchgange) ').firstMatch(t);
  return m == null ? 1 : int.parse(m.group(1)!).clamp(1, 10);
}

/// Rooms of [rooms] that [text] mentions, by name or by kind, in the order
/// they were said.
List<String> findRoomsInText(String text, List<Named> rooms) =>
    _findRooms(normalizeSpeech(text), rooms);

/// Rooms mentioned in [t], in the order they were said.
List<String> _findRooms(String t, List<Named> rooms) {
  final spans = <({String id, int start, int end, RoomKind? kind})>[];
  final kinds = {for (final r in rooms) r.id: RoomKind.match(r.name)};
  for (final r in rooms) {
    final name = normalizeSpeech(r.name).trim();
    if (name.isEmpty) continue;
    final i = t.indexOf(' $name ');
    if (i >= 0) {
      spans.add((
        id: r.id,
        start: i + 1,
        end: i + 1 + name.length,
        kind: kinds[r.id],
      ));
    }
  }
  // By kind: "kitchen" for a room named "Küche", unless a room of that kind
  // was named exactly ("bedroom" with rooms "Bedroom" and "Guest bedroom").
  final words = t.trim().split(' ');
  final named = {for (final s in spans) s.id};
  final namedKinds = {for (final s in spans) ?s.kind};
  for (final r in rooms) {
    final kind = kinds[r.id];
    if (kind == null || named.contains(r.id) || namedKinds.contains(kind)) {
      continue;
    }
    var offset = 1;
    for (final w in words) {
      if (RoomKind.match(w) == kind) {
        spans.add((
          id: r.id,
          start: offset,
          end: offset + w.length,
          kind: kind,
        ));
        break;
      }
      offset += w.length + 1;
    }
  }
  // "Bedroom 2" also contains "Bedroom": keep the longer name only.
  final kept = [
    for (final s in spans)
      if (!spans.any(
        (o) =>
            o != s &&
            o.start <= s.start &&
            o.end >= s.end &&
            (o.end - o.start) > (s.end - s.start),
      ))
        s,
  ]..sort((a, b) => a.start.compareTo(b.start));
  return [for (final s in kept) s.id]
      .fold(<String>[], (out, id) => out.contains(id) ? out : (out..add(id)));
}
