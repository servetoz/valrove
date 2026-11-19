import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart' show WidgetsFlutterBinding;
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/cleanup/robot_files.dart';
import '../../core/persistence/stores.dart';
import '../../state/cleanup.dart' show historyDirectory;
import '../cleanup/cleanup_service.dart';
import 'assistant_actions.dart';

/// The channel `AssistantBridge.kt` talks to.
const assistantChannel = MethodChannel('dev.valroveapp.valrove/assistant');

/// Started by `AssistantBridge.kt` in a Flutter engine without a screen when
/// an assistant calls one of Valrove's AppFunctions.
@pragma('vm:entry-point')
Future<void> assistantMain() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();
  final actions = AssistantActions(
    prefs: prefs,
    secrets: SecureSecretStore(),
    files: () async => RobotFiles(await historyDirectory()),
    onCleaningStarted: (robotId) async {
      // Follow the cleanup like the app does, when notifications are on.
      if (prefs.getBool('settings.cleanupNotifications') ?? true) {
        try {
          await CleanupService.start(robotId, askPermission: false);
        } catch (e) {
          debugPrint('Could not follow the cleanup: $e');
        }
      }
    },
  );
  assistantChannel.setMethodCallHandler(
    (call) => actions.handle(
      call.method,
      (call.arguments as Map<Object?, Object?>?) ?? const {},
    ),
  );
  await assistantChannel.invokeMethod<void>('ready');
}
