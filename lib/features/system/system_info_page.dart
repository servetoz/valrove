import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/util/format.dart';
import '../../core/valetudo/models/models.dart';
import '../../state/data.dart';
import '../../state/session.dart';
import '../../ui/dialogs.dart';
import '../../ui/theme.dart';
import '../../ui/widgets.dart';

String _mib(double bytes) => '${(bytes / 1024 / 1024).toStringAsFixed(2)} MiB';

class SystemInfoPage extends ConsumerWidget {
  const SystemInfoPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final robot = ref.watch(robotInfoProvider);
    final props = ref.watch(robotPropertiesProvider);
    final version = ref.watch(valetudoVersionProvider);
    final info = ref.watch(valetudoInfoProvider);
    final host = ref.watch(hostInfoProvider);
    final runtime = ref.watch(runtimeInfoProvider);
    final c = context.colors;

    return ValrovePage(
      title: 'System information',
      subtitle: 'Robot, Valetudo and host details',
      onRefresh: () async {
        ref.invalidate(runtimeInfoProvider);
        ref.invalidate(hostInfoProvider);
        await ref.read(hostInfoProvider.future);
      },
      children: [
        const SectionLabel('Robot'),
        robot.hasValue
            ? TileGroup(
                children: [
                  InfoRow('Manufacturer', robot.value!.manufacturer),
                  InfoRow('Model', robot.value!.modelName),
                  InfoRow(
                    'Valetudo implementation',
                    robot.value!.implementation,
                    mono: true,
                  ),
                  if (props.value?.firmwareVersion != null)
                    InfoRow('Firmware version', props.value!.firmwareVersion!),
                ],
              )
            : const SkeletonCard(rows: 2),
        const SectionLabel('Valetudo'),
        version.hasValue
            ? TileGroup(
                children: [
                  InfoRow('Release', version.value!.release),
                  InfoRow('Commit', version.value!.commit, mono: true),
                  InfoRow('Embedded', '${info.value?.embedded ?? false}'),
                  if (info.value != null)
                    InfoRow('System ID', info.value!.systemId),
                ],
              )
            : const SkeletonCard(rows: 2),
        const SectionLabel('Host'),
        host.when(
          skipLoadingOnRefresh: true,
          data: (h) => ValroveCard(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: _Stat(label: 'Hostname', value: h.hostname),
                    ),
                    Expanded(
                      child: _Stat(label: 'Arch', value: h.arch),
                    ),
                    Expanded(
                      child: _Stat(
                        label: 'Uptime',
                        value: compactDuration(h.uptime),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                Text('System memory (RAM)', style: context.text.labelLarge),
                const SizedBox(height: 8),
                RatioBar(
                  total: h.memTotal,
                  parts: [
                    RatioPart(
                      'System',
                      h.memTotal - h.memFree - h.memValetudoCurrent,
                      c.success,
                      _mib(h.memTotal - h.memFree - h.memValetudoCurrent),
                    ),
                    RatioPart(
                      'Valetudo',
                      h.memValetudoCurrent,
                      c.danger,
                      _mib(h.memValetudoCurrent),
                    ),
                    RatioPart(
                      'Valetudo (max)',
                      h.memValetudoMax - h.memValetudoCurrent,
                      const Color(0xFF2DD4BF),
                      _mib(h.memValetudoMax),
                    ),
                  ],
                  noneLabel: 'Free · ${_mib(h.memFree)}',
                ),
                const SizedBox(height: 18),
                Text('CPU usage', style: context.text.labelLarge),
                const SizedBox(height: 8),
                for (var i = 0; i < h.cpus.length; i++) ...[
                  RatioBar(
                    total: 100,
                    showLegend: i == h.cpus.length - 1,
                    parts: [
                      RatioPart(
                        'user',
                        h.cpus[i].user,
                        c.success,
                        '${h.cpus[i].user} %',
                      ),
                      RatioPart(
                        'nice',
                        h.cpus[i].nice,
                        const Color(0xFF2DD4BF),
                        '${h.cpus[i].nice} %',
                      ),
                      RatioPart(
                        'sys',
                        h.cpus[i].sys,
                        c.danger,
                        '${h.cpus[i].sys} %',
                      ),
                      RatioPart(
                        'irq',
                        h.cpus[i].irq,
                        const Color(0xFFA78BFA),
                        '${h.cpus[i].irq} %',
                      ),
                    ],
                    noneLabel: 'idle',
                  ),
                  const SizedBox(height: 6),
                ],
                const SizedBox(height: 8),
                Text(
                  'Load average: ${h.load1.toStringAsFixed(2)} · ${h.load5.toStringAsFixed(2)} · ${h.load15.toStringAsFixed(2)}',
                  style: context.text.bodySmall,
                ),
              ],
            ),
          ),
          loading: () => const SkeletonCard(rows: 3),
          error: (e, _) => ValroveCard(
            child: InlineError(
              'No system host information',
              onRetry: () => ref.invalidate(hostInfoProvider),
            ),
          ),
        ),
        const SectionLabel('Runtime'),
        runtime.when(
          data: (r) => Column(
            children: [
              TileGroup(
                children: [
                  InfoRow('Valetudo uptime', compactDuration(r.uptime)),
                  InfoRow('UID / GID', '${r.uid} / ${r.gid}'),
                  InfoRow('PID', '${r.pid}'),
                  InfoRow(
                    'Reincarnation',
                    r.canReincarnate ? 'Possible' : 'Impossible',
                  ),
                  InfoRow('Generation', '${r.generation}'),
                  InfoRow('argv', r.argv.join(' '), mono: true),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => _showNode(context, r),
                      child: const Text('Node'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => _showEnv(context, r),
                      child: const Text('Environment'),
                    ),
                  ),
                ],
              ),
            ],
          ),
          loading: () => const SkeletonCard(rows: 2),
          error: (e, _) => ValroveCard(
            child: InlineError(
              'No runtime information',
              onRetry: () => ref.invalidate(runtimeInfoProvider),
            ),
          ),
        ),
      ],
    );
  }

  void _showNode(BuildContext context, SystemRuntimeInfo r) {
    showValroveSheet<void>(
      context,
      builder: (context) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.7,
        builder: (context, scroll) => ListView(
          controller: scroll,
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: [
            const SheetHeader(title: 'Node information'),
            TileGroup(
              children: [
                InfoRow('execPath', r.execPath, mono: true),
                InfoRow('execArgv', r.execArgv.join(' '), mono: true),
              ],
            ),
            const SectionLabel('Dependencies'),
            TileGroup(
              children: [
                for (final e in r.versions.entries)
                  InfoRow(e.key, e.value, mono: true),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _showEnv(BuildContext context, SystemRuntimeInfo r) {
    final keys = r.env.keys.toList()..sort();
    showValroveSheet<void>(
      context,
      builder: (context) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.7,
        builder: (context, scroll) => ListView(
          controller: scroll,
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: [
            const SheetHeader(title: 'Environment'),
            TileGroup(
              children: [
                for (final k in keys) InfoRow(k, r.env[k]!, mono: true),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label.toUpperCase(), style: context.text.labelSmall),
      const SizedBox(height: 3),
      Text(
        value,
        style: context.text.titleSmall,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    ],
  );
}

class RatioPart {
  const RatioPart(this.label, this.value, this.color, this.valueLabel);

  final String label;
  final double value;
  final Color color;
  final String valueLabel;
}

/// Stacked horizontal bar with legend (Valetudo's RatioBar).
class RatioBar extends StatelessWidget {
  const RatioBar({
    super.key,
    required this.total,
    required this.parts,
    this.noneLabel,
    this.showLegend = true,
  });

  final double total;
  final List<RatioPart> parts;
  final String? noneLabel;
  final bool showLegend;

  @override
  Widget build(BuildContext context) {
    final track = context.isDark
        ? const Color(0xFF233041)
        : const Color(0xFFDCE5F2);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: SizedBox(
            height: 10,
            child: LayoutBuilder(
              builder: (context, constraints) {
                var x = 0.0;
                final children = <Widget>[];
                for (final p in parts) {
                  final w = total <= 0
                      ? 0.0
                      : (p.value / total).clamp(0.0, 1.0) *
                            constraints.maxWidth;
                  children.add(
                    AnimatedPositioned(
                      duration: const Duration(milliseconds: 400),
                      left: x,
                      width: w,
                      top: 0,
                      bottom: 0,
                      child: Tooltip(
                        message: '${p.label}: ${p.valueLabel}',
                        child: ColoredBox(color: p.color),
                      ),
                    ),
                  );
                  x += w;
                }
                return Stack(
                  children: [
                    Positioned.fill(child: ColoredBox(color: track)),
                    ...children,
                  ],
                );
              },
            ),
          ),
        ),
        if (showLegend) ...[
          const SizedBox(height: 6),
          Wrap(
            spacing: 10,
            runSpacing: 4,
            children: [
              for (final p in parts)
                _Legend(color: p.color, label: '${p.label} · ${p.valueLabel}'),
              if (noneLabel != null) _Legend(color: track, label: noneLabel!),
            ],
          ),
        ],
      ],
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: 8,
        height: 8,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      ),
      const SizedBox(width: 5),
      Text(label, style: context.text.bodySmall),
    ],
  );
}
