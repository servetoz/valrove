import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/valetudo/capabilities.dart';
import '../../core/valetudo/models/models.dart';
import '../../state/commands.dart';
import '../../state/session.dart';
import '../../ui/glass.dart';
import '../../ui/glyphs.dart';
import '../../ui/theme.dart';
import '../../ui/widgets.dart';
import '../connectivity/connectivity_pages.dart' show wifiIcon;

final _scanProvider = FutureProvider.autoDispose<List<WifiNetwork>>((
  ref,
) async {
  final networks = await requireClient(ref).scanWifi();
  final bySsid = <String, WifiNetwork>{};
  for (final n in networks) {
    if (n.ssid == null || n.ssid!.isEmpty) continue;
    bySsid[n.ssid!] = n;
  }
  return bySsid.values.toList()
    ..sort((a, b) => (b.signal ?? -999).compareTo(a.signal ?? -999));
});

/// Shown when the robot runs its own hotspot and is not on a Wi-Fi yet.
class ProvisioningPage extends ConsumerStatefulWidget {
  const ProvisioningPage({super.key, required this.onSkip});

  final VoidCallback onSkip;

  @override
  ConsumerState<ProvisioningPage> createState() => _ProvisioningPageState();
}

class _ProvisioningPageState extends ConsumerState<ProvisioningPage> {
  final _ssid = TextEditingController();
  final _psk = TextEditingController();
  bool _obscure = true;
  bool _applying = false;
  bool _applied = false;
  int _shown = 5;

  @override
  void dispose() {
    _ssid.dispose();
    _psk.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final caps = ref.watch(capsProvider);
    final robot = ref.watch(robotInfoProvider).value;
    final version = ref.watch(valetudoVersionProvider).value;
    final media = MediaQuery.of(context);
    return Scaffold(
      body: AmbientBackground(
        accent: context.scheme.primary,
        child: ListView(
          padding: EdgeInsets.fromLTRB(
            20,
            media.padding.top + 28,
            20,
            media.padding.bottom + 24,
          ),
          children: [
            const Center(child: RobotGlyph(size: 56)),
            const SizedBox(height: 18),
            Text(
              'Join your Wi-Fi',
              textAlign: TextAlign.center,
              style: context.text.headlineLarge,
            ),
            const SizedBox(height: 8),
            Text(
              'Please join the robot to your Wi-Fi network to start using Valetudo.',
              textAlign: TextAlign.center,
              style: context.text.bodyMedium,
            ),
            if (robot != null && version != null) ...[
              const SizedBox(height: 16),
              Text(
                '${robot.manufacturer} ${robot.modelName} · Valetudo ${version.release}',
                textAlign: TextAlign.center,
                style: context.text.labelMedium,
              ),
            ],
            const SizedBox(height: 24),
            if (_applied)
              const Glass(
                radius: 26,
                padding: EdgeInsets.all(20),
                child: Column(
                  children: [
                    Icon(Icons.wifi_rounded, size: 40),
                    SizedBox(height: 12),
                    Text(
                      'Wi-Fi configuration is applying',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 17,
                      ),
                    ),
                    SizedBox(height: 8),
                    Text(
                      "If you've entered your Wi-Fi credentials correctly, the robot should now join your network. "
                      'Reconnect your phone to your home Wi-Fi and add the robot again using its new address.',
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              )
            else ...[
              if (caps.has(Cap.wifiScan)) ...[
                const SectionLabel('Networks', icon: Icons.wifi_find_rounded),
                _scanList(context),
                const SizedBox(height: 16),
              ],
              ValroveCard(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextField(
                      controller: _ssid,
                      onChanged: (_) => setState(() {}),
                      decoration: const InputDecoration(
                        labelText: 'SSID / Wi-Fi name',
                        prefixIcon: Icon(Icons.wifi_rounded),
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: _psk,
                      obscureText: _obscure,
                      onChanged: (_) => setState(() {}),
                      decoration: InputDecoration(
                        labelText: 'PSK / Password',
                        prefixIcon: const Icon(Icons.key_rounded),
                        suffixIcon: IconButton(
                          icon: Icon(
                            _obscure
                                ? Icons.visibility_rounded
                                : Icons.visibility_off_rounded,
                          ),
                          onPressed: () => setState(() => _obscure = !_obscure),
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    FilledButton(
                      onPressed:
                          _ssid.text.isEmpty || _psk.text.isEmpty || _applying
                          ? null
                          : () async {
                              setState(() => _applying = true);
                              final ok = await ref
                                  .read(commandsProvider)
                                  .run(
                                    'apply the Wi-Fi configuration',
                                    (c) => c.setWifiConfiguration(
                                      ssid: _ssid.text,
                                      password: _psk.text,
                                    ),
                                  );
                              if (mounted) {
                                setState(() {
                                  _applying = false;
                                  _applied = ok;
                                });
                              }
                            },
                      child: _applying
                          ? const SizedBox.square(
                              dimension: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Text('Apply'),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 16),
            TextButton(
              onPressed: widget.onSkip,
              child: const Text('Continue to the robot anyway'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _scanList(BuildContext context) {
    final scan = ref.watch(_scanProvider);
    return ValroveCard(
      child: scan.when(
        data: (list) => Column(
          children: [
            if (list.isEmpty)
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  'No Wi-Fi networks found or background network scan still active',
                  style: context.text.bodyMedium,
                ),
              ),
            for (final n in list.take(_shown))
              ValroveTile(
                title: n.ssid!,
                subtitle: '${n.signal?.round() ?? 'unknown'} dBm',
                icon: wifiIcon('connected', n.signal),
                onTap: () => setState(() => _ssid.text = n.ssid!),
              ),
            if (list.length > _shown)
              TextButton(
                onPressed: () => setState(() => _shown += 5),
                child: const Text('See more results'),
              ),
            TextButton.icon(
              onPressed: () => ref.invalidate(_scanProvider),
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Scan again'),
            ),
          ],
        ),
        loading: () => const Padding(
          padding: EdgeInsets.all(20),
          child: Row(
            children: [
              SizedBox.square(
                dimension: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              SizedBox(width: 12),
              Text('Scanning…'),
            ],
          ),
        ),
        error: (e, _) => InlineError(
          'Scan failed',
          onRetry: () => ref.invalidate(_scanProvider),
        ),
      ),
    );
  }
}
