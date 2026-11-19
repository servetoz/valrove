import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

import '../core/persistence/robot_profile.dart';
import '../core/valetudo/client/valetudo_client.dart';

/// Id of the demo robot's profile.
const demoRobotId = 'demo';

const _demoHost = 'demo.valrove.invalid';

/// The demo robot, for trying Valrove without a robot (and for app review).
RobotProfile demoRobotProfile() => RobotProfile(
  id: demoRobotId,
  name: 'Demo robot',
  url: 'http://$_demoHost/',
  model: 'L40 Ultra',
  manufacturer: 'Dreame',
  addedAt: DateTime.now(),
);

bool isDemoRobot(RobotProfile? profile) => profile?.id == demoRobotId;

/// Connects to the robot at [endpoint], or to the demo robot.
ValetudoClient connectRobot(ValetudoEndpoint endpoint) {
  if (endpoint.baseUri.host != _demoHost) {
    return ValetudoClient.connect(endpoint);
  }
  final client = DemoHttpClient(DemoRobot.instance);
  return ValetudoClient(
    ValetudoTransport(endpoint, client: client, streamClient: client),
  );
}

/// A pretend Dreame L40 Ultra. It answers with the recorded responses in
/// `assets/demo` and plays along with commands: cleaning, pausing, docking,
/// presets and switches show up in the app, and the battery drains and
/// charges.
class DemoRobot {
  DemoRobot({AssetBundle? bundle}) : _bundle = bundle ?? rootBundle;

  static final instance = DemoRobot();

  /// How often the robot's state moves on (and keep-alives are sent).
  static const tick = Duration(seconds: 5);

  /// Ticks a cleanup lasts before the robot heads home, and the drive home.
  static const cleanupTicks = 18, driveTicks = 2;

  final AssetBundle _bundle;
  final _assets = <String, Future<String?>>{};

  /// Responses changed by commands, by API path.
  final _changed = <String, Object?>{};
  List<Map<String, Object?>>? _attributes;
  final _attributeStreams = <StreamController<List<int>>>{};
  final _streams = <StreamController<List<int>>>{};
  Timer? _timer;
  int _ticks = 0;

  Future<String?> _asset(String path) => _assets.putIfAbsent(path, () async {
    try {
      return await _bundle.loadString(
        'assets/demo/${path.replaceAll('/', '__')}.json',
      );
    } on Object {
      return null;
    }
  });

  Future<List<Map<String, Object?>>> _currentAttributes() async =>
      _attributes ??= [
        for (final a in jsonDecode(
          await _asset('robot/state/attributes') ?? '[]',
        ) as List)
          Map<String, Object?>.from(a as Map),
      ];

  /// Body of a GET request to [path], or null when there is none.
  Future<String?> get(String path) async {
    switch (path) {
      case 'robot/state/attributes':
        return jsonEncode(await _currentAttributes());
      case 'robot/state':
        final state = await _asset(path);
        if (state == null) return null;
        final json = jsonDecode(state) as Map<String, Object?>;
        json['attributes'] = await _currentAttributes();
        return jsonEncode(json);
    }
    if (_changed.containsKey(path)) return jsonEncode(_changed[path]);
    return _asset(path);
  }

  /// Opens the event stream at [path]; it starts with the current state.
  Stream<List<int>> events(String path) {
    late final StreamController<List<int>> controller;
    controller = StreamController<List<int>>(
      onListen: () async {
        _streams.add(controller);
        _run();
        if (path == 'robot/state/attributes/sse') {
          _attributeStreams.add(controller);
          final attributes = jsonEncode(await _currentAttributes());
          if (_streams.contains(controller)) {
            controller.add(_event('StateAttributesUpdated', attributes));
          }
        } else if (path == 'robot/state/map/sse') {
          final map = await _asset('robot/state/map');
          if (map != null && _streams.contains(controller)) {
            controller.add(_event('MapUpdated', map));
          }
        }
      },
      onCancel: () {
        _streams.remove(controller);
        _attributeStreams.remove(controller);
        // Nobody is watching: the robot pauses until the app is back.
        if (_streams.isEmpty) {
          _timer?.cancel();
          _timer = null;
        }
      },
    );
    return controller.stream;
  }

  static List<int> _event(String name, String data) =>
      utf8.encode('event: $name\ndata: $data\n\n');

  /// Carries out a PUT or POST to [path].
  Future<void> command(String path, Object? body) async {
    final b = body is Map
        ? Map<String, Object?>.from(body)
        : const <String, Object?>{};
    await _currentAttributes();
    switch (path) {
      case 'robot/capabilities/BasicControlCapability':
        switch (b['action']) {
          case 'start':
            _status('cleaning');
          case 'pause':
            _status('paused');
          case 'stop':
            _status('idle');
          case 'home':
            _status('returning');
        }
      case 'robot/capabilities/MapSegmentationCapability':
        _status('cleaning', flag: 'segment');
      case 'robot/capabilities/ZoneCleaningCapability':
        _status('cleaning', flag: 'zone');
      case 'robot/capabilities/GoToLocationCapability':
        _status('moving', flag: 'target');
      case 'robot/capabilities/FanSpeedControlCapability/preset':
        _preset('fan_speed', b['name']);
      case 'robot/capabilities/WaterUsageControlCapability/preset':
        _preset('water_grade', b['name']);
      case 'robot/capabilities/OperationModeControlCapability/preset':
        _preset('operation_mode', b['name']);
      // The demo has no camera stream to show.
      case 'valetudo/config/duststreaming':
        break;
      default:
        await _remember(path, b);
    }
    _publish();
  }

  /// Keeps switches and settings as set: `{action: enable}` turns into
  /// `{enabled: true}`, and settings objects take the new values.
  Future<void> _remember(String path, Map<String, Object?> body) async {
    final action = body['action'];
    if (body.length == 1 && (action == 'enable' || action == 'disable')) {
      _changed[path] = {'enabled': action == 'enable'};
      return;
    }
    final current = await get(path);
    if (current == null || body.isEmpty) return;
    final json = jsonDecode(current);
    if (json is Map && body.keys.every(json.containsKey)) {
      _changed[path] = {...Map<String, Object?>.from(json), ...body};
    }
  }

  Map<String, Object?>? _attribute(String className, [String? type]) {
    for (final a in _attributes ?? const <Map<String, Object?>>[]) {
      if (a['__class'] == className && (type == null || a['type'] == type)) {
        return a;
      }
    }
    return null;
  }

  void _status(String value, {String flag = 'none'}) {
    _attribute('StatusStateAttribute')
      ?..['value'] = value
      ..['flag'] = flag;
    if (value != 'docked') {
      _attribute('DockStatusStateAttribute')?['value'] = 'idle';
    }
    _ticks = 0;
    _run();
  }

  void _preset(String type, Object? name) {
    if (name is! String) return;
    _attribute('PresetSelectionStateAttribute', type)?['value'] = name;
  }

  void _publish() {
    final attributes = _attributes;
    if (attributes == null) return;
    final event = _event('StateAttributesUpdated', jsonEncode(attributes));
    for (final c in _attributeStreams) {
      c.add(event);
    }
  }

  /// Runs the robot while the app watches it.
  void _run() {
    if (_streams.isNotEmpty) _timer ??= Timer.periodic(tick, (_) => _step());
  }

  /// Moves the robot's state on by one [tick].
  void _step() {
    for (final c in _streams) {
      c.add(utf8.encode(':keep-alive\n\n'));
    }
    final status = _attribute('StatusStateAttribute');
    final battery = _attribute('BatteryStateAttribute');
    if (status == null || battery == null) return;
    _ticks++;
    final level = (battery['level'] as num?)?.toInt() ?? 50;
    var changed = true;
    switch (status['value']) {
      case 'cleaning':
        if (_ticks % 3 == 0) battery['level'] = (level - 1).clamp(5, 100);
        if (_ticks >= cleanupTicks) _status('returning');
      case 'returning' || 'moving':
        if (_ticks >= driveTicks) {
          _status(status['value'] == 'returning' ? 'docked' : 'idle');
        }
      case 'docked':
        battery['level'] = (level + 1).clamp(0, 100);
      default:
        changed = false;
    }
    final docked = status['value'] == 'docked';
    final now = (battery['level'] as num?)?.toInt() ?? level;
    battery['flag'] = !docked
        ? 'discharging'
        : now >= 100
        ? 'charged'
        : 'charging';
    if (changed) _publish();
  }
}

/// Answers the app's HTTP requests from the [DemoRobot].
class DemoHttpClient extends http.BaseClient {
  DemoHttpClient(this.robot);

  final DemoRobot robot;

  static const _json = {
    'content-type': 'application/json; charset=utf-8',
    'x-valetudo-commit-id': 'demo',
    'x-valetudo-version': '0.6.0',
  };

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final path = request.url.path.replaceFirst(RegExp(r'^.*?/api/v2/'), '');
    if (path.endsWith('/sse')) {
      return http.StreamedResponse(
        robot.events(path),
        200,
        headers: {'content-type': 'text/event-stream'},
      );
    }
    if (request.method != 'GET') {
      Object? body;
      if (request is http.Request && request.body.isNotEmpty) {
        try {
          body = jsonDecode(request.body);
        } on FormatException {
          body = null;
        }
      }
      await robot.command(path, body);
      return http.StreamedResponse(
        Stream.value(utf8.encode('OK')),
        200,
        headers: {'content-type': 'text/plain'},
      );
    }
    final body = await robot.get(path);
    if (body == null) {
      return http.StreamedResponse(
        Stream.value(utf8.encode('Not Found')),
        404,
        headers: {'content-type': 'text/plain'},
      );
    }
    return http.StreamedResponse(
      Stream.value(utf8.encode(body)),
      200,
      headers: _json,
    );
  }
}
