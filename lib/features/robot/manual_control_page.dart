import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/valetudo/capabilities.dart';
import '../../core/valetudo/client/valetudo_client.dart';
import '../../state/app_state.dart';
import '../../state/commands.dart';
import '../../state/data.dart';
import '../../state/session.dart';
import '../../ui/glass.dart';
import '../../ui/theme.dart';
import '../../ui/widgets.dart';
import '../camera/camera_view.dart';
import 'capability_tiles.dart';
import '../../ui/haptics.dart';

/// Movement vector: velocity −1…1 (forward positive), angle −120…120°.
class MoveVector {
  const MoveVector(this.velocity, this.angle);

  static const zero = MoveVector(0, 0);

  final double velocity;
  final double angle;

  bool get isZero => velocity == 0 && angle == 0;
}

/// Sends movement at 4 Hz while non-zero (keep-alive), with at most one
/// request in flight and a single "latest wins" pending slot.
class MovementSampler {
  MovementSampler({required this.send, required this.sendStop});

  final Future<void> Function(MoveVector v) send;
  final bool sendStop;

  MoveVector _current = MoveVector.zero;
  Timer? _timer;
  bool _inFlight = false;
  MoveVector? _pending;

  bool get active => _timer != null;

  void update(MoveVector v) {
    _current = v;
    if (!v.isZero && _timer == null) {
      _dispatch(v);
      _timer = Timer.periodic(
        const Duration(milliseconds: 250),
        (_) => _dispatch(_current),
      );
    } else if (v.isZero && _timer != null) {
      _timer?.cancel();
      _timer = null;
      if (sendStop) _dispatch(MoveVector.zero);
    }
  }

  void _dispatch(MoveVector v) {
    if (_inFlight) {
      _pending = v;
      return;
    }
    _inFlight = true;
    send(v).catchError((_) {}).whenComplete(() {
      _inFlight = false;
      final next = _pending;
      _pending = null;
      if (next != null) _dispatch(next);
    });
  }

  /// Stops sending; optionally issues a final stop vector.
  void halt({bool stop = true}) {
    final wasActive = _timer != null;
    _timer?.cancel();
    _timer = null;
    _current = MoveVector.zero;
    if (wasActive && stop && sendStop) _dispatch(MoveVector.zero);
  }
}

enum _InputMode { joystick, dpad, keyboard }

class ManualControlPage extends ConsumerStatefulWidget {
  const ManualControlPage({super.key});

  @override
  ConsumerState<ManualControlPage> createState() => _ManualControlPageState();
}

class _ManualControlPageState extends ConsumerState<ManualControlPage> {
  MovementSampler? _sampler;
  _InputMode? _mode;
  MoveVector _vector = MoveVector.zero;
  bool _toggling = false;
  final _keys = <String>{};
  final _focus = FocusNode();

  bool get _highRes =>
      ref.read(capsProvider).has(Cap.highResolutionManualControl);

  @override
  void initState() {
    super.initState();
    ref.listenManual<bool>(appInForegroundProvider, (prev, fg) {
      if (!fg) _reset();
    });
  }

  @override
  void dispose() {
    _sampler?.halt();
    _focus.dispose();
    super.dispose();
  }

  MovementSampler _ensureSampler(
    ValetudoClient client,
    bool highRes,
    List<String> commands,
  ) {
    return _sampler ??= MovementSampler(
      sendStop: highRes,
      send: (v) async {
        if (highRes) {
          await client.highResolutionManualControl(
            'move',
            velocity: v.velocity,
            angle: v.angle,
          );
          return;
        }
        String? cmd;
        if (v.velocity > 0.3 && commands.contains('forward')) {
          cmd = 'forward';
        } else if (v.velocity < -0.3 && commands.contains('backward')) {
          cmd = 'backward';
        } else if (v.angle > 30 && commands.contains('rotate_clockwise')) {
          cmd = 'rotate_clockwise';
        } else if (v.angle < -30 &&
            commands.contains('rotate_counterclockwise')) {
          cmd = 'rotate_counterclockwise';
        }
        if (cmd != null) {
          await client.manualControl('move', movementCommand: cmd);
        }
      },
    );
  }

  void _move(MoveVector v) {
    setState(() => _vector = v);
    _sampler?.update(v);
  }

  void _reset() {
    _keys.clear();
    if (mounted) setState(() => _vector = MoveVector.zero);
    _sampler?.halt();
  }

  Future<void> _toggle(bool enable) async {
    setState(() => _toggling = true);
    final cap = _highRes ? Cap.highResolutionManualControl : Cap.manualControl;
    if (!enable) _reset();
    await ref
        .read(commandsProvider)
        .run(
          enable ? 'enable manual control' : 'disable manual control',
          (c) => _highRes
              ? c.highResolutionManualControl(enable ? 'enable' : 'disable')
              : c.manualControl(enable ? 'enable' : 'disable'),
          invalidate: [
            _highRes
                ? highResManualControlEnabledProvider
                : manualControlEnabledProvider,
          ],
          refreshState: true,
          haptic: HapticKind.medium,
        );
    try {
      await ref.read(
        (_highRes
                ? highResManualControlEnabledProvider
                : manualControlEnabledProvider)
            .future,
      );
    } catch (_) {}
    if (mounted) setState(() => _toggling = false);
    debugPrint('manual control toggled via $cap');
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event, bool enabled) {
    if (!enabled || _mode != _InputMode.keyboard) return KeyEventResult.ignored;
    final key = switch (event.logicalKey) {
      LogicalKeyboardKey.keyW || LogicalKeyboardKey.arrowUp => 'w',
      LogicalKeyboardKey.keyS || LogicalKeyboardKey.arrowDown => 's',
      LogicalKeyboardKey.keyA || LogicalKeyboardKey.arrowLeft => 'a',
      LogicalKeyboardKey.keyD || LogicalKeyboardKey.arrowRight => 'd',
      _ => null,
    };
    if (key == null) return KeyEventResult.ignored;
    if (event is KeyDownEvent) {
      _keys.add(key);
    } else if (event is KeyUpEvent) {
      _keys.remove(key);
    } else {
      return KeyEventResult.handled;
    }
    _applyKeys();
    return KeyEventResult.handled;
  }

  /// On-screen key caps: held like keyboard keys.
  void _setKey(String key, bool down) {
    if (down) {
      _keys.add(key);
    } else {
      _keys.remove(key);
    }
    _applyKeys();
  }

  void _applyKeys() {
    final y = (_keys.contains('w') ? 1 : 0) - (_keys.contains('s') ? 1 : 0);
    final x = (_keys.contains('d') ? 1 : 0) - (_keys.contains('a') ? 1 : 0);
    if (x == 0 && y == 0) {
      _move(MoveVector.zero);
    } else if (_highRes) {
      final len = math.sqrt(x * x + y * y);
      _move(MoveVector(y / len, x / len * 120));
    } else {
      _move(
        y > 0
            ? const MoveVector(1, 0)
            : y < 0
            ? const MoveVector(-1, 0)
            : x < 0
            ? const MoveVector(0, -120)
            : const MoveVector(0, 120),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final caps = ref.watch(capsProvider);
    final highRes = caps.has(Cap.highResolutionManualControl);
    final legacy = caps.has(Cap.manualControl);
    if (!highRes && !legacy) {
      return const ValrovePage(
        title: 'Manual control',
        children: [
          EmptyState(
            icon: Icons.sports_esports_rounded,
            title: 'Not supported',
            message: 'This robot does not support manual control.',
          ),
        ],
      );
    }
    _mode ??= highRes ? _InputMode.joystick : _InputMode.dpad;
    final state = ref.watch(
      highRes
          ? highResManualControlEnabledProvider
          : manualControlEnabledProvider,
    );
    final commands = highRes
        ? const <String>[]
        : (ref.watch(movementCommandsProvider).value ?? const <String>[]);
    final client = ref.watch(clientProvider);
    final enabled =
        state.value == true &&
        (highRes || ref.watch(movementCommandsProvider).hasValue);
    if (client != null) _ensureSampler(client, highRes, commands);
    if (!enabled && _sampler?.active == true) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _sampler?.halt(stop: false),
      );
    }
    final cameraEnabled =
        caps.has(Cap.duststreaming) &&
        (ref.watch(duststreamingEnabledProvider).value ?? false);
    final cameraLight = caps.has(Cap.cameraLightControl);
    final accent = context.scheme.primary;

    // The camera light switch sits on the camera view, or beside the manual
    // control switch while the camera stream is off.
    final camera = cameraEnabled
        ? ClipRRect(
            borderRadius: const BorderRadius.all(Radius.circular(22)),
            child: Stack(
              children: [
                const CameraView(allowFullscreen: false),
                if (cameraLight)
                  const Positioned(
                    top: 6,
                    right: 6,
                    child: _CameraLightButton(),
                  ),
              ],
            ),
          )
        : null;
    final toggle = TileGroup(
      children: [
        ToggleTile(
          title: 'Enable manual control',
          subtitle: state.hasError && !state.hasValue
              ? 'Error loading manual controls'
              : 'The robot leaves its current task and listens to your input',
          icon: Icons.sports_esports_rounded,
          value: state.value,
          busy: _toggling,
          onChanged: _toggle,
        ),
        if (cameraLight && camera == null)
          const CapabilityToggleTile(
            capability: Cap.cameraLightControl,
            title: 'Camera light',
            subtitle: "The robot switches it on when it's dark",
            icon: Icons.flashlight_on_rounded,
          ),
      ],
    );
    final selector = LayoutBuilder(
      builder: (context, box) {
        // Narrow phones: labels only, so "Joystick" doesn't wrap.
        final icons = box.maxWidth >= 350;
        return Center(
          child: SegmentedButton<_InputMode>(
            segments: [
              ButtonSegment(
                value: _InputMode.joystick,
                label: const Text('Joystick'),
                icon: icons ? const Icon(Icons.gamepad_rounded) : null,
              ),
              ButtonSegment(
                value: _InputMode.dpad,
                label: const Text('D-Pad'),
                icon: icons ? const Icon(Icons.control_camera_rounded) : null,
              ),
              ButtonSegment(
                value: _InputMode.keyboard,
                label: const Text('Keys'),
                icon: icons ? const Icon(Icons.keyboard_rounded) : null,
              ),
            ],
            selected: {_mode!},
            showSelectedIcon: false,
            onSelectionChanged: (s) {
              _reset();
              setState(() => _mode = s.first);
            },
          ),
        );
      },
    );
    final controls = _ControlArea(
      child: switch (_mode!) {
        _InputMode.joystick => _Joystick(
          enabled: enabled,
          accent: accent,
          onChanged: _move,
        ),
        _InputMode.dpad => _DPad(
          enabled: enabled,
          accent: accent,
          onChanged: _move,
        ),
        _InputMode.keyboard => _KeyPad(
          enabled: enabled,
          vector: _vector,
          accent: accent,
          onKey: _setKey,
        ),
      },
    );
    final status = Text(
      enabled
          ? 'Velocity ${(_vector.velocity * 100).round()}% · Steering ${_vector.angle.round()}°'
          : 'Enable manual control to drive',
      style: context.text.bodySmall,
      textAlign: TextAlign.center,
    );

    // The page never scrolls, so dragging a control can't move it.
    return Focus(
      focusNode: _focus,
      autofocus: true,
      onKeyEvent: (node, event) => _onKey(node, event, enabled),
      child: ValrovePage(
        title: 'Manual control',
        subtitle: highRes ? 'Analog driving' : 'Discrete driving commands',
        scrollable: false,
        children: [
          Expanded(
            child: LayoutBuilder(
              builder: (context, box) {
                // Phone in landscape: settings beside the controls.
                if (box.maxWidth > box.maxHeight && box.maxHeight < 440) {
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(
                        child: SingleChildScrollView(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              if (camera != null) ...[
                                camera,
                                const SizedBox(height: 12),
                              ],
                              toggle,
                              const SizedBox(height: 14),
                              selector,
                              const SizedBox(height: 10),
                              status,
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      SizedBox(
                        width: math.min(box.maxHeight, 300),
                        child: controls,
                      ),
                    ],
                  );
                }
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (camera != null) ...[
                      Flexible(child: Center(child: camera)),
                      const SizedBox(height: 12),
                    ],
                    toggle,
                    const SizedBox(height: 18),
                    selector,
                    const SizedBox(height: 16),
                    Expanded(
                      child: Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Flexible(child: controls),
                            const SizedBox(height: 8),
                            status,
                          ],
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// Shows a control at its full 280dp when there is room, smaller otherwise.
class _ControlArea extends StatelessWidget {
  const _ControlArea({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => FittedBox(
    fit: BoxFit.scaleDown,
    child: SizedBox.square(dimension: 280, child: Center(child: child)),
  );
}

/// The camera light switch, on the camera view.
///
/// It is Valetudo's "Camera light" setting: with it on, the robot switches
/// the light on by itself when it's dark. Valetudo can't switch the light
/// directly.
class _CameraLightButton extends ConsumerStatefulWidget {
  const _CameraLightButton();

  @override
  ConsumerState<_CameraLightButton> createState() => _CameraLightButtonState();
}

class _CameraLightButtonState extends ConsumerState<_CameraLightButton> {
  static const _lit = Color(0xFFFFD54F);

  bool _busy = false;

  Future<void> _set(bool on) async {
    setState(() => _busy = true);
    final light = toggleProvider(Cap.cameraLightControl);
    await ref
        .read(commandsProvider)
        .run(
          'switch the camera light',
          (c) => c.setToggle(Cap.cameraLightControl, on),
          invalidate: [light],
          // The button already ticks.
          haptic: null,
          success: on
              ? "Camera light on: the robot lights up the camera when it's "
                    'dark'
              : null,
        );
    // Wait for the refetch so the button shows the confirmed state.
    try {
      await ref.read(light.future);
    } catch (_) {}
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(toggleProvider(Cap.cameraLightControl));
    final on = state.value;
    final busy = _busy || (state.isLoading && !state.hasValue);
    final foreground = on == true ? Colors.black : Colors.white;
    return Tooltip(
      message: switch (on) {
        true => 'Camera light on',
        false => 'Camera light off',
        null => 'Camera light',
      },
      child: Semantics(
        toggled: on,
        child: Pressable(
          // Dimmed when its state couldn't be loaded.
          enabled: on != null || busy,
          onTap: on == null || busy ? null : () => _set(!on),
          semanticLabel: 'Camera light',
          // A 48 dp target around the button, which lines up with the
          // camera's LIVE badge.
          child: Padding(
            padding: const EdgeInsets.all(6),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 36,
              height: 36,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: on == true ? _lit : Colors.black.withValues(alpha: 0.55),
                shape: BoxShape.circle,
              ),
              child: busy
                  ? SizedBox.square(
                      dimension: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: foreground,
                      ),
                    )
                  : Icon(
                      on == true
                          ? Icons.flashlight_on_rounded
                          : Icons.flashlight_off_rounded,
                      size: 20,
                      color: foreground,
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A pan that wins the gesture arena as soon as the finger lands, so nothing
/// around the joystick (a scroll view, the back swipe) can take its touch.
class _EagerPanGestureRecognizer extends PanGestureRecognizer {
  _EagerPanGestureRecognizer({super.debugOwner});

  @override
  void addAllowedPointer(PointerDownEvent event) {
    super.addAllowedPointer(event);
    resolve(GestureDisposition.accepted);
  }
}

class _Joystick extends StatefulWidget {
  const _Joystick({
    required this.enabled,
    required this.accent,
    required this.onChanged,
  });

  final bool enabled;
  final Color accent;
  final ValueChanged<MoveVector> onChanged;

  @override
  State<_Joystick> createState() => _JoystickState();
}

class _JoystickState extends State<_Joystick>
    with SingleTickerProviderStateMixin {
  Offset _knob = Offset.zero;
  static const _radius = 110.0;
  late final AnimationController _spring = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 260),
  );
  Offset _springFrom = Offset.zero;
  DateTime _lastEmit = DateTime.fromMillisecondsSinceEpoch(0);

  @override
  void initState() {
    super.initState();
    _spring.addListener(
      () => setState(
        () => _knob = Offset.lerp(
          _springFrom,
          Offset.zero,
          Curves.easeOutBack.transform(_spring.value),
        )!,
      ),
    );
  }

  @override
  void dispose() {
    _spring.dispose();
    super.dispose();
  }

  void _update(Offset local) {
    final center = const Offset(_radius, _radius);
    var d = local - center;
    if (d.distance > _radius) d = d / d.distance * _radius;
    setState(() => _knob = d);
    final now = DateTime.now();
    if (now.difference(_lastEmit) < const Duration(milliseconds: 100)) return;
    _lastEmit = now;
    widget.onChanged(
      MoveVector(
        (-d.dy / _radius).clamp(-1, 1),
        (d.dx / _radius * 120).clamp(-120, 120),
      ),
    );
  }

  void _release() {
    _springFrom = _knob;
    _spring.forward(from: 0);
    _lastEmit = DateTime.fromMillisecondsSinceEpoch(0);
    widget.onChanged(MoveVector.zero);
    Haptics.light();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final opacity = widget.enabled ? 1.0 : 0.4;
    // The glass fades itself; an Opacity around it would hide its blur.
    return RawGestureDetector(
      gestures: {
        _EagerPanGestureRecognizer:
            GestureRecognizerFactoryWithHandlers<_EagerPanGestureRecognizer>(
              () => _EagerPanGestureRecognizer(debugOwner: this),
              (r) => r
                ..onStart = widget.enabled
                    ? (d) {
                        _spring.stop();
                        Haptics.selection();
                        _update(d.localPosition);
                      }
                    : null
                ..onUpdate = widget.enabled
                    ? (d) => _update(d.localPosition)
                    : null
                ..onEnd = widget.enabled ? (_) => _release() : null
                ..onCancel = widget.enabled ? _release : null,
            ),
      },
      child: SizedBox.square(
        dimension: _radius * 2,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Glass(
              radius: _radius,
              opacity: opacity,
              child: const SizedBox.expand(),
            ),
            Opacity(
              opacity: opacity,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  CustomPaint(
                    size: const Size.square(_radius * 2),
                    painter: _JoystickGuides(c.textTertiary),
                  ),
                  Transform.translate(
                    offset: _knob,
                    child: Container(
                      width: 86,
                      height: 86,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            widget.accent,
                            Color.lerp(widget.accent, Colors.black, 0.3)!,
                          ],
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: widget.accent.withValues(alpha: 0.45),
                            blurRadius: 24,
                            offset: const Offset(0, 8),
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.navigation_rounded,
                        color: Colors.white,
                        size: 30,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _JoystickGuides extends CustomPainter {
  _JoystickGuides(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final p = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = color.withValues(alpha: 0.35);
    canvas.drawCircle(c, size.width * 0.27, p);
    for (var i = 0; i < 4; i++) {
      final a = i * math.pi / 2;
      final dir = Offset(math.cos(a), math.sin(a));
      final tip = c + dir * (size.width / 2 - 14);
      final path = Path()
        ..moveTo(tip.dx, tip.dy)
        ..lineTo(
          (tip - dir * 8 + Offset(-dir.dy, dir.dx) * 6).dx,
          (tip - dir * 8 + Offset(-dir.dy, dir.dx) * 6).dy,
        )
        ..lineTo(
          (tip - dir * 8 - Offset(-dir.dy, dir.dx) * 6).dx,
          (tip - dir * 8 - Offset(-dir.dy, dir.dx) * 6).dy,
        )
        ..close();
      canvas.drawPath(path, Paint()..color = color.withValues(alpha: 0.5));
    }
  }

  @override
  bool shouldRepaint(_JoystickGuides old) => old.color != color;
}

class _DPad extends StatelessWidget {
  const _DPad({
    required this.enabled,
    required this.accent,
    required this.onChanged,
  });

  final bool enabled;
  final Color accent;
  final ValueChanged<MoveVector> onChanged;

  @override
  Widget build(BuildContext context) {
    Widget button(IconData icon, MoveVector v, String label) => _HoldButton(
      icon: icon,
      label: label,
      enabled: enabled,
      accent: accent,
      onDown: () => onChanged(v),
      onUp: () => onChanged(MoveVector.zero),
    );
    return SizedBox(
      width: 240,
      height: 240,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          button(Icons.arrow_upward_rounded, const MoveVector(1, 0), 'Forward'),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              button(
                Icons.rotate_left_rounded,
                const MoveVector(0, -120),
                'Rotate left',
              ),
              button(
                Icons.rotate_right_rounded,
                const MoveVector(0, 120),
                'Rotate right',
              ),
            ],
          ),
          button(
            Icons.arrow_downward_rounded,
            const MoveVector(-1, 0),
            'Backward',
          ),
        ],
      ),
    );
  }
}

class _HoldButton extends StatefulWidget {
  const _HoldButton({
    required this.icon,
    required this.label,
    required this.enabled,
    required this.accent,
    required this.onDown,
    required this.onUp,
  });

  final IconData icon;
  final String label;
  final bool enabled;
  final Color accent;
  final VoidCallback onDown;
  final VoidCallback onUp;

  @override
  State<_HoldButton> createState() => _HoldButtonState();
}

class _HoldButtonState extends State<_HoldButton> {
  bool _down = false;

  void _set(bool down) {
    if (!widget.enabled || down == _down) return;
    setState(() => _down = down);
    if (down) {
      Haptics.selection();
      widget.onDown();
    } else {
      widget.onUp();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: widget.label,
      child: Listener(
        onPointerDown: (_) => _set(true),
        onPointerUp: (_) => _set(false),
        onPointerCancel: (_) => _set(false),
        child: AnimatedScale(
          scale: _down ? 0.92 : 1,
          duration: const Duration(milliseconds: 120),
          child: Opacity(
            opacity: widget.enabled ? 1 : 0.4,
            child: Container(
              width: 76,
              height: 76,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _down
                    ? widget.accent
                    : context.colors.textPrimary.withValues(alpha: 0.07),
                border: Border.all(
                  color: widget.accent.withValues(alpha: _down ? 0 : 0.35),
                ),
              ),
              child: Icon(
                widget.icon,
                size: 32,
                color: _down ? Colors.white : context.colors.textPrimary,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _KeyPad extends StatelessWidget {
  const _KeyPad({
    required this.enabled,
    required this.vector,
    required this.accent,
    required this.onKey,
  });

  final bool enabled;
  final MoveVector vector;
  final Color accent;
  final void Function(String key, bool down) onKey;

  @override
  Widget build(BuildContext context) {
    Widget key(String key, String label, bool active) => _KeyCap(
      label: key.toUpperCase(),
      semanticLabel: label,
      enabled: enabled,
      active: active,
      accent: accent,
      onChanged: (down) => onKey(key, down),
    );
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        key('w', 'Forward', vector.velocity > 0.1),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            key('a', 'Left', vector.angle < -10),
            key('s', 'Backward', vector.velocity < -0.1),
            key('d', 'Right', vector.angle > 10),
          ],
        ),
        const SizedBox(height: 14),
        Text(
          'Hold a key to drive, or use W A S D or the arrow keys on a keyboard',
          style: context.text.bodySmall,
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}

/// A key cap that drives while held, like the keyboard key it shows.
class _KeyCap extends StatefulWidget {
  const _KeyCap({
    required this.label,
    required this.semanticLabel,
    required this.enabled,
    required this.active,
    required this.accent,
    required this.onChanged,
  });

  final String label;
  final String semanticLabel;
  final bool enabled;

  /// Lit by the current movement (also when driven from a keyboard).
  final bool active;
  final Color accent;
  final ValueChanged<bool> onChanged;

  @override
  State<_KeyCap> createState() => _KeyCapState();
}

class _KeyCapState extends State<_KeyCap> {
  final _pointers = <int>{};

  void _down(PointerDownEvent event) {
    if (!widget.enabled) return;
    if (_pointers.isEmpty) {
      Haptics.selection();
      widget.onChanged(true);
    }
    setState(() => _pointers.add(event.pointer));
  }

  void _up(PointerEvent event) {
    if (!_pointers.contains(event.pointer)) return;
    setState(() => _pointers.remove(event.pointer));
    if (_pointers.isEmpty) widget.onChanged(false);
  }

  @override
  Widget build(BuildContext context) {
    final held = _pointers.isNotEmpty;
    final lit = widget.enabled && (held || widget.active);
    return Semantics(
      button: true,
      label: widget.semanticLabel,
      child: Listener(
        onPointerDown: _down,
        onPointerUp: _up,
        onPointerCancel: _up,
        child: AnimatedScale(
          scale: held ? 0.92 : 1,
          duration: const Duration(milliseconds: 120),
          child: Opacity(
            opacity: widget.enabled ? 1 : 0.4,
            child: Container(
              width: 56,
              height: 56,
              margin: const EdgeInsets.all(4),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: lit
                    ? widget.accent
                    : context.colors.textPrimary.withValues(alpha: 0.07),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: context.colors.textTertiary.withValues(alpha: 0.5),
                  width: 2,
                ),
              ),
              child: Text(
                widget.label,
                style: context.text.titleMedium?.copyWith(
                  color: lit ? Colors.white : context.colors.textSecondary,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
