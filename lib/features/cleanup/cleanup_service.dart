import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart'
    hide NotificationVisibility;
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/cleanup/cleanup_tracker.dart';
import '../../core/cleanup/history_store.dart';
import '../../core/cleanup/map_summary.dart';
import '../../core/cleanup/robot_files.dart';
import '../../core/persistence/stores.dart';
import '../../core/valetudo/capabilities.dart';
import '../../core/valetudo/client/valetudo_client.dart';
import '../../core/valetudo/models/models.dart';
import '../../state/cleanup.dart';
import '../../state/demo_robot.dart';
import 'cleanup_extras.dart';

/// Follows a cleanup in an Android foreground service, so the live
/// notification, the alerts and the history also work while Valrove is
/// closed. The service stops itself when the cleanup is over.
abstract final class CleanupService {
  static bool get supported => !kIsWeb && Platform.isAndroid;

  static const _robotKey = 'robotId';

  /// Sent to the app when a cleanup was added to the history.
  static const historyMessage = 'history';

  /// Sent to the app when obstacles were added to lost & found.
  static const foundMessage = 'found';

  /// Call once before `runApp` so the service can talk to the app.
  static void initCommunication() {
    if (supported) FlutterForegroundTask.initCommunicationPort();
  }

  static Future<bool> get running async =>
      supported && await FlutterForegroundTask.isRunningService;

  /// Starts following the cleanup of robot [robotId]. Without a screen
  /// ([askPermission] false) a missing notification permission is not asked
  /// for.
  static Future<void> start(String robotId, {bool askPermission = true}) async {
    // The demo robot only exists in the app, which records its cleanups.
    if (robotId == demoRobotId) return;
    if (!supported || await FlutterForegroundTask.isRunningService) return;
    final permission =
        await FlutterForegroundTask.checkNotificationPermission();
    if (permission != NotificationPermission.granted && askPermission) {
      await FlutterForegroundTask.requestNotificationPermission();
    }
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'cleanup_live',
        channelName: 'Cleaning in progress',
        channelDescription:
            'Shows the running cleanup with buttons to pause or send the '
            'robot home.',
        onlyAlertOnce: true,
        visibility: NotificationVisibility.VISIBILITY_PUBLIC,
      ),
      iosNotificationOptions: const IOSNotificationOptions(
        showNotification: false,
      ),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.repeat(5000),
        allowWakeLock: true,
        allowWifiLock: true,
        stopWithTask: false,
      ),
    );
    await FlutterForegroundTask.saveData(key: _robotKey, value: robotId);
    await FlutterForegroundTask.startService(
      serviceId: 410,
      serviceTypes: const [ForegroundServiceTypes.connectedDevice],
      notificationTitle: 'Cleaning',
      notificationText: 'Connecting to the robot…',
      notificationIcon: notificationIcon,
      callback: startCleanupTask,
    );
  }

  static const notificationIcon = NotificationIcon(
    metaDataName: 'dev.valroveapp.valrove.NOTIFICATION_ICON',
  );
}

@pragma('vm:entry-point')
void startCleanupTask() =>
    FlutterForegroundTask.setTaskHandler(CleanupTaskHandler());

/// Runs in the service's own isolate: polls the robot every five seconds
/// and feeds a [CleanupTracker].
class CleanupTaskHandler extends TaskHandler {
  ValetudoClient? _client;
  CleanupTracker? _tracker;
  HistoryStore? _store;
  Capabilities _caps = Capabilities.empty;
  final _notifications = FlutterLocalNotificationsPlugin();
  CleanupExtras? _extras;
  int _tick = 0;
  int _idleTicks = 0;
  bool _busy = false;
  DateTime _lastContact = DateTime.now();
  String? _shown;

  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    try {
      final robotId = await FlutterForegroundTask.getData<String>(
        key: CleanupService._robotKey,
      );
      final prefs = await SharedPreferences.getInstance();
      final profiles = await ProfileRepository(
        prefs,
        SecureSecretStore(),
      ).load();
      final profile = profiles.where((p) => p.id == robotId).firstOrNull;
      if (profile == null) {
        await FlutterForegroundTask.stopService();
        return;
      }
      _client = ValetudoClient.connect(profile.endpoint);
      _tracker = CleanupTracker(robotId: profile.id);
      _store = HistoryStore(await historyDirectory());
      await _notifications.initialize(
        settings: const InitializationSettings(
          android: AndroidInitializationSettings('ic_stat_valrove'),
        ),
      );
      _caps = await _client!.getCapabilities();
      _extras = CleanupExtras(
        client: _client!,
        robotId: profile.id,
        caps: _caps,
        files: RobotFiles(await historyDirectory()),
        history: _store!,
      );
    } catch (e) {
      debugPrint('Cleanup service could not start: $e');
    }
    await _poll();
  }

  @override
  void onRepeatEvent(DateTime timestamp) => _poll();

  Future<void> _poll() async {
    final client = _client;
    final tracker = _tracker;
    if (client == null || tracker == null || _busy) return;
    _busy = true;
    final first = _tick == 0;
    _tick++;
    try {
      final state = await client.getStateAttributes();
      double? area;
      int? seconds;
      if ((first || _tick % 3 == 0) && _caps.has(Cap.currentStatistics)) {
        for (final p in await client.getStatistics(Cap.currentStatistics)) {
          if (p.type == 'area') area = p.value;
          if (p.type == 'time') seconds = p.value.round();
        }
      }
      // The map every 10 s: rooms, path, obstacles and where the robot is
      // (for the Wi-Fi readings).
      MapSummary? map;
      List<ValetudoEvent>? events;
      if (first || _tick.isEven) map = await _map(client);
      if (first || _tick % 6 == 0) events = await client.getEvents();
      final update = tracker.add(
        CleanupSample(
          at: DateTime.now(),
          state: state,
          areaCm2: area,
          seconds: seconds,
          map: map,
          events: events,
        ),
      );
      _lastContact = DateTime.now();
      for (final alert in update.alerts) {
        await _alert(alert);
      }
      if (update.ended) {
        await _finish(client, tracker);
        return;
      }
      final ongoing = update.ongoing;
      if (ongoing == null) {
        // Started for a cleanup that is already over.
        if (++_idleTicks >= 2) await FlutterForegroundTask.stopService();
        return;
      }
      _idleTicks = 0;
      await _show(ongoing);
      if (map != null) await _extrasFor(map);
    } catch (e) {
      if (DateTime.now().difference(_lastContact) >
          const Duration(minutes: 10)) {
        await FlutterForegroundTask.stopService();
      } else {
        await FlutterForegroundTask.updateService(
          notificationText: 'The robot is not reachable, retrying…',
        );
        _shown = null;
      }
    } finally {
      _busy = false;
    }
  }

  Future<MapSummary?> _map(ValetudoClient client) async {
    try {
      return MapSummary.fromJson(jsonDecode(await client.getMapJson()));
    } catch (_) {
      return null;
    }
  }

  /// Wi-Fi reading and new obstacles; failures only skip this round.
  Future<void> _extrasFor(MapSummary map) async {
    final extras = _extras;
    if (extras == null) return;
    try {
      await extras.sampleWifi(map);
    } catch (_) {}
    try {
      if ((await extras.collectObstacles(map)).isNotEmpty) {
        FlutterForegroundTask.sendDataToMain({
          CleanupService.foundMessage: extras.robotId,
        });
      }
    } catch (_) {}
  }

  Future<void> _finish(ValetudoClient client, CleanupTracker tracker) async {
    final map = await _map(client);
    final record = tracker.finish(map: map);
    var nextStep = false;
    if (record != null) {
      try {
        await _store?.add(record);
        FlutterForegroundTask.sendDataToMain({
          CleanupService.historyMessage: record.robotId,
        });
      } catch (e) {
        debugPrint('Could not save the cleanup: $e');
      }
      await _alert(CleanupTracker.finishedAlert(record));
      if (map != null) await _extrasFor(map);
      final after = await _extras?.afterCleanup(record, map: map);
      for (final alert in after?.alerts ?? const <CleanupAlert>[]) {
        await _alert(alert);
      }
      nextStep = after?.nextStepStarted ?? false;
    }
    // The next step of a preset: keep following the robot.
    if (nextStep) {
      _shown = null;
      _idleTicks = -3;
      return;
    }
    await FlutterForegroundTask.stopService();
  }

  Future<void> _show(OngoingCleanup ongoing) async {
    final key = '${ongoing.title}|${ongoing.text}|${ongoing.actions}';
    if (key == _shown) return;
    _shown = key;
    await FlutterForegroundTask.updateService(
      notificationTitle: ongoing.title,
      notificationText: ongoing.text,
      notificationIcon: CleanupService.notificationIcon,
      notificationButtons: [
        for (final a in ongoing.actions)
          NotificationButton(
            id: a.name,
            text: switch (a) {
              CleanupAction.pause => 'Pause',
              CleanupAction.resume => 'Resume',
              CleanupAction.dock => 'Dock',
            },
          ),
      ],
    );
  }

  Future<void> _alert(CleanupAlert alert) async {
    try {
      await _notifications.show(
        id: alert.key.hashCode & 0x7fffffff,
        title: alert.title,
        body: alert.body,
        notificationDetails: const NotificationDetails(
          android: AndroidNotificationDetails(
            'cleanup_alerts',
            'Cleaning alerts',
            channelDescription:
                'When a cleanup finishes or the robot needs help.',
            importance: Importance.high,
            priority: Priority.high,
            icon: 'ic_stat_valrove',
          ),
        ),
      );
    } catch (e) {
      debugPrint('Could not show "${alert.title}": $e');
    }
  }

  @override
  void onNotificationButtonPressed(String id) {
    final client = _client;
    if (client == null) return;
    final action = switch (id) {
      'pause' => 'pause',
      'resume' => 'start',
      'dock' => 'home',
      _ => null,
    };
    if (action == null) return;
    client.basicControl(action).then((_) => _poll(), onError: (_) {});
  }

  @override
  void onNotificationPressed() => FlutterForegroundTask.launchApp();

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {
    _client?.close();
    _client = null;
  }
}
