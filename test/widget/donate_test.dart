import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:valrove/app.dart';
import 'package:valrove/features/donate/donate.dart';
import 'package:valrove/features/system/about_page.dart';
import 'package:valrove/state/app_state.dart';
import 'package:valrove/state/toasts.dart';
import 'package:valrove/ui/theme.dart';

import '../support/fake_robot.dart';
import '../support/test_support.dart';
import 'interaction_test.dart' show settle;

const _question = 'Do you enjoy using Valrove?';

/// Records the links the app opens; [opens] is what the platform answers.
List<String> _recordLinks(WidgetTester tester, {bool opens = true}) {
  const channel = MethodChannel('plugins.flutter.io/url_launcher');
  final messenger = tester.binding.defaultBinaryMessenger;
  final links = <String>[];
  messenger.setMockMethodCallHandler(channel, (call) async {
    if (call.method == 'launch') {
      links.add((call.arguments as Map)['url'] as String);
    }
    return opens;
  });
  addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
  return links;
}

/// Lets a dialog finish opening or closing.
Future<void> _dialogTransition(WidgetTester tester) async {
  for (var i = 0; i < 3; i++) {
    await tester.pump(const Duration(milliseconds: 200));
  }
}

void main() {
  setUpAll(loadAppFonts);

  /// The openings, of the first 50, on which the question comes; on the
  /// [missed] ones it was due but couldn't be asked.
  Future<List<int>> askedOn({Set<int> missed = const {}}) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final asked = <int>[];
    for (var opening = 1; opening <= 50; opening++) {
      if (!DonatePrompt.due(prefs, opening) || missed.contains(opening)) {
        continue;
      }
      asked.add(opening);
      DonatePrompt.markAsked(prefs, opening);
    }
    return asked;
  }

  test('asks on the 5th and the 20th opening', () async {
    expect(await askedOn(), [5, 20]);
  });

  test('an opening it could not ask on moves the question on', () async {
    expect(await askedOn(missed: {5, 6, 20}), [7, 21]);
    // Missed until the 20th, it asks once, not twice in a row.
    expect(await askedOn(missed: {for (var i = 5; i < 20; i++) i}), [20]);
  });

  testWidgets('launches count as openings, and so do returns after 30 min', (
    tester,
  ) async {
    var now = DateTime(2026, 11, 19, 9);
    final scope = await fakeRobotOverrides(
      FixtureHttpClient(),
      prefs: {'app.openings': 2},
    );
    final container = ProviderContainer(
      overrides: [
        ...scope,
        appOpeningsProvider.overrideWith(
          () => AppOpeningsNotifier(clock: () => now),
        ),
      ],
    );
    addTearDown(container.dispose);

    Future<void> lifecycle(AppLifecycleState state) =>
        tester.binding.defaultBinaryMessenger.handlePlatformMessage(
          SystemChannels.lifecycle.name,
          SystemChannels.lifecycle.codec.encodeMessage(state.toString()),
          (_) {},
        );
    Future<void> away(Duration time) async {
      await lifecycle(AppLifecycleState.paused);
      now = now.add(time);
      await lifecycle(AppLifecycleState.resumed);
    }

    expect(container.read(appOpeningsProvider), 3);
    await away(const Duration(minutes: 29));
    expect(container.read(appOpeningsProvider), 3);
    await away(const Duration(minutes: 30));
    expect(container.read(appOpeningsProvider), 4);
    final prefs = container.read(sharedPreferencesProvider);
    expect(prefs.getInt('app.openings'), 4);
  });

  /// Opens the app, opened [before] times and asked [asked] times for a
  /// donation before, and waits until the question would come.
  Future<SharedPreferences> openApp(
    WidgetTester tester, {
    required int before,
    int asked = 0,
  }) async {
    final scope = await fakeRobotOverrides(
      FixtureHttpClient(),
      prefs: {
        'settings.theme': 'light',
        'app.openings': before,
        'donate.asked': asked,
      },
    );
    await tester.pumpWidget(
      ProviderScope(overrides: scope, child: const ValroveApp()),
    );
    await settle(tester);
    await tester.pump(DonatePrompt.delay);
    await _dialogTransition(tester);
    return SharedPreferences.getInstance();
  }

  testWidgets('the 5th opening asks for a donation', (tester) async {
    await withPhoneSurface(tester, () async {
      final prefs = await openApp(tester, before: 4);
      expect(find.text(_question), findsOneWidget);
      expect(
        find.text('Support the development with a donation on Ko-fi.'),
        findsOneWidget,
      );
      expect(prefs.getInt('donate.asked'), 1);

      await tester.tap(find.text('Not now'));
      await _dialogTransition(tester);
      expect(find.text(_question), findsNothing);
    });
  });

  testWidgets('so does the 20th, and Donate opens Ko-fi', (tester) async {
    final links = _recordLinks(tester);
    await withPhoneSurface(tester, () async {
      final prefs = await openApp(tester, before: 19, asked: 1);
      expect(find.text(_question), findsOneWidget);

      await tester.tap(find.text('Donate'));
      await _dialogTransition(tester);
      expect(links, ['https://ko-fi.com/valrove']);
      expect(find.text(_question), findsNothing);
      expect(prefs.getInt('donate.asked'), 2);
    });
  });

  testWidgets('other openings do not ask', (tester) async {
    await withPhoneSurface(tester, () async {
      for (final (before, asked) in [
        (0, 0),
        (3, 0),
        (5, 1),
        (18, 1),
        (20, 2),
        (60, 2),
      ]) {
        await openApp(tester, before: before, asked: asked);
        expect(
          find.text(_question),
          findsNothing,
          reason: 'opening ${before + 1}',
        );
        // Closes the app.
        await tester.pumpWidget(const SizedBox());
      }
    });
  });

  testWidgets('About has a Donate page that opens Ko-fi', (tester) async {
    final links = _recordLinks(tester);
    await withPhoneSurface(tester, () async {
      final scope = await fakeRobotOverrides(FixtureHttpClient());
      await tester.pumpWidget(
        ProviderScope(
          overrides: scope,
          child: MaterialApp(theme: AppTheme.light(), home: const AboutPage()),
        ),
      );
      await settle(tester);
      if (playStoreBuild) {
        // Run with --dart-define=STORE=play: the page is left out.
        expect(find.text('SUPPORT VALROVE'), findsNothing);
        expect(find.text('Donate'), findsNothing);
        return;
      }
      expect(find.text('SUPPORT VALROVE'), findsOneWidget);

      await tester.tap(find.text('Donate'));
      await settle(tester);
      expect(find.text('Support Valrove'), findsOneWidget);

      await tester.tap(find.text('Donate on Ko-fi'));
      await tester.pump();
      expect(links, ['https://ko-fi.com/valrove']);
    });
  });

  testWidgets("without a browser, a toast says where to donate", (
    tester,
  ) async {
    final links = _recordLinks(tester, opens: false);
    await withPhoneSurface(tester, () async {
      final scope = await fakeRobotOverrides(FixtureHttpClient());
      await tester.pumpWidget(
        ProviderScope(
          overrides: scope,
          child: MaterialApp(theme: AppTheme.light(), home: const DonatePage()),
        ),
      );
      await settle(tester);
      await tester.tap(find.text('Donate on Ko-fi'));
      await tester.pump();
      expect(links, ['https://ko-fi.com/valrove']);

      final toasts = ProviderScope.containerOf(
        tester.element(find.byType(DonatePage)),
      ).read(toastProvider).toasts;
      expect(toasts.single.message, "Couldn't open the browser");
      expect(toasts.single.detail, 'Donate at ko-fi.com/valrove');
    });
  });
}
