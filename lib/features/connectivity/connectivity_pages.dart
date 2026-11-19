import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/util/format.dart';
import '../../core/valetudo/capabilities.dart';
import '../../core/valetudo/json_utils.dart';
import '../../core/valetudo/models/models.dart';
import '../../state/app_state.dart';
import '../../state/commands.dart';
import '../../state/data.dart';
import '../../state/session.dart';
import '../../state/toasts.dart';
import '../../ui/dialogs.dart';
import '../../ui/markdown.dart';
import '../../ui/theme.dart';
import '../../ui/widgets.dart';
import '../navigation.dart';
import '../cleanup/wifi_coverage_page.dart';

String extractHostFromUrl(String v) => v
    .replaceFirst(RegExp(r'^[a-zA-Z]+://'), '')
    .replaceAll(RegExp(r'/.*'), '')
    .trim();

/// Hint card used for Valetudo's explanatory notes.
class InfoNote extends StatelessWidget {
  const InfoNote(
    this.markdown, {
    super.key,
    this.icon = Icons.campaign_rounded,
  });

  final String markdown;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.colors.info.withValues(
          alpha: context.isDark ? 0.10 : 0.07,
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: context.colors.info.withValues(alpha: 0.2)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: context.colors.info),
          const SizedBox(width: 12),
          Expanded(child: MarkdownText(markdown)),
        ],
      ),
    );
  }
}

class SaveBar extends StatelessWidget {
  const SaveBar({
    super.key,
    required this.enabled,
    required this.saving,
    required this.onSave,
    this.label = 'Save configuration',
  });

  final bool enabled;
  final bool saving;
  final VoidCallback onSave;
  final String label;

  @override
  Widget build(BuildContext context) {
    return AnimatedSlide(
      offset: enabled || saving ? Offset.zero : const Offset(0, 2),
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOutCubic,
      child: AnimatedOpacity(
        opacity: enabled || saving ? 1 : 0,
        duration: const Duration(milliseconds: 250),
        child: FilledButton.icon(
          onPressed: enabled && !saving ? onSave : null,
          icon: saving
              ? const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Icon(Icons.save_rounded),
          label: Text(label),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Overview
// ---------------------------------------------------------------------------

class ConnectivityPage extends ConsumerWidget {
  const ConnectivityPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final caps = ref.watch(capsProvider);
    return ValrovePage(
      title: 'Connectivity',
      subtitle: 'Configure how Valetudo and your robot communicate with the outside world',
      children: [
        if (caps.has(Cap.wifiConfiguration)) ...[
          TileGroup(
            children: [
              NavTile(
                title: 'Wi-Fi',
                subtitle:
                    'Check connection details and modify the configuration',
                icon: Icons.wifi_rounded,
                onTap: () => openWifi(context),
              ),
            ],
          ),
          const SizedBox(height: 14),
        ],
        TileGroup(
          children: [
            NavTile(
              title: 'MQTT',
              subtitle: 'Connect Valetudo to your MQTT Broker',
              icon: Icons.hub_rounded,
              iconColor: const Color(0xFF8B5CF6),
              onTap: () => openMqtt(context),
            ),
            NavTile(
              title: 'NTP',
              subtitle:
                  'Configure the integrated Network Time Protocol (NTP) client',
              icon: Icons.access_time_rounded,
              iconColor: const Color(0xFF2DD4BF),
              onTap: () => openNtp(context),
            ),
            NavTile(
              title: 'Network advertisement',
              subtitle: 'Control Bonjour/mDNS and SSDP/UPnP discoverability',
              icon: Icons.auto_fix_high_rounded,
              iconColor: const Color(0xFFF59E0B),
              onTap: () => openNetworkAdvertisement(context),
            ),
            NavTile(
              title: 'Access control',
              subtitle: 'Restrict access to Valetudo with HTTP Basic Auth',
              icon: Icons.vpn_key_rounded,
              iconColor: const Color(0xFFEF4444),
              onTap: () => openAuth(context),
            ),
          ],
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Wi-Fi
// ---------------------------------------------------------------------------

IconData wifiIcon(String state, double? signal) {
  if (state == 'not_connected') return Icons.signal_wifi_off_rounded;
  if (state != 'connected') return Icons.wifi_rounded;
  if (signal == null || signal >= -55) return Icons.signal_wifi_4_bar_rounded;
  if (signal >= -66) return Icons.network_wifi_3_bar_rounded;
  if (signal >= -77) return Icons.network_wifi_2_bar_rounded;
  if (signal >= -88) return Icons.network_wifi_1_bar_rounded;
  return Icons.signal_wifi_0_bar_rounded;
}

const _wifiResetHint = '''To connect your robot to a different Wi-Fi network, you need to do a Wi-Fi reset and then configure the new one using Valetudo. For most Xiaomi-ecosystem-style robots, this means pressing and holding the two outer buttons (usually "Home" and "Spot Clean" or "Home" and "Power" if there are just two) until the robot talks to you.

Some supported robots may have dedicated connectivity buttons you need to press and hold. If it is anything more special than that, you will find guidance for your model of robot on the "Supported Robots" page in the docs on [valetudo.cloud](https://valetudo.cloud).
The robot may also have come with a manual by the vendor, which might contain guidance.

**Note:** Don't be confused by buttons labelled "Reset" close to a Wi-Fi LED. Proximity does not mean that they're related. Instead, they usually factory-reset the machine, which is not what you want.''';

class WifiPage extends ConsumerStatefulWidget {
  const WifiPage({super.key});

  @override
  ConsumerState<WifiPage> createState() => _WifiPageState();
}

class _WifiPageState extends ConsumerState<WifiPage> {
  final _ssid = TextEditingController();
  final _psk = TextEditingController();
  bool _obscure = true;
  bool _saving = false;

  @override
  void dispose() {
    _ssid.dispose();
    _psk.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final ok = await showConfirm(
      context,
      title: 'Apply new Wi-Fi configuration?',
      message: 'Are you sure you want to apply the new Wi-Fi settings?\n\nHint: you can always revert back to the integrated Wi-Fi hotspot. Check the documentation supplied with your robot for instructions on how to do so.',
      confirmLabel: 'Apply',
    );
    if (!ok || !mounted) return;
    setState(() => _saving = true);
    final sent = await ref
        .read(commandsProvider)
        .run(
          'apply the Wi-Fi configuration',
          (c) => c.setWifiConfiguration(ssid: _ssid.text, password: _psk.text),
          invalidate: [wifiStatusProvider],
        );
    if (!mounted) return;
    setState(() => _saving = false);
    if (sent) {
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          title: const Text('New Wi-Fi configuration is applying'),
          content: const Text(
            'The robot will now try to join the new network. Its address will most likely change — once it is online again, update the address of this robot in Valrove.',
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('OK'),
            ),
          ],
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final status = ref.watch(wifiStatusProvider);
    final reconfig = ref.watch(wifiReconfigurationSupportedProvider);
    final c = context.colors;
    final canSave = _ssid.text.isNotEmpty && _psk.text.isNotEmpty;
    return ValrovePage(
      title: 'Wi-Fi',
      subtitle: 'Connection details and configuration',
      onRefresh: () async => ref.refresh(wifiStatusProvider.future),
      children: [
        status.when(
          data: (s) => ValroveCard(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                Icon(
                  wifiIcon(s.state, s.signal),
                  size: 56,
                  color: s.state == 'connected' ? c.success : c.textTertiary,
                ),
                const SizedBox(height: 10),
                Text(switch (s.state) {
                  'connected' => s.ssid ?? 'Unknown SSID',
                  'not_connected' => 'Not connected',
                  _ => 'Unknown',
                }, style: context.text.headlineSmall),
                if (s.state == 'connected') ...[
                  const SizedBox(height: 14),
                  if (s.signal != null)
                    InfoRow('Signal', '${s.signal!.round()} dBm'),
                  if (s.ips.isNotEmpty)
                    InfoRow('IP addresses', s.ips.join('\n'), mono: true),
                  if (s.frequency != null)
                    InfoRow(
                      'Band',
                      s.frequency == '5ghz' ? '5 GHz' : '2.4 GHz',
                    ),
                  if (s.upspeed != null)
                    InfoRow('Link speed', '${s.upspeed} Mbit/s'),
                ],
              ],
            ),
          ),
          loading: () => const SkeletonCard(rows: 2),
          error: (e, _) => ErrorState(
            message: 'Error loading Wi-Fi status',
            onRetry: () => ref.invalidate(wifiStatusProvider),
          ),
        ),
        const SizedBox(height: 12),
        TileGroup(
          children: [
            NavTile(
              title: 'Coverage map',
              subtitle:
                  'Signal strength around your home, measured while '
                  'the robot cleans',
              icon: Icons.wifi_find_rounded,
              onTap: () => openWifiCoverage(context),
            ),
          ],
        ),
        const SectionLabel('Change Wi-Fi configuration'),
        if (reconfig.value == true)
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
                  onPressed: canSave && !_saving ? _save : null,
                  child: _saving
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text('Save configuration'),
                ),
              ],
            ),
          )
        else if (reconfig.hasValue)
          const InfoNote(_wifiResetHint)
        else if (reconfig.isLoading)
          const SkeletonCard(rows: 1),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// MQTT
// ---------------------------------------------------------------------------

Json _deepCopy(Json json) => asJson(jsonDecode(jsonEncode(json)));

Object? _getIn(Json json, List<String> path) {
  Object? cur = json;
  for (final p in path) {
    if (cur is! Map) return null;
    cur = cur[p];
  }
  return cur;
}

void _setIn(Json json, List<String> path, Object? value) {
  var cur = json;
  for (final p in path.take(path.length - 1)) {
    final next = cur[p];
    if (next is Map<String, dynamic>) {
      cur = next;
    } else {
      final created = <String, dynamic>{};
      cur[p] = created;
      cur = created;
    }
  }
  cur[path.last] = value;
}

class MqttPage extends ConsumerStatefulWidget {
  const MqttPage({super.key});

  @override
  ConsumerState<MqttPage> createState() => _MqttPageState();
}

class _MqttPageState extends ConsumerState<MqttPage> {
  Json? _edit;
  Json? _source;
  bool _modified = false;
  bool _saving = false;
  bool _showPassword = false;

  void _set(List<String> path, Object? value) {
    setState(() {
      _setIn(_edit!, path, value);
      _modified = true;
    });
  }

  Future<void> _save() async {
    final edit = _deepCopy(_edit!);
    var prefix = asString(_getIn(edit, ['customizations', 'topicPrefix']));
    if (prefix.startsWith('/')) prefix = prefix.substring(1);
    if (prefix.endsWith('/')) prefix = prefix.substring(0, prefix.length - 1);
    _setIn(edit, ['customizations', 'topicPrefix'], prefix);
    setState(() => _saving = true);
    final ok = await ref
        .read(commandsProvider)
        .run(
          'update MQTT settings',
          (c) => c.setMqttConfiguration(edit),
          invalidate: [mqttConfigProvider, mqttStatusProvider],
          success: 'MQTT configuration saved',
        );
    if (!mounted) return;
    setState(() {
      _saving = false;
      _modified = false;
      if (!ok) _source = null; // revert to the last server state
    });
  }

  @override
  Widget build(BuildContext context) {
    final config = ref.watch(mqttConfigProvider);
    final props = ref.watch(mqttPropertiesProvider);
    final status = ref.watch(mqttStatusProvider);
    final server = config.value;
    if (server != null &&
        (!identical(server, _source)) &&
        !_modified &&
        !_saving) {
      _source = server;
      _edit = _deepCopy(server);
    }

    if (config.hasError || props.hasError) {
      return ValrovePage(
        title: 'MQTT',
        children: [
          ErrorState(
            message: 'Error loading MQTT configuration',
            onRetry: () {
              ref.invalidate(mqttConfigProvider);
              ref.invalidate(mqttPropertiesProvider);
            },
          ),
        ],
      );
    }
    final edit = _edit;
    final p = props.value;
    if (edit == null || p == null) {
      return const ValrovePage(
        title: 'MQTT',
        children: [
          SkeletonCard(rows: 2),
          SizedBox(height: 12),
          SkeletonCard(rows: 5),
        ],
      );
    }

    bool b(List<String> path) => asBool(_getIn(edit, path));
    String s(List<String> path) => asString(_getIn(edit, path));
    final defaults = asJson(p['defaults']);
    final defaultPrefix = asString(
      asJson(defaults['customizations'])['topicPrefix'],
      'valetudo',
    );
    final defaultIdentifier = asString(
      asJson(defaults['identity'])['identifier'],
    );
    final exposable = asStringList(p['optionalExposableCapabilities']);
    final exposed = asStringList(edit['optionalExposedCapabilities']);
    var prefixPreview = s(['customizations', 'topicPrefix'])
        .replaceAll(RegExp(r'^/|/$'), '');
    if (prefixPreview.isEmpty) prefixPreview = defaultPrefix;
    var idPreview = s(['identity', 'identifier']);
    if (idPreview.isEmpty) idPreview = defaultIdentifier;

    return ValrovePage(
      title: 'MQTT',
      subtitle: 'Connect Valetudo to your MQTT broker',
      floating: SaveBar(enabled: _modified, saving: _saving, onSave: _save),
      children: [
        _MqttStatusCard(status: status),
        const SizedBox(height: 14),
        ValroveCard(
          child: ToggleTile(
            title: 'MQTT enabled',
            icon: Icons.power_settings_new_rounded,
            value: b(['enabled']),
            onChanged: (v) => _set(['enabled'], v),
          ),
        ),
        const SectionLabel('Connection'),
        ValroveCard(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              _Field(
                label: 'Host',
                helper: 'The MQTT Broker hostname',
                value: s(['connection', 'host']),
                required: true,
                onChanged: (v) =>
                    _set(['connection', 'host'], extractHostFromUrl(v)),
              ),
              const SizedBox(height: 12),
              _Field(
                label: 'Port',
                helper: 'The MQTT Broker port',
                value:
                    asIntOrNull(_getIn(edit, ['connection', 'port']))
                        ?.toString() ??
                    '',
                required: true,
                keyboardType: TextInputType.number,
                onChanged: (v) => _set(['connection', 'port'], int.tryParse(v)),
              ),
            ],
          ),
        ),
        _Group(
          title: 'TLS',
          enabled: b(['connection', 'tls', 'enabled']),
          onToggle: (v) => _set(['connection', 'tls', 'enabled'], v),
          children: [
            _Field(
              label: 'CA',
              helper: 'The optional Certificate Authority to verify the connection with',
              value: s(['connection', 'tls', 'ca']),
              multiline: true,
              onChanged: (v) => _set(['connection', 'tls', 'ca'], v),
            ),
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              title: Text(
                'Ignore certificate errors',
                style: context.text.titleSmall,
              ),
              value: b(['connection', 'tls', 'ignoreCertificateErrors']),
              onChanged: (v) =>
                  _set(['connection', 'tls', 'ignoreCertificateErrors'], v),
            ),
          ],
        ),
        _Group(
          title: 'Credentials',
          enabled: b([
            'connection',
            'authentication',
            'credentials',
            'enabled',
          ]),
          onToggle: (v) => _set([
            'connection',
            'authentication',
            'credentials',
            'enabled',
          ], v),
          children: [
            _Field(
              label: 'Username',
              helper: 'Username for authentication',
              value: s([
                'connection',
                'authentication',
                'credentials',
                'username',
              ]),
              required: true,
              onChanged: (v) => _set([
                'connection',
                'authentication',
                'credentials',
                'username',
              ], v),
            ),
            const SizedBox(height: 12),
            _Field(
              label: 'Password',
              helper: 'Password for authentication',
              value: s([
                'connection',
                'authentication',
                'credentials',
                'password',
              ]),
              obscure: !_showPassword,
              suffix: IconButton(
                icon: Icon(
                  _showPassword
                      ? Icons.visibility_off_rounded
                      : Icons.visibility_rounded,
                ),
                onPressed: () => setState(() => _showPassword = !_showPassword),
              ),
              onChanged: (v) => _set([
                'connection',
                'authentication',
                'credentials',
                'password',
              ], v),
            ),
          ],
        ),
        _Group(
          title: 'Client certificate',
          enabled: b([
            'connection',
            'authentication',
            'clientCertificate',
            'enabled',
          ]),
          onToggle: (v) => _set([
            'connection',
            'authentication',
            'clientCertificate',
            'enabled',
          ], v),
          children: [
            _Field(
              label: 'Certificate',
              helper: 'The full certificate as a multi-line string',
              value: s([
                'connection',
                'authentication',
                'clientCertificate',
                'certificate',
              ]),
              required: true,
              multiline: true,
              onChanged: (v) => _set([
                'connection',
                'authentication',
                'clientCertificate',
                'certificate',
              ], v),
            ),
            const SizedBox(height: 12),
            _Field(
              label: 'Key',
              helper: 'The full key as a multi-line string',
              value: s([
                'connection',
                'authentication',
                'clientCertificate',
                'key',
              ]),
              required: true,
              multiline: true,
              onChanged: (v) => _set([
                'connection',
                'authentication',
                'clientCertificate',
                'key',
              ], v),
            ),
          ],
        ),
        const SectionLabel('Customizations'),
        ValroveCard(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _Field(
                label: 'Topic prefix',
                helper: 'MQTT topic prefix',
                hint: defaultPrefix,
                value: s(['customizations', 'topicPrefix']),
                onChanged: (v) => _set(
                  ['customizations', 'topicPrefix'],
                  v
                      .replaceAll(RegExp(r'[^a-zA-Z0-9_\-/]'), '')
                      .replaceAll('//', '/'),
                ),
              ),
              const SizedBox(height: 12),
              _Field(
                label: 'Identifier',
                helper: 'The machine-readable name of the robot',
                hint: defaultIdentifier,
                value: s(['identity', 'identifier']),
                onChanged: (v) => _set([
                  'identity',
                  'identifier',
                ], v.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '')),
              ),
              const SizedBox(height: 16),
              Text(
                'The MQTT topic structure will look like this:',
                style: context.text.bodySmall,
              ),
              const SizedBox(height: 6),
              SelectableText.rich(
                TextSpan(
                  style: const TextStyle(
                    fontFamily: AppTheme.monoFamily,
                    fontSize: 13,
                  ),
                  children: [
                    TextSpan(
                      text: prefixPreview,
                      style: TextStyle(color: context.colors.warning),
                    ),
                    TextSpan(
                      text: '/',
                      style: TextStyle(color: context.colors.textSecondary),
                    ),
                    TextSpan(
                      text: idPreview,
                      style: TextStyle(color: context.scheme.primary),
                    ),
                    TextSpan(
                      text: '/BatteryStateAttribute/level',
                      style: TextStyle(color: context.colors.textSecondary),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        if (exposable.isNotEmpty) ...[
          const SectionLabel('Optionally exposable capabilities'),
          TileGroup(
            children: [
              for (final cap in exposable)
                CheckboxListTile(
                  value: exposed.contains(cap),
                  title: Text(
                    cap.replaceAll('Capability', ''),
                    style: context.text.titleSmall,
                  ),
                  subtitle: Text(cap, style: context.text.bodySmall),
                  onChanged: (v) {
                    final next = [...exposed];
                    if (v == true) {
                      if (!next.contains(cap)) next.add(cap);
                    } else {
                      next.remove(cap);
                    }
                    _set(['optionalExposedCapabilities'], next);
                  },
                ),
            ],
          ),
        ],
        const SizedBox(height: 18),
        const InfoNote(
          "Valetudo is developed against and tested with the Mosquitto MQTT broker.\n"
          "In an ideal world, any broker would work, but in reality, some only implement subsets of the MQTT spec. Thus, if you're experiencing any issues, try Mosquitto.\n\n"
          'Another common issue are incorrectly configured ACLs. Because the MQTT v3 protocol does not provide feedback on ACL failures, Valetudo cannot report these, meaning that things fail silently.',
        ),
      ],
    );
  }
}

class _MqttStatusCard extends StatelessWidget {
  const _MqttStatusCard({required this.status});

  final AsyncValue<MqttStatus> status;

  @override
  Widget build(BuildContext context) {
    final s = status.value;
    if (s == null) {
      return status.hasError
          ? InlineError('Error loading MQTT status')
          : const SkeletonCard(rows: 1);
    }
    final c = context.colors;
    final (icon, label, color) = switch (s.state) {
      'ready' => (Icons.link_rounded, 'Connected', c.success),
      'init' => (Icons.sync_rounded, 'Connecting / reconfiguring', c.info),
      'lost' ||
      'alert' => (Icons.warning_rounded, 'Connection error', c.danger),
      _ => (Icons.link_off_rounded, 'Disconnected', c.textTertiary),
    };
    return ValroveCard(
      padding: const EdgeInsets.all(18),
      child: Column(
        children: [
          Row(
            children: [
              TileIcon(icon, color: color, size: 44),
              const SizedBox(width: 14),
              Text(label, style: context.text.titleLarge),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('MESSAGES', style: context.text.labelSmall),
                    const SizedBox(height: 6),
                    Text(
                      'Sent ${s.messagesSent} · ${bytesToHuman(s.bytesSent)}',
                      style: context.text.bodySmall,
                    ),
                    Text(
                      'Received ${s.messagesReceived} · ${bytesToHuman(s.bytesReceived)}',
                      style: context.text.bodySmall,
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('CONNECTION', style: context.text.labelSmall),
                    const SizedBox(height: 6),
                    Text(
                      'Connects ${s.connects} · Disconnects ${s.disconnects}',
                      style: context.text.bodySmall,
                    ),
                    Text(
                      'Reconnects ${s.reconnects} · Errors ${s.errors}',
                      style: context.text.bodySmall,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Group extends StatelessWidget {
  const _Group({
    required this.title,
    required this.enabled,
    required this.onToggle,
    required this.children,
  });

  final String title;
  final bool enabled;
  final ValueChanged<bool> onToggle;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: ValroveCard(
        child: Column(
          children: [
            SwitchListTile.adaptive(
              contentPadding: const EdgeInsets.symmetric(horizontal: 16),
              title: Text(title, style: context.text.titleSmall),
              value: enabled,
              onChanged: onToggle,
            ),
            AnimatedSize(
              duration: const Duration(milliseconds: 260),
              curve: Curves.easeOutCubic,
              child: enabled
                  ? Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                      child: Column(children: children),
                    )
                  : const SizedBox(width: double.infinity),
            ),
          ],
        ),
      ),
    );
  }
}

/// Text field that keeps its own controller in sync with an external value.
class _Field extends StatefulWidget {
  const _Field({
    required this.label,
    this.helper,
    this.hint,
    required this.value,
    required this.onChanged,
    this.required = false,
    this.multiline = false,
    this.obscure = false,
    this.keyboardType,
    this.suffix,
  });

  final String label;
  final String? helper;
  final String? hint;
  final String value;
  final ValueChanged<String> onChanged;
  final bool required;
  final bool multiline;
  final bool obscure;
  final TextInputType? keyboardType;
  final Widget? suffix;

  @override
  State<_Field> createState() => _FieldState();
}

class _FieldState extends State<_Field> {
  late final TextEditingController _c = TextEditingController(
    text: widget.value,
  );

  @override
  void didUpdateWidget(_Field old) {
    super.didUpdateWidget(old);
    if (widget.value != _c.text) {
      _c.value = TextEditingValue(
        text: widget.value,
        selection: TextSelection.collapsed(offset: widget.value.length),
      );
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _c,
      obscureText: widget.obscure,
      keyboardType: widget.multiline
          ? TextInputType.multiline
          : widget.keyboardType,
      minLines: widget.multiline ? 3 : 1,
      maxLines: widget.multiline ? 10 : 1,
      style: widget.multiline
          ? const TextStyle(fontFamily: AppTheme.monoFamily, fontSize: 12.5)
          : null,
      onChanged: widget.onChanged,
      decoration: InputDecoration(
        labelText: widget.required ? '${widget.label} *' : widget.label,
        helperText: widget.helper,
        hintText: widget.hint,
        errorText: widget.required && widget.value.isEmpty ? 'Required' : null,
        suffixIcon: widget.suffix,
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// NTP
// ---------------------------------------------------------------------------

class NtpPage extends ConsumerStatefulWidget {
  const NtpPage({super.key});

  @override
  ConsumerState<NtpPage> createState() => _NtpPageState();
}

class _NtpPageState extends ConsumerState<NtpPage> {
  Json? _edit;
  Json? _source;
  bool _modified = false;
  bool _saving = false;

  void _set(String key, Object? value) => setState(() {
    _edit![key] = value;
    _modified = true;
  });

  @override
  Widget build(BuildContext context) {
    final status = ref.watch(ntpStatusProvider);
    final config = ref.watch(ntpConfigProvider);
    final server = config.value;
    if (server != null && !identical(server, _source) && !_modified) {
      _source = server;
      _edit = Map.of(server);
    }
    final edit = _edit;
    final c = context.colors;
    return ValrovePage(
      title: 'NTP',
      subtitle: 'Network time synchronization',
      onRefresh: () async => ref.refresh(ntpStatusProvider.future),
      floating: SaveBar(
        enabled: _modified,
        saving: _saving,
        onSave: () async {
          setState(() {
            _saving = true;
            _modified = false;
          });
          await ref
              .read(commandsProvider)
              .run(
                'update NTP settings',
                (cl) => cl.setNtpConfiguration(edit!),
                invalidate: [ntpConfigProvider, ntpStatusProvider],
                success: 'NTP configuration saved',
              );
          if (mounted) setState(() => _saving = false);
        },
      ),
      children: [
        status.when(
          skipLoadingOnRefresh: true,
          data: (s) {
            final (icon, title, detail, color) = switch (s.stateClass) {
              'ValetudoNTPClientEnabledState' => (
                Icons.sync_rounded,
                'Time sync enabled',
                null,
                c.info,
              ),
              'ValetudoNTPClientDisabledState' => (
                Icons.sync_disabled_rounded,
                'Time sync disabled',
                null,
                c.textTertiary,
              ),
              'ValetudoNTPClientSyncedState' => (
                Icons.sync_lock_rounded,
                'Time sync successful',
                'Offset: ${s.offset?.round() ?? 0} ms',
                c.success,
              ),
              'ValetudoNTPClientErrorState' => (
                Icons.sync_problem_rounded,
                'Error: ${s.errorType ?? 'unknown'}',
                s.message,
                c.danger,
              ),
              _ => (
                Icons.help_rounded,
                humanize(s.stateClass),
                null,
                c.textTertiary,
              ),
            };
            return ValroveCard(
              padding: const EdgeInsets.all(18),
              child: Row(
                children: [
                  TileIcon(icon, color: color, size: 48),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: context.text.titleLarge?.copyWith(
                            color: s.stateClass.contains('Error')
                                ? c.danger
                                : null,
                          ),
                        ),
                        if (detail != null)
                          Text(detail, style: context.text.bodyMedium),
                        const SizedBox(height: 4),
                        Text(
                          'Robot time: ${s.robotTime == null ? '?' : dateTime(s.robotTime!)}',
                          style: context.text.bodySmall,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
          loading: () => const SkeletonCard(rows: 1),
          error: (e, _) => InlineError(
            'Error loading NTP client status',
            onRetry: () => ref.invalidate(ntpStatusProvider),
          ),
        ),
        const SizedBox(height: 14),
        if (edit == null)
          config.hasError
              ? InlineError('Error loading NTP client configuration')
              : const SkeletonCard(rows: 3)
        else ...[
          ValroveCard(
            child: ToggleTile(
              title: 'NTP enabled',
              icon: Icons.access_time_rounded,
              value: asBool(edit['enabled']),
              onChanged: (v) => _set('enabled', v),
            ),
          ),
          const SizedBox(height: 12),
          ValroveCard(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                _Field(
                  label: 'Server',
                  value: asString(edit['server']),
                  onChanged: (v) => _set('server', extractHostFromUrl(v)),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: _Field(
                        label: 'Port',
                        value: asIntOrNull(edit['port'])?.toString() ?? '',
                        keyboardType: TextInputType.number,
                        onChanged: (v) => _set('port', int.tryParse(v)),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _Field(
                        label: 'Interval (hours)',
                        value: asNumOrNull(edit['interval']) == null
                            ? ''
                            : (asDouble(edit['interval']) / 3600000)
                                  .round()
                                  .toString(),
                        keyboardType: TextInputType.number,
                        onChanged: (v) => _set(
                          'interval',
                          int.tryParse(v) == null
                              ? null
                              : int.parse(v) * 3600000,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _Field(
                        label: 'Timeout (s)',
                        value: asNumOrNull(edit['timeout']) == null
                            ? ''
                            : (asDouble(edit['timeout']) / 1000)
                                  .round()
                                  .toString(),
                        keyboardType: TextInputType.number,
                        onChanged: (v) => _set(
                          'timeout',
                          int.tryParse(v) == null ? null : int.parse(v) * 1000,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 18),
        const InfoNote(
          'Valetudo needs a synchronized clock for timers to work and the log timestamps to make sense. Additionally, anything using TLS (e.g. the inbuilt Updater) also requires the correct current time to work.',
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// HTTP Basic Auth
// ---------------------------------------------------------------------------

class AuthPage extends ConsumerStatefulWidget {
  const AuthPage({super.key});

  @override
  ConsumerState<AuthPage> createState() => _AuthPageState();
}

class _AuthPageState extends ConsumerState<AuthPage> {
  Json? _source;
  bool _enabled = false;
  final _user = TextEditingController();
  final _password = TextEditingController();
  bool _obscure = true;
  bool _modified = false;
  bool _saving = false;

  @override
  void dispose() {
    _user.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_enabled && _password.text.isEmpty) {
      ref
          .read(toastProvider)
          .error(
            'Password required',
            detail: 'Enter a password to enable HTTP Basic Auth.',
          );
      return;
    }
    setState(() {
      _saving = true;
      _modified = false;
    });
    final username = _user.text;
    final password = _password.text;
    final enabled = _enabled;
    final ok = await ref
        .read(commandsProvider)
        .run(
          'update the access settings',
          (c) => c.setHttpBasicAuth(
            enabled: enabled,
            username: username,
            password: password,
          ),
          success: 'Access settings saved',
        );
    if (ok) {
      // Keep this app signed in with the new credentials.
      final profile = ref.read(activeProfileProvider);
      if (profile != null) {
        await ref
            .read(robotsProvider.notifier)
            .upsert(
              enabled
                  ? profile.copyWith(username: username, password: password)
                  : profile.copyWith(clearCredentials: true),
            );
      }
      ref.invalidate(httpAuthProvider);
      _password.clear();
    }
    if (mounted) setState(() => _saving = false);
  }

  @override
  Widget build(BuildContext context) {
    final config = ref.watch(httpAuthProvider);
    final server = config.value;
    if (server != null && !identical(server, _source) && !_modified) {
      _source = server;
      _enabled = asBool(server['enabled']);
      _user.text = asString(server['username']);
    }
    return ValrovePage(
      title: 'Access control',
      subtitle: 'HTTP Basic Auth',
      floating: SaveBar(enabled: _modified, saving: _saving, onSave: _save),
      children: [
        if (server == null)
          config.hasError
              ? InlineError('Error loading HTTP Basic Auth configuration')
              : const SkeletonCard(rows: 2)
        else ...[
          ValroveCard(
            child: ToggleTile(
              title: 'HTTP Basic Auth enabled',
              subtitle: 'Require a username and password to use Valetudo',
              icon: Icons.vpn_key_rounded,
              value: _enabled,
              onChanged: (v) => setState(() {
                _enabled = v;
                _modified = true;
              }),
            ),
          ),
          const SizedBox(height: 12),
          ValroveCard(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                TextField(
                  controller: _user,
                  enabled: _enabled,
                  onChanged: (_) => setState(() => _modified = true),
                  decoration: const InputDecoration(
                    labelText: 'Username',
                    prefixIcon: Icon(Icons.person_rounded),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _password,
                  enabled: _enabled,
                  obscureText: _obscure,
                  onChanged: (_) => setState(() => _modified = true),
                  decoration: InputDecoration(
                    labelText: 'Password',
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
              ],
            ),
          ),
        ],
        const SizedBox(height: 18),
        const InfoNote(
          'Valetudo will by default try to block access from public-routable IP addresses for your safety and convenience.\n'
          'If you want to allow external access to your Valetudo instance, consider using a VPN such as WireGuard or OpenVPN to ensure the safety of your network.\n\n'
          "If you don't want to use a VPN, usage of a reverse proxy in front of Valetudo and all of your other IoT and network services (e.g. Home Assistant, Jellyfin) is strongly recommended. "
          'A proper Webserver (e.g. nginx, Apache) is engineered and hardened to be public-facing. Additionally, a setup like that provides you with central access logs and the ability to implement a central auth.',
          icon: Icons.shield_rounded,
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Network advertisement
// ---------------------------------------------------------------------------

class NetworkAdvertisementPage extends ConsumerStatefulWidget {
  const NetworkAdvertisementPage({super.key});

  @override
  ConsumerState<NetworkAdvertisementPage> createState() =>
      _NetworkAdvertisementPageState();
}

class _NetworkAdvertisementPageState
    extends ConsumerState<NetworkAdvertisementPage> {
  bool? _enabled;
  bool _saving = false;

  @override
  Widget build(BuildContext context) {
    final enabled = ref.watch(networkAdvertisementProvider);
    final props = ref.watch(networkAdvertisementPropertiesProvider);
    final current = _enabled ?? enabled.value;
    final modified = _enabled != null && _enabled != enabled.value;
    return ValrovePage(
      title: 'Network advertisement',
      subtitle: 'Bonjour/mDNS and SSDP/UPnP discoverability',
      floating: SaveBar(
        enabled: modified,
        saving: _saving,
        onSave: () async {
          setState(() => _saving = true);
          await ref
              .read(commandsProvider)
              .run(
                'update network advertisement',
                (c) => c.setNetworkAdvertisementEnabled(_enabled!),
                invalidate: [networkAdvertisementProvider],
                success: 'Network advertisement saved',
              );
          if (mounted) {
            setState(() {
              _saving = false;
              _enabled = null;
            });
          }
        },
      ),
      children: [
        if (enabled.hasError || props.hasError)
          InlineError('Error loading Network Advertisement configuration')
        else if (current == null)
          const SkeletonCard(rows: 2)
        else
          TileGroup(
            children: [
              ToggleTile(
                title: 'Network advertisement enabled',
                icon: Icons.auto_fix_high_rounded,
                value: current,
                onChanged: (v) => setState(() => _enabled = v),
              ),
              InfoRow(
                'Zeroconf hostname',
                asString(props.value?['zeroconfHostname'], '…'),
                mono: true,
              ),
            ],
          ),
        const SizedBox(height: 18),
        const InfoNote(
          'To allow quick autodiscovery by companion apps (like this one), Valetudo advertises its presence on your local network using mDNS/Bonjour and SSDP/UPnP. It is not recommended to disable this feature, as it will break those companion apps.\n\n'
          "One common pitfall of these \"it just works\" technologies is that they're incredibly hard to debug the moment they don't anymore. They're using Multicast broadcasts, which, by-default, cannot traverse subnet boundaries.\n"
          'They are, however, optional, as you just need to know the IP of the robot to talk with Valetudo.',
        ),
      ],
    );
  }
}
