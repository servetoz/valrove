import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:valrove/state/app_state.dart';
import 'package:valrove/state/commands.dart';
import 'package:valrove/ui/glass.dart';
import 'package:valrove/ui/haptics.dart';

import '../support/fake_robot.dart';

void main() {
  const vibrator = MethodChannel('dev.valroveapp.valrove/haptics');
  late List<String> played;
  late List<String> flutterHaptics;

  setUp(() {
    played = [];
    flutterHaptics = [];
    Haptics.enabled = true;
    Haptics.useVibrator = true;
  });
  tearDown(() {
    Haptics.enabled = true;
    Haptics.useVibrator = null;
  });

  void listen(WidgetTester tester, {bool vibratorFails = false}) {
    final messenger = tester.binding.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(vibrator, (call) async {
      if (vibratorFails) throw PlatformException(code: 'unavailable');
      played.add('${call.method}:${call.arguments}');
      return null;
    });
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'HapticFeedback.vibrate') {
        flutterHaptics.add('${call.arguments}');
      }
      return null;
    });
  }

  Future<void> pumpButton(WidgetTester tester) => tester.pumpWidget(
    MaterialApp(
      home: Center(
        child: Pressable(
          onTap: () {},
          onLongPress: () {},
          child: const Text('Dock'),
        ),
      ),
    ),
  );

  testWidgets('buttons play effects on the vibrator', (tester) async {
    listen(tester);
    await pumpButton(tester);
    await tester.tap(find.text('Dock'));
    await tester.longPress(find.text('Dock'));
    await tester.pump();
    expect(played, ['play:selection', 'play:medium']);
    expect(flutterHaptics, isEmpty);
  });

  testWidgets("the app's setting silences all of them", (tester) async {
    listen(tester);
    final scope = await fakeRobotOverrides(FixtureHttpClient());
    final container = ProviderContainer(overrides: scope);
    addTearDown(container.dispose);
    container.read(settingsProvider.notifier).setHaptics(false);
    await pumpButton(tester);
    await tester.tap(find.text('Dock'));
    await tester.pump();
    expect(played, isEmpty);
    expect(flutterHaptics, isEmpty);

    container.read(settingsProvider.notifier).setHaptics(true);
    await tester.tap(find.text('Dock'));
    await tester.pump();
    expect(played, ['play:selection']);
  });

  testWidgets("without the vibrator Flutter's haptics are used", (
    tester,
  ) async {
    listen(tester, vibratorFails: true);
    await pumpButton(tester);
    await tester.tap(find.text('Dock'));
    await tester.pump();
    expect(flutterHaptics, ['HapticFeedbackType.selectionClick']);

    Haptics.useVibrator = false;
    Haptics.heavy();
    await tester.pump();
    expect(flutterHaptics.last, 'HapticFeedbackType.heavyImpact');
  });

  testWidgets('a failed command plays the error pattern', (tester) async {
    listen(tester);
    final scope = await fakeRobotOverrides(FixtureHttpClient());
    final container = ProviderContainer(overrides: scope);
    addTearDown(container.dispose);
    final ok = await container
        .read(commandsProvider)
        .run('do something', (c) => throw StateError('nope'));
    await tester.pump();
    expect(ok, isFalse);
    expect(played, ['play:light', 'play:error']);
  });
}
