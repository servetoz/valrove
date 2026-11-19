import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../state/commands.dart';
import '../../state/data.dart';
import '../../state/session.dart';
import '../../ui/theme.dart';
import '../../ui/widgets.dart';

class LogEntry {
  LogEntry(this.timestamp, this.level, this.content);

  final String timestamp;
  final String level;
  String content;
}

final _linePattern = RegExp(
  r'^\[(\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}.\d{3}Z)\] \[([A-Z]+)\] (.*)$',
);

/// Parses Valetudo's log format: `[ISO timestamp] [LEVEL] message`, with
/// continuation lines appended to the previous entry.
List<LogEntry> parseLog(String text) {
  final entries = <LogEntry>[];
  for (final line in text.split('\n')) {
    final m = _linePattern.firstMatch(line);
    if (m != null) {
      entries.add(
        LogEntry(m.group(1)!, m.group(2)!.toLowerCase(), m.group(3)!),
      );
    } else if (entries.isNotEmpty) {
      entries.last.content += '\n$line';
    }
  }
  return entries;
}

/// Full log text: initial download plus live SSE lines.
class LiveLogNotifier extends Notifier<AsyncValue<String>> {
  StreamSubscription<String>? _sub;

  @override
  AsyncValue<String> build() {
    final client = ref.watch(clientProvider);
    ref.onDispose(() => _sub?.cancel());
    if (client == null) return const AsyncLoading();
    _sub = client.logChannel.stream.listen((line) {
      final current = state.value;
      state = AsyncData(current == null ? line : '${current.trim()}\n$line');
    });
    Future.microtask(refresh);
    return const AsyncLoading();
  }

  Future<void> refresh() async {
    final client = ref.read(clientProvider);
    if (client == null) return;
    try {
      final text = await client.getLog();
      if (ref.mounted) state = AsyncData(text);
    } catch (e, st) {
      if (ref.mounted && !state.hasValue) state = AsyncError(e, st);
    }
  }
}

final liveLogProvider =
    NotifierProvider.autoDispose<LiveLogNotifier, AsyncValue<String>>(
      LiveLogNotifier.new,
    );

class LogPage extends ConsumerStatefulWidget {
  const LogPage({super.key});

  @override
  ConsumerState<LogPage> createState() => _LogPageState();
}

class _LogPageState extends ConsumerState<LogPage> {
  final _scroll = ScrollController();
  final _filter = TextEditingController();
  bool _stick = true;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      if (!_scroll.hasClients) return;
      _stick = _scroll.position.pixels >= _scroll.position.maxScrollExtent - 24;
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    _filter.dispose();
    super.dispose();
  }

  Color _levelColor(BuildContext context, String level) => switch (level) {
    'trace' => const Color(0xFFA78BFA),
    'debug' => const Color(0xFF2DD4BF),
    'info' => context.colors.success,
    'warn' => context.colors.warning,
    'error' => context.colors.danger,
    _ => context.colors.textSecondary,
  };

  @override
  Widget build(BuildContext context) {
    final log = ref.watch(liveLogProvider);
    final level = ref.watch(logLevelProvider);
    final f = _filter.text.toLowerCase();
    final entries = log.whenData(parseLog).value ?? const <LogEntry>[];
    final shown = f.isEmpty
        ? entries
        : entries
              .where(
                (e) =>
                    e.level.contains(f) || e.content.toLowerCase().contains(f),
              )
              .toList();
    if (_stick) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scroll.hasClients) {
          _scroll.jumpTo(_scroll.position.maxScrollExtent);
        }
      });
    }
    final media = MediaQuery.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Log'),
        actions: [
          IconButton(
            tooltip: 'Copy log',
            icon: const Icon(Icons.copy_all_rounded),
            onPressed: log.value == null
                ? null
                : () {
                    Clipboard.setData(ClipboardData(text: log.value!));
                    ref.read(commandsProvider).haptic();
                  },
          ),
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh_rounded),
            onPressed: () {
              ref.invalidate(logLevelProvider);
              ref.read(liveLogProvider.notifier).refresh();
            },
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _filter,
                    onChanged: (_) => setState(() {}),
                    decoration: const InputDecoration(
                      hintText: 'Filter…',
                      prefixIcon: Icon(Icons.filter_alt_rounded),
                      isDense: true,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                level.when(
                  data: (l) => DropdownButton<String>(
                    value: l.presets.contains(l.current) ? l.current : null,
                    hint: const Text('Level'),
                    underline: const SizedBox.shrink(),
                    borderRadius: BorderRadius.circular(16),
                    items: [
                      for (final p in l.presets)
                        DropdownMenuItem(value: p, child: Text(p)),
                    ],
                    onChanged: (v) {
                      if (v != null) {
                        ref
                            .read(commandsProvider)
                            .run(
                              'change the log level',
                              (c) => c.setLogLevel(v),
                              invalidate: [logLevelProvider],
                            );
                      }
                    },
                  ),
                  loading: () => const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  error: (e, _) => const Icon(Icons.error_outline_rounded),
                ),
              ],
            ),
          ),
          Expanded(
            child: log.hasError && !log.hasValue
                ? ErrorState(
                    message: 'Error loading log',
                    onRetry: () => ref.read(liveLogProvider.notifier).refresh(),
                  )
                : !log.hasValue
                ? const Center(child: CircularProgressIndicator())
                : Container(
                    margin: const EdgeInsets.fromLTRB(12, 0, 12, 0),
                    decoration: BoxDecoration(
                      color: context.isDark
                          ? const Color(0xFF07090D)
                          : const Color(0xFF0F1420),
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: Scrollbar(
                      controller: _scroll,
                      child: ListView.builder(
                        controller: _scroll,
                        padding: EdgeInsets.fromLTRB(
                          12,
                          10,
                          12,
                          12 + media.padding.bottom,
                        ),
                        itemCount: shown.length,
                        itemBuilder: (context, i) {
                          final e = shown[i];
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: SelectableText.rich(
                              TextSpan(
                                style: const TextStyle(
                                  fontFamily: AppTheme.monoFamily,
                                  fontSize: 11.5,
                                  height: 1.4,
                                  color: Color(0xFFDCE3EE),
                                ),
                                children: [
                                  TextSpan(
                                    text: '${e.timestamp} ',
                                    style: const TextStyle(
                                      color: Color(0xFF7F8AA0),
                                    ),
                                  ),
                                  TextSpan(
                                    text:
                                        '${e.level[0].toUpperCase()}${e.level.substring(1)} ',
                                    style: TextStyle(
                                      color: _levelColor(context, e.level),
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                  TextSpan(text: '\n${e.content}'),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}
