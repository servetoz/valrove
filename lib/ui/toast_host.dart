import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../state/toasts.dart';
import 'glass.dart';
import 'theme.dart';

/// Renders queued toasts as glass pills at the top of the screen.
class ToastHost extends ConsumerWidget {
  const ToastHost({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.watch(toastProvider);
    return Stack(
      children: [
        child,
        Positioned(
          top: MediaQuery.paddingOf(context).top + 8,
          left: 12,
          right: 12,
          child: ListenableBuilder(
            listenable: controller,
            builder: (context, _) => Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final toast in controller.toasts)
                  _ToastView(
                    key: ValueKey(toast.id),
                    toast: toast,
                    onDismiss: () => controller.dismiss(toast),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _ToastView extends StatefulWidget {
  const _ToastView({super.key, required this.toast, required this.onDismiss});

  final Toast toast;
  final VoidCallback onDismiss;

  @override
  State<_ToastView> createState() => _ToastViewState();
}

class _ToastViewState extends State<_ToastView>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 360),
  )..forward();
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer(
      Duration(
        milliseconds: widget.toast.kind == ToastKind.error ? 6000 : 3200,
      ),
      _close,
    );
  }

  Future<void> _close() async {
    _timer?.cancel();
    if (!mounted) return;
    await _c.reverse();
    if (mounted) widget.onDismiss();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final (icon, color) = switch (widget.toast.kind) {
      ToastKind.error => (Icons.error_rounded, c.danger),
      ToastKind.success => (Icons.check_circle_rounded, c.success),
      ToastKind.info => (Icons.info_rounded, c.info),
    };
    final anim = CurvedAnimation(
      parent: _c,
      curve: Curves.easeOutBack,
      reverseCurve: Curves.easeIn,
    );
    return SizeTransition(
      sizeFactor: CurvedAnimation(parent: _c, curve: Curves.easeOut),
      alignment: Alignment.topCenter,
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, child) =>
            GlassOpacity(opacity: _c.value, child: child!),
        child: SlideTransition(
          position: Tween(
            begin: const Offset(0, -0.4),
            end: Offset.zero,
          ).animate(anim),
          child: Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Dismissible(
              key: ValueKey(widget.toast.id),
              direction: DismissDirection.up,
              onDismissed: (_) => widget.onDismiss(),
              child: Material(
                type: MaterialType.transparency,
                child: GestureDetector(
                  onTap: _close,
                  child: Glass(
                    radius: 20,
                    tint: color,
                    padding: const EdgeInsets.fromLTRB(14, 12, 16, 12),
                    child: Row(
                      children: [
                        Icon(icon, color: color, size: 22),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                widget.toast.message,
                                style: context.text.titleSmall,
                              ),
                              if (widget.toast.detail != null) ...[
                                const SizedBox(height: 2),
                                Text(
                                  widget.toast.detail!,
                                  style: context.text.bodySmall,
                                  maxLines: 4,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
