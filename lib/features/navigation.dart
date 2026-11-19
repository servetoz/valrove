import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../core/valetudo/capabilities.dart';
import '../map/map_controller.dart';
import '../state/app_state.dart';
import 'camera/camera_page.dart';
import 'connectivity/connectivity_pages.dart';
import 'map/coverage_page.dart';
import 'map/map_editor_page.dart';
import 'map/map_management_page.dart';
import 'robot/consumables_page.dart';
import 'robot/manual_control_page.dart';
import 'robot/quirks_page.dart';
import 'robot/robot_options_page.dart';
import 'robot/sound_page.dart';
import 'robot/statistics_page.dart';
import 'robots/robots_sheet.dart';
import 'settings/app_settings_page.dart';
import 'settings/settings_hub.dart';
import 'system/about_page.dart';
import 'system/log_page.dart';
import 'system/system_info_page.dart';
import 'system/updater_page.dart';
import 'system/valetudo_options_page.dart';
import 'timers/timers_page.dart';

Future<T?> _push<T>(BuildContext context, Widget page) =>
    Navigator.of(context).push<T>(MaterialPageRoute(builder: (_) => page));

bool hasMapManagement(Capabilities caps) => caps.hasAny([
  Cap.persistentMapControl,
  Cap.mappingPass,
  Cap.mapReset,
  Cap.mapSegmentEdit,
  Cap.mapSegmentRename,
  Cap.combinedVirtualRestrictions,
  Cap.mapAnnotations,
  Cap.multipleMap,
]);

void openSettingsHub(BuildContext context) =>
    _push(context, const SettingsHubPage());
void openConsumables(BuildContext context) =>
    _push(context, const ConsumablesPage());
void openStatistics(BuildContext context) =>
    _push(context, const StatisticsPage());
void openManualControl(BuildContext context) =>
    _push(context, const ManualControlPage());
void openTimers(BuildContext context) => _push(context, const TimersPage());
void openMapManagement(BuildContext context) =>
    _push(context, const MapManagementPage());
void openMapEditor(BuildContext context, MapMode mode) =>
    _push(context, MapEditorPage(mode: mode));
void openCoverageMap(BuildContext context) =>
    _push(context, const CoverageMapPage());
void openCamera(BuildContext context) => _push(context, const CameraPage());
void openRobotOptions(BuildContext context) =>
    _push(context, const RobotOptionsPage());
void openSoundOptions(BuildContext context) =>
    _push(context, const SoundPage());
void openQuirks(BuildContext context) => _push(context, const QuirksPage());
void openConnectivity(BuildContext context) =>
    _push(context, const ConnectivityPage());
void openWifi(BuildContext context) => _push(context, const WifiPage());
void openMqtt(BuildContext context) => _push(context, const MqttPage());
void openNtp(BuildContext context) => _push(context, const NtpPage());
void openAuth(BuildContext context) => _push(context, const AuthPage());
void openNetworkAdvertisement(BuildContext context) =>
    _push(context, const NetworkAdvertisementPage());
void openUpdater(BuildContext context) => _push(context, const UpdaterPage());
void openLog(BuildContext context) => _push(context, const LogPage());
void openSystemInfo(BuildContext context) =>
    _push(context, const SystemInfoPage());
void openAbout(BuildContext context) => _push(context, const AboutPage());
void openHelp(BuildContext context) => _push(context, const HelpPage());
void openValetudoOptions(BuildContext context) =>
    _push(context, const ValetudoOptionsPage());
void openAppSettings(BuildContext context) =>
    _push(context, const AppSettingsPage());

/// Opens the connection settings of the active robot (e.g. to sign in).
void editActiveRobot(BuildContext context, WidgetRef ref) {
  final profile = ref.read(activeProfileProvider);
  if (profile != null) showEditRobotSheet(context, profile, authRequired: true);
}
