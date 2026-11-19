import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/persistence/robot_profile.dart';
import '../core/persistence/stores.dart';
import '../ui/haptics.dart';

/// Overridden in `main()` with the loaded instance.
final sharedPreferencesProvider = Provider<SharedPreferences>(
  (ref) => throw UnimplementedError(),
);

final secretStoreProvider = Provider<SecretStore>((ref) => SecureSecretStore());

/// Profiles loaded before the app starts (overridden in `main()`).
final initialProfilesProvider = Provider<List<RobotProfile>>((ref) => const []);

final profileRepositoryProvider = Provider<ProfileRepository>(
  (ref) => ProfileRepository(
    ref.watch(sharedPreferencesProvider),
    ref.watch(secretStoreProvider),
  ),
);

// ---------------------------------------------------------------------------
// Settings
// ---------------------------------------------------------------------------

enum AppThemeMode { system, light, dark }

class AppSettings {
  const AppSettings({
    this.themeMode = AppThemeMode.system,
    this.haptics = true,
    this.cleanupNotifications = true,
  });

  final AppThemeMode themeMode;
  final bool haptics;

  /// Follow cleanups in a background service with a live notification and
  /// alerts (Android).
  final bool cleanupNotifications;

  AppSettings copyWith({
    AppThemeMode? themeMode,
    bool? haptics,
    bool? cleanupNotifications,
  }) => AppSettings(
    themeMode: themeMode ?? this.themeMode,
    haptics: haptics ?? this.haptics,
    cleanupNotifications: cleanupNotifications ?? this.cleanupNotifications,
  );
}

class SettingsNotifier extends Notifier<AppSettings> {
  static const _themeKey = 'settings.theme';
  static const _hapticsKey = 'settings.haptics';
  static const _cleanupNotificationsKey = 'settings.cleanupNotifications';

  SharedPreferences get _prefs => ref.read(sharedPreferencesProvider);

  @override
  AppSettings build() {
    final prefs = ref.watch(sharedPreferencesProvider);
    final theme = AppThemeMode.values
        .where((m) => m.name == prefs.getString(_themeKey))
        .firstOrNull;
    final haptics = prefs.getBool(_hapticsKey) ?? true;
    Haptics.enabled = haptics;
    return AppSettings(
      themeMode: theme ?? AppThemeMode.system,
      haptics: haptics,
      cleanupNotifications: prefs.getBool(_cleanupNotificationsKey) ?? true,
    );
  }

  void setThemeMode(AppThemeMode mode) {
    state = state.copyWith(themeMode: mode);
    _prefs.setString(_themeKey, mode.name);
  }

  void setHaptics(bool enabled) {
    Haptics.enabled = enabled;
    state = state.copyWith(haptics: enabled);
    _prefs.setBool(_hapticsKey, enabled);
  }

  void setCleanupNotifications(bool enabled) {
    state = state.copyWith(cleanupNotifications: enabled);
    _prefs.setBool(_cleanupNotificationsKey, enabled);
  }
}

final settingsProvider = NotifierProvider<SettingsNotifier, AppSettings>(
  SettingsNotifier.new,
);

// ---------------------------------------------------------------------------
// Platform brightness & lifecycle
// ---------------------------------------------------------------------------

class _BindingObserver extends WidgetsBindingObserver {
  _BindingObserver({this.onBrightness, this.onLifecycle});

  final VoidCallback? onBrightness;
  final ValueChanged<AppLifecycleState>? onLifecycle;

  @override
  void didChangePlatformBrightness() => onBrightness?.call();

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) =>
      onLifecycle?.call(state);
}

class PlatformBrightnessNotifier extends Notifier<Brightness> {
  @override
  Brightness build() {
    final dispatcher = WidgetsBinding.instance.platformDispatcher;
    final observer = _BindingObserver(
      onBrightness: () => state = dispatcher.platformBrightness,
    );
    WidgetsBinding.instance.addObserver(observer);
    ref.onDispose(() => WidgetsBinding.instance.removeObserver(observer));
    return dispatcher.platformBrightness;
  }
}

final platformBrightnessProvider =
    NotifierProvider<PlatformBrightnessNotifier, Brightness>(
      PlatformBrightnessNotifier.new,
    );

/// Whether the dark theme is in effect.
final isDarkProvider = Provider<bool>((ref) {
  final mode = ref.watch(settingsProvider.select((s) => s.themeMode));
  return switch (mode) {
    AppThemeMode.dark => true,
    AppThemeMode.light => false,
    AppThemeMode.system =>
      ref.watch(platformBrightnessProvider) == Brightness.dark,
  };
});

class AppLifecycleNotifier extends Notifier<AppLifecycleState> {
  @override
  AppLifecycleState build() {
    final observer = _BindingObserver(onLifecycle: (s) => state = s);
    WidgetsBinding.instance.addObserver(observer);
    ref.onDispose(() => WidgetsBinding.instance.removeObserver(observer));
    return WidgetsBinding.instance.lifecycleState ?? AppLifecycleState.resumed;
  }
}

final appLifecycleProvider =
    NotifierProvider<AppLifecycleNotifier, AppLifecycleState>(
      AppLifecycleNotifier.new,
    );

/// Whether the app is visible to the user in [lifecycle].
bool isForeground(AppLifecycleState lifecycle) =>
    lifecycle == AppLifecycleState.resumed ||
    lifecycle == AppLifecycleState.inactive;

/// True while the app is visible to the user.
final appInForegroundProvider = Provider<bool>(
  (ref) => isForeground(ref.watch(appLifecycleProvider)),
);

// ---------------------------------------------------------------------------
// Openings
// ---------------------------------------------------------------------------

/// How many times the app has been opened on this phone: each launch counts,
/// and so does coming back after [sessionGap] or more in the background.
class AppOpeningsNotifier extends Notifier<int> {
  AppOpeningsNotifier({DateTime Function()? clock})
    : _now = clock ?? DateTime.now;

  static const _key = 'app.openings';

  /// Time away after which coming back counts as opening the app again.
  static const sessionGap = Duration(minutes: 30);

  final DateTime Function() _now;
  DateTime? _leftAt;

  @override
  int build() {
    // Observed directly: Riverpod pauses listeners on pages that are
    // covered, and returns to such a page count too.
    final observer = _BindingObserver(onLifecycle: _lifecycleChanged);
    WidgetsBinding.instance.addObserver(observer);
    ref.onDispose(() => WidgetsBinding.instance.removeObserver(observer));
    return _count();
  }

  void _lifecycleChanged(AppLifecycleState lifecycle) {
    if (!isForeground(lifecycle)) {
      _leftAt ??= _now();
    } else if (_leftAt case final left?) {
      _leftAt = null;
      if (_now().difference(left) >= sessionGap) state = _count();
    }
  }

  int _count() {
    final prefs = ref.read(sharedPreferencesProvider);
    final count = (prefs.getInt(_key) ?? 0) + 1;
    prefs.setInt(_key, count);
    return count;
  }
}

final appOpeningsProvider = NotifierProvider<AppOpeningsNotifier, int>(
  AppOpeningsNotifier.new,
);

// ---------------------------------------------------------------------------
// Robot profiles
// ---------------------------------------------------------------------------

class RobotsState {
  const RobotsState({required this.profiles, required this.activeId});

  final List<RobotProfile> profiles;
  final String? activeId;

  RobotProfile? get active =>
      profiles.where((p) => p.id == activeId).firstOrNull ??
      profiles.firstOrNull;
}

class RobotsNotifier extends Notifier<RobotsState> {
  ProfileRepository get _repo => ref.read(profileRepositoryProvider);

  @override
  RobotsState build() {
    final profiles = ref.watch(initialProfilesProvider);
    return RobotsState(
      profiles: profiles,
      activeId: ref.read(profileRepositoryProvider).activeId,
    );
  }

  static String newId() {
    final r = math.Random.secure();
    return List.generate(12, (_) => r.nextInt(36).toRadixString(36)).join();
  }

  Future<void> upsert(RobotProfile profile, {bool activate = true}) async {
    final list = [...state.profiles];
    final i = list.indexWhere((p) => p.id == profile.id);
    if (i >= 0) {
      list[i] = profile;
    } else {
      list.add(profile);
    }
    state = RobotsState(
      profiles: list,
      activeId: activate ? profile.id : state.activeId,
    );
    await _repo.save(list);
    if (activate) await _repo.setActiveId(profile.id);
  }

  Future<void> remove(String id) async {
    final list = state.profiles.where((p) => p.id != id).toList();
    final active = state.activeId == id ? list.firstOrNull?.id : state.activeId;
    state = RobotsState(profiles: list, activeId: active);
    await _repo.save(list);
    await _repo.deleteSecrets(id);
    await _repo.setActiveId(active);
  }

  Future<void> activate(String id) async {
    if (state.activeId == id) return;
    state = RobotsState(profiles: state.profiles, activeId: id);
    await _repo.setActiveId(id);
  }
}

final robotsProvider = NotifierProvider<RobotsNotifier, RobotsState>(
  RobotsNotifier.new,
);

final activeProfileProvider = Provider<RobotProfile?>(
  (ref) => ref.watch(robotsProvider).active,
);
