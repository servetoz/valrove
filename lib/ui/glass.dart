import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:material_ui/material_ui.dart';

import 'theme.dart';
import 'haptics.dart';

/// Blur strength of every glass surface.
///
/// Backdrop blurs are the most expensive thing the app draws: each one makes
/// the GPU copy the whole frame out of and back into tile memory. Glass uses
/// grouped backdrop filters, so inside a [SharedBackdrop] all surfaces with
/// this identical blur share one backdrop capture and one blur pass.
const double kGlassBlurSigma = 28;

/// Lets the glass surfaces below share one backdrop capture and blur pass.
///
/// Every grouped blur reads the content as it was when the first one was
/// drawn, so the glass surfaces inside should not overlap each other.
class SharedBackdrop extends StatefulWidget {
  const SharedBackdrop({super.key, required this.child});

  final Widget child;

  @override
  State<SharedBackdrop> createState() => _SharedBackdropState();
}

class _SharedBackdropState extends State<SharedBackdrop> {
  // A stable key: a new one would defeat sharing across frames and rebuild
  // every glass surface below.
  final _key = BackdropKey();

  @override
  Widget build(BuildContext context) =>
      BackdropGroup(backdropKey: _key, child: widget.child);
}

/// Fades the [Glass] surfaces below it without an offscreen layer.
///
/// Wrapping a backdrop blur in [Opacity] renders it into a separate layer, where
/// it only sees that (empty) layer instead of the content behind it and can't
/// share the backdrop of its group. Glass reads this value and fades its tint,
/// blur and content individually instead. Content outside of glass is not
/// affected.
class GlassOpacity extends StatelessWidget {
  const GlassOpacity({super.key, required this.opacity, required this.child});

  final double opacity;
  final Widget child;

  static double of(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<_GlassOpacityScope>()
          ?.opacity ??
      1;

  @override
  Widget build(BuildContext context) => _GlassOpacityScope(
    opacity: (opacity * of(context)).clamp(0.0, 1.0),
    child: child,
  );
}

/// [FadeTransition] for subtrees whose visible content is all inside [Glass]:
/// fades through [GlassOpacity], so the blur keeps working during the
/// animation.
class GlassFadeTransition extends AnimatedWidget {
  const GlassFadeTransition({
    super.key,
    required Animation<double> opacity,
    required this.child,
  }) : super(listenable: opacity);

  final Widget child;

  @override
  Widget build(BuildContext context) => GlassOpacity(
    opacity: (listenable as Animation<double>).value,
    child: child,
  );
}

class _GlassOpacityScope extends InheritedWidget {
  const _GlassOpacityScope({required this.opacity, required super.child});

  final double opacity;

  @override
  bool updateShouldNotify(_GlassOpacityScope oldWidget) =>
      oldWidget.opacity != opacity;
}

/// Frosted, translucent panel ("liquid glass").
class Glass extends StatelessWidget {
  const Glass({
    super.key,
    required this.child,
    this.radius = 24,
    this.padding = EdgeInsets.zero,
    this.tint,
    this.shadow = true,
    this.borderRadius,
    this.opacity = 1,
  });

  final Widget child;
  final double radius;
  final BorderRadius? borderRadius;
  final EdgeInsetsGeometry padding;

  /// Optional color mixed into the glass (e.g. the state accent).
  final Color? tint;
  final bool shadow;

  /// Fades the surface (multiplied with any [GlassOpacity] above).
  final double opacity;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final o = (opacity * GlassOpacity.of(context)).clamp(0.0, 1.0);
    Color fade(Color color) =>
        o >= 1 ? color : color.withValues(alpha: color.a * o);
    final br = borderRadius ?? BorderRadius.circular(radius);
    var top = c.glassTop;
    var bottom = c.glassBottom;
    if (tint != null) {
      top = Color.alphaBlend(
        tint!.withValues(alpha: context.isDark ? 0.10 : 0.08),
        top,
      );
      bottom = Color.alphaBlend(
        tint!.withValues(alpha: context.isDark ? 0.06 : 0.04),
        bottom,
      );
    }
    Widget content = Material(
      type: MaterialType.transparency,
      child: Padding(padding: padding, child: child),
    );
    // Only the content goes into a layer; the blur stays outside of it.
    if (o < 1) content = Opacity(opacity: o, child: content);
    // While fading, the blur weakens instead of the frosted area popping out.
    final sigma = kGlassBlurSigma * o;
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: br,
        boxShadow: shadow
            ? [
                BoxShadow(
                  color: fade(c.shadow),
                  blurRadius: 30,
                  offset: const Offset(0, 12),
                  spreadRadius: -6,
                ),
              ]
            : null,
      ),
      child: ClipRRect(
        borderRadius: br,
        child: BackdropFilter.grouped(
          enabled: o > 0.01,
          filter: ui.ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
          child: CustomPaint(
            foregroundPainter: _RimPainter(
              br,
              fade(c.glassBorder),
              fade(c.glassBorderSoft),
            ),
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [fade(top), fade(bottom)],
                ),
              ),
              child: content,
            ),
          ),
        ),
      ),
    );
  }
}

/// Paints a 1px rim that is brighter at the top, like light hitting glass.
class _RimPainter extends CustomPainter {
  _RimPainter(this.radius, this.bright, this.soft);

  final BorderRadius radius;
  final Color bright;
  final Color soft;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final rrect = radius.toRRect(rect).deflate(0.5);
    canvas.drawRRect(
      rrect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..shader = ui.Gradient.linear(
          rect.topCenter,
          rect.bottomCenter,
          [bright, soft],
          [0, 0.6],
        ),
    );
  }

  @override
  bool shouldRepaint(_RimPainter old) =>
      old.bright != bright || old.soft != soft || old.radius != radius;
}

/// Progressive blur along one edge.
///
/// Bands that get narrower and stronger towards the edge are stacked on top of
/// each other. They are grouped backdrop filters, so inside a [SharedBackdrop]
/// they reuse the backdrop capture of the glass surfaces: each band blurs the
/// original content and covers the weaker, wider bands below it. A color fade
/// on top softens the steps.
class ProgressiveBlurEdge extends StatelessWidget {
  const ProgressiveBlurEdge({
    super.key,
    required this.height,
    this.top = true,
    this.maxSigma = 12,
    this.steps = 4,
    this.color,
  });

  final double height;
  final bool top;
  final double maxSigma;
  final int steps;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final fade = color ?? context.colors.background;
    return IgnorePointer(
      child: SizedBox(
        height: height,
        child: Stack(
          children: [
            for (var i = 0; i < steps; i++)
              Positioned(
                left: 0,
                right: 0,
                top: top ? 0 : null,
                bottom: top ? null : 0,
                height: height * (steps - i) / steps,
                child: ClipRect(
                  child: BackdropFilter.grouped(
                    filter: ui.ImageFilter.blur(
                      sigmaX: maxSigma * math.pow((i + 1) / steps, 1.5),
                      sigmaY: maxSigma * math.pow((i + 1) / steps, 1.5),
                    ),
                    child: const SizedBox.expand(),
                  ),
                ),
              ),
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: top ? Alignment.topCenter : Alignment.bottomCenter,
                    end: top ? Alignment.bottomCenter : Alignment.topCenter,
                    colors: [
                      fade.withValues(alpha: 0.78),
                      fade.withValues(alpha: 0.0),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Adds a tactile scale-down on press, optional haptics and an ink-free tap.
class Pressable extends StatefulWidget {
  const Pressable({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.scale = 0.95,
    this.haptic = true,
    this.enabled = true,
    this.semanticLabel,
  });

  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final double scale;
  final bool haptic;
  final bool enabled;
  final String? semanticLabel;

  @override
  State<Pressable> createState() => _PressableState();
}

class _PressableState extends State<Pressable> {
  bool _down = false;

  bool get _active =>
      widget.enabled && (widget.onTap != null || widget.onLongPress != null);

  void _set(bool down) {
    if (_down != down) setState(() => _down = down);
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      enabled: _active,
      label: widget.semanticLabel,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: _active ? (_) => _set(true) : null,
        onTapUp: _active ? (_) => _set(false) : null,
        onTapCancel: _active ? () => _set(false) : null,
        onTap: _active && widget.onTap != null
            ? () {
                if (widget.haptic) Haptics.selection();
                widget.onTap!();
              }
            : null,
        onLongPress: _active && widget.onLongPress != null
            ? () {
                _set(false);
                Haptics.medium();
                widget.onLongPress!();
              }
            : null,
        child: AnimatedScale(
          scale: _down ? widget.scale : 1,
          duration: Duration(milliseconds: _down ? 90 : 220),
          curve: _down ? Curves.easeOut : Curves.easeOutBack,
          child: AnimatedOpacity(
            opacity: widget.enabled ? 1 : 0.45,
            duration: const Duration(milliseconds: 200),
            child: widget.child,
          ),
        ),
      ),
    );
  }
}

/// Round glass icon button.
class GlassIconButton extends StatelessWidget {
  const GlassIconButton({
    super.key,
    required this.icon,
    required this.onPressed,
    this.size = 48,
    this.tooltip,
    this.badge,
    this.color,
    this.iconSize = 22,
  });

  final IconData icon;
  final VoidCallback? onPressed;
  final double size;
  final double iconSize;
  final String? tooltip;
  final Widget? badge;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    Widget button = Pressable(
      onTap: onPressed,
      semanticLabel: tooltip,
      child: SizedBox(
        width: size,
        height: size,
        child: Glass(
          radius: size / 2,
          child: Center(
            child: Icon(
              icon,
              size: iconSize,
              color: color ?? context.colors.textPrimary,
            ),
          ),
        ),
      ),
    );
    if (badge != null) {
      button = Stack(
        clipBehavior: Clip.none,
        children: [
          button,
          Positioned(top: -2, right: -2, child: badge!),
        ],
      );
    }
    return tooltip == null ? button : Tooltip(message: tooltip!, child: button);
  }
}

/// Full-screen ambient backdrop: a soft gradient with a glow tinted by the
/// robot state (pure black in dark mode for OLED panels).
class AmbientBackground extends StatelessWidget {
  const AmbientBackground({
    super.key,
    required this.accent,
    this.child,
    this.intensity = 1,
  });

  final Color accent;
  final double intensity;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final dark = context.isDark;
    return TweenAnimationBuilder<Color?>(
      tween: ColorTween(end: accent),
      duration: const Duration(milliseconds: 900),
      curve: Curves.easeOutCubic,
      builder: (context, color, child) {
        final glow = color ?? accent;
        return DecoratedBox(
          decoration: BoxDecoration(
            color: c.background,
            gradient: dark
                ? null
                : LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [c.background, c.backgroundAlt],
                  ),
          ),
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: const Alignment(0, -0.15),
                radius: 1.05,
                colors: [
                  glow.withValues(alpha: (dark ? 0.16 : 0.13) * intensity),
                  glow.withValues(alpha: 0),
                ],
              ),
            ),
            child: child,
          ),
        );
      },
      child: child,
    );
  }
}
