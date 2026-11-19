import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/discovery/robot_discovery.dart';
import '../../core/persistence/robot_profile.dart';
import '../../core/valetudo/client/valetudo_client.dart';
import '../../core/valetudo/models/models.dart';
import '../../state/app_state.dart';
import '../../state/commands.dart';
import '../../ui/glass.dart';
import '../../ui/glyphs.dart';
import '../../ui/theme.dart';
import '../../ui/widgets.dart';

/// What a successful connection test found.
class ProbeResult {
  const ProbeResult({
    required this.info,
    required this.version,
    this.friendlyName,
    this.systemId,
  });

  final RobotInformation info;
  final ValetudoVersion version;
  final String? friendlyName;
  final String? systemId;

  String get suggestedName =>
      (friendlyName != null && friendlyName!.trim().isNotEmpty)
      ? friendlyName!.trim()
      : '${info.manufacturer} ${info.modelName}';
}

/// Verifies that [endpoint] is a reachable Valetudo instance.
Future<ProbeResult> probeRobot(ValetudoEndpoint endpoint) async {
  final client = ValetudoClient.connect(endpoint);
  try {
    final RobotInformation info;
    final ValetudoVersion version;
    try {
      info = await client.getRobotInformation();
      version = await client.getValetudoVersion();
    } on ValetudoApiException {
      throw const NotValetudoException();
    } on FormatException {
      throw const NotValetudoException();
    }
    if (info.manufacturer == 'Unknown' && version.release == '?') {
      throw const NotValetudoException();
    }
    String? friendly;
    String? systemId;
    try {
      friendly = (await client.getCustomizations()).friendlyName;
      systemId = (await client.getValetudoInformation()).systemId;
    } catch (_) {}
    return ProbeResult(
      info: info,
      version: version,
      friendlyName: friendly,
      systemId: systemId,
    );
  } finally {
    client.close();
  }
}

/// Add or edit a robot connection.
class RobotSetupView extends ConsumerStatefulWidget {
  const RobotSetupView({
    super.key,
    this.existing,
    this.onDone,
    this.showDiscovery = true,
    this.initialAuthRequired = false,
  });

  final RobotProfile? existing;
  final ValueChanged<RobotProfile>? onDone;
  final bool showDiscovery;
  final bool initialAuthRequired;

  @override
  ConsumerState<RobotSetupView> createState() => _RobotSetupViewState();
}

class _RobotSetupViewState extends ConsumerState<RobotSetupView> {
  final _discovery = RobotDiscovery();
  late final TextEditingController _address = TextEditingController(
    text: _initialAddress(),
  );
  late final TextEditingController _user = TextEditingController(
    text: widget.existing?.username ?? '',
  );
  late final TextEditingController _password = TextEditingController(
    text: widget.existing?.password ?? '',
  );
  late bool _auth =
      widget.initialAuthRequired ||
      (widget.existing?.username?.isNotEmpty ?? false);
  bool _obscure = true;
  bool _testing = false;
  String? _error;
  List<DiscoveredRobot> _found = const [];

  String _initialAddress() {
    final url = widget.existing?.url;
    if (url == null) return '';
    final uri = Uri.parse(url);
    final port = uri.hasPort && uri.port != 80 && uri.port != 443
        ? ':${uri.port}'
        : '';
    final path = uri.path == '/' ? '' : uri.path;
    return '${uri.scheme == 'https' ? 'https://' : ''}${uri.host}$port$path';
  }

  @override
  void initState() {
    super.initState();
    if (widget.showDiscovery) {
      _discovery.robots.listen((robots) {
        if (mounted) setState(() => _found = robots);
      });
      _discovery.start();
    }
  }

  @override
  void dispose() {
    _discovery.dispose();
    _address.dispose();
    _user.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _connect({String? address}) async {
    final input = address ?? _address.text;
    final base = ValetudoEndpoint.tryParse(input);
    if (base == null) {
      setState(
        () => _error = 'Enter an IP address or hostname, e.g. 192.168.1.50',
      );
      return;
    }
    if (address != null) _address.text = input;
    setState(() {
      _testing = true;
      _error = null;
    });
    final endpoint = ValetudoEndpoint(
      baseUri: base,
      username: _auth ? _user.text : null,
      password: _auth ? _password.text : null,
    );
    try {
      final result = await probeRobot(endpoint);
      final existing = widget.existing;
      final profile = RobotProfile(
        id: existing?.id ?? RobotsNotifier.newId(),
        name: existing?.name ?? result.suggestedName,
        url: endpoint.baseUri.toString(),
        username: _auth && _user.text.isNotEmpty ? _user.text : null,
        password: _auth && _password.text.isNotEmpty ? _password.text : null,
        model: result.info.modelName,
        manufacturer: result.info.manufacturer,
        systemId: result.systemId,
        addedAt: existing?.addedAt ?? DateTime.now(),
      );
      await ref.read(robotsProvider.notifier).upsert(profile);
      ref.read(commandsProvider).haptic(HapticKind.medium);
      widget.onDone?.call(profile);
    } on ValetudoUnauthorizedException {
      setState(() {
        _error = _auth
            ? 'The username or password is not correct.'
            : 'This robot is protected. Enter its username and password.';
        _auth = true;
      });
    } catch (e) {
      setState(() => _error = describeError(e));
    } finally {
      if (mounted) setState(() => _testing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final known = ref
        .watch(robotsProvider)
        .profiles
        .map((p) => Uri.parse(p.url).host)
        .toSet();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (widget.showDiscovery && _discovery.supported) ...[
          SectionLabel(
            'On this network',
            icon: Icons.wifi_find_rounded,
            trailing: const SizedBox.square(
              dimension: 14,
              child: CircularProgressIndicator(strokeWidth: 1.8),
            ),
            padding: const EdgeInsets.fromLTRB(4, 4, 4, 10),
          ),
          if (_found.isEmpty)
            ValroveCard(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Icon(Icons.radar_rounded, color: c.textTertiary),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Looking for Valetudo robots…',
                      style: context.text.bodyMedium,
                    ),
                  ),
                ],
              ),
            )
          else
            TileGroup(
              children: [
                for (final robot in _found)
                  ValroveTile(
                    title: robot.title,
                    subtitle: robot.subtitle,
                    icon: Icons.cleaning_services_rounded,
                    trailing: known.contains(robot.host)
                        ? Text('Added', style: context.text.labelMedium)
                        : Icon(
                            Icons.add_circle_rounded,
                            color: context.scheme.primary,
                          ),
                    onTap: _testing
                        ? null
                        : () => _connect(
                            address: robot.port == 80
                                ? robot.host
                                : '${robot.host}:${robot.port}',
                          ),
                  ),
              ],
            ),
          const SizedBox(height: 20),
        ],
        SectionLabel(
          widget.existing == null ? 'Enter address' : 'Connection',
          icon: Icons.edit_location_alt_rounded,
          padding: const EdgeInsets.fromLTRB(4, 4, 4, 10),
        ),
        TextField(
          controller: _address,
          keyboardType: TextInputType.url,
          autocorrect: false,
          textInputAction: TextInputAction.go,
          onSubmitted: (_) => _connect(),
          decoration: const InputDecoration(
            labelText: 'Robot address',
            hintText: '192.168.1.50 or robot.local',
            prefixIcon: Icon(Icons.lan_rounded),
          ),
        ),
        const SizedBox(height: 8),
        SwitchListTile.adaptive(
          contentPadding: const EdgeInsets.symmetric(horizontal: 4),
          value: _auth,
          onChanged: (v) => setState(() => _auth = v),
          title: Text('Uses a password', style: context.text.titleSmall),
          subtitle: Text(
            'Only if HTTP Basic Auth is enabled in Valetudo',
            style: context.text.bodySmall,
          ),
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOutCubic,
          child: _auth
              ? Column(
                  children: [
                    const SizedBox(height: 4),
                    TextField(
                      controller: _user,
                      autocorrect: false,
                      decoration: const InputDecoration(
                        labelText: 'Username',
                        prefixIcon: Icon(Icons.person_rounded),
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: _password,
                      obscureText: _obscure,
                      autocorrect: false,
                      onSubmitted: (_) => _connect(),
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
                )
              : const SizedBox(width: double.infinity),
        ),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 200),
          child: _error == null
              ? const SizedBox(height: 16)
              : Padding(
                  key: ValueKey(_error),
                  padding: const EdgeInsets.only(top: 12, bottom: 4),
                  child: Row(
                    children: [
                      Icon(Icons.error_rounded, color: c.danger, size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _error!,
                          style: context.text.bodyMedium?.copyWith(
                            color: c.danger,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
        ),
        const SizedBox(height: 8),
        FilledButton(
          onPressed: _testing ? null : () => _connect(),
          child: _testing
              ? const SizedBox.square(
                  dimension: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.4,
                    color: Colors.white,
                  ),
                )
              : Text(widget.existing == null ? 'Connect' : 'Save & reconnect'),
        ),
      ],
    );
  }
}

/// First-run screen: no robot configured yet.
class OnboardingScreen extends StatelessWidget {
  const OnboardingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    return Scaffold(
      body: AmbientBackground(
        accent: context.scheme.primary,
        child: ListView(
          padding: EdgeInsets.fromLTRB(
            20,
            media.padding.top + 36,
            20,
            media.padding.bottom + 24,
          ),
          children: [
            Center(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: context.scheme.primary.withValues(alpha: 0.4),
                      blurRadius: 30,
                      offset: const Offset(0, 12),
                    ),
                  ],
                ),
                child: const ValroveLogo(size: 84),
              ),
            ),
            const SizedBox(height: 26),
            Text(
              'Welcome to Valrove',
              textAlign: TextAlign.center,
              style: context.text.displaySmall,
            ),
            const SizedBox(height: 10),
            Text(
              'A cloud-free remote for robot vacuums running Valetudo. Connect to your robot on the local network to get started.',
              textAlign: TextAlign.center,
              style: context.text.bodyLarge?.copyWith(
                color: context.colors.textSecondary,
              ),
            ),
            const SizedBox(height: 30),
            Glass(
              radius: 28,
              padding: const EdgeInsets.all(18),
              child: const RobotSetupView(),
            ),
            const SizedBox(height: 18),
            Text(
              'Your phone needs to be on the same network as the robot. Credentials are stored in the device keystore.',
              textAlign: TextAlign.center,
              style: context.text.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}
