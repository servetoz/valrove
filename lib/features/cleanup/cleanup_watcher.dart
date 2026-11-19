import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/cleanup/cleanup_tracker.dart';
import '../../core/cleanup/map_summary.dart';
import '../../core/valetudo/capabilities.dart';
import '../../core/valetudo/models/models.dart';
import '../../state/app_state.dart';
import '../../state/cleanup.dart';
import '../../state/session.dart';
import '../../state/toasts.dart';
import 'cleanup_extras.dart';
import 'cleanup_service.dart';

/// Whether platform integrations (background service, widget, shortcuts)
/// are available. False on desktops and in tests.
final integrationsEnabledProvider = Provider<bool>(
  (ref) =>
      !kIsWeb &&
      (Platform.isAndroid || Platform.isIOS) &&
      !Platform.environment.containsKey('FLUTTER_TEST'),
);

/// Starts the background service when a cleanup begins. Without it (iOS, or
/// notifications turned off) the app records cleanups itself while open.
class CleanupWatcher {
  CleanupWatcher(this._ref)
    : _serviceMessages =
          _ref.read(integrationsEnabledProvider) && CleanupService.supported {
    _ref.listen<RobotState>(
      robotStateProvider,
      (_, state) => _onState(state),
      fireImmediately: true,
    );
    // The service may have saved a cleanup while the app was away.
    _ref.listen<bool>(appInForegroundProvider, (_, foreground) {
      if (!foreground) return;
      _ref
        ..invalidate(historyProvider)
        ..invalidate(wifiCoverageProvider)
        ..invalidate(lostFoundProvider);
    });
    if (_serviceMessages) {
      FlutterForegroundTask.addTaskDataCallback(_onTaskData);
    }
  }

  final Ref _ref;
  final bool _serviceMessages;
  CleanupTracker? _tracker;
  Timer? _poll;
  bool _starting = false;
  bool _polling = false;

  void _onTaskData(Object data) {
    if (data is! Map) return;
    if (data.containsKey(CleanupService.historyMessage)) {
      _ref
        ..invalidate(historyProvider)
        ..invalidate(wifiCoverageProvider);
    }
    if (data.containsKey(CleanupService.foundMessage)) {
      _ref.invalidate(lostFoundProvider);
    }
  }

  bool get _useService =>
      _serviceMessages && _ref.read(settingsProvider).cleanupNotifications;

  Future<void> _onState(RobotState state) async {
    final robot = _ref.read(activeProfileProvider);
    if (robot == null || !state.hasStatus) return;
    if (_useService) {
      _stopRecording();
      if (state.job != JobState.none && !_starting) {
        _starting = true;
        try {
          await CleanupService.start(robot.id);
        } catch (e) {
          debugPrint('Could not start the cleanup service: $e');
        } finally {
          _starting = false;
        }
      }
      return;
    }
    if (_tracker?.robotId != robot.id) {
      _stopRecording();
      _tracker = CleanupTracker(robotId: robot.id);
    }
    _feed(CleanupSample(at: DateTime.now(), state: state));
    if (_tracker!.tracking) {
      _poll ??= Timer.periodic(const Duration(seconds: 15), (_) => _details());
    }
  }

  void _feed(CleanupSample sample) {
    final tracker = _tracker;
    if (tracker == null) return;
    if (tracker.add(sample).ended) {
      _poll?.cancel();
      _poll = null;
      unawaited(_finish(tracker));
    }
  }

  /// Statistics and the map, which the live state doesn't carry.
  Future<void> _details() async {
    final client = _ref.read(clientProvider);
    if (client == null || _polling) return;
    _polling = true;
    try {
      double? area;
      int? seconds;
      if (_ref.read(capsProvider).has(Cap.currentStatistics)) {
        for (final p in await client.getStatistics(Cap.currentStatistics)) {
          if (p.type == 'area') area = p.value;
          if (p.type == 'time') seconds = p.value.round();
        }
      }
      final map = MapSummary.fromJson(jsonDecode(await client.getMapJson()));
      _feed(
        CleanupSample(
          at: DateTime.now(),
          state: _ref.read(robotStateProvider),
          areaCm2: area,
          seconds: seconds,
          map: map,
        ),
      );
      await _extrasFor(map);
    } catch (_) {
      // Next time.
    } finally {
      _polling = false;
    }
  }

  Future<void> _finish(CleanupTracker tracker) async {
    MapSummary? map;
    try {
      final client = _ref.read(clientProvider);
      if (client != null) {
        map = MapSummary.fromJson(jsonDecode(await client.getMapJson()));
      }
    } catch (_) {}
    final record = tracker.finish(map: map);
    if (record == null) return;
    try {
      final store = await _ref.read(historyStoreProvider.future);
      await store.add(record);
      _ref.invalidate(historyProvider);
    } catch (e) {
      debugPrint('Could not save the cleanup: $e');
    }
    if (map != null) await _extrasFor(map);
    final extras = await _extras();
    if (extras == null) return;
    final after = await extras.afterCleanup(record, map: map);
    for (final alert in after.alerts) {
      _ref.read(toastProvider).show(alert.title, detail: alert.body);
    }
  }

  Future<CleanupExtras?> _extras() async {
    final client = _ref.read(clientProvider);
    final robot = _ref.read(activeProfileProvider);
    if (client == null || robot == null) return null;
    return CleanupExtras(
      client: client,
      robotId: robot.id,
      caps: _ref.read(capsProvider),
      files: await _ref.read(robotFilesProvider.future),
      history: await _ref.read(historyStoreProvider.future),
    );
  }

  /// Wi-Fi reading and new obstacles while the app follows the cleanup.
  Future<void> _extrasFor(MapSummary map) async {
    try {
      final extras = await _extras();
      if (extras == null) return;
      try {
        await extras.sampleWifi(map);
        _ref.invalidate(wifiCoverageProvider);
      } catch (_) {}
      if ((await extras.collectObstacles(map)).isNotEmpty) {
        _ref.invalidate(lostFoundProvider);
      }
    } catch (_) {}
  }

  void _stopRecording() {
    _poll?.cancel();
    _poll = null;
    _tracker = null;
  }

  void dispose() {
    _stopRecording();
    if (_serviceMessages) {
      FlutterForegroundTask.removeTaskDataCallback(_onTaskData);
    }
  }
}

final cleanupWatcherProvider = Provider<CleanupWatcher>((ref) {
  final watcher = CleanupWatcher(ref);
  ref.onDispose(watcher.dispose);
  return watcher;
});
