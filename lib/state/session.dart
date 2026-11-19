import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/valetudo/capabilities.dart';
import '../core/valetudo/client/valetudo_client.dart';
import '../core/valetudo/models/models.dart';
import '../map/processing/map_palette.dart';
import '../map/processing/map_processor.dart';
import '../map/render/map_scene.dart';
import 'app_state.dart';
import 'demo_robot.dart';

/// Creates clients (for the demo robot too); overridden in tests to serve
/// recorded responses.
final clientFactoryProvider =
    Provider<ValetudoClient Function(ValetudoEndpoint)>((ref) => connectRobot);

/// Client for the active robot (null when no robot is configured).
final clientProvider = Provider<ValetudoClient?>((ref) {
  final key = ref.watch(activeProfileProvider.select((p) => p?.connectionKey));
  final profile = ref.read(activeProfileProvider);
  if (key == null || profile == null) return null;
  final client = ref.read(clientFactoryProvider)(profile.endpoint);
  ref.onDispose(client.close);

  // Valetudo was updated/replaced: drop everything derived from the old
  // backend (capabilities can change between versions).
  final sub = client.transport.commitIdChanges.listen(
    (_) => ref.invalidateSelf(),
  );
  ref.onDispose(sub.cancel);
  return client;
});

ValetudoClient requireClient(Ref ref) {
  final client = ref.watch(clientProvider);
  if (client == null) {
    throw const ValetudoConnectionException('No robot selected');
  }
  return client;
}

// ---------------------------------------------------------------------------
// Connection health
// ---------------------------------------------------------------------------

enum LinkState { connecting, online, offline, unauthorized }

class ConnectionHealth {
  const ConnectionHealth({required this.state, this.error, this.lastContact});

  final LinkState state;
  final Object? error;
  final DateTime? lastContact;

  bool get isOnline => state == LinkState.online;
}

class ConnectionHealthNotifier extends Notifier<ConnectionHealth> {
  @override
  ConnectionHealth build() {
    ref.watch(clientProvider);
    return const ConnectionHealth(state: LinkState.connecting);
  }

  void reportSuccess() {
    if (state.state != LinkState.online || state.lastContact == null) {
      state = ConnectionHealth(
        state: LinkState.online,
        lastContact: DateTime.now(),
      );
    }
  }

  void reportError(Object error) {
    if (error is ValetudoUnauthorizedException) {
      state = ConnectionHealth(
        state: LinkState.unauthorized,
        error: error,
        lastContact: state.lastContact,
      );
    } else if (error is ValetudoConnectionException) {
      state = ConnectionHealth(
        state: LinkState.offline,
        error: error,
        lastContact: state.lastContact,
      );
    }
  }
}

final connectionHealthProvider =
    NotifierProvider<ConnectionHealthNotifier, ConnectionHealth>(
      ConnectionHealthNotifier.new,
    );

// ---------------------------------------------------------------------------
// Static robot information
// ---------------------------------------------------------------------------

/// Capabilities of the active robot. A cached copy from the last session is
/// used immediately so the interface can adapt before the robot answers.
final capabilitiesProvider = FutureProvider<Capabilities>((ref) async {
  final client = requireClient(ref);
  final prefs = ref.read(sharedPreferencesProvider);
  final profileId = ref.read(activeProfileProvider)?.id;
  final cacheKey = 'robot.$profileId.capabilities';
  try {
    final caps = await client.getCapabilities();
    ref.read(connectionHealthProvider.notifier).reportSuccess();
    unawaited(prefs.setString(cacheKey, jsonEncode(caps.names.toList())));
    return caps;
  } catch (e) {
    ref.read(connectionHealthProvider.notifier).reportError(e);
    final cached = prefs.getString(cacheKey);
    if (cached != null && e is ValetudoConnectionException) {
      // Retry in the background while showing the cached capabilities.
      final timer = Timer(const Duration(seconds: 5), ref.invalidateSelf);
      ref.onDispose(timer.cancel);
      return Capabilities.fromJson(jsonDecode(cached));
    }
    rethrow;
  }
});

/// Synchronous view of the capabilities (empty while unknown).
final capsProvider = Provider<Capabilities>(
  (ref) => ref.watch(capabilitiesProvider).value ?? Capabilities.empty,
);

final robotInfoProvider = FutureProvider<RobotInformation>(
  (ref) => requireClient(ref).getRobotInformation(),
);

final robotPropertiesProvider = FutureProvider<RobotProperties>(
  (ref) => requireClient(ref).getRobotProperties(),
);

final valetudoInfoProvider = FutureProvider<ValetudoInformation>(
  (ref) => requireClient(ref).getValetudoInformation(),
);

final valetudoVersionProvider = FutureProvider<ValetudoVersion>(
  (ref) => requireClient(ref).getValetudoVersion(),
);

final customizationsProvider = FutureProvider<ValetudoCustomizations>(
  (ref) => requireClient(ref).getCustomizations(),
);

// ---------------------------------------------------------------------------
// Live robot state (attributes)
// ---------------------------------------------------------------------------

class LiveStateNotifier extends Notifier<AsyncValue<RobotState>> {
  StreamSubscription<String>? _events;
  StreamSubscription<SseState>? _states;
  Timer? _safetyPoll;
  int _generation = 0;

  @override
  AsyncValue<RobotState> build() {
    final client = ref.watch(clientProvider);
    _generation++;
    ref.onDispose(_stop);
    if (client == null) return const AsyncLoading();

    ref.listen<bool>(appInForegroundProvider, (prev, foreground) {
      if (foreground) {
        _start(client);
        refresh();
      } else {
        _stop();
      }
    });
    if (ref.read(appInForegroundProvider)) _start(client);
    Future.microtask(refresh);
    return const AsyncLoading();
  }

  void _start(ValetudoClient client) {
    _stop();
    _events = client.attributesChannel.stream.listen((data) {
      try {
        final parsed = RobotState.fromJson(jsonDecode(data));
        state = AsyncData(parsed);
        ref.read(connectionHealthProvider.notifier).reportSuccess();
      } catch (e) {
        debugPrint('Invalid attributes event: $e');
      }
    });
    _states = client.attributesChannel.states.listen((s) {
      if (s == SseState.open) {
        // Events may have been missed while disconnected.
        refresh();
      } else if (s == SseState.retrying) {
        final error = client.attributesChannel.lastError;
        if (error != null) {
          ref.read(connectionHealthProvider.notifier).reportError(error);
        }
      }
    });
    _safetyPoll = Timer.periodic(const Duration(seconds: 60), (_) => refresh());
  }

  void _stop() {
    _events?.cancel();
    _states?.cancel();
    _safetyPoll?.cancel();
    _events = null;
    _states = null;
    _safetyPoll = null;
  }

  /// Fetches the attributes now (also used after sending commands).
  Future<void> refresh() async {
    final client = ref.read(clientProvider);
    if (client == null) return;
    final generation = _generation;
    try {
      final result = await client.getStateAttributes();
      if (generation != _generation || !ref.mounted) return;
      state = AsyncData(result);
      ref.read(connectionHealthProvider.notifier).reportSuccess();
    } catch (e, st) {
      if (generation != _generation || !ref.mounted) return;
      ref.read(connectionHealthProvider.notifier).reportError(e);
      if (!state.hasValue) state = AsyncError(e, st);
    }
  }

  /// Applies attributes returned by a command round-trip.
  void set(RobotState value) => state = AsyncData(value);
}

final liveStateProvider =
    NotifierProvider<LiveStateNotifier, AsyncValue<RobotState>>(
      LiveStateNotifier.new,
    );

/// Last known robot state (empty until the first response).
final robotStateProvider = Provider<RobotState>(
  (ref) => ref.watch(liveStateProvider).value ?? RobotState.empty,
);

final robotStatusProvider = Provider<StatusAttribute>(
  (ref) => ref.watch(robotStateProvider).status,
);

// ---------------------------------------------------------------------------
// Live map
// ---------------------------------------------------------------------------

class LiveMapState {
  const LiveMapState({
    this.scene,
    this.error,
    this.loading = true,
    this.rawJson,
  });

  final MapScene? scene;
  final Object? error;
  final bool loading;

  /// Raw JSON of the current map (used for exporting).
  final String? rawJson;

  bool get hasMap => scene != null && scene!.data.hasLayers;
}

class LiveMapNotifier extends Notifier<LiveMapState> {
  StreamSubscription<String>? _events;
  StreamSubscription<SseState>? _states;
  MapSceneBuilder? _builder;
  String? _pending;
  String? _lastJson;
  bool _processing = false;
  int _generation = 0;

  @override
  LiveMapState build() {
    final client = ref.watch(clientProvider);
    _generation++;
    // A drain loop of a previous generation exits on its next check; start
    // with a clean queue so new updates are never stuck behind it.
    _processing = false;
    _pending = null;
    _lastJson = null;
    final builder = MapSceneBuilder();
    _builder = builder;
    ref.onDispose(() {
      _stop();
      builder.dispose();
    });
    if (client == null) return const LiveMapState(loading: false);

    ref.listen<bool>(appInForegroundProvider, (prev, foreground) {
      if (foreground) {
        _start(client);
        refresh();
      } else {
        _stop();
      }
    });
    ref.listen<bool>(isDarkProvider, (prev, dark) {
      final json = _lastJson;
      if (json != null) _submit(json);
    });
    if (ref.read(appInForegroundProvider)) _start(client);
    Future.microtask(refresh);
    return const LiveMapState();
  }

  void _start(ValetudoClient client) {
    _stop();
    _events = client.mapChannel.stream.listen(_submit);
    _states = client.mapChannel.states.listen((s) {
      if (s == SseState.open) refresh();
    });
  }

  void _stop() {
    _events?.cancel();
    _states?.cancel();
    _events = null;
    _states = null;
  }

  Future<void> refresh() async {
    final client = ref.read(clientProvider);
    if (client == null) return;
    final generation = _generation;
    try {
      final json = await client.getMapJson();
      if (generation != _generation || !ref.mounted) return;
      _submit(json);
    } catch (e) {
      if (generation != _generation || !ref.mounted) return;
      ref.read(connectionHealthProvider.notifier).reportError(e);
      if (state.scene == null) state = LiveMapState(error: e, loading: false);
    }
  }

  /// Queues a map for processing; while one is being processed only the
  /// newest pending map is kept.
  void _submit(String json) {
    _pending = json;
    if (!_processing) _drain();
  }

  Future<void> _drain() async {
    _processing = true;
    final generation = _generation;
    try {
      while (_pending != null) {
        final json = _pending!;
        _pending = null;
        final dark = ref.read(isDarkProvider);
        try {
          final processed = await processMapInBackground(
            json,
            dark ? MapPalette.dark : MapPalette.light,
            dark ? 1 : 0,
          );
          if (generation != _generation || !ref.mounted) return;
          final scene = await _builder!.build(processed);
          if (generation != _generation || !ref.mounted) return;
          _lastJson = json;
          state = LiveMapState(scene: scene, loading: false, rawJson: json);
          ref.read(connectionHealthProvider.notifier).reportSuccess();
        } catch (e) {
          if (generation != _generation || !ref.mounted) return;
          debugPrint('Map processing failed: $e');
          if (state.scene == null) {
            state = LiveMapState(error: e, loading: false);
          }
        }
      }
    } finally {
      if (generation == _generation) _processing = false;
    }
  }
}

final liveMapProvider = NotifierProvider<LiveMapNotifier, LiveMapState>(
  LiveMapNotifier.new,
);
