import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:valrove/core/licenses.dart';
import 'package:valrove/features/system/about_page.dart';
import 'package:valrove/ui/theme.dart';

import '../support/fake_robot.dart';
import '../support/test_support.dart';
import 'interaction_test.dart' show settle;

void main() {
  setUpAll(loadAppFonts);

  Finder text(String part) => find.textContaining(part, findRichText: true);

  testWidgets("the About page has Valrove's license, not Valetudo's", (
    tester,
  ) async {
    await withPhoneSurface(tester, () async {
      final scope = await fakeRobotOverrides(FixtureHttpClient());
      await tester.pumpWidget(
        ProviderScope(
          overrides: scope,
          child: MaterialApp(theme: AppTheme.light(), home: const AboutPage()),
        ),
      );
      await settle(tester);

      // Valetudo's credits stay; its license section is gone.
      expect(text('shoulders of giants'), findsOneWidget);
      expect(text("won't read"), findsNothing);
      expect(text('lorem ipsum'), findsNothing);

      final license = find.text('Valrove license');
      await tester.scrollUntilVisible(license, 300);
      expect(text(valroveCopyright), findsOneWidget);
      expect(text('the same license as Valetudo'), findsOneWidget);
      expect(text('simplify.js (BSD 2-Clause'), findsOneWidget);

      await tester.tap(license);
      await settle(tester);
      expect(find.text('Apache License 2.0'), findsOneWidget);
      expect(text('TERMS AND CONDITIONS FOR USE'), findsOneWidget);
      await tester.scrollUntilVisible(text(valroveCopyright), 600);
      expect(text(valroveCopyright), findsOneWidget);
    });
  });

  testWidgets('About has the privacy policy', (tester) async {
    await withPhoneSurface(tester, () async {
      final scope = await fakeRobotOverrides(FixtureHttpClient());
      await tester.pumpWidget(
        ProviderScope(
          overrides: scope,
          child: MaterialApp(theme: AppTheme.light(), home: const AboutPage()),
        ),
      );
      await settle(tester);
      final privacy = find.text('Privacy policy');
      // Built first, then scrolled fully onto the screen.
      await tester.scrollUntilVisible(privacy, 300);
      await tester.ensureVisible(privacy);
      await settle(tester, rounds: 3);
      await tester.tap(privacy);
      await settle(tester);
      expect(
        text('Valrove does not collect any personal data'),
        findsOneWidget,
      );
    });
  });
}
