import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'transport.dart';

/// A single Server-Sent Event.
class SseEvent {
  const SseEvent({required this.event, required this.data, this.id});

  final String event;
  final String data;
  final String? id;

  @override
  String toString() => 'SseEvent($event, ${data.length} chars)';
}

/// Incremental parser for the `text/event-stream` format.
///
/// Implemented per the WHATWG spec: `data` lines are joined with `\n`,
/// comment lines (starting with `:`) are ignored and an empty line
/// dispatches the event.
class SseParser extends StreamTransformerBase<String, SseEvent> {
  const SseParser();

  @override
  Stream<SseEvent> bind(Stream<String> lines) {
    return Stream<SseEvent>.eventTransformed(lines, _SseSink.new);
  }
}

class _SseSink implements EventSink<String> {
  _SseSink(this._out);

  final EventSink<SseEvent> _out;
  String _event = '';
  final _data = StringBuffer();
  bool _hasData = false;
  String? _id;

  @override
  void add(String line) {
    if (line.isEmpty) {
      if (_hasData) {
        _out.add(
          SseEvent(
            event: _event.isEmpty ? 'message' : _event,
            data: _data.toString(),
            id: _id,
          ),
        );
      }
      _event = '';
      _data.clear();
      _hasData = false;
      return;
    }
    if (line.startsWith(':')) return;

    final colon = line.indexOf(':');
    final field = colon == -1 ? line : line.substring(0, colon);
    var value = colon == -1 ? '' : line.substring(colon + 1);
    if (value.startsWith(' ')) value = value.substring(1);

    switch (field) {
      case 'event':
        _event = value;
      case 'data':
        if (_hasData) _data.write('\n');
        _data.write(value);
        _hasData = true;
      case 'id':
        _id = value;
      default:
        break; // `retry` and unknown fields are ignored.
    }
  }

  @override
  void addError(Object error, [StackTrace? stackTrace]) =>
      _out.addError(error, stackTrace);

  @override
  void close() => _out.close();
}

/// Connection state of an [SseChannel].
enum SseState { idle, connecting, open, retrying }

/// A shared, auto-reconnecting subscription to one SSE endpoint.
///
/// Listeners get a broadcast stream of event payloads. The underlying HTTP
/// connection is opened on the first listener and closed shortly after the
/// last one leaves. Valetudo caps every SSE hub at five clients (dropping the
/// oldest), so connections are shared and released eagerly.
class SseChannel {
  SseChannel({
    required this.transport,
    required this.path,
    required this.eventName,
    this.closeGracePeriod = const Duration(milliseconds: 500),
    this.maxRetryDelay = const Duration(seconds: 30),
    this.stallTimeout = const Duration(seconds: 20),
  }) {
    _controller = StreamController<String>.broadcast(
      onListen: _onListen,
      onCancel: _onCancel,
    );
  }

  final ValetudoTransport transport;
  final String path;
  final String eventName;
  final Duration closeGracePeriod;
  final Duration maxRetryDelay;

  /// Valetudo sends keep-alive comments every 5s; if nothing arrives for this
  /// long the connection is considered dead and re-established.
  final Duration stallTimeout;

  late final StreamController<String> _controller;
  final _stateController = StreamController<SseState>.broadcast();
  StreamSubscription<SseEvent>? _subscription;
  Timer? _closeTimer;
  Timer? _retryTimer;
  Timer? _stallTimer;
  int _attempt = 0;
  bool _active = false;
  bool _disposed = false;
  SseState _state = SseState.idle;
  Object? lastError;

  /// Raw event payloads (the `data` field) of [eventName] events.
  Stream<String> get stream => _controller.stream;

  SseState get state => _state;

  Stream<SseState> get states => _stateController.stream;

  void _setState(SseState state) {
    if (_state == state) return;
    _state = state;
    if (!_stateController.isClosed) _stateController.add(state);
  }

  void _onListen() {
    _closeTimer?.cancel();
    _closeTimer = null;
    if (!_active) {
      _active = true;
      _connect();
    }
  }

  void _onCancel() {
    _closeTimer?.cancel();
    _closeTimer = Timer(closeGracePeriod, () {
      if (!_controller.hasListener) _shutdown();
    });
  }

  /// Forces an immediate reconnect (e.g. after the app returns to foreground).
  void reconnect() {
    if (!_active || _disposed) return;
    _teardownConnection();
    _attempt = 0;
    _connect();
  }

  Future<void> _connect() async {
    if (!_active || _disposed) return;
    _retryTimer?.cancel();
    _setState(SseState.connecting);
    try {
      final response = await transport.openStream(
        path,
        headers: const {'accept': 'text/event-stream'},
      );
      if (!_active || _disposed) {
        // Listener left while connecting.
        response.stream.listen(null).cancel();
        return;
      }
      _attempt = 0;
      lastError = null;
      _setState(SseState.open);
      _armStallTimer();

      // Cancelling `_subscription` propagates through the transformers and
      // closes the HTTP response (and thus the robot-side SSE client slot).
      _subscription = response.stream
          .map((chunk) {
            _armStallTimer();
            return chunk;
          })
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .transform(const SseParser())
          .listen(
            (event) {
              if (event.event == eventName && !_controller.isClosed) {
                _controller.add(event.data);
              }
            },
            onError: (Object error, StackTrace st) => _scheduleRetry(error),
            onDone: () => _scheduleRetry(
              const ValetudoConnectionException('Event stream closed'),
            ),
            cancelOnError: true,
          );
    } catch (error) {
      _scheduleRetry(error);
    }
  }

  void _armStallTimer() {
    _stallTimer?.cancel();
    _stallTimer = Timer(stallTimeout, () {
      _scheduleRetry(const ValetudoConnectionException('Event stream stalled'));
    });
  }

  void _scheduleRetry(Object error) {
    lastError = error;
    _teardownConnection();
    if (!_active || _disposed) return;
    _setState(SseState.retrying);
    // Unauthorized will not fix itself quickly; back off harder.
    final base = error is ValetudoUnauthorizedException ? 10000 : 1000;
    final delayMs = math.min(
      maxRetryDelay.inMilliseconds,
      base * math.pow(2, _attempt).toInt(),
    );
    _attempt = math.min(_attempt + 1, 10);
    _retryTimer?.cancel();
    _retryTimer = Timer(Duration(milliseconds: delayMs), _connect);
  }

  void _teardownConnection() {
    _stallTimer?.cancel();
    _stallTimer = null;
    final sub = _subscription;
    _subscription = null;
    sub?.cancel();
  }

  void _shutdown() {
    _active = false;
    _retryTimer?.cancel();
    _teardownConnection();
    _setState(SseState.idle);
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _closeTimer?.cancel();
    _shutdown();
    _controller.close();
    _stateController.close();
  }
}
