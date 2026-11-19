import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/support_copy.dart';
import '../../state/toasts.dart';
import '../../ui/haptics.dart';
import '../../ui/theme.dart';
import '../../ui/widgets.dart';

/// Whether this is the Google Play build (`--dart-define=STORE=play`). It
/// leaves out the Donate page under About; the donation popup stays.
const playStoreBuild = String.fromEnvironment('STORE') == 'play';

/// Color of the donation icons.
const donateColor = Color(0xFFF472B6);

Future<void> _openSupportPage(ToastController toasts) async {
  Haptics.light();
  bool opened;
  try {
    opened = await launchUrl(
      Uri.parse(SupportCopy.valroveUrl),
      mode: LaunchMode.externalApplication,
    );
  } on Exception {
    opened = false;
  }
  if (!opened) {
    toasts.error(
      "Couldn't open the browser",
      detail: SupportCopy.valroveBrowserFallback,
    );
  }
}

/// When Valrove asks for a donation: on the 5th and the 20th opening of the
/// app (counted by `appOpeningsProvider`). An opening on which it can't ask,
/// because the robot is offline or something is open over the map, moves
/// the question to the next opening.
abstract final class DonatePrompt {
  /// Openings of the app on which to ask.
  static const openings = [5, 20];

  /// How long the home screen shows a connected robot before the question.
  static const delay = Duration(seconds: 2);

  static final _askedKey = utf8.decode(base64Decode('ZG9uYXRlLmFza2Vk'));

  /// Whether to ask on the [opening]-th opening of the app.
  static bool due(SharedPreferences prefs, int opening) {
    final asked = prefs.getInt(_askedKey) ?? 0;
    return asked < openings.length && opening >= openings[asked];
  }

  /// Notes that the question was asked on the [opening]-th opening. Asked
  /// late, it counts for every opening it was due on, so it never comes
  /// twice in a row.
  static void markAsked(SharedPreferences prefs, int opening) =>
      prefs.setInt(_askedKey, openings.where((n) => n <= opening).length);
}

/// Asks whether the user enjoys Valrove and offers to donate.
Future<void> showDonatePrompt(BuildContext context, WidgetRef ref) async {
  final toasts = ref.read(toastProvider);
  final donate = await showDialog<bool>(
    context: context,
    builder: (_) => const DonateDialog(),
  );
  if (donate ?? false) await _openSupportPage(toasts);
}

class DonateDialog extends StatelessWidget {
  const DonateDialog({super.key});

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      icon: const Center(
        child: TileIcon(
          Icons.volunteer_activism_rounded,
          color: donateColor,
          size: 56,
        ),
      ),
      title: Text(SupportCopy.valrovePromptTitle),
      content: Text(
        SupportCopy.valrovePromptBody,
        textAlign: TextAlign.center,
        style: context.text.bodyMedium,
      ),
      actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Not now'),
        ),
        FilledButton.icon(
          autofocus: true,
          onPressed: () => Navigator.pop(context, true),
          icon: const Icon(Icons.coffee_rounded, size: 18),
          label: Text(SupportCopy.valroveAction),
        ),
      ],
    );
  }
}

/// Donating to Valrove, under About.
class DonatePage extends ConsumerWidget {
  const DonatePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ValrovePage(
      title: SupportCopy.valroveAction,
      children: [
        ValroveCard(
          padding: const EdgeInsets.fromLTRB(20, 28, 20, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Center(
                child: TileIcon(
                  Icons.volunteer_activism_rounded,
                  color: donateColor,
                  size: 64,
                ),
              ),
              const SizedBox(height: 18),
              Text(
                SupportCopy.valroveHeading,
                textAlign: TextAlign.center,
                style: context.text.titleLarge,
              ),
              const SizedBox(height: 8),
              Text(
                SupportCopy.valrovePageBody,
                textAlign: TextAlign.center,
                style: context.text.bodyMedium,
              ),
              const SizedBox(height: 22),
              FilledButton.icon(
                onPressed: () => _openSupportPage(ref.read(toastProvider)),
                icon: const Icon(Icons.coffee_rounded),
                label: Text(SupportCopy.valroveBrowserAction),
              ),
              const SizedBox(height: 10),
              Text(
                SupportCopy.valroveBrowserHint,
                textAlign: TextAlign.center,
                style: context.text.bodySmall,
              ),
            ],
          ),
        ),
      ],
    );
  }
}
