/// Colors used to rasterize map layers. Plain ARGB ints so the palette can be
/// sent to a background isolate.
class MapPalette {
  const MapPalette({
    required this.floor,
    required this.wall,
    required this.segments,
    required this.accentAmount,
  });

  final int floor;
  final int wall;

  /// Four colors for the four-color solution plus a fallback.
  final List<int> segments;

  /// Brightness change (percent, may be negative) for material textures.
  final double accentAmount;

  static const light = MapPalette(
    floor: 0xFF7FAEF5,
    wall: 0xFF3B4454,
    segments: [0xFF5FBDB0, 0xFF95C878, 0xFFF29A72, 0xFFF4C95D, 0xFFAF95EA],
    accentAmount: -9,
  );

  static const dark = MapPalette(
    floor: 0xFF2F67C2,
    wall: 0xFFC9D2DF,
    segments: [0xFF1F978A, 0xFF4F9A43, 0xFFC0603F, 0xFFC09430, 0xFF7459C4],
    accentAmount: 14,
  );

  int segmentColor(int index) => segments[index.clamp(0, segments.length - 1)];

  List<int> toList() => [floor, wall, accentAmount.round(), ...segments];

  static MapPalette fromList(List<int> list) => MapPalette(
    floor: list[0],
    wall: list[1],
    accentAmount: list[2].toDouble(),
    segments: list.sublist(3),
  );
}

/// Scales each RGB channel by `(100 + percent) / 100`, like the web UI.
int adjustBrightness(int argb, double percent) {
  final m = (100 + percent) / 100;
  int ch(int shift) => (((argb >> shift) & 0xFF) * m).round().clamp(0, 255);
  return (argb & 0xFF000000) | (ch(16) << 16) | (ch(8) << 8) | ch(0);
}
