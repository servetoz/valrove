import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:valrove/core/licenses.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test("Valrove's license is Valetudo's with its own copyright line", () {
    final valrove = File('LICENSE').readAsLinesSync();
    final valetudo = File('assets/licenses/Valetudo-LICENSE.txt')
        .readAsLinesSync();
    expect(valrove, hasLength(valetudo.length));
    expect(valrove.first.trim(), 'Apache License');
    expect(
      [
        for (var i = 0; i < valrove.length; i++)
          if (valrove[i] != valetudo[i])
            (valetudo[i].trim(), valrove[i].trim()),
      ],
      [('Copyright 2018 Sören Beye', valroveCopyright)],
    );
  });

  test('the licenses page has the full texts of the bundled work', () async {
    LicenseRegistry.reset();
    registerLicenses();
    final texts = <String, String>{
      await for (final entry in LicenseRegistry.licenses)
        for (final package in entry.packages)
          package: entry.paragraphs.map((p) => p.text).join('\n'),
    };
    String text(String package) =>
        texts.entries.singleWhere((e) => e.key.startsWith(package)).value;

    expect(text('Valetudo'), contains('TERMS AND CONDITIONS FOR USE'));
    expect(text('Valetudo'), contains('Copyright 2018 Sören Beye'));
    expect(text('simplify.js'), contains('Copyright (c) 2017, Vladimir'));
    expect(text('simplify.js'), contains('Redistributions in binary form'));
    expect(text('jsmpeg'), contains('Copyright (c) 2017 Dominic Szablewski'));
    expect(text('Inter'), contains('SIL OPEN FONT LICENSE'));
    expect(text('JetBrains Mono'), contains('SIL OPEN FONT LICENSE'));
    LicenseRegistry.reset();
  });
}
