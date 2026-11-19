import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'mpeg/mpeg1_decoder.dart';
import 'mpeg/ts_demuxer.dart';

/// A decoded RGBA video frame.
class CameraFrame {
  const CameraFrame(this.rgba, this.width, this.height);

  final Uint8List rgba;
  final int width;
  final int height;
}

sealed class CameraEvent {
  const CameraEvent();
}

class CameraFrameEvent extends CameraEvent {
  const CameraFrameEvent(this.frame);

  final CameraFrame frame;
}

class CameraErrorEvent extends CameraEvent {
  const CameraErrorEvent(this.message, {this.statusCode});

  final String message;
  final int? statusCode;
}

class CameraClosedEvent extends CameraEvent {
  const CameraClosedEvent();
}

/// Plays Valetudo's duststream (MPEG-TS with MPEG-1 video) by downloading,
/// demuxing and decoding it on a background isolate.
class CameraStreamSession {
  CameraStreamSession._(this._isolate, this._receive, this._events);

  final Isolate _isolate;
  final ReceivePort _receive;
  final StreamController<CameraEvent> _events;
  SendPort? _control;
  bool _closed = false;

  Stream<CameraEvent> get events => _events.stream;

  static Future<CameraStreamSession> start({
    required Uri url,
    required Map<String, String> headers,
  }) async {
    final receive = ReceivePort();
    final events = StreamController<CameraEvent>();
    final isolate = await Isolate.spawn(
      _worker,
      _WorkerArgs(receive.sendPort, url.toString(), headers),
      debugName: 'duststream',
    );
    final session = CameraStreamSession._(isolate, receive, events);
    receive.listen((message) {
      switch (message) {
        case SendPort port:
          session._control = port;
        case (TransferableTypedData data, int width, int height):
          if (!events.isClosed) {
            events.add(
              CameraFrameEvent(
                CameraFrame(data.materialize().asUint8List(), width, height),
              ),
            );
          }
        case (String error, int? status):
          if (!events.isClosed) {
            events.add(CameraErrorEvent(error, statusCode: status));
          }
        case 'closed':
          if (!events.isClosed) events.add(const CameraClosedEvent());
      }
    });
    return session;
  }

  /// Tells the decoder the last frame was displayed and the next may be sent.
  void ack() => _control?.send('ack');

  void close() {
    if (_closed) return;
    _closed = true;
    _control?.send('stop');
    Future<void>.delayed(
      const Duration(milliseconds: 300),
      () => _isolate.kill(priority: Isolate.immediate),
    );
    _receive.close();
    _events.close();
  }
}

class _WorkerArgs {
  const _WorkerArgs(this.port, this.url, this.headers);

  final SendPort port;
  final String url;
  final Map<String, String> headers;
}

Future<void> _worker(_WorkerArgs args) async {
  final out = args.port;
  final control = ReceivePort();
  out.send(control.sendPort);

  final client = HttpClient()
    ..connectionTimeout = const Duration(seconds: 8)
    ..autoUncompress = true;
  StreamSubscription<List<int>>? sub;
  var ready = true;
  var pending = false;
  final decoder = Mpeg1Decoder();
  final demuxer = TsDemuxer();
  Uint8List? buffer;

  void sendFrame() {
    final rgba = decoder.toRgba();
    if (rgba == null) return;
    ready = false;
    pending = false;
    out.send((
      TransferableTypedData.fromList([rgba]),
      decoder.width,
      decoder.height,
    ));
  }

  demuxer.connect(TsDemuxer.videoStream, (pts, buffers) {
    decoder.write(buffers);
    var decoded = false;
    while (decoder.decode()) {
      decoded = true;
    }
    if (decoded) {
      if (ready) {
        sendFrame();
      } else {
        pending = true;
      }
    }
  });

  control.listen((message) {
    if (message == 'ack') {
      ready = true;
      if (pending) sendFrame();
    } else if (message == 'stop') {
      sub?.cancel();
      client.close(force: true);
      control.close();
      Isolate.exit();
    }
  });

  try {
    final request = await client.getUrl(Uri.parse(args.url));
    args.headers.forEach(request.headers.set);
    final response = await request.close();
    if (response.statusCode != 200) {
      out.send(('HTTP ${response.statusCode}', response.statusCode));
      await response.drain<void>().catchError((_) {});
      out.send('closed');
      return;
    }
    sub = response.listen(
      (chunk) {
        buffer = chunk is Uint8List ? chunk : Uint8List.fromList(chunk);
        try {
          demuxer.write(buffer!);
        } catch (e) {
          // Corrupt data: skip this chunk and resync on the next one.
        }
      },
      onError: (Object e) => out.send((e.toString(), null)),
      onDone: () => out.send('closed'),
      cancelOnError: true,
    );
  } catch (e) {
    out.send((e.toString(), null));
    out.send('closed');
  }
}
