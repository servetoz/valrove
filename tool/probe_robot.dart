// Read-only smoke test of the API layer against a real robot.
//
//   dart run tool/probe_robot.dart http://192.168.1.122 [seconds-of-sse]
//
// Only GET requests are issued; nothing on the robot is changed.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:valrove/core/valetudo/capabilities.dart';
import 'package:valrove/core/valetudo/client/valetudo_client.dart';
import 'package:valrove/core/valetudo/json_utils.dart';
import 'package:valrove/core/valetudo/models/models.dart';

Future<void> main(List<String> args) async {
  final base = ValetudoEndpoint.tryParse(
    args.isEmpty ? '192.168.1.122' : args.first,
  );
  if (base == null) {
    stderr.writeln('Invalid address');
    exit(2);
  }
  final sseSeconds = args.length > 1 ? int.parse(args[1]) : 12;
  final client = ValetudoClient.connect(ValetudoEndpoint(baseUri: base));
  var failures = 0;

  Future<void> check<T>(
    String name,
    Future<T> Function() fn, [
    String Function(T)? describe,
  ]) async {
    final sw = Stopwatch()..start();
    try {
      final result = await fn();
      stdout.writeln(
        'ok   ${name.padRight(34)} ${sw.elapsedMilliseconds.toString().padLeft(4)}ms  '
        '${describe?.call(result) ?? ''}',
      );
    } catch (e) {
      failures++;
      stdout.writeln('FAIL ${name.padRight(34)} $e');
    }
  }

  final caps = await client.getCapabilities();
  stdout.writeln('${caps.names.length} capabilities');

  await check(
    'robot',
    client.getRobotInformation,
    (r) => '${r.manufacturer} ${r.modelName}',
  );
  await check(
    'robot properties',
    client.getRobotProperties,
    (r) => 'fw ${r.firmwareVersion}',
  );
  await check(
    'valetudo',
    client.getValetudoInformation,
    (v) => 'embedded=${v.embedded} id=${v.systemId}',
  );
  await check('version', client.getValetudoVersion, (v) => v.release);
  await check('attributes', client.getStateAttributes, (s) {
    return 'status=${s.status.value}/${s.status.flag} battery=${s.battery?.level}/${s.battery?.flag} '
        'fan=${s.fanSpeed?.value} water=${s.waterGrade?.value} mode=${s.operationMode?.value} '
        'dock=${s.dockStatus?.value} comps=${s.dockComponents.map((c) => '${c.type}:${c.value}').join(',')} '
        'attach=${s.attachments.map((a) => '${a.type}:${a.attached}').join(',')}';
  });
  await check(
    'map',
    () async {
      final json = await client.getMapJson();
      return ValetudoMap.fromJson(asJson(jsonDecode(json)));
    },
    (m) =>
        'v${m.version} ${m.layers.length} layers, ${m.entities.length} entities, px=${m.pixelSize}, '
        'segments=${m.segments.map((s) => '${s.segmentId}:${s.pixels.length ~/ 2}px').join(',')}',
  );

  for (final cap in [
    Cap.fanSpeedControl,
    Cap.waterUsageControl,
    Cap.operationModeControl,
  ]) {
    if (caps.has(cap)) {
      await check(
        'presets $cap',
        () => client.getPresets(cap),
        (p) => p.join(','),
      );
    }
  }
  if (caps.has(Cap.zoneCleaning)) {
    await check(
      'zone props',
      client.getZoneProperties,
      (p) => 'zones ${p.zoneCount.max} it ${p.iterationCount.max}',
    );
  }
  if (caps.has(Cap.mapSegmentation)) {
    await check(
      'segments',
      client.getSegments,
      (s) => s.map((e) => '${e.id}:${e.displayName}').join(','),
    );
    await check(
      'segmentation props',
      client.getMapSegmentationProperties,
      (p) => 'it ${p.iterationCount.max} order ${p.customOrderSupport}',
    );
  }
  if (caps.has(Cap.consumableMonitoring)) {
    await check(
      'consumables',
      client.getConsumables,
      (c) => c.map((e) => '${e.key}=${e.value}${e.unit[0]}').join(' '),
    );
    await check(
      'consumable props',
      client.getConsumableProperties,
      (c) => '${c.length} kinds',
    );
  }
  for (final cap in [Cap.totalStatistics, Cap.currentStatistics]) {
    if (caps.has(cap)) {
      await check(
        'stats $cap',
        () => client.getStatistics(cap),
        (s) => s.map((d) => '${d.type}=${d.value}').join(' '),
      );
    }
  }
  for (final cap in [
    Cap.keyLock,
    Cap.carpetModeControl,
    Cap.obstacleAvoidanceControl,
    Cap.petObstacleAvoidanceControl,
    Cap.collisionAvoidantNavigation,
    Cap.mopExtensionControl,
    Cap.cameraLightControl,
    Cap.mopTwistControl,
    Cap.mopExtensionFurnitureLegHandlingControl,
    Cap.mopDockMopAutoDryingControl,
    Cap.floorMaterialDirectionAwareNavigationControl,
    Cap.obstacleImages,
    Cap.highResolutionManualControl,
  ]) {
    if (caps.has(cap)) {
      await check(
        'toggle ${cap.replaceAll('Capability', '')}',
        () => client.getToggle(cap),
        (v) => '$v',
      );
    }
  }
  if (caps.has(Cap.speakerVolumeControl)) {
    await check('volume', client.getSpeakerVolume, (v) => '$v');
  }
  if (caps.has(Cap.voicePackManagement)) {
    await check(
      'voice',
      client.getVoicePackStatus,
      (v) => '${v.currentLanguage} ${v.operationType}',
    );
  }
  if (caps.has(Cap.speakerPlayAudio)) {
    await check('audio list', client.getAudioList, (v) => '${v.length} clips');
  }
  if (caps.has(Cap.doNotDisturb)) {
    await check(
      'dnd',
      client.getDnd,
      (d) =>
          '${d.enabled} ${d.startHour}:${d.startMinute}-${d.endHour}:${d.endMinute} UTC',
    );
  }
  if (caps.has(Cap.quirks)) {
    await check(
      'quirks',
      client.getQuirks,
      (q) => q.map((e) => e.title).join(' | '),
    );
  }
  if (caps.has(Cap.wifiConfiguration)) {
    await check(
      'wifi',
      client.getWifiStatus,
      (w) => '${w.state} ${w.signal}dBm ${w.frequency}',
    );
  }
  if (caps.has(Cap.multipleMap)) {
    await check(
      'maps',
      client.getMaps,
      (m) => m.map((e) => '${e.id}:${e.name}${e.active ? '*' : ''}').join(','),
    );
  }
  if (caps.has(Cap.duststreaming)) {
    await check(
      'duststream props',
      client.getDuststreamingProperties,
      (d) =>
          '${d.dimensions.width}x${d.dimensions.height} installed=${d.duststreamerInstalled}',
    );
  }
  await check('timers', client.getTimers, (t) => '${t.length} timers');
  await check(
    'timer props',
    client.getTimerProperties,
    (t) => t.supportedActions.join(','),
  );
  await check(
    'delayed start',
    client.getDelayedStart,
    (d) => d == null ? 'none' : '${d.remaining}s',
  );
  await check('events', client.getEvents, (e) => '${e.length} events');
  await check('updater state', client.getUpdaterState, (u) => u.className);
  await check('update provider', client.getUpdateProvider, (p) => p);
  await check(
    'ntp status',
    client.getNtpStatus,
    (n) => '${n.stateClass} offset=${n.offset}',
  );
  await check('mqtt status', client.getMqttStatus, (m) => m.state);
  await check(
    'host info',
    client.getSystemHostInfo,
    (h) => '${h.hostname} ${h.arch} cpus=${h.cpus.length} up=${h.uptime}',
  );
  await check(
    'runtime info',
    client.getSystemRuntimeInfo,
    (r) => 'pid ${r.pid} gen ${r.generation}',
  );
  await check(
    'log level',
    client.getLogLevel,
    (l) => '${l.current} of ${l.presets.join('/')}',
  );
  await check('log', client.getLog, (l) => '${l.split('\n').length} lines');
  await check(
    'customizations',
    client.getCustomizations,
    (c) => '"${c.friendlyName}"',
  );
  await check(
    'net adv',
    client.getNetworkAdvertisementProperties,
    (p) => '${p['zeroconfHostname']}',
  );

  // Live updates: verify the SSE channel connects, survives keep-alives and
  // delivers parseable payloads.
  stdout.writeln('listening to SSE for ${sseSeconds}s ...');
  final states = <SseState>[];
  final stateSub = client.attributesChannel.states.listen(states.add);
  var attrEvents = 0;
  var mapEvents = 0;
  final a = client.attributesChannel.stream.listen((data) {
    attrEvents++;
    RobotState.fromJson(jsonDecode(data));
  });
  final m = client.mapChannel.stream.listen((data) {
    mapEvents++;
    ValetudoMap.fromJson(asJson(jsonDecode(data)));
  });
  await Future<void>.delayed(Duration(seconds: sseSeconds));
  await a.cancel();
  await m.cancel();
  await stateSub.cancel();
  stdout.writeln(
    'sse states: ${states.map((s) => s.name).join(' -> ')}; '
    'attribute events: $attrEvents, map events: $mapEvents, '
    'lastError: ${client.attributesChannel.lastError}',
  );
  if (!states.contains(SseState.open)) failures++;
  stdout.writeln(
    'commit ${client.transport.commitId} version ${client.transport.reportedVersion}',
  );

  client.close();
  stdout.writeln(failures == 0 ? 'ALL OK' : '$failures FAILURES');
  exit(failures == 0 ? 0 : 1);
}
