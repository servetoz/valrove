import 'dart:convert';
import 'dart:io';

import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Loads the bundled fonts (and Material icons) so golden images show real
/// text instead of the test font's boxes.
Future<void> loadAppFonts() async {
  final inter = FontLoader('Inter');
  for (final w in ['Regular', 'Medium', 'SemiBold', 'Bold']) {
    inter.addFont(rootBundle.load('assets/fonts/Inter-$w.ttf'));
  }
  await inter.load();
  final mono = FontLoader('JetBrainsMono')
    ..addFont(rootBundle.load('assets/fonts/JetBrainsMono-Regular.ttf'))
    ..addFont(rootBundle.load('assets/fonts/JetBrainsMono-Medium.ttf'));
  await mono.load();
  final icons = FontLoader('MaterialIcons')
    ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
  await icons.load();
}

/// Reads a captured API response from `test/fixtures/<robot>/<name>.json`.
String fixtureText(String name, {String robot = 'l40'}) =>
    File('test/fixtures/$robot/$name.json').readAsStringSync();

Object? fixtureJson(String name, {String robot = 'l40'}) =>
    jsonDecode(fixtureText(name, robot: robot));

/// Runs [body] with a phone-sized surface.
Future<void> withPhoneSurface(
  WidgetTester tester,
  Future<void> Function() body, {
  Size size = const Size(400, 860),
}) async {
  tester.view.physicalSize = size * 2;
  tester.view.devicePixelRatio = 2;
  // Render real (blurred) shadows so goldens look like the device.
  debugDisableShadows = false;
  try {
    await body();
  } finally {
    debugDisableShadows = true;
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  }
}
