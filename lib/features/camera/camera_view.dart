import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/valetudo/capabilities.dart';
import '../../core/valetudo/models/models.dart';
import '../../state/app_state.dart';
import '../../state/data.dart';
import '../../state/session.dart';
import '../../ui/theme.dart';
import 'camera_stream.dart';

/// Live view of the robot camera (Valetudo "duststreaming").
class CameraView extends ConsumerStatefulWidget {
  const CameraView({super.key, this.allowFullscreen = true});

  final bool allowFullscreen;

  @override
  ConsumerState<CameraView> createState() => _CameraViewState();
}

class _CameraViewState extends ConsumerState<CameraView> {
  CameraStreamSession? _session;
  StreamSubscription<CameraEvent>? _sub;
  ui.Image? _image;
  String? _status = 'Connecting…';
  Timer? _retry;
  bool _starting = false;

  @override
  void initState() {
    super.initState();
    ref.listenManual<bool>(appInForegroundProvider, (prev, fg) {
      if (fg) {
        _start();
      } else {
        _stop();
      }
    });
  }

  @override
  void dispose() {
    _stop();
    _image?.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    if (_session != null || _starting || !mounted) return;
    final client = ref.read(clientProvider);
    if (client == null) return;
    _starting = true;
    _retry?.cancel();
    try {
      final session = await CameraStreamSession.start(
        url: client.endpoint.api(client.duststreamPath),
        headers: client.endpoint.authHeaders,
      );
      if (!mounted) {
        session.close();
        return;
      }
      _session = session;
      _sub = session.events.listen(_onEvent);
    } finally {
      _starting = false;
    }
  }

  void _stop() {
    _retry?.cancel();
    _sub?.cancel();
    _sub = null;
    _session?.close();
    _session = null;
  }

  void _scheduleRetry(String status) {
    _stop();
    if (!mounted) return;
    setState(() => _status = status);
    _retry = Timer(const Duration(seconds: 3), _start);
  }

  void _onEvent(CameraEvent event) {
    switch (event) {
      case CameraFrameEvent(:final frame):
        ui.decodeImageFromPixels(
          frame.rgba,
          frame.width,
          frame.height,
          ui.PixelFormat.rgba8888,
          (image) {
            if (!mounted) {
              image.dispose();
              return;
            }
            final old = _image;
            setState(() {
              _image = image;
              _status = null;
            });
            old?.dispose();
            _session?.ack();
          },
        );
      case CameraErrorEvent(:final message, :final statusCode):
        _scheduleRetry(switch (statusCode) {
          403 => 'Camera streaming is disabled',
          503 => 'Camera busy or streamer unavailable — retrying',
          _ => 'Stream interrupted — reconnecting ($message)',
        });
      case CameraClosedEvent():
        _scheduleRetry('Stream ended — reconnecting');
    }
  }

  @override
  Widget build(BuildContext context) {
    final caps = ref.watch(capsProvider);
    final props = ref.watch(duststreamingPropertiesProvider).value;
    final enabled = ref.watch(duststreamingEnabledProvider).value ?? false;
    final dims = props?.dimensions ?? const ImageDimensions(640, 480);
    final installed = props?.duststreamerInstalled ?? false;
    final ready = caps.has(Cap.duststreaming) && enabled && installed;
    if (ready && _session == null && !_starting && _retry == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _start());
    } else if (!ready && _session != null) {
      _stop();
    }

    Widget content;
    if (!ready) {
      content = _Placeholder(
        title: !enabled ? 'Camera streaming is off' : 'Setup incomplete',
        message: !enabled
            ? 'Enable it in Valetudo options.'
            : 'The duststreamer binary is not installed on the robot.',
      );
    } else if (_image == null) {
      content = _Placeholder(
        title: _status ?? 'Connecting…',
        message: 'Waiting for the first frame',
        busy: true,
      );
    } else {
      content = Stack(
        fit: StackFit.expand,
        children: [
          RawImage(
            image: _image,
            fit: BoxFit.contain,
            filterQuality: FilterQuality.medium,
          ),
          const IgnorePointer(child: _CrtOverlay()),
          Positioned(
            left: 12,
            top: 12,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.55),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: const BoxDecoration(
                      color: Color(0xFFEF4444),
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 6),
                  const Text(
                    'LIVE',
                    style: TextStyle(
                      fontFamily: AppTheme.monoFamily,
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (_status != null)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Container(
                color: Colors.black.withValues(alpha: 0.6),
                padding: const EdgeInsets.all(8),
                child: Text(
                  _status!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white, fontSize: 12),
                ),
              ),
            ),
        ],
      );
    }

    return AspectRatio(
      aspectRatio: dims.aspectRatio,
      child: GestureDetector(
        onTap: widget.allowFullscreen && _image != null
            ? () => _openFullscreen(context)
            : null,
        child: ColoredBox(color: Colors.black, child: content),
      ),
    );
  }

  void _openFullscreen(BuildContext context) {
    Navigator.of(context).push(
      PageRouteBuilder<void>(
        opaque: true,
        pageBuilder: (context, _, _) => GestureDetector(
          onTap: () => Navigator.pop(context),
          child: const ColoredBox(
            color: Colors.black,
            child: SafeArea(
              child: Center(child: CameraView(allowFullscreen: false)),
            ),
          ),
        ),
        transitionsBuilder: (context, anim, _, child) =>
            FadeTransition(opacity: anim, child: child),
      ),
    );
  }
}

/// Subtle scanlines and vignette — a nod to Valetudo's CRT compositor.
class _CrtOverlay extends StatelessWidget {
  const _CrtOverlay();

  @override
  Widget build(BuildContext context) => CustomPaint(painter: _CrtPainter());
}

class _CrtPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final line = Paint()..color = const Color(0x14000000);
    for (var y = 0.0; y < size.height; y += 3) {
      canvas.drawRect(Rect.fromLTWH(0, y, size.width, 1), line);
    }
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = RadialGradient(
          colors: const [Color(0x00000000), Color(0x66000000)],
          stops: const [0.6, 1],
        ).createShader(Offset.zero & size),
    );
    final tp = TextPainter(
      text: const TextSpan(
        text: 'VALETUDO',
        style: TextStyle(
          fontFamily: AppTheme.monoFamily,
          fontSize: 11,
          color: Color(0x99FFFFFF),
          letterSpacing: 2,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(
      canvas,
      Offset(size.width - tp.width - 12, size.height - tp.height - 10),
    );
  }

  @override
  bool shouldRepaint(_CrtPainter oldDelegate) => false;
}

class _Placeholder extends StatelessWidget {
  const _Placeholder({
    required this.title,
    required this.message,
    this.busy = false,
  });

  final String title;
  final String message;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (busy)
              const SizedBox.square(
                dimension: 28,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  color: Colors.white70,
                ),
              )
            else
              const Icon(
                Icons.videocam_off_rounded,
                color: Colors.white54,
                size: 40,
              ),
            const SizedBox(height: 12),
            Text(
              title,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600,
                fontSize: 15,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 4),
            Text(
              message,
              style: const TextStyle(color: Colors.white60, fontSize: 12.5),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
