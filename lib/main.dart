import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app.dart';
import 'core/licenses.dart';
import 'core/persistence/stores.dart';
import 'core/valetudo/client/transport.dart';
import 'features/assistant/assistant_entry.dart';
import 'features/cleanup/cleanup_service.dart';
import 'state/app_state.dart';

/// Entry points started by Android without the app's screen; listed here so
/// release builds keep them.
const backgroundEntryPoints = [assistantMain, startCleanupTask];

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  CleanupService.initCommunication();
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  registerLicenses();

  final prefs = await SharedPreferences.getInstance();
  final secrets = SecureSecretStore();
  final profiles = await ProfileRepository(prefs, secrets).load();

  runApp(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        secretStoreProvider.overrideWithValue(secrets),
        initialProfilesProvider.overrideWithValue(profiles),
      ],
      // Retry only transient network failures; API errors (e.g. a missing
      // capability) and authentication failures will not fix themselves.
      retry: (count, error) {
        if (error is ValetudoConnectionException && count < 6) {
          return Duration(milliseconds: 800 * (1 << count));
        }
        return null;
      },
      child: const ValroveApp(),
    ),
  );
}
