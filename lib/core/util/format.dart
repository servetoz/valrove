/// Human-readable formatting shared by all screens.
library;

String _two(num n) => n.toInt().toString().padLeft(2, '0');

/// `1d 02h 03m 04s` / `26h 03m` (Valetudo's `convertSecondsToHumans`).
String secondsToHuman(
  double seconds, {
  bool showSeconds = true,
  bool showDays = true,
}) {
  final total = seconds.isFinite ? seconds.floor() : 0;
  final s = total % 60;
  final m = (total ~/ 60) % 60;
  if (showDays) {
    final d = total ~/ 86400;
    final h = (total ~/ 3600) % 24;
    return '${d}d ${_two(h)}h ${_two(m)}m${showSeconds ? ' ${_two(s)}s' : ''}';
  }
  final h = total ~/ 3600;
  return '${_two(h)}h ${_two(m)}m${showSeconds ? ' ${_two(s)}s' : ''}';
}

/// Compact duration such as `1 h 05 min` or `42 min`.
String compactDuration(double seconds) {
  final total = seconds.isFinite ? seconds.round() : 0;
  final h = total ~/ 3600;
  final m = (total ~/ 60) % 60;
  if (h >= 24) {
    final d = h ~/ 24;
    return '$d d ${h % 24} h';
  }
  if (h > 0) return '$h h ${_two(m)} min';
  if (total >= 60) return '$m min';
  return '$total s';
}

/// Area from cm² to `12.5 m²`.
String areaFromCm2(double cm2, {int decimals = 1}) =>
    '${(cm2 / 10000).toStringAsFixed(decimals)} m²';

String bytesToHuman(num bytes) {
  const k = 1024;
  if (bytes >= k * k * k) {
    return '${(bytes / (k * k * k)).toStringAsFixed(2)} GiB';
  }
  if (bytes >= k * k) return '${(bytes / (k * k)).toStringAsFixed(2)} MiB';
  if (bytes >= k) return '${(bytes / k).toStringAsFixed(2)} KiB';
  return '$bytes bytes';
}

/// `YYYY-MM-DD HH:mm:ss` in local time.
String dateTime(DateTime t) {
  final l = t.toLocal();
  return '${l.year}-${_two(l.month)}-${_two(l.day)} ${_two(l.hour)}:${_two(l.minute)}:${_two(l.second)}';
}

String timeOfDay(int hour, int minute) => '${_two(hour)}:${_two(minute)}';

String relativeTime(DateTime t, {DateTime? now}) {
  final diff = (now ?? DateTime.now()).difference(t);
  if (diff.isNegative) return 'In the future';
  if (diff.inSeconds < 60) return 'Just now';
  if (diff.inMinutes < 60) {
    return '${diff.inMinutes} ${diff.inMinutes == 1 ? 'minute' : 'minutes'} ago';
  }
  if (diff.inHours < 24) {
    return '${diff.inHours} ${diff.inHours == 1 ? 'hour' : 'hours'} ago';
  }
  return dateTime(t);
}

/// "today at 14:05", "yesterday", "3 days ago".
String lastCleanedLabel(DateTime t, {DateTime? now}) {
  final n = now ?? DateTime.now();
  final days = DateTime(
    n.year,
    n.month,
    n.day,
  ).difference(DateTime(t.year, t.month, t.day)).inDays;
  return switch (days) {
    <= 0 => 'today at ${timeOfDay(t.hour, t.minute)}',
    1 => 'yesterday',
    _ => '$days days ago',
  };
}

String romanNumeral(int n) {
  const values = [
    (90, 'XC'),
    (50, 'L'),
    (40, 'XL'),
    (10, 'X'),
    (9, 'IX'),
    (5, 'V'),
    (4, 'IV'),
    (1, 'I'),
  ];
  var rest = n;
  final out = StringBuffer();
  for (final (v, s) in values) {
    while (rest >= v) {
      out.write(s);
      rest -= v;
    }
  }
  return out.toString();
}

String capitalize(String s) =>
    s.isEmpty ? s : '${s[0].toUpperCase()}${s.substring(1)}';

/// `vacuum_and_mop` → `Vacuum and mop`.
String humanize(String raw) => capitalize(raw.replaceAll('_', ' '));

// ---------------------------------------------------------------------------
// Robot vocabulary
// ---------------------------------------------------------------------------

String statusLabel(String value) => switch (value) {
  'error' => 'Error',
  'docked' => 'Docked',
  'idle' => 'Idle',
  'returning' => 'Returning to dock',
  'cleaning' => 'Cleaning',
  'paused' => 'Paused',
  'manual_control' => 'Manual control',
  'moving' => 'Moving',
  _ => humanize(value),
};

String? flagLabel(String flag) => switch (flag) {
  'none' => null,
  'zone' => 'Zones',
  'segment' => 'Rooms',
  'spot' => 'Spot',
  'target' => 'Go to target',
  'resumable' => 'Resumable',
  'mapping' => 'Mapping',
  _ => humanize(flag),
};

String presetLabel(String value) => switch (value) {
  'off' => 'Off',
  'min' => 'Min',
  'low' => 'Low',
  'medium' => 'Medium',
  'high' => 'High',
  'max' => 'Max',
  'turbo' => 'Turbo',
  'custom' => 'Custom',
  'vacuum_and_mop' => 'Vacuum & Mop',
  'vacuum_then_mop' => 'Vacuum then Mop',
  'vacuum' => 'Vacuum',
  'mop' => 'Mop',
  _ => humanize(value),
};

String dockStatusLabel(String value) => switch (value) {
  'idle' => 'Idle',
  'pause' => 'Paused',
  'emptying' => 'Emptying',
  'cleaning' => 'Washing mops',
  'drying' => 'Drying mops',
  'error' => 'Error',
  _ => humanize(value),
};

String dockComponentLabel(String type) => switch (type) {
  'water_tank_clean' => 'Freshwater',
  'water_tank_dirty' => 'Wastewater',
  'detergent' => 'Detergent',
  'dustbag' => 'Dustbag',
  _ => 'Unknown',
};

String dockComponentStateLabel(String value) => switch (value) {
  'ok' => 'OK',
  'empty' => 'Empty',
  'full' => 'Full',
  'missing' => 'Missing',
  _ => 'Unknown',
};

String attachmentLabel(String type) => switch (type) {
  'dustbin' => 'Dustbin',
  'watertank' => 'Water tank',
  'mop' => 'Mop',
  _ => humanize(type),
};

const _consumableTypes = {
  'brush': 'Brush',
  'filter': 'Filter',
  'cleaning': 'Cleaning',
  'mop': 'Mop',
  'detergent': 'Detergent',
  'bin': 'Bin',
};

const _consumableSubTypes = {
  'main': 'Main',
  'secondary': 'Secondary',
  'side_right': 'Right',
  'side_left': 'Left',
  'dock': 'Dock',
  'sensor': 'Sensor',
  'wheel': 'Wheel',
  'all': '',
  'none': '',
};

/// `brush/side_left` → `Left Brush` (Valetudo's `getConsumableName`).
String consumableName(String type, String? subType) {
  final parts = <String>[];
  final sub = subType == null ? null : _consumableSubTypes[subType];
  if (sub != null && sub.isNotEmpty) parts.add(sub);
  final t = _consumableTypes[type];
  if (t != null) parts.add(t);
  final name = parts.join(' ').trim();
  return name.isEmpty ? 'Unknown consumable: $type, $subType' : name;
}

// ---------------------------------------------------------------------------
// Capability option labels
// ---------------------------------------------------------------------------

/// Display order and labels of select-style capabilities.
const capabilityOptionLabels = <String, List<(String, String)>>{
  'CarpetSensorModeControlCapability': [
    ('lift', 'Lift Mop'),
    ('avoid', 'Avoid Carpet'),
    ('detach', 'Detach Mop'),
    ('off', 'None'),
  ],
  'AutoEmptyDockAutoEmptyIntervalControlCapability': [
    ('frequent', 'Frequent'),
    ('normal', 'Normal'),
    ('infrequent', 'Infrequent'),
    ('off', 'Off'),
  ],
  'AutoEmptyDockAutoEmptyDurationControlCapability': [
    ('auto', 'Auto'),
    ('short', 'Short'),
    ('medium', 'Medium'),
    ('long', 'Long'),
  ],
  'MopDockMopWashTemperatureControlCapability': [
    ('cold', 'Cold'),
    ('warm', 'Warm'),
    ('hot', 'Hot'),
    ('scalding', 'Scalding'),
    ('boiling', 'Boiling'),
  ],
  'CleanRouteControlCapability': [
    ('quick', 'Quick'),
    ('normal', 'Normal'),
    ('intensive', 'Intensive'),
    ('deep', 'Deep'),
  ],
  'MopDockMopDryingTimeControlCapability': [
    ('2h', '2 Hours'),
    ('3h', '3 Hours'),
    ('4h', '4 Hours'),
    ('5h', '5 Hours'),
    ('quiet', 'Quiet'),
    ('cold', 'Cold'),
  ],
};

/// Sorts [supported] in the canonical order and attaches labels.
List<(String, String)> optionsFor(String capability, List<String> supported) {
  final known = capabilityOptionLabels[capability] ?? const [];
  int rank(String v) {
    final i = known.indexWhere((e) => e.$1 == v);
    return i < 0 ? 10 : i;
  }

  final sorted = [...supported]..sort((a, b) => rank(a).compareTo(rank(b)));
  return [
    for (final v in sorted)
      (v, known.where((e) => e.$1 == v).firstOrNull?.$2 ?? humanize(v)),
  ];
}

String optionLabel(String capability, String value) =>
    (capabilityOptionLabels[capability] ?? const [])
        .where((e) => e.$1 == value)
        .firstOrNull
        ?.$2 ??
    humanize(value);
