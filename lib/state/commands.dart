import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderOrFamily;

import '../core/valetudo/client/valetudo_client.dart';
import 'session.dart';
import 'toasts.dart';

export '../ui/haptics.dart' show HapticKind;
import '../ui/haptics.dart';

/// Sends commands to the active robot with consistent feedback.
class Commands {
  Commands(this._ref);

  final Ref _ref;

  ValetudoClient? get client => _ref.read(clientProvider);

  void haptic([HapticKind kind = HapticKind.light]) => Haptics.play(kind);

  /// Runs [action]. On failure a toast describing [what] is shown.
  ///
  /// - [refreshState]: re-fetch robot attributes afterwards (like the web UI
  ///   does after control commands) so the interface reacts immediately.
  /// - [invalidate]: providers to refresh after success.
  /// - [success]: optional confirmation toast.
  Future<bool> run(
    String what,
    Future<void> Function(ValetudoClient client) action, {
    bool refreshState = false,
    List<ProviderOrFamily> invalidate = const [],
    String? success,
    HapticKind? haptic = HapticKind.light,
  }) async {
    final c = client;
    if (c == null) return false;
    if (haptic != null) this.haptic(haptic);
    try {
      await action(c);
      _ref.read(connectionHealthProvider.notifier).reportSuccess();
      if (refreshState) await _ref.read(liveStateProvider.notifier).refresh();
      for (final p in invalidate) {
        _ref.invalidate(p);
      }
      if (success != null) _ref.read(toastProvider).success(success);
      return true;
    } catch (e) {
      _ref.read(connectionHealthProvider.notifier).reportError(e);
      _ref
          .read(toastProvider)
          .error("Couldn't $what", detail: describeError(e));
      Haptics.error();
      return false;
    }
  }
}

/// Human readable error text.
String describeError(Object error) => switch (error) {
  ValetudoUnauthorizedException() => 'The robot asks for valid credentials.',
  ValetudoConnectionException(:final message) => message,
  ValetudoApiException(:final message, :final statusCode) =>
    statusCode == 404 ? 'Not supported by this robot.' : message,
  NotValetudoException(:final message) => message,
  _ => error.toString(),
};

final commandsProvider = Provider<Commands>((ref) => Commands(ref));
