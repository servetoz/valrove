// On-device frame timing benchmark of the home screen.
//
// Runs the real app (using the robot that is saved on the device) and records
// frame build and raster times while idling, panning and pinching the map,
// dragging the control sheet and opening a page. Nothing is sent to the robot:
// the gestures only move the camera and the sheet.
//
//   flutter build apk --profile -t integration_test/perf_test.dart
//   flutter drive --profile -d <device> \
//     --use-application-binary build/app/outputs/flutter-apk/app-profile.apk \
//     --driver test_driver/perf_driver.dart -t integration_test/perf_test.dart
//
// Results are written to build/integration_response_data.json.
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:valrove/features/home/control_sheet.dart';
import 'package:valrove/main.dart' as app;
import 'package:valrove/map/widgets/map_canvas.dart';
import 'package:valrove/state/session.dart';
import 'package:valrove/ui/glass.dart';

double _percentile(List<double> sorted, double p) {
  if (sorted.isEmpty) return 0;
  final i = ((sorted.length - 1) * p).round();
  return sorted[i];
}

double _round(double v) => (v * 100).round() / 100;

Map<String, Object> _stats(List<FrameTiming> timings, double budgetMs) {
  double ms(Duration d) => d.inMicroseconds / 1000;
  final build = timings.map((t) => ms(t.buildDuration)).toList()..sort();
  final raster = timings.map((t) => ms(t.rasterDuration)).toList()..sort();
  final vsyncs =
      timings
          .map((t) => t.timestampInMicroseconds(FramePhase.vsyncStart))
          .toList()
        ..sort();
  final spanMs = vsyncs.length < 2 ? 0.0 : (vsyncs.last - vsyncs.first) / 1000;
  Map<String, double> summary(List<double> v) => {
    'p50': _round(_percentile(v, 0.5)),
    'p90': _round(_percentile(v, 0.9)),
    'p99': _round(_percentile(v, 0.99)),
    'max': _round(v.isEmpty ? 0 : v.last),
  };
  return {
    'frames': timings.length,
    'fps': spanMs == 0 ? 0 : _round((timings.length - 1) / spanMs * 1000),
    'buildMs': summary(build),
    'rasterMs': summary(raster),
    'slowFrames': timings
        .where(
          (t) =>
              ms(t.buildDuration) > budgetMs || ms(t.rasterDuration) > budgetMs,
        )
        .length,
    'verySlowFrames': timings
        .where(
          (t) =>
              ms(t.buildDuration) > budgetMs * 2 ||
              ms(t.rasterDuration) > budgetMs * 2,
        )
        .length,
  };
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  testWidgets('home screen frame timings', (tester) async {
    await app.main();
    final deadline = DateTime.now().add(const Duration(seconds: 40));
    while (find.byType(MapCanvas).evaluate().isEmpty) {
      if (DateTime.now().isAfter(deadline)) fail('The map did not load');
      await tester.pump(const Duration(milliseconds: 200));
    }
    await tester.pump(const Duration(seconds: 3));

    final display = PlatformDispatcher.instance.displays.first;
    final budgetMs = 1000 / display.refreshRate;
    final results = <String, Object>{};

    Future<void> measure(String name, Future<void> Function() action) async {
      await Future<void>.delayed(const Duration(milliseconds: 1500));
      final timings = <FrameTiming>[];
      void collect(List<FrameTiming> t) => timings.addAll(t);
      SchedulerBinding.instance.addTimingsCallback(collect);
      await action();
      // Frame timings are reported in batches; wait for the last ones.
      await Future<void>.delayed(const Duration(milliseconds: 1500));
      SchedulerBinding.instance.removeTimingsCallback(collect);
      results[name] = _stats(timings, budgetMs);
      debugPrint('PERF $name ${results[name]}');
    }

    Offset sheetHandle() {
      final glass = find.descendant(
        of: find.byType(ControlSheet),
        matching: find.byType(Glass),
      );
      final rect = tester.getRect(glass.first);
      return Offset(rect.center.dx, rect.top + 12);
    }

    final center =
        tester.getCenter(find.byType(MapCanvas)) - const Offset(0, 80);

    await measure(
      'idle',
      () => Future<void>.delayed(const Duration(seconds: 4)),
    );

    await measure('map_pan', () async {
      for (var i = 0; i < 3; i++) {
        await tester.timedDragFrom(
          center,
          const Offset(-140, -110),
          const Duration(milliseconds: 700),
          frequency: 120,
        );
        await tester.timedDragFrom(
          center + const Offset(-140, -110),
          const Offset(140, 110),
          const Duration(milliseconds: 700),
          frequency: 120,
        );
      }
      await tester.pump(const Duration(milliseconds: 800)); // fling settles
    });

    await measure('map_pinch', () async {
      for (var round = 0; round < 2; round++) {
        final a = await tester.startGesture(
          center - const Offset(30, 0),
          pointer: 11,
        );
        final b = await tester.startGesture(
          center + const Offset(30, 0),
          pointer: 12,
        );
        for (var i = 0; i < 50; i++) {
          final d = (round.isEven ? 2.0 : -2.0) * math.min(1, i / 5 + 0.2);
          await a.moveBy(Offset(-d, 0));
          await b.moveBy(Offset(d, 0));
          await tester.pump();
        }
        await a.up();
        await b.up();
        await tester.pump(const Duration(milliseconds: 300));
      }
    });

    await measure('sheet_drag', () async {
      for (var i = 0; i < 2; i++) {
        await tester.timedDragFrom(
          sheetHandle(),
          const Offset(0, -420),
          const Duration(milliseconds: 900),
          frequency: 120,
        );
        await tester.pump(const Duration(milliseconds: 700));
        await tester.timedDragFrom(
          sheetHandle(),
          const Offset(0, 420),
          const Duration(milliseconds: 900),
          frequency: 120,
        );
        await tester.pump(const Duration(milliseconds: 700));
      }
    });

    await measure('settings_page', () async {
      await tester.tap(find.byTooltip('Settings'));
      await tester.pump(const Duration(milliseconds: 900));
      final size = tester.view.physicalSize / tester.view.devicePixelRatio;
      await tester.timedDragFrom(
        Offset(size.width / 2, size.height * 0.7),
        const Offset(0, -350),
        const Duration(milliseconds: 500),
        frequency: 120,
      );
      await tester.pump(const Duration(milliseconds: 1200));
      tester.state<NavigatorState>(find.byType(Navigator).first).pop();
      await tester.pump(const Duration(milliseconds: 900));
    });

    final container = ProviderScope.containerOf(
      tester.element(find.byType(MapCanvas)),
    );
    binding.reportData = {
      'refreshRate': display.refreshRate,
      'budgetMs': _round(budgetMs),
      'robotStatus': container.read(robotStateProvider).status.value,
      ...results,
    };
  });
}
