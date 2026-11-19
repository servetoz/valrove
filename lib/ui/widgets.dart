import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import 'glass.dart';
import 'theme.dart';

// ---------------------------------------------------------------------------
// Page scaffold
// ---------------------------------------------------------------------------

/// Standard secondary page: large title that collapses into a glass app bar.
class ValrovePage extends StatelessWidget {
  const ValrovePage({
    super.key,
    required this.title,
    this.subtitle,
    required this.children,
    this.actions = const [],
    this.onRefresh,
    this.padding = const EdgeInsets.fromLTRB(16, 4, 16, 32),
    this.floating,
    this.accent,
    this.scrollable = true,
  });

  final String title;
  final String? subtitle;
  final List<Widget> children;
  final List<Widget> actions;
  final Future<void> Function()? onRefresh;
  final EdgeInsets padding;
  final Widget? floating;
  final Color? accent;

  /// False keeps the page still: [children] are laid out in a column that
  /// gets the height below the header, so drags on the content (a joystick,
  /// hold-to-drive buttons) never move the page.
  final bool scrollable;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final top = MediaQuery.paddingOf(context).top;
    final bottom =
        MediaQuery.paddingOf(context).bottom + (floating != null ? 88 : 0);
    final header = _PageHeaderDelegate(
      title: title,
      subtitle: subtitle,
      actions: actions,
      topPadding: top,
      canPop: Navigator.of(context).canPop(),
    );
    Widget scroll = scrollable
        ? CustomScrollView(
            physics: const BouncingScrollPhysics(
              parent: AlwaysScrollableScrollPhysics(),
            ),
            slivers: [
              SliverPersistentHeader(pinned: true, delegate: header),
              SliverPadding(
                padding: padding,
                sliver: SliverList.list(children: children),
              ),
              SliverToBoxAdapter(child: SizedBox(height: bottom)),
            ],
          )
        : Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                height: header.maxExtent,
                child: header.build(context, 0, false),
              ),
              Expanded(
                child: Padding(
                  padding: padding + EdgeInsets.only(bottom: bottom),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: children,
                  ),
                ),
              ),
            ],
          );
    if (onRefresh != null) {
      scroll = RefreshIndicator(
        onRefresh: onRefresh!,
        edgeOffset: top + 56,
        child: scroll,
      );
    }
    return Scaffold(
      backgroundColor: c.background,
      body: AmbientBackground(
        accent: accent ?? Theme.of(context).colorScheme.primary,
        intensity: 0.55,
        child: Stack(
          children: [
            Positioned.fill(child: scroll),
            if (floating != null)
              Positioned(
                left: 16,
                right: 16,
                bottom: MediaQuery.paddingOf(context).bottom + 16,
                child: floating!,
              ),
          ],
        ),
      ),
    );
  }
}

class _PageHeaderDelegate extends SliverPersistentHeaderDelegate {
  _PageHeaderDelegate({
    required this.title,
    required this.subtitle,
    required this.actions,
    required this.topPadding,
    required this.canPop,
  });

  final String title;
  final String? subtitle;
  final List<Widget> actions;
  final double topPadding;
  final bool canPop;

  static const _barHeight = 58.0;

  double get _expandedBody => subtitle == null ? 62 : 86;

  @override
  double get minExtent => topPadding + _barHeight;

  @override
  double get maxExtent => topPadding + _barHeight + _expandedBody;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    final t = (shrinkOffset / (maxExtent - minExtent)).clamp(0.0, 1.0);
    final c = context.colors;
    return Stack(
      fit: StackFit.expand,
      children: [
        Glass(
          radius: 0,
          shadow: false,
          opacity: t,
          child: const SizedBox.expand(),
        ),
        Positioned(
          top: topPadding,
          left: 6,
          right: 8,
          height: _barHeight,
          child: Row(
            children: [
              if (canPop)
                IconButton(
                  tooltip: 'Back',
                  icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
                  onPressed: () => Navigator.of(context).maybePop(),
                )
              else
                const SizedBox(width: 10),
              Expanded(
                child: Opacity(
                  opacity: Curves.easeIn.transform(t),
                  child: Text(
                    title,
                    style: context.text.titleMedium,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
              ...actions,
            ],
          ),
        ),
        Positioned(
          left: 20,
          right: 20,
          bottom: 10 + (1 - t) * 4,
          child: Opacity(
            opacity: 1 - Curves.easeOut.transform(math.min(1, t * 1.6)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: context.text.headlineLarge,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    subtitle!,
                    style: context.text.bodyMedium?.copyWith(
                      color: c.textSecondary,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }

  @override
  bool shouldRebuild(_PageHeaderDelegate old) =>
      old.title != title ||
      old.subtitle != subtitle ||
      old.actions != actions ||
      old.topPadding != topPadding;
}

// ---------------------------------------------------------------------------
// Cards & sections
// ---------------------------------------------------------------------------

class SectionLabel extends StatelessWidget {
  const SectionLabel(
    this.text, {
    super.key,
    this.icon,
    this.trailing,
    this.padding = const EdgeInsets.fromLTRB(6, 22, 6, 10),
  });

  final String text;
  final IconData? icon;
  final Widget? trailing;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding,
      child: Row(
        children: [
          if (icon != null) ...[
            Icon(icon, size: 16, color: context.colors.textTertiary),
            const SizedBox(width: 8),
          ],
          Expanded(
            child: Text(
              text.toUpperCase(),
              style: context.text.labelSmall?.copyWith(
                color: context.colors.textTertiary,
                letterSpacing: 1.1,
              ),
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}

/// Solid card used for grouped content on secondary pages.
class ValroveCard extends StatelessWidget {
  const ValroveCard({
    super.key,
    required this.child,
    this.padding = EdgeInsets.zero,
    this.color,
    this.onTap,
    this.radius = 22,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color? color;
  final VoidCallback? onTap;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final card = DecoratedBox(
      decoration: BoxDecoration(
        color: color ?? c.tile,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: c.tileBorder),
        boxShadow: context.isDark
            ? null
            : [
                BoxShadow(
                  color: c.shadow.withValues(alpha: 0.05),
                  blurRadius: 22,
                  offset: const Offset(0, 10),
                  spreadRadius: -8,
                ),
              ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        // List tiles and ink effects need a Material between them and the
        // decorated background.
        child: Material(
          type: MaterialType.transparency,
          child: Padding(padding: padding, child: child),
        ),
      ),
    );
    return onTap == null
        ? card
        : Pressable(onTap: onTap, scale: 0.98, child: card);
  }
}

/// Card with tiles separated by inset dividers.
class TileGroup extends StatelessWidget {
  const TileGroup({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final visible = children
        .where((w) => w is! SizedBox || (w.width ?? 1) != 0)
        .toList();
    if (visible.isEmpty) return const SizedBox.shrink();
    return ValroveCard(
      child: Column(
        children: [
          for (var i = 0; i < visible.length; i++) ...[
            if (i > 0)
              Divider(indent: 64, height: 1, color: context.colors.tileBorder),
            visible[i],
          ],
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Tiles
// ---------------------------------------------------------------------------

class TileIcon extends StatelessWidget {
  const TileIcon(this.icon, {super.key, this.color, this.size = 36});

  final IconData icon;
  final Color? color;
  final double size;

  @override
  Widget build(BuildContext context) {
    final tint = color ?? context.scheme.primary;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: tint.withValues(alpha: context.isDark ? 0.16 : 0.12),
        borderRadius: BorderRadius.circular(size * 0.32),
      ),
      child: Icon(icon, size: size * 0.55, color: tint),
    );
  }
}

/// Base tile: icon, title, subtitle and a trailing widget.
class ValroveTile extends StatelessWidget {
  const ValroveTile({
    super.key,
    required this.title,
    this.subtitle,
    this.subtitleWidget,
    this.icon,
    this.iconColor,
    this.trailing,
    this.onTap,
    this.enabled = true,
    this.dense = false,
  });

  final String title;
  final String? subtitle;
  final Widget? subtitleWidget;
  final IconData? icon;
  final Color? iconColor;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool enabled;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final content = Padding(
      padding: EdgeInsets.symmetric(horizontal: 14, vertical: dense ? 10 : 14),
      child: Row(
        children: [
          if (icon != null) ...[
            TileIcon(icon!, color: iconColor),
            const SizedBox(width: 14),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: context.text.titleSmall?.copyWith(
                    color: enabled ? c.textPrimary : c.textTertiary,
                  ),
                ),
                if (subtitleWidget != null) ...[
                  const SizedBox(height: 3),
                  subtitleWidget!,
                ] else if (subtitle != null && subtitle!.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(subtitle!, style: context.text.bodySmall),
                ],
              ],
            ),
          ),
          if (trailing != null) ...[const SizedBox(width: 12), trailing!],
        ],
      ),
    );
    if (onTap == null) return content;
    return Material(
      type: MaterialType.transparency,
      child: InkWell(onTap: enabled ? onTap : null, child: content),
    );
  }
}

class NavTile extends StatelessWidget {
  const NavTile({
    super.key,
    required this.title,
    this.subtitle,
    required this.icon,
    this.iconColor,
    required this.onTap,
    this.badge,
  });

  final String title;
  final String? subtitle;
  final IconData icon;
  final Color? iconColor;
  final VoidCallback onTap;
  final Widget? badge;

  @override
  Widget build(BuildContext context) => ValroveTile(
    title: title,
    subtitle: subtitle,
    icon: icon,
    iconColor: iconColor,
    onTap: onTap,
    trailing: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        ?badge,
        Icon(Icons.chevron_right_rounded, color: context.colors.textTertiary),
      ],
    ),
  );
}

/// Toggle tile bound to an async value.
class ToggleTile extends StatelessWidget {
  const ToggleTile({
    super.key,
    required this.title,
    this.subtitle,
    this.icon,
    this.iconColor,
    required this.value,
    required this.onChanged,
    this.busy = false,
    this.error = false,
  });

  final String title;
  final String? subtitle;
  final IconData? icon;
  final Color? iconColor;

  /// Null while unknown.
  final bool? value;
  final ValueChanged<bool>? onChanged;
  final bool busy;
  final bool error;

  @override
  Widget build(BuildContext context) {
    Widget trailing;
    if (error) {
      trailing = Text(
        'Error',
        style: context.text.labelMedium?.copyWith(color: context.colors.danger),
      );
    } else {
      trailing = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedOpacity(
            opacity: busy ? 1 : 0,
            duration: const Duration(milliseconds: 200),
            child: const Padding(
              padding: EdgeInsets.only(right: 8),
              child: SizedBox.square(
                dimension: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          ),
          Switch(
            value: value ?? false,
            onChanged: value == null || busy ? null : onChanged,
          ),
        ],
      );
    }
    return ValroveTile(
      title: title,
      subtitle: subtitle,
      icon: icon,
      iconColor: iconColor,
      trailing: trailing,
      onTap: value == null || busy || error || onChanged == null
          ? null
          : () => onChanged!(!value!),
    );
  }
}

/// Tile with a trailing button.
class ActionTile extends StatelessWidget {
  const ActionTile({
    super.key,
    required this.title,
    this.subtitle,
    this.icon,
    this.iconColor,
    required this.actionLabel,
    required this.onAction,
    this.busy = false,
    this.danger = false,
    this.subtitleWidget,
  });

  final String title;
  final String? subtitle;
  final Widget? subtitleWidget;
  final IconData? icon;
  final Color? iconColor;
  final String actionLabel;
  final VoidCallback? onAction;
  final bool busy;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final color = danger ? context.colors.danger : context.scheme.primary;
    return ValroveTile(
      title: title,
      subtitle: subtitle,
      subtitleWidget: subtitleWidget,
      icon: icon,
      iconColor: iconColor ?? (danger ? context.colors.danger : null),
      trailing: SizedBox(
        height: 38,
        child: FilledButton.tonal(
          style: FilledButton.styleFrom(
            minimumSize: const Size(64, 38),
            padding: const EdgeInsets.symmetric(horizontal: 16),
            backgroundColor: color.withValues(
              alpha: context.isDark ? 0.18 : 0.12,
            ),
            foregroundColor: color,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          onPressed: busy ? null : onAction,
          child: busy
              ? SizedBox.square(
                  dimension: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: color,
                  ),
                )
              : Text(actionLabel),
        ),
      ),
    );
  }
}

/// Key/value information row.
class InfoRow extends StatelessWidget {
  const InfoRow(
    this.label,
    this.value, {
    super.key,
    this.mono = false,
    this.valueColor,
  });

  final String label;
  final String value;
  final bool mono;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(flex: 4, child: Text(label, style: context.text.bodyMedium)),
          const SizedBox(width: 12),
          Expanded(
            flex: 6,
            child: SelectableText(
              value,
              textAlign: TextAlign.right,
              style:
                  (mono
                          ? context.text.bodyMedium?.copyWith(
                              fontFamily: AppTheme.monoFamily,
                              fontSize: 13,
                            )
                          : context.text.bodyMedium)
                      ?.copyWith(
                        color: valueColor ?? context.colors.textPrimary,
                        fontWeight: FontWeight.w500,
                      ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Status
// ---------------------------------------------------------------------------

/// Pulsing state indicator.
class Beacon extends StatefulWidget {
  const Beacon({
    super.key,
    required this.color,
    this.size = 10,
    this.active = true,
  });

  final Color color;
  final double size;
  final bool active;

  @override
  State<Beacon> createState() => _BeaconState();
}

class _BeaconState extends State<Beacon> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1800),
  );

  @override
  void initState() {
    super.initState();
    if (widget.active) _c.repeat();
  }

  @override
  void didUpdateWidget(Beacon old) {
    super.didUpdateWidget(old);
    if (widget.active && !_c.isAnimating) _c.repeat();
    if (!widget.active && _c.isAnimating) _c.stop();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.size;
    return SizedBox.square(
      dimension: s * 2.4,
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, _) => CustomPaint(
          painter: _BeaconPainter(
            widget.color,
            s,
            widget.active ? _c.value : -1,
          ),
        ),
      ),
    );
  }
}

class _BeaconPainter extends CustomPainter {
  _BeaconPainter(this.color, this.size, this.t);

  final Color color;
  final double size;
  final double t;

  @override
  void paint(Canvas canvas, Size canvasSize) {
    final c = canvasSize.center(Offset.zero);
    if (t >= 0) {
      final r = size / 2 * (1 + t * 1.4);
      canvas.drawCircle(
        c,
        r,
        Paint()..color = color.withValues(alpha: (1 - t) * 0.45),
      );
    }
    canvas.drawCircle(c, size / 2, Paint()..color = color);
    canvas.drawCircle(
      c,
      size / 2 * 0.42,
      Paint()..color = Colors.white.withValues(alpha: 0.55),
    );
  }

  @override
  bool shouldRepaint(_BeaconPainter old) => old.t != t || old.color != color;
}

/// Battery level pill with charging indication.
class BatteryPill extends StatelessWidget {
  const BatteryPill({
    super.key,
    required this.level,
    required this.flag,
    this.compact = false,
  });

  final double level;
  final String flag;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final color = level > 60 ? c.success : (level > 20 ? c.warning : c.danger);
    final charging = flag == 'charging';
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 26,
          height: 13,
          child: CustomPaint(
            painter: _BatteryPainter(level / 100, color, c.textTertiary),
          ),
        ),
        const SizedBox(width: 6),
        Text(
          '${level.round()}%',
          style: context.text.labelLarge?.copyWith(
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
        if (charging) ...[
          const SizedBox(width: 2),
          Icon(Icons.bolt_rounded, size: 16, color: c.success),
        ],
      ],
    );
  }
}

class _BatteryPainter extends CustomPainter {
  _BatteryPainter(this.fraction, this.color, this.outline);

  final double fraction;
  final Color color;
  final Color outline;

  @override
  void paint(Canvas canvas, Size size) {
    final body = RRect.fromRectAndRadius(
      Rect.fromLTWH(0, 0, size.width - 3, size.height),
      const Radius.circular(3.5),
    );
    canvas.drawRRect(
      body,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4
        ..color = outline,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(size.width - 2, size.height * 0.3, 2, size.height * 0.4),
        const Radius.circular(1),
      ),
      Paint()..color = outline,
    );
    final inner = Rect.fromLTWH(
      2.2,
      2.2,
      (size.width - 7.4) * fraction.clamp(0.0, 1.0),
      size.height - 4.4,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(inner, const Radius.circular(2)),
      Paint()..color = color,
    );
  }

  @override
  bool shouldRepaint(_BatteryPainter old) =>
      old.fraction != fraction || old.color != color;
}

/// Rounded linear progress.
class ProgressTrack extends StatelessWidget {
  const ProgressTrack({
    super.key,
    required this.value,
    this.color,
    this.height = 6,
  });

  final double? value;
  final Color? color;
  final double height;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(height),
      child: SizedBox(
        height: height,
        child: value == null
            ? LinearProgressIndicator(color: color)
            : TweenAnimationBuilder<double>(
                tween: Tween(end: value!.clamp(0, 1)),
                duration: const Duration(milliseconds: 600),
                curve: Curves.easeOutCubic,
                builder: (context, v, _) => LinearProgressIndicator(
                  value: v,
                  color: color,
                  minHeight: height,
                ),
              ),
      ),
    );
  }
}

class CountBadge extends StatelessWidget {
  const CountBadge(this.text, {super.key, this.color});

  final String text;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minWidth: 18),
      height: 18,
      padding: const EdgeInsets.symmetric(horizontal: 5),
      decoration: BoxDecoration(
        color: color ?? context.colors.danger,
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: context.colors.background, width: 1.5),
      ),
      alignment: Alignment.center,
      child: Text(
        text,
        style: const TextStyle(
          fontFamily: AppTheme.fontFamily,
          fontSize: 10.5,
          fontWeight: FontWeight.w700,
          color: Colors.white,
          height: 1,
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Loading / empty / error
// ---------------------------------------------------------------------------

/// Shimmering placeholder.
class Skeleton extends StatefulWidget {
  const Skeleton({super.key, this.height = 16, this.width, this.radius = 10});

  final double height;
  final double? width;
  final double radius;

  @override
  State<Skeleton> createState() => _SkeletonState();
}

class _SkeletonState extends State<Skeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  )..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final base = context.isDark
        ? const Color(0xFF161B23)
        : const Color(0xFFE6EAF1);
    final shine = context.isDark
        ? const Color(0xFF222935)
        : const Color(0xFFF4F6FA);
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) => Container(
        height: widget.height,
        width: widget.width,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(widget.radius),
          gradient: LinearGradient(
            begin: Alignment(-1.5 + _c.value * 3, 0),
            end: Alignment(-0.5 + _c.value * 3, 0),
            colors: [base, shine, base],
          ),
        ),
      ),
    );
  }
}

/// A card-shaped skeleton list.
class SkeletonCard extends StatelessWidget {
  const SkeletonCard({super.key, this.rows = 3});

  final int rows;

  @override
  Widget build(BuildContext context) {
    return ValroveCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          for (var i = 0; i < rows; i++) ...[
            if (i > 0) const SizedBox(height: 18),
            Row(
              children: [
                const Skeleton(width: 36, height: 36, radius: 11),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Skeleton(height: 13, width: 120 + (i % 2) * 40),
                      const SizedBox(height: 8),
                      const Skeleton(height: 10),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.message,
    this.action,
  });

  final IconData icon;
  final String title;
  final String? message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 36),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                colors: [
                  context.scheme.primary.withValues(alpha: 0.18),
                  context.scheme.primary.withValues(alpha: 0.04),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: Icon(icon, size: 32, color: context.scheme.primary),
          ),
          const SizedBox(height: 18),
          Text(
            title,
            style: context.text.titleMedium,
            textAlign: TextAlign.center,
          ),
          if (message != null) ...[
            const SizedBox(height: 6),
            Text(
              message!,
              style: context.text.bodyMedium?.copyWith(color: c.textSecondary),
              textAlign: TextAlign.center,
            ),
          ],
          if (action != null) ...[const SizedBox(height: 18), action!],
        ],
      ),
    );
  }
}

class ErrorState extends StatelessWidget {
  const ErrorState({
    super.key,
    required this.message,
    this.onRetry,
    this.title = 'Something went wrong',
  });

  final String title;
  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return EmptyState(
      icon: Icons.wifi_tethering_error_rounded,
      title: title,
      message: message,
      action: onRetry == null
          ? null
          : FilledButton.tonalIcon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Try again'),
            ),
    );
  }
}

/// Inline error text used inside cards.
class InlineError extends StatelessWidget {
  const InlineError(this.message, {super.key, this.onRetry});

  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Icon(
            Icons.error_outline_rounded,
            color: context.colors.danger,
            size: 20,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: context.text.bodyMedium?.copyWith(
                color: context.colors.danger,
              ),
            ),
          ),
          if (onRetry != null)
            TextButton(onPressed: onRetry, child: const Text('Retry')),
        ],
      ),
    );
  }
}
