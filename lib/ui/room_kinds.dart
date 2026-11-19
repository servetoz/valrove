import 'package:material_ui/material_ui.dart';

/// A kind of room: a suggested name and the icon shown for it.
///
/// Valetudo only stores room names, so the kind is recognised from the name
/// (in several languages) unless the user picked an icon on this phone.
class RoomKind {
  const RoomKind._(this.id, this.label, this.icon, this._keywords);

  /// Stable id, used to remember a picked icon.
  final String id;

  /// Suggested room name.
  final String label;
  final IconData icon;

  /// Words that identify the kind in a room name, separated by `|` and
  /// already folded (lower case, no accents). Up to three letters must start
  /// or end a word; longer ones may appear anywhere, so compounds like
  /// "Elternschlafzimmer" match.
  final String _keywords;

  static const living = RoomKind._(
    'living',
    'Living room',
    Icons.weekend_rounded,
    'living|lounge|family room|sitting|tv|wohnzimmer|wohnraum|wohnbereich|stube|salon|sejour|soggiorno|sala de estar|woonkamer',
  );
  static const kitchen = RoomKind._(
    'kitchen',
    'Kitchen',
    Icons.soup_kitchen_rounded,
    'kitchen|kuche|kueche|cuisine|cocina|cucina|keuken',
  );
  static const dining = RoomKind._(
    'dining',
    'Dining room',
    Icons.restaurant_rounded,
    'dining|esszimmer|essbereich|essecke|salle a manger|comedor|sala da pranzo|eetkamer',
  );
  static const bedroom = RoomKind._(
    'bedroom',
    'Bedroom',
    Icons.bed_rounded,
    'bedroom|bed|schlaf|chambre|dormitorio|camera da letto|slaapkamer',
  );
  static const kids = RoomKind._(
    'kids',
    "Kids' room",
    Icons.toys_rounded,
    'kid|child|nursery|baby|playroom|kinder|spielzimmer|enfant|nino|bambin|speelkamer',
  );
  static const guest = RoomKind._(
    'guest',
    'Guest room',
    Icons.single_bed_rounded,
    'guest|gast|gaest|invite|huesped|ospit|logeer',
  );
  static const bathroom = RoomKind._(
    'bathroom',
    'Bathroom',
    Icons.bathtub_rounded,
    'bath|shower|bad|dusche|salle de bain|bano|bagno|badkamer',
  );
  static const toilet = RoomKind._(
    'toilet',
    'Toilet',
    Icons.wc_rounded,
    'toilet|wc|restroom|lavatory|loo|powder room|klo|toilette|aseo',
  );
  static const hallway = RoomKind._(
    'hallway',
    'Hallway',
    Icons.directions_walk_rounded,
    'hall|corridor|passage|flur|diele|gang|couloir|pasillo|corridoio|overloop',
  );
  static const entrance = RoomKind._(
    'entrance',
    'Entrance',
    Icons.door_front_door_rounded,
    'entrance|entry|foyer|vestibule|mudroom|eingang|windfang|entree|entrada|ingresso|ingang',
  );
  static const office = RoomKind._(
    'office',
    'Office',
    Icons.desk_rounded,
    'office|study|workroom|buro|buero|arbeitszimmer|bureau|oficina|despacho|ufficio|studio|kantoor|werkkamer',
  );
  static const laundry = RoomKind._(
    'laundry',
    'Laundry room',
    Icons.local_laundry_service_rounded,
    'laundry|utility|wasch|hauswirtschaft|hwr|buanderie|lavadero|lavanderia|washok|wasruimte',
  );
  static const storage = RoomKind._(
    'storage',
    'Storage room',
    Icons.inventory_2_rounded,
    'storage|store room|storeroom|pantry|abstell|vorrat|speisekammer|lager|cellier|debarras|despensa|trastero|ripostiglio|berging|bijkeuken',
  );
  static const closet = RoomKind._(
    'closet',
    'Walk-in closet',
    Icons.checkroom_rounded,
    'closet|wardrobe|dressing|ankleide|garderobe|vestidor|armadio|kleedkamer|inloopkast',
  );
  static const stairs = RoomKind._(
    'stairs',
    'Stairs',
    Icons.stairs_rounded,
    'stair|treppe|escalier|escalera|scala|trap',
  );
  static const gym = RoomKind._(
    'gym',
    'Gym',
    Icons.fitness_center_rounded,
    'gym|fitness|workout|training|sportraum',
  );
  static const garage = RoomKind._(
    'garage',
    'Garage',
    Icons.garage_rounded,
    'garage|garaje|carport',
  );
  static const basement = RoomKind._(
    'basement',
    'Basement',
    Icons.foundation_rounded,
    'basement|cellar|keller|cave|sotano|cantina|kelder',
  );
  static const terrace = RoomKind._(
    'terrace',
    'Terrace',
    Icons.deck_rounded,
    'terrace|balcony|patio|veranda|porch|conservatory|wintergarten|terrasse|balkon|balcon|terraza|terrazza|serre',
  );

  /// In the order they are suggested.
  static const all = [
    living,
    kitchen,
    bedroom,
    bathroom,
    hallway,
    office,
    kids,
    dining,
    toilet,
    guest,
    entrance,
    laundry,
    storage,
    closet,
    stairs,
    gym,
    garage,
    basement,
    terrace,
  ];

  /// Order names are matched in: specific kinds before the ones they contain
  /// ("Gäste-WC" is a toilet, "Kinderbad" a bathroom, "Entrance hall" an
  /// entrance).
  static const _matchOrder = [
    toilet,
    bathroom,
    laundry,
    kitchen,
    dining,
    kids,
    guest,
    closet,
    bedroom,
    office,
    living,
    entrance,
    hallway,
    stairs,
    storage,
    gym,
    garage,
    basement,
    terrace,
  ];

  /// Icon for rooms without a recognised kind.
  static const IconData genericIcon = Icons.meeting_room_rounded;

  static RoomKind? byId(String? id) => all.where((k) => k.id == id).firstOrNull;

  /// The kind [name] describes, if any.
  static RoomKind? match(String? name) {
    if (name == null || name.trim().isEmpty) return null;
    final folded = fold(name);
    final words = folded.split(RegExp('[^a-z0-9]+'));
    for (final kind in _matchOrder) {
      for (final keyword in kind._keywords.split('|')) {
        final hit = keyword.length > 3
            ? folded.contains(keyword)
            : words.any((w) => w.startsWith(keyword) || w.endsWith(keyword));
        if (hit) return kind;
      }
    }
    return null;
  }

  /// Lower case without accents, so "Küche" and "Kuche" compare equal.
  static String fold(String text) {
    const from = 'äöüßàáâãåèéêëìíîïòóôõùúûñçæœ';
    const to = 'a|o|u|ss|a|a|a|a|a|e|e|e|e|i|i|i|i|o|o|o|o|u|u|u|n|c|ae|oe';
    final replacements = to.split('|');
    final buffer = StringBuffer();
    for (final rune in text.toLowerCase().runes) {
      final c = String.fromCharCode(rune);
      final i = from.indexOf(c);
      buffer.write(i < 0 ? c : replacements[i]);
    }
    return buffer.toString();
  }
}

/// A suggested room name.
typedef RoomSuggestion = ({RoomKind kind, String name});

/// Names to offer when renaming a room. Names other rooms already use get a
/// number ("Bedroom 2"); [query] narrows the list to matching names.
List<RoomSuggestion> roomNameSuggestions({
  required Iterable<String> takenNames,
  String query = '',
}) {
  final taken = {for (final n in takenNames) RoomKind.fold(n.trim())};
  final q = RoomKind.fold(query.trim());
  final out = <RoomSuggestion>[];
  for (final kind in RoomKind.all) {
    var name = kind.label;
    for (var n = 2; taken.contains(RoomKind.fold(name)); n++) {
      name = '${kind.label} $n';
    }
    if (q.isNotEmpty && !RoomKind.fold(name).contains(q)) continue;
    out.add((kind: kind, name: name));
  }
  return out;
}
