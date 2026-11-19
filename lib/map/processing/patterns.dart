import '../../core/valetudo/models/map_data.dart';

/// Returns true when a pixel should be drawn in the accent color.
///
/// These are the exact floor-material textures used by Valetudo's web
/// interface, so a room looks the same in the app and in the browser.
typedef PixelPattern = bool Function(int x, int y);

bool _solid(int x, int y) => false;

bool _tile(int x, int y) => x % 6 == 0 || y % 6 == 0;

PixelPattern _plank({required bool horizontal}) {
  const plankWidth = 5;
  const plankLength = 24;
  const jointOffset = plankLength ~/ 2;
  return (x, y) {
    final main = horizontal ? y : x;
    final cross = horizontal ? x : y;
    if (main % plankWidth == 0) return true;
    final strip = main ~/ plankWidth;
    final joint = strip.isEven ? 0 : jointOffset;
    return cross % plankLength == joint;
  };
}

bool _chevron(int x, int y) {
  const plankWidth = 4;
  const sectionWidth = 8;
  final zig = (x ~/ sectionWidth).isEven;
  final diagonal = zig ? (x + y) : (x - y);
  return diagonal % plankWidth == 0;
}

bool _carpetLow(int x, int y) =>
    (x % 4 == 0 && y % 4 == 0) || (x % 4 == 2 && y % 4 == 2);

bool _carpet(int x, int y) => ((x ~/ 2) + y).isEven;

const _carpetHighPattern = [
  [1, 0, 0, 0, 0, 0, 1, 0],
  [0, 1, 0, 0, 0, 0, 0, 1],
  [0, 0, 0, 1, 1, 0, 0, 0],
  [0, 0, 0, 0, 0, 0, 0, 0],
  [0, 0, 1, 0, 0, 0, 1, 0],
  [0, 1, 0, 0, 0, 1, 0, 0],
  [0, 0, 0, 0, 0, 0, 0, 0],
  [0, 0, 0, 1, 1, 0, 0, 0],
];

bool _carpetHigh(int x, int y) => _carpetHighPattern[y % 8][x % 8] == 1;

const _fallbackPattern = [
  [0, 0, 0, 0, 0, 0, 0, 0, 0],
  [0, 0, 0, 0, 0, 0, 0, 0, 0],
  [0, 0, 0, 1, 1, 1, 0, 0, 0],
  [0, 0, 1, 0, 0, 0, 1, 0, 0],
  [0, 0, 0, 0, 0, 0, 1, 0, 0],
  [0, 0, 0, 0, 1, 1, 0, 0, 0],
  [0, 0, 0, 0, 1, 0, 0, 0, 0],
  [0, 0, 0, 0, 0, 0, 0, 0, 0],
  [0, 0, 0, 0, 1, 0, 0, 0, 0],
  [0, 0, 0, 0, 0, 0, 0, 0, 0],
  [0, 0, 0, 0, 0, 0, 0, 0, 0],
];

/// Unknown materials render a "?" texture, as in the web interface.
bool _fallback(int x, int y) =>
    _fallbackPattern[y % _fallbackPattern.length][x %
        _fallbackPattern[0].length] ==
    1;

final PixelPattern _woodHorizontal = _plank(horizontal: true);
final PixelPattern _woodVertical = _plank(horizontal: false);

PixelPattern patternForMaterial(String? material) {
  if (material == null) return _solid;
  return switch (material) {
    SegmentMaterial.generic => _solid,
    SegmentMaterial.tile => _tile,
    SegmentMaterial.wood => _chevron,
    SegmentMaterial.woodHorizontal => _woodHorizontal,
    SegmentMaterial.woodVertical => _woodVertical,
    SegmentMaterial.carpet => _carpet,
    SegmentMaterial.carpetLow => _carpetLow,
    SegmentMaterial.carpetHigh => _carpetHigh,
    _ => _fallback,
  };
}
