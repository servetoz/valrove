import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:valrove/app.dart';
import 'package:valrove/features/map/room_rename_dialog.dart';
import 'package:valrove/map/widgets/map_canvas.dart';
import 'package:valrove/state/room_icons.dart';
import 'package:valrove/state/session.dart';
import 'package:valrove/ui/room_kinds.dart';
import 'package:valrove/ui/theme.dart';

import '../support/fake_robot.dart';
import '../support/test_support.dart';
import 'interaction_test.dart' show settle;

void main() {
  setUpAll(loadAppFonts);

  Future<RoomRename? Function()> openDialog(
    WidgetTester tester, {
    String currentName = '',
    List<String> takenNames = const [],
  }) async {
    RoomRename? result;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Builder(
          builder: (context) => Center(
            child: FilledButton(
              onPressed: () async => result = await showRoomRenameDialog(
                context,
                roomLabel: 'Room 4',
                currentName: currentName,
                takenNames: takenNames,
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    return () => result;
  }

  String fieldText(WidgetTester tester) =>
      tester.widget<TextField>(find.byType(TextField)).controller!.text;

  testWidgets('a suggestion fills in the name and brings its icon', (
    tester,
  ) async {
    final result = await openDialog(tester, takenNames: ['Bedroom']);
    expect(find.text('Bedroom 2'), findsOneWidget);
    expect(find.text('Bedroom'), findsNothing);

    await tester.tap(find.text('Kitchen'));
    await tester.pump();
    expect(fieldText(tester), 'Kitchen');
    expect(find.text('From the name: Kitchen'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(TextField),
        matching: find.byIcon(Icons.soup_kitchen_rounded),
      ),
      findsOneWidget,
    );

    await tester.tap(find.text('Rename'));
    await tester.pumpAndSettle();
    expect(result(), (name: 'Kitchen', kind: null));
  });

  testWidgets('typing narrows the suggestions; an icon can be picked', (
    tester,
  ) async {
    final result = await openDialog(tester);
    await tester.enterText(find.byType(TextField), 'Lena');
    await tester.pump();
    expect(find.text('SUGGESTIONS'), findsNothing);
    expect(find.text('None recognised'), findsOneWidget);

    await tester.tap(find.byTooltip('Bedroom'));
    await tester.pump();
    expect(
      find.descendant(
        of: find.byType(TextField),
        matching: find.byIcon(Icons.bed_rounded),
      ),
      findsOneWidget,
    );
    expect(find.textContaining('kept on this phone'), findsOneWidget);

    await tester.tap(find.text('Rename'));
    await tester.pumpAndSettle();
    expect(result(), (name: 'Lena', kind: RoomKind.bedroom));
  });

  testWidgets('picked icons are kept per robot while the name stays', (
    tester,
  ) async {
    final overrides = await fakeRobotOverrides(FixtureHttpClient());
    final first = ProviderContainer(overrides: overrides);
    addTearDown(first.dispose);
    final choices = first.read(roomIconChoicesProvider.notifier)
      ..set('4', name: 'Lena', kind: RoomKind.bedroom)
      // The kind the name implies needs no pick.
      ..set('3', name: 'Kitchen', kind: RoomKind.kitchen);
    expect(choices.state.keys, ['4']);

    final again = ProviderContainer(overrides: overrides);
    addTearDown(again.dispose);
    final kept = again.read(roomIconChoicesProvider);
    expect(roomKindOf(kept, '4', 'Lena'), RoomKind.bedroom);
    // Renamed elsewhere: back to recognising the name.
    expect(roomKindOf(kept, '4', 'Office'), RoomKind.office);
    expect(roomKindOf(kept, '4', 'Room 4'), isNull);
  });

  testWidgets('named rooms show their icon on the map and in the room sheet', (
    tester,
  ) async {
    await withPhoneSurface(tester, () async {
      final map = jsonDecode(fixtureText('robot__state__map')) as Map;
      for (final layer in (map['layers'] as List).cast<Map>()) {
        final meta = layer['metaData'] as Map;
        if (meta['segmentId'] == '4') meta['name'] = 'Küche';
      }
      final http = FixtureHttpClient(overrides: {'robot/state/map': map});
      final scope = await fakeRobotOverrides(http);
      await tester.pumpWidget(
        ProviderScope(overrides: scope, child: const ValroveApp()),
      );
      await settle(tester);

      final canvas = tester.widget<MapCanvas>(find.byType(MapCanvas));
      expect(canvas.roomIcons, {'4': Icons.soup_kitchen_rounded});

      final container = ProviderScope.containerOf(
        tester.element(find.byType(MapCanvas)),
      );
      final room = container.read(liveMapProvider).scene!.data.segment('4')!;
      final at =
          tester.getTopLeft(find.byType(MapCanvas)) +
          canvas.controller.viewport.worldToScreen(
            Offset(room.labelX, room.labelY),
          );
      await tester.longPressAt(at);
      await settle(tester, rounds: 4);
      expect(find.text('Küche'), findsWidgets);
      expect(find.byIcon(Icons.soup_kitchen_rounded), findsOneWidget);
    });
  });
}
