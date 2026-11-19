import 'package:cupertino_ui/cupertino_ui.dart'
    show CupertinoPageTransitionsBuilder;
import 'package:material_ui/material_ui.dart';

import '../core/valetudo/models/robot_state.dart';

/// Accent colors that reflect what the robot is doing.
abstract final class StateColors {
  static const cleaning = Color(0xFF2DD4BF);
  static const returning = Color(0xFFF59E0B);
  static const docked = Color(0xFF60A5FA);
  static const charging = Color(0xFF34D399);
  static const paused = Color(0xFFA78BFA);
  static const idle = Color(0xFF94A3B8);
  static const error = Color(0xFFFB7185);
  static const moving = Color(0xFF38BDF8);
  static const offline = Color(0xFF64748B);

  static Color forState(RobotState state, {bool online = true}) {
    if (!online) return offline;
    final battery = state.battery;
    return switch (state.status.value) {
      RobotStatus.cleaning => cleaning,
      RobotStatus.returning => returning,
      RobotStatus.docked => battery?.flag == 'charging' ? charging : docked,
      RobotStatus.paused => paused,
      RobotStatus.error => error,
      RobotStatus.moving || RobotStatus.manualControl => moving,
      RobotStatus.idle => idle,
      _ => idle,
    };
  }
}

/// Semantic colors beyond the Material color scheme.
@immutable
class ValroveColors extends ThemeExtension<ValroveColors> {
  const ValroveColors({
    required this.background,
    required this.backgroundAlt,
    required this.glassTop,
    required this.glassBottom,
    required this.glassBorder,
    required this.glassBorderSoft,
    required this.textPrimary,
    required this.textSecondary,
    required this.textTertiary,
    required this.tile,
    required this.tileBorder,
    required this.success,
    required this.warning,
    required this.danger,
    required this.info,
    required this.shadow,
  });

  final Color background;
  final Color backgroundAlt;
  final Color glassTop;
  final Color glassBottom;
  final Color glassBorder;
  final Color glassBorderSoft;
  final Color textPrimary;
  final Color textSecondary;
  final Color textTertiary;
  final Color tile;
  final Color tileBorder;
  final Color success;
  final Color warning;
  final Color danger;
  final Color info;
  final Color shadow;

  static const light = ValroveColors(
    background: Color(0xFFEEF1F6),
    backgroundAlt: Color(0xFFE3E8F1),
    glassTop: Color(0xD9FFFFFF),
    glassBottom: Color(0xB8FFFFFF),
    glassBorder: Color(0xCCFFFFFF),
    glassBorderSoft: Color(0x0F0B1220),
    textPrimary: Color(0xFF0E1420),
    textSecondary: Color(0xFF586274),
    textTertiary: Color(0xFF8A93A3),
    tile: Color(0xFFFFFFFF),
    tileBorder: Color(0x0F0B1220),
    success: Color(0xFF10B981),
    warning: Color(0xFFF59E0B),
    danger: Color(0xFFEF4444),
    info: Color(0xFF3B82F6),
    shadow: Color(0x1A0B1220),
  );

  static const dark = ValroveColors(
    background: Color(0xFF000000),
    backgroundAlt: Color(0xFF07090D),
    glassTop: Color(0xC21B202A),
    glassBottom: Color(0xA80D1016),
    glassBorder: Color(0x29FFFFFF),
    glassBorderSoft: Color(0x0DFFFFFF),
    textPrimary: Color(0xFFF2F5FA),
    textSecondary: Color(0xFF9AA4B5),
    textTertiary: Color(0xFF677184),
    tile: Color(0xFF0E1218),
    tileBorder: Color(0x14FFFFFF),
    success: Color(0xFF34D399),
    warning: Color(0xFFFBBF24),
    danger: Color(0xFFFB7185),
    info: Color(0xFF60A5FA),
    shadow: Color(0x66000000),
  );

  @override
  ValroveColors copyWith() => this;

  @override
  ValroveColors lerp(ValroveColors? other, double t) {
    if (other == null) return this;
    Color l(Color a, Color b) => Color.lerp(a, b, t)!;
    return ValroveColors(
      background: l(background, other.background),
      backgroundAlt: l(backgroundAlt, other.backgroundAlt),
      glassTop: l(glassTop, other.glassTop),
      glassBottom: l(glassBottom, other.glassBottom),
      glassBorder: l(glassBorder, other.glassBorder),
      glassBorderSoft: l(glassBorderSoft, other.glassBorderSoft),
      textPrimary: l(textPrimary, other.textPrimary),
      textSecondary: l(textSecondary, other.textSecondary),
      textTertiary: l(textTertiary, other.textTertiary),
      tile: l(tile, other.tile),
      tileBorder: l(tileBorder, other.tileBorder),
      success: l(success, other.success),
      warning: l(warning, other.warning),
      danger: l(danger, other.danger),
      info: l(info, other.info),
      shadow: l(shadow, other.shadow),
    );
  }
}

extension ValroveThemeX on BuildContext {
  ValroveColors get colors =>
      Theme.of(this).extension<ValroveColors>() ?? ValroveColors.light;
  TextTheme get text => Theme.of(this).textTheme;
  bool get isDark => Theme.of(this).brightness == Brightness.dark;
  ColorScheme get scheme => Theme.of(this).colorScheme;
}

abstract final class AppTheme {
  static const brand = Color(0xFF4C6FFF);
  static const brandDark = Color(0xFF7D95FF);
  static const fontFamily = 'Inter';
  static const monoFamily = 'JetBrainsMono';

  static ThemeData light() =>
      _build(Brightness.light, ValroveColors.light, brand);

  static ThemeData dark() =>
      _build(Brightness.dark, ValroveColors.dark, brandDark);

  static ThemeData _build(
    Brightness brightness,
    ValroveColors c,
    Color primary,
  ) {
    final dark = brightness == Brightness.dark;
    final scheme =
        ColorScheme.fromSeed(
          seedColor: primary,
          brightness: brightness,
          primary: primary,
          surface: dark ? const Color(0xFF0B0E13) : const Color(0xFFFFFFFF),
          error: c.danger,
        ).copyWith(
          surfaceContainerLowest: dark
              ? const Color(0xFF000000)
              : const Color(0xFFFFFFFF),
          surfaceContainerLow: c.tile,
          surfaceContainer: dark
              ? const Color(0xFF12161D)
              : const Color(0xFFF6F8FB),
          surfaceContainerHigh: dark
              ? const Color(0xFF181D26)
              : const Color(0xFFEFF2F7),
          surfaceContainerHighest: dark
              ? const Color(0xFF1F2530)
              : const Color(0xFFE6EAF1),
          onSurface: c.textPrimary,
          onSurfaceVariant: c.textSecondary,
          outline: dark ? const Color(0x33FFFFFF) : const Color(0x260B1220),
          outlineVariant: c.tileBorder,
        );

    final base = ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      fontFamily: fontFamily,
      scaffoldBackgroundColor: c.background,
      extensions: [c],
      splashFactory: InkSparkle.splashFactory,
      visualDensity: VisualDensity.standard,
    );

    final t = base.textTheme;
    TextStyle s(
      TextStyle? style,
      double size,
      FontWeight weight, {
      double tracking = 0,
      double? height,
      Color? color,
    }) => (style ?? const TextStyle()).copyWith(
      fontFamily: fontFamily,
      fontSize: size,
      fontWeight: weight,
      letterSpacing: tracking,
      height: height,
      color: color ?? c.textPrimary,
    );
    final textTheme = t.copyWith(
      displayLarge: s(
        t.displayLarge,
        44,
        FontWeight.w700,
        tracking: -1.4,
        height: 1.05,
      ),
      displayMedium: s(
        t.displayMedium,
        36,
        FontWeight.w700,
        tracking: -1.0,
        height: 1.08,
      ),
      displaySmall: s(
        t.displaySmall,
        30,
        FontWeight.w700,
        tracking: -0.8,
        height: 1.1,
      ),
      headlineLarge: s(t.headlineLarge, 28, FontWeight.w700, tracking: -0.6),
      headlineMedium: s(t.headlineMedium, 24, FontWeight.w600, tracking: -0.5),
      headlineSmall: s(t.headlineSmall, 21, FontWeight.w600, tracking: -0.4),
      titleLarge: s(t.titleLarge, 19, FontWeight.w600, tracking: -0.3),
      titleMedium: s(t.titleMedium, 16, FontWeight.w600, tracking: -0.15),
      titleSmall: s(t.titleSmall, 14, FontWeight.w600, tracking: -0.05),
      bodyLarge: s(t.bodyLarge, 16, FontWeight.w400, height: 1.45),
      bodyMedium: s(
        t.bodyMedium,
        14.5,
        FontWeight.w400,
        height: 1.45,
        color: c.textSecondary,
      ),
      bodySmall: s(
        t.bodySmall,
        12.5,
        FontWeight.w400,
        height: 1.4,
        color: c.textSecondary,
      ),
      labelLarge: s(t.labelLarge, 14.5, FontWeight.w600, tracking: -0.05),
      labelMedium: s(t.labelMedium, 12.5, FontWeight.w600, tracking: 0.1),
      labelSmall: s(
        t.labelSmall,
        11,
        FontWeight.w600,
        tracking: 0.6,
        color: c.textSecondary,
      ),
    );

    final shape12 = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(14),
    );
    return base.copyWith(
      textTheme: textTheme,
      primaryTextTheme: textTheme,
      iconTheme: IconThemeData(color: c.textPrimary, size: 22),
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        foregroundColor: c.textPrimary,
        titleTextStyle: textTheme.titleLarge,
      ),
      dividerTheme: DividerThemeData(
        color: c.tileBorder,
        thickness: 1,
        space: 1,
      ),
      switchTheme: SwitchThemeData(
        trackOutlineColor: WidgetStateProperty.all(Colors.transparent),
        thumbColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected)
              ? Colors.white
              : (dark ? const Color(0xFF8A93A3) : Colors.white),
        ),
        trackColor: WidgetStateProperty.resolveWith((s) {
          if (s.contains(WidgetState.disabled)) {
            return dark ? const Color(0xFF1C222C) : const Color(0xFFE2E6ED);
          }
          return s.contains(WidgetState.selected)
              ? primary
              : (dark ? const Color(0xFF262D39) : const Color(0xFFD5DBE5));
        }),
      ),
      sliderTheme: SliderThemeData(
        trackHeight: 6,
        activeTrackColor: primary,
        inactiveTrackColor: dark
            ? const Color(0xFF242A35)
            : const Color(0xFFDDE3EC),
        thumbColor: Colors.white,
        overlayColor: primary.withValues(alpha: 0.12),
        thumbShape: const RoundSliderThumbShape(
          enabledThumbRadius: 11,
          elevation: 3,
          pressedElevation: 6,
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(48, 50),
          padding: const EdgeInsets.symmetric(horizontal: 22),
          shape: shape12,
          textStyle: textTheme.labelLarge,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(48, 46),
          padding: const EdgeInsets.symmetric(horizontal: 18),
          shape: shape12,
          side: BorderSide(color: scheme.outline),
          foregroundColor: c.textPrimary,
          textStyle: textTheme.labelLarge,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          shape: shape12,
          textStyle: textTheme.labelLarge,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: dark ? const Color(0xFF12161D) : const Color(0xFFF3F5F9),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 15,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: c.tileBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: primary, width: 1.6),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: c.danger),
        ),
        labelStyle: textTheme.bodyMedium,
        floatingLabelStyle: textTheme.labelMedium?.copyWith(color: primary),
        hintStyle: textTheme.bodyMedium?.copyWith(color: c.textTertiary),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: dark ? const Color(0xFF12161D) : Colors.white,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(26)),
        titleTextStyle: textTheme.titleLarge,
        contentTextStyle: textTheme.bodyMedium,
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: dark ? const Color(0xFF0E1218) : Colors.white,
        surfaceTintColor: Colors.transparent,
        modalBarrierColor: Colors.black.withValues(alpha: dark ? 0.6 : 0.32),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        showDragHandle: false,
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: primary,
        linearTrackColor: dark
            ? const Color(0xFF1C222C)
            : const Color(0xFFE3E8F0),
        circularTrackColor: Colors.transparent,
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: dark ? const Color(0xFF2A303B) : const Color(0xFF1F2633),
          borderRadius: BorderRadius.circular(10),
        ),
        textStyle: textTheme.labelMedium?.copyWith(color: Colors.white),
      ),
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: FadeForwardsPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
        },
      ),
    );
  }
}
