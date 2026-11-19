import 'package:flutter_test/flutter_test.dart';
import 'package:valrove/ui/room_kinds.dart';

void main() {
  test('recognises rooms by name in several languages', () {
    const cases = {
      'Kitchen': RoomKind.kitchen,
      'Küche': RoomKind.kitchen,
      'Wohnküche': RoomKind.kitchen,
      'Cuisine': RoomKind.kitchen,
      'Cocina': RoomKind.kitchen,
      'Living room': RoomKind.living,
      'Wohnzimmer': RoomKind.living,
      'Woonkamer': RoomKind.living,
      'Bedroom 2': RoomKind.bedroom,
      'Master bedroom': RoomKind.bedroom,
      'Schlafzimmer': RoomKind.bedroom,
      'Elternschlafzimmer': RoomKind.bedroom,
      "Kids' room": RoomKind.kids,
      'Kinderzimmer': RoomKind.kids,
      'Bad': RoomKind.bathroom,
      'Badezimmer': RoomKind.bathroom,
      'Kinderbad': RoomKind.bathroom,
      'Salle de bain': RoomKind.bathroom,
      'Gäste-WC': RoomKind.toilet,
      'Gästezimmer': RoomKind.guest,
      'Flur': RoomKind.hallway,
      'Entrance hall': RoomKind.entrance,
      'Eingangsbereich': RoomKind.entrance,
      'Büro': RoomKind.office,
      'Arbeitszimmer': RoomKind.office,
      'Esszimmer': RoomKind.dining,
      'Hauswirtschaftsraum': RoomKind.laundry,
      'Abstellraum': RoomKind.storage,
      'Walk-in closet': RoomKind.closet,
      'Treppenhaus': RoomKind.stairs,
    };
    for (final MapEntry(:key, :value) in cases.entries) {
      expect(RoomKind.match(key), value, reason: key);
    }
    for (final name in ['Room 4', 'Lena', 'Garden', ' ', null]) {
      expect(RoomKind.match(name), isNull, reason: '$name');
    }
  });

  test('every suggested name is recognised as its own kind', () {
    for (final kind in RoomKind.all) {
      expect(RoomKind.match(kind.label), kind, reason: kind.label);
    }
  });

  test('suggests free names, narrowed to what was typed', () {
    final names = [
      for (final s in roomNameSuggestions(
        takenNames: ['Bedroom', 'bedroom 2', 'Kitchen'],
      ))
        s.name,
    ];
    expect(names, containsAll(['Bedroom 3', 'Kitchen 2', 'Living room']));
    expect(names, isNot(contains('Bedroom')));
    expect(
      [
        for (final s in roomNameSuggestions(takenNames: [], query: 'KI'))
          s.name,
      ],
      ['Kitchen', "Kids' room"],
    );
  });
}
