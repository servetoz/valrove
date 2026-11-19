import 'dart:async';
import 'dart:io';

import 'package:bonsoir/bonsoir.dart';
import 'package:flutter/foundation.dart';

/// A Valetudo instance found on the local network via mDNS (`_valetudo._tcp`).
class DiscoveredRobot {
  const DiscoveredRobot({
    required this.serviceName,
    required this.host,
    required this.port,
    this.id,
    this.model,
    this.manufacturer,
    this.version,
    this.friendlyName,
  });

  final String serviceName;
  final String host;
  final int port;
  final String? id;
  final String? model;
  final String? manufacturer;
  final String? version;
  final String? friendlyName;

  String get url => port == 80 ? 'http://$host/' : 'http://$host:$port/';

  String get title {
    if (friendlyName != null && friendlyName!.isNotEmpty) return friendlyName!;
    if (manufacturer != null && model != null) return '$manufacturer $model';
    return serviceName;
  }

  String get subtitle => [
    if (friendlyName != null && model != null) '$manufacturer $model',
    port == 80 ? host : '$host:$port',
    if (version != null) 'Valetudo $version',
  ].join(' · ');
}

/// Scans the local network for Valetudo robots while listened to.
class RobotDiscovery {
  final _controller = StreamController<List<DiscoveredRobot>>.broadcast();
  final Map<String, DiscoveredRobot> _found = {};
  BonsoirDiscovery? _discovery;
  StreamSubscription<BonsoirDiscoveryEvent>? _sub;

  Stream<List<DiscoveredRobot>> get robots => _controller.stream;

  List<DiscoveredRobot> get current => _found.values.toList();

  bool get supported =>
      !kIsWeb && (Platform.isAndroid || Platform.isIOS || Platform.isMacOS);

  Future<void> start() async {
    if (!supported || _discovery != null) return;
    try {
      final discovery = BonsoirDiscovery(
        type: '_valetudo._tcp',
        printLogs: false,
      );
      _discovery = discovery;
      await discovery.initialize();
      _sub = discovery.eventStream?.listen((event) {
        switch (event) {
          case BonsoirDiscoveryServiceFoundEvent():
            discovery.serviceResolver.resolveService(event.service);
          case BonsoirDiscoveryServiceResolvedEvent():
            _add(event.service);
          case BonsoirDiscoveryServiceUpdatedEvent():
            _add(event.service);
          case BonsoirDiscoveryServiceLostEvent():
            _found.remove(event.service.name);
            _emit();
          default:
            break;
        }
      });
      await discovery.start();
    } catch (e) {
      debugPrint('mDNS discovery unavailable: $e');
    }
  }

  void _add(BonsoirService service) {
    final attributes = service.attributes;
    final host =
        service.hostAddresses.where((a) => !a.contains(':')).firstOrNull ??
        service.hostAddress ??
        service.hostname;
    if (host == null || host.isEmpty) return;
    _found[service.name] = DiscoveredRobot(
      serviceName: service.name,
      host: host.endsWith('.') ? host.substring(0, host.length - 1) : host,
      port: service.port,
      id: attributes['id'],
      model: attributes['model'],
      manufacturer: attributes['manufacturer'],
      version: attributes['version'],
      friendlyName: attributes['name'],
    );
    _emit();
  }

  void _emit() {
    if (!_controller.isClosed) _controller.add(current);
  }

  Future<void> stop() async {
    await _sub?.cancel();
    _sub = null;
    final d = _discovery;
    _discovery = null;
    try {
      if (d != null && !d.isStopped) await d.stop();
    } catch (_) {}
  }

  Future<void> dispose() async {
    await stop();
    await _controller.close();
  }
}
