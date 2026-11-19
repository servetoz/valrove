import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

/// The app icon artwork (`assets/brand/`, rendered from valrove-icon.svg by
/// tool/icons/render.mjs).
class ValroveLogo extends StatelessWidget {
  const ValroveLogo({super.key, this.size = 56});

  final double size;

  @override
  Widget build(BuildContext context) => Image.asset(
    'assets/brand/logo.png',
    width: size,
    height: size,
    filterQuality: FilterQuality.medium,
    excludeFromSemantics: true,
  );
}

/// Top-down robot vacuum glyph (body, bumper and lidar turret).
class RobotGlyph extends StatelessWidget {
  const RobotGlyph({super.key, this.size = 24, this.color, this.accent});

  final double size;
  final Color? color;
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    final c = color ?? IconTheme.of(context).color ?? Colors.black;
    return SizedBox.square(
      dimension: size,
      child: CustomPaint(painter: _RobotGlyphPainter(c, accent ?? c)),
    );
  }
}

class _RobotGlyphPainter extends CustomPainter {
  _RobotGlyphPainter(this.color, this.accent);

  final Color color;
  final Color accent;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.width / 2;
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = r * 0.16
      ..color = color;
    canvas.drawCircle(c, r * 0.86, stroke);
    canvas.drawArc(
      Rect.fromCircle(center: c, radius: r * 0.56),
      -math.pi / 2 - 0.85,
      1.7,
      false,
      stroke..strokeCap = StrokeCap.round,
    );
    canvas.drawCircle(
      c + Offset(0, r * 0.12),
      r * 0.24,
      Paint()..color = accent,
    );
  }

  @override
  bool shouldRepaint(_RobotGlyphPainter old) =>
      old.color != color || old.accent != accent;
}

/// Icon for a preset value.
IconData presetIcon(String type, String value) {
  if (type == 'operation_mode') {
    return switch (value) {
      'vacuum' => Icons.cyclone_rounded,
      'mop' => Icons.water_drop_rounded,
      'vacuum_and_mop' => Icons.layers_rounded,
      'vacuum_then_mop' => Icons.low_priority_rounded,
      _ => Icons.tune_rounded,
    };
  }
  if (type == 'water_grade') {
    return value == 'off'
        ? Icons.format_color_reset_rounded
        : Icons.water_drop_rounded;
  }
  return value == 'off' ? Icons.mode_fan_off_rounded : Icons.air_rounded;
}

/// Number of "intensity bars" to visualize a preset level (0–4).
int presetLevel(String value) => switch (value) {
  'off' => 0,
  'min' => 1,
  'low' => 1,
  'medium' => 2,
  'high' => 3,
  'max' => 4,
  'turbo' => 4,
  _ => 2,
};

/// Small vertical bars indicating an intensity level.
class LevelBars extends StatelessWidget {
  const LevelBars({
    super.key,
    required this.level,
    required this.color,
    this.max = 4,
    this.height = 14,
  });

  final int level;
  final int max;
  final Color color;
  final double height;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        for (var i = 0; i < max; i++)
          Container(
            margin: const EdgeInsets.only(right: 2),
            width: 3,
            height: height * (0.4 + 0.6 * (i + 1) / max),
            decoration: BoxDecoration(
              color: i < level ? color : color.withValues(alpha: 0.22),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
      ],
    );
  }
}
