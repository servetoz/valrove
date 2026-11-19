import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

enum ToastKind { info, success, error }

class Toast {
  Toast(this.message, {this.kind = ToastKind.info, this.detail}) : id = _next++;

  static int _next = 0;
  final int id;
  final String message;
  final String? detail;
  final ToastKind kind;
}

/// Queue of transient notifications rendered by `ToastHost`.
class ToastController extends ChangeNotifier {
  final List<Toast> _toasts = [];

  List<Toast> get toasts => List.unmodifiable(_toasts);

  void show(String message, {ToastKind kind = ToastKind.info, String? detail}) {
    // Suppress identical toasts that are already visible.
    if (_toasts.any((t) => t.message == message && t.detail == detail)) return;
    _toasts.add(Toast(message, kind: kind, detail: detail));
    if (_toasts.length > 3) _toasts.removeAt(0);
    notifyListeners();
  }

  void error(String message, {String? detail}) =>
      show(message, kind: ToastKind.error, detail: detail);

  void success(String message) => show(message, kind: ToastKind.success);

  void dismiss(Toast toast) {
    _toasts.remove(toast);
    notifyListeners();
  }
}

final toastProvider = Provider<ToastController>((ref) {
  final controller = ToastController();
  ref.onDispose(controller.dispose);
  return controller;
});
