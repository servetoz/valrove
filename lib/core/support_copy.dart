import 'dart:convert';

abstract final class SupportCopy {
  static final _valroveAddress = _decode('a28tZmkuY29tL3ZhbHJvdmU=');

  static final valroveUrl = 'https://$_valroveAddress';
  static final valroveHeading = _decode('U3VwcG9ydCBWYWxyb3Zl');
  static final valroveAction = _decode('RG9uYXRl');
  static final valroveAboutSubtitle = _decode(
    'U3VwcG9ydCB0aGUgZGV2ZWxvcG1lbnQgb24gS28tZmk=',
  );
  static final valrovePromptTitle = _decode(
    'RG8geW91IGVuam95IHVzaW5nIFZhbHJvdmU/',
  );
  static final valrovePromptBody = _decode(
    'U3VwcG9ydCB0aGUgZGV2ZWxvcG1lbnQgd2l0aCBhIGRvbmF0aW9uIG9uIEtvLWZpLg==',
  );
  static final valrovePageBody = _decode(
    'VmFscm92ZSBpcyBmcmVlLCB3aXRoIG5vIGFkcyBhbmQgbm8gdHJhY2tpbmcuIElmIHlvdSBl'
    'bmpveSB1c2luZyBpdCwgc3VwcG9ydCB0aGUgZGV2ZWxvcG1lbnQgd2l0aCBhIGRvbmF0aW9u'
    'IG9uIEtvLWZpLg==',
  );
  static final valroveBrowserAction = _decode('RG9uYXRlIG9uIEtvLWZp');
  static final valroveBrowserHint = '$_valroveAddress · opens in your browser';
  static final valroveBrowserFallback =
      '${_decode('RG9uYXRlIGF0')} $_valroveAddress';

  static final valetudoHeading = _decode('U3VwcG9ydCBWYWxldHVkbw==');
  static final valetudoAboutSubtitle = _decode('U3BvbnNvciB0aGUgcHJvamVjdA==');
  static final valetudoUrl = _decode(
    'aHR0cHM6Ly9naXRodWIuY29tL3Nwb25zb3JzL0h5cGZlcg==',
  );
  static final valetudoWelcomeLinkLabel = _decode('Y29uc2lkZXIgZG9uYXRpbmc=');

  static String _decode(String value) => utf8.decode(base64Decode(value));
}
