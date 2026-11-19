import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/help_texts.dart';
import '../../core/licenses.dart';
import '../../core/store.dart';
import '../../core/support_copy.dart';
import '../../state/app_state.dart';
import '../../state/session.dart';
import '../../ui/glyphs.dart';
import '../../ui/markdown.dart';
import '../../ui/theme.dart';
import '../../ui/widgets.dart';
import '../donate/donate.dart';

final _packageInfoProvider = FutureProvider<PackageInfo>(
  (ref) => PackageInfo.fromPlatform(),
);

class AboutPage extends ConsumerWidget {
  const AboutPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final app = ref.watch(_packageInfoProvider).value;
    final version = ref.watch(valetudoVersionProvider).value;
    return ValrovePage(
      title: 'About',
      children: [
        ValroveCard(
          padding: const EdgeInsets.all(20),
          child: Row(
            children: [
              const ValroveLogo(size: 56),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Valrove', style: context.text.titleLarge),
                    Text(
                      'Version ${app?.version ?? '…'} (${app?.buildNumber ?? '…'})',
                      style: context.text.bodySmall,
                    ),
                    Text(
                      'A cloud-free remote for Valetudo robots',
                      style: context.text.bodySmall,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        Text(
          'Valrove is an independent client and is not affiliated with the Valetudo project. '
          '${version == null ? '' : 'Connected robot runs Valetudo ${version.release}.'}',
          style: context.text.bodySmall,
        ),
        if (!playStoreBuild) ...[
          SectionLabel(SupportCopy.valroveHeading),
          TileGroup(
            children: [
              NavTile(
                title: SupportCopy.valroveAction,
                subtitle: SupportCopy.valroveAboutSubtitle,
                icon: Icons.volunteer_activism_rounded,
                iconColor: donateColor,
                onTap: () => Navigator.of(
                  context,
                ).push(MaterialPageRoute(builder: (_) => const DonatePage())),
              ),
            ],
          ),
        ],
        const SectionLabel('About Valetudo'),
        ValroveCard(
          padding: const EdgeInsets.all(16),
          child: MarkdownText(HelpTexts.aboutText),
        ),
        const SectionLabel('Links'),
        TileGroup(
          children: [
            NavTile(
              title: 'Valetudo documentation',
              subtitle: 'valetudo.cloud',
              icon: Icons.menu_book_rounded,
              onTap: () => _open('https://valetudo.cloud'),
            ),
            NavTile(
              title: 'API documentation',
              subtitle: 'Swagger UI served by your robot',
              icon: Icons.api_rounded,
              onTap: () {
                final base = ref.read(activeProfileProvider)?.url;
                if (base != null) _open('${base}swagger/');
              },
            ),
            NavTile(
              title: 'Source code',
              subtitle: 'github.com/Hypfer/Valetudo',
              icon: Icons.code_rounded,
              onTap: () => _open('https://github.com/Hypfer/Valetudo'),
            ),
            if (!playStoreBuild)
              NavTile(
                title: SupportCopy.valetudoHeading,
                subtitle: SupportCopy.valetudoAboutSubtitle,
                icon: Icons.favorite_rounded,
                iconColor: const Color(0xFFF472B6),
                onTap: () => _open(SupportCopy.valetudoUrl),
              ),
            NavTile(
              title: 'Analytics',
              subtitle: 'Learn how your data is used',
              icon: Icons.equalizer_rounded,
              onTap: () => Navigator.of(
                context,
              ).push(MaterialPageRoute(builder: (_) => const AnalyticsPage())),
            ),
          ],
        ),
        const SectionLabel('License'),
        ValroveCard(
          padding: const EdgeInsets.all(16),
          child: MarkdownText(_licenseText),
        ),
        const SizedBox(height: 10),
        TileGroup(
          children: [
            NavTile(
              title: 'Valrove license',
              subtitle: 'Apache License 2.0, full text',
              icon: Icons.description_rounded,
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const ValroveLicensePage()),
              ),
            ),
            NavTile(
              title: 'Open-source licenses',
              subtitle: 'Fonts, ported code and packages in Valrove',
              icon: Icons.gavel_rounded,
              onTap: () => showLicensePage(
                context: context,
                applicationName: 'Valrove',
                applicationVersion: app?.version,
              ),
            ),
          ],
        ),
      ],
    );
  }

  static void _open(String url) =>
      launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
}

/// Valrove's license in plain words; [ValroveLicensePage] has the full text.
const _licenseText = '''$valroveCopyright

Valrove is licensed under the [Apache License 2.0](https://www.apache.org/licenses/LICENSE-2.0), the same license as Valetudo.

In short: you may use, copy, change and share Valrove, on its own or as part of your own work. When you pass it on, include the license, keep the copyright notices and mark the files you changed. The license doesn't give you the right to use the name Valrove for your own version.

Valrove comes as is, without warranty of any kind, and its authors aren't liable for any damage from using it.

This is only a summary; the full license text below is what counts.

Valrove also contains work by others, under their own licenses: texts, map textures, room colors and achievements from Valetudo (Apache License 2.0, © Sören Beye and the Valetudo contributors), code ported from simplify.js (BSD 2-Clause, © Vladimir Agafonkin) and jsmpeg (MIT, © Dominic Szablewski), and the Inter and JetBrains Mono fonts (SIL Open Font License 1.1). Their licenses, and those of the packages Valrove is built with, are under Open-source licenses.''';

/// The full text of Valrove's license (the LICENSE file).
class ValroveLicensePage extends StatefulWidget {
  const ValroveLicensePage({super.key});

  @override
  State<ValroveLicensePage> createState() => _ValroveLicensePageState();
}

class _ValroveLicensePageState extends State<ValroveLicensePage> {
  late final Future<String> _text = rootBundle.loadString(valroveLicenseAsset);

  @override
  Widget build(BuildContext context) {
    final style = context.text.bodySmall?.copyWith(
      color: context.colors.textPrimary,
    );
    return ValrovePage(
      title: 'Valrove license',
      subtitle: 'Apache License 2.0',
      children: [
        FutureBuilder<String>(
          future: _text,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return Text("Couldn't load the license.", style: style);
            }
            final text = snapshot.data;
            if (text == null) {
              return const Padding(
                padding: EdgeInsets.all(32),
                child: Center(child: CircularProgressIndicator()),
              );
            }
            // Reflowed like Flutter's license page, so it reads on a phone.
            final paragraphs = LicenseEntryWithLineBreaks(
              const [],
              text,
            ).paragraphs;
            return ValroveCard(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: SelectionArea(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final p in paragraphs)
                      if (p.indent == LicenseParagraph.centeredIndent)
                        Padding(
                          padding: const EdgeInsets.only(top: 16),
                          child: Text(
                            p.text,
                            textAlign: TextAlign.center,
                            style: style?.copyWith(fontWeight: FontWeight.w600),
                          ),
                        )
                      else
                        Padding(
                          padding: EdgeInsetsDirectional.only(
                            top: 8,
                            start: 16.0 * p.indent,
                          ),
                          child: Text(p.text, style: style),
                        ),
                  ],
                ),
              ),
            );
          },
        ),
      ],
    );
  }
}

class HelpPage extends StatelessWidget {
  const HelpPage({super.key});

  @override
  Widget build(BuildContext context) {
    return ValrovePage(
      title: 'Help',
      subtitle: 'General Valetudo help',
      children: [
        ValroveCard(
          padding: const EdgeInsets.all(16),
          child: MarkdownText(HelpTexts.helpText),
        ),
      ],
    );
  }
}

/// Valetudo's explanation of why it collects no analytics.
class AnalyticsPage extends StatelessWidget {
  const AnalyticsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final t = context.text.bodyMedium?.copyWith(
      color: context.colors.textPrimary,
    );
    return ValrovePage(
      title: 'Analytics',
      children: [
        Text(
          'Software analytics allow teams to build better software and focus their resources on what matters, when the Venn diagram of the team and the target demographic looks somewhat like this:',
          style: t,
        ),
        const SizedBox(height: 16),
        SizedBox(
          height: 180,
          child: CustomPaint(
            painter: _VennPainter(
              apart: true,
              textColor: context.colors.textPrimary,
            ),
          ),
        ),
        const SizedBox(height: 16),
        Text(
          "As a developer, analytics help you to fill in the gap between your own perception and your user's perception - a gap that widens the further those two circles have drifted apart.",
          style: t,
        ),
        const SizedBox(height: 28),
        Text(
          "Here's the desired state of that visualization for Valetudo:",
          style: t,
        ),
        const SizedBox(height: 16),
        SizedBox(
          height: 170,
          child: CustomPaint(
            painter: _VennPainter(
              apart: false,
              textColor: context.colors.textPrimary,
            ),
          ),
        ),
        const SizedBox(height: 16),
        Text(
          'As you can see, the gap there is zero.\n'
          'The industry calls this (among other things) "eating your own dog food" - or "dogfooding" for short.\n'
          'The hackers call this (among other things) "scratching your own itch" - or "spaß am gerät" for short.\n\n'
          'The beauty of that approach is that the "analytics" are collected by developers simply feeling the pain themselves, which neatly bypasses the need to maintain cloud infrastructure to ingest usage metrics.\n\n'
          'Another interesting intuitive takeaway of this visualization is that pulling these circles apart (e.g. by "making things more approachable", or just plain "growth") inevitably invites in the need to introduce measures that fill that widening gap.',
          style: t,
        ),
        const SizedBox(height: 28),
        Text(
          'Back in the real world, however, analytics are rarely just implemented purely to fill that knowledge and perception gap. Instead, they also often exist to cater to less factual and more emotionally resonant (or financially motivated) desires.',
          style: t,
        ),
        const SizedBox(height: 16),
        Text(
          "So for that, here's the final visualization to complete the trifecta:",
          style: t,
        ),
        const SizedBox(height: 16),
        SizedBox(
          height: 110,
          child: CustomPaint(
            painter: _LineUpPainter(
              context.colors.danger,
              context.colors.textSecondary,
            ),
          ),
        ),
      ],
    );
  }
}

class _VennPainter extends CustomPainter {
  _VennPainter({required this.apart, required this.textColor});

  final bool apart;
  final Color textColor;

  void _text(Canvas canvas, String s, Offset c, double size) {
    final tp = TextPainter(
      text: TextSpan(
        text: s,
        style: TextStyle(
          fontFamily: AppTheme.fontFamily,
          fontSize: size,
          fontWeight: FontWeight.w600,
          color: textColor,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, c - Offset(tp.width / 2, tp.height / 2));
  }

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.height * 0.38;
    if (apart) {
      canvas.drawCircle(
        c - Offset(r * 0.65, 0),
        r,
        Paint()..color = const Color(0x803B82F6),
      );
      canvas.drawCircle(
        c + Offset(r * 0.65, 0),
        r,
        Paint()..color = const Color(0x80F59E0B),
      );
      _text(canvas, 'Developers', c - Offset(r * 0.95, 0), 13);
      _text(canvas, 'Users', c + Offset(r * 0.95, 0), 13);
    } else {
      canvas.drawCircle(c, r, Paint()..color = const Color(0x8010B981));
      canvas.drawCircle(
        c,
        r * 1.03,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3
          ..color = const Color(0xCC3B82F6),
      );
      _text(canvas, 'Cool people', c, 14);
    }
  }

  @override
  bool shouldRepaint(_VennPainter old) => old.textColor != textColor;
}

class _LineUpPainter extends CustomPainter {
  _LineUpPainter(this.color, this.textColor);

  final Color color;
  final Color textColor;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final path = Path()..moveTo(w * 0.15, h * 0.8);
    for (var i = 1; i <= 4; i++) {
      path.lineTo(w * (0.15 + i * 0.175), h * (0.8 - i * 0.17));
    }
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..color = color,
    );
    final tp = TextPainter(
      text: TextSpan(
        text: 'line that goes up',
        style: TextStyle(
          fontFamily: AppTheme.fontFamily,
          fontSize: 12,
          color: textColor,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset(w / 2 - tp.width / 2, h - tp.height));
  }

  @override
  bool shouldRepaint(_LineUpPainter old) => false;
}
