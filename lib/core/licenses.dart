import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Valrove's copyright notice, as in the LICENSE file.
const valroveCopyright = 'Copyright 2026 The Valrove Authors';

/// Asset key of Valrove's license, the LICENSE file at the project root.
///
/// Flutter also lists it as `valrove` on the open-source licenses page.
const valroveLicenseAsset = 'LICENSE';

/// Adds the licenses of the fonts, ported code and texts in Valrove to the
/// open-source licenses page; Flutter adds those of the packages.
void registerLicenses() {
  LicenseRegistry.addLicense(() async* {
    yield LicenseEntryWithLineBreaks([
      'Inter',
    ], await rootBundle.loadString('assets/licenses/Inter-OFL.txt'));
    yield LicenseEntryWithLineBreaks([
      'JetBrains Mono',
    ], await rootBundle.loadString('assets/licenses/JetBrainsMono-OFL.txt'));
    yield const LicenseEntryWithLineBreaks([
      'jsmpeg (MPEG-1 decoder port)',
    ], _jsmpegLicense);
    yield LicenseEntryWithLineBreaks(
      ['simplify.js (path simplification port)'],
      await rootBundle.loadString(
        'assets/licenses/simplify-js-BSD-2-Clause.txt',
      ),
    );
    yield LicenseEntryWithLineBreaks([
      'Valetudo (help texts, map textures, room colors, achievements)',
    ], await rootBundle.loadString('assets/licenses/Valetudo-LICENSE.txt'));
  });
}

const _jsmpegLicense = '''
The MIT License (MIT)
Copyright (c) 2017 Dominic Szablewski

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.''';
