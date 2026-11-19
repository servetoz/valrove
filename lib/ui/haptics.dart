import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Kinds of haptic feedback, from subtle to strong.
enum HapticKind {
  /// Picking an option, toggling a room, ticking a key.
  selection,

  /// A tap that sends a command.
  light,

  /// A command that changes what the robot does, a long press.
  medium,

  /// Something important.
  heavy,

  /// A command failed.
  error,
}

/// Plays haptic feedback, following the app's "Haptic feedback" setting.
///
/// On Android, Flutter's own haptics ask the system for touch feedback, which
/// many phones silence (Samsung's "Touch interactions" switch, power saving),
/// so Valrove plays short effects on the vibrator itself (`Haptics.kt`); the
/// phone's vibration strength still applies. Elsewhere Flutter's haptics are
/// used.
abstract final class Haptics {
  static const _channel = MethodChannel('dev.valroveapp.valrove/haptics');

  /// Mirrors the app's "Haptic feedback" setting.
  static bool enabled = true;

  /// Whether to use the native vibrator channel (Android); tests override it.
  @visibleForTesting
  static bool? useVibrator;

  static bool get _native => useVibrator ?? (!kIsWeb && Platform.isAndroid);

  static void selection() => play(HapticKind.selection);
  static void light() => play(HapticKind.light);
  static void medium() => play(HapticKind.medium);
  static void heavy() => play(HapticKind.heavy);
  static void error() => play(HapticKind.error);

  static void play(HapticKind kind) {
    if (!enabled) return;
    if (_native) {
      _channel
          .invokeMethod<void>('play', kind.name)
          .catchError((Object _) => _flutter(kind));
      return;
    }
    _flutter(kind);
  }

  static Future<void> _flutter(HapticKind kind) => switch (kind) {
    HapticKind.selection => HapticFeedback.selectionClick(),
    HapticKind.light => HapticFeedback.lightImpact(),
    HapticKind.medium => HapticFeedback.mediumImpact(),
    HapticKind.heavy || HapticKind.error => HapticFeedback.heavyImpact(),
  };
}
