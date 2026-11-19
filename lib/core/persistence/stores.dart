import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../valetudo/json_utils.dart';
import 'robot_profile.dart';

/// Storage for secrets (robot passwords).
abstract interface class SecretStore {
  Future<String?> read(String key);
  Future<void> write(String key, String? value);
}

class SecureSecretStore implements SecretStore {
  SecureSecretStore([FlutterSecureStorage? storage])
    : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  @override
  Future<String?> read(String key) async {
    try {
      return await _storage.read(key: key);
    } catch (_) {
      // Keystore can become unreadable (e.g. after a backup restore); treat
      // as missing so the user is asked for the password again.
      return null;
    }
  }

  @override
  Future<void> write(String key, String? value) async {
    if (value == null || value.isEmpty) {
      await _storage.delete(key: key);
    } else {
      await _storage.write(key: key, value: value);
    }
  }
}

/// In-memory secret store for tests.
class MemorySecretStore implements SecretStore {
  final Map<String, String> values = {};

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String? value) async {
    if (value == null || value.isEmpty) {
      values.remove(key);
    } else {
      values[key] = value;
    }
  }
}

/// Persists robot profiles (passwords go to the [SecretStore]).
class ProfileRepository {
  ProfileRepository(this._prefs, this._secrets);

  static const _profilesKey = 'robots.v1';
  static const _activeKey = 'robots.active';

  final SharedPreferences _prefs;
  final SecretStore _secrets;

  static String _passwordKey(String id) => 'robot.$id.password';

  Future<List<RobotProfile>> load() async {
    final raw = _prefs.getString(_profilesKey);
    if (raw == null) return [];
    List<RobotProfile> profiles;
    try {
      profiles = asJsonList(jsonDecode(raw))
          .map(RobotProfile.fromJson)
          .where((p) => p.url.isNotEmpty)
          .toList();
    } catch (_) {
      return [];
    }
    return [
      for (final p in profiles)
        p.copyWith(password: await _secrets.read(_passwordKey(p.id))),
    ];
  }

  Future<void> save(List<RobotProfile> profiles) async {
    await _prefs.setString(
      _profilesKey,
      jsonEncode(profiles.map((p) => p.toJson()).toList()),
    );
    for (final p in profiles) {
      await _secrets.write(_passwordKey(p.id), p.password);
    }
  }

  Future<void> deleteSecrets(String id) =>
      _secrets.write(_passwordKey(id), null);

  String? get activeId => _prefs.getString(_activeKey);

  Future<void> setActiveId(String? id) async {
    if (id == null) {
      await _prefs.remove(_activeKey);
    } else {
      await _prefs.setString(_activeKey, id);
    }
  }
}
