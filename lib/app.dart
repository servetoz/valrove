import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import 'core/valetudo/capabilities.dart';
import 'features/home/home_screen.dart';
import 'features/provisioning/provisioning_page.dart';
import 'features/robots/robot_setup.dart';
import 'state/app_state.dart';
import 'state/data.dart';
import 'state/session.dart';
import 'ui/theme.dart';
import 'ui/toast_host.dart';

class ValroveApp extends ConsumerWidget {
  const ValroveApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(settingsProvider.select((s) => s.themeMode));
    return MaterialApp(
      title: 'Valrove',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: switch (mode) {
        AppThemeMode.light => ThemeMode.light,
        AppThemeMode.dark => ThemeMode.dark,
        AppThemeMode.system => ThemeMode.system,
      },
      builder: (context, child) {
        final dark = Theme.of(context).brightness == Brightness.dark;
        return AnnotatedRegion<SystemUiOverlayStyle>(
          value: (dark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark)
              .copyWith(
                statusBarColor: Colors.transparent,
                systemNavigationBarColor: Colors.transparent,
                systemNavigationBarContrastEnforced: false,
              ),
          child: ToastHost(child: child ?? const SizedBox.shrink()),
        );
      },
      home: const RootGate(),
    );
  }
}

/// Chooses between onboarding, Wi-Fi provisioning and the main experience.
class RootGate extends ConsumerStatefulWidget {
  const RootGate({super.key});

  @override
  ConsumerState<RootGate> createState() => _RootGateState();
}

class _RootGateState extends ConsumerState<RootGate> {
  /// Robot ids for which the provisioning check has been resolved this session.
  final Set<String> _provisioningResolved = {};

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(activeProfileProvider);
    Widget child;
    if (profile == null) {
      child = const OnboardingScreen(key: ValueKey('onboarding'));
    } else if (_needsProvisioning(profile.id)) {
      child = ProvisioningPage(
        key: const ValueKey('provisioning'),
        onSkip: () => setState(() => _provisioningResolved.add(profile.id)),
      );
    } else {
      child = const HomeScreen(key: ValueKey('home'));
    }
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 450),
      switchInCurve: Curves.easeOutCubic,
      transitionBuilder: (child, anim) => FadeTransition(
        opacity: anim,
        child: ScaleTransition(
          scale: Tween(begin: 0.98, end: 1.0).animate(anim),
          child: child,
        ),
      ),
      child: child,
    );
  }

  /// Valetudo shows provisioning when it is embedded, supports Wi-Fi
  /// configuration and reports "not_connected" (robot in hotspot mode).
  bool _needsProvisioning(String id) {
    if (_provisioningResolved.contains(id)) return false;
    final caps = ref.watch(capabilitiesProvider).value;
    final info = ref.watch(valetudoInfoProvider).value;
    if (caps == null || info == null) return false;
    if (!caps.has(Cap.wifiConfiguration) || !info.embedded) {
      _provisioningResolved.add(id);
      return false;
    }
    final wifi = ref.watch(wifiStatusProvider).value;
    if (wifi == null) return false;
    if (wifi.state != 'not_connected') {
      _provisioningResolved.add(id);
      return false;
    }
    return true;
  }
}
