import 'package:flutter/gestures.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:material_ui/material_ui.dart';
import 'package:url_launcher/url_launcher.dart';

import 'theme.dart';

/// Renders GitHub-flavored Markdown with the app's typography.
class MarkdownText extends StatefulWidget {
  const MarkdownText(this.data, {super.key, this.selectable = false});

  final String data;
  final bool selectable;

  @override
  State<MarkdownText> createState() => _MarkdownTextState();
}

class _MarkdownTextState extends State<MarkdownText> {
  final List<TapGestureRecognizer> _recognizers = [];
  List<md.Node>? _nodes;

  @override
  void initState() {
    super.initState();
    _parse();
  }

  @override
  void didUpdateWidget(MarkdownText old) {
    super.didUpdateWidget(old);
    if (old.data != widget.data) _parse();
  }

  void _parse() {
    // Valetudo's texts use a few raw HTML line breaks.
    final source = widget.data
        .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '  \n')
        .replaceAll(RegExp(r'</?(?!br)[a-z][^>]*>', caseSensitive: false), '');
    final doc = md.Document(
      extensionSet: md.ExtensionSet.gitHubFlavored,
      encodeHtml: false,
    );
    _nodes = doc.parse(source);
  }

  @override
  void dispose() {
    for (final r in _recognizers) {
      r.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    for (final r in _recognizers) {
      r.dispose();
    }
    _recognizers.clear();
    final blocks = <Widget>[];
    for (final node in _nodes ?? const <md.Node>[]) {
      final w = _block(context, node, 0);
      if (w != null) blocks.add(w);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: blocks,
    );
  }

  Widget? _block(BuildContext context, md.Node node, int depth) {
    final t = context.text;
    if (node is md.Text) {
      final text = node.text.trim();
      return text.isEmpty ? null : _paragraph(context, [node], t.bodyMedium!);
    }
    if (node is! md.Element) return null;
    switch (node.tag) {
      case 'h1':
      case 'h2':
        return _padded(
          _paragraph(context, node.children ?? [], t.titleLarge!),
          top: 14,
          bottom: 6,
        );
      case 'h3':
      case 'h4':
      case 'h5':
      case 'h6':
        return _padded(
          _paragraph(context, node.children ?? [], t.titleMedium!),
          top: 12,
          bottom: 4,
        );
      case 'p':
        return _padded(
          _paragraph(
            context,
            node.children ?? [],
            t.bodyMedium!.copyWith(
              color: context.colors.textPrimary.withValues(alpha: 0.86),
            ),
          ),
          bottom: 10,
        );
      case 'hr':
        return const Padding(
          padding: EdgeInsets.symmetric(vertical: 12),
          child: Divider(),
        );
      case 'blockquote':
        return Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.fromLTRB(14, 10, 12, 2),
          decoration: BoxDecoration(
            color: context.scheme.primary.withValues(alpha: 0.06),
            border: Border(
              left: BorderSide(
                color: context.scheme.primary.withValues(alpha: 0.5),
                width: 3,
              ),
            ),
            borderRadius: const BorderRadius.horizontal(
              right: Radius.circular(10),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final c in node.children ?? <md.Node>[])
                ?_block(context, c, depth),
            ],
          ),
        );
      case 'pre':
        final code = node.textContent;
        return Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: context.isDark
                ? const Color(0xFF0A0D12)
                : const Color(0xFF0F1420),
            borderRadius: BorderRadius.circular(12),
          ),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SelectableText(
              code.trimRight(),
              style: const TextStyle(
                fontFamily: AppTheme.monoFamily,
                fontSize: 12.5,
                color: Color(0xFFE6EDF7),
                height: 1.45,
              ),
            ),
          ),
        );
      case 'ul':
      case 'ol':
        final ordered = node.tag == 'ol';
        var index = int.tryParse(node.attributes['start'] ?? '') ?? 1;
        final items = <Widget>[];
        for (final li in node.children ?? <md.Node>[]) {
          if (li is! md.Element) continue;
          final marker = ordered ? '${index++}.' : '•';
          final inline = <md.Node>[];
          final nested = <Widget>[];
          for (final child in li.children ?? <md.Node>[]) {
            if (child is md.Element &&
                (child.tag == 'ul' ||
                    child.tag == 'ol' ||
                    child.tag == 'p' ||
                    child.tag == 'pre')) {
              if (child.tag == 'p') {
                inline.addAll(child.children ?? []);
              } else {
                final w = _block(context, child, depth + 1);
                if (w != null) nested.add(w);
              }
            } else {
              inline.add(child);
            }
          }
          items.add(
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 22,
                    child: Text(
                      marker,
                      style: t.bodyMedium?.copyWith(
                        color: context.scheme.primary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _paragraph(
                          context,
                          inline,
                          t.bodyMedium!.copyWith(
                            color: context.colors.textPrimary.withValues(
                              alpha: 0.86,
                            ),
                          ),
                        ),
                        ...nested,
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        }
        return Padding(
          padding: EdgeInsets.only(left: depth * 12.0, bottom: 8),
          child: Column(children: items),
        );
      case 'table':
        return _table(context, node);
      default:
        return _paragraph(context, node.children ?? [], t.bodyMedium!);
    }
  }

  Widget _table(BuildContext context, md.Element table) {
    final rows = <List<md.Element>>[];
    void collect(md.Element e) {
      for (final c in e.children ?? <md.Node>[]) {
        if (c is! md.Element) continue;
        if (c.tag == 'tr') {
          rows.add([
            for (final cell in c.children ?? <md.Node>[])
              if (cell is md.Element) cell,
          ]);
        } else {
          collect(c);
        }
      }
    }

    collect(table);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Table(
        border: TableBorder.all(color: context.colors.tileBorder),
        defaultColumnWidth: const IntrinsicColumnWidth(flex: 1),
        children: [
          for (final row in rows)
            TableRow(
              children: [
                for (final cell in row)
                  Padding(
                    padding: const EdgeInsets.all(8),
                    child: _paragraph(
                      context,
                      cell.children ?? [],
                      cell.tag == 'th'
                          ? context.text.labelLarge!
                          : context.text.bodySmall!,
                    ),
                  ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _padded(Widget child, {double top = 0, double bottom = 0}) => Padding(
    padding: EdgeInsets.only(top: top, bottom: bottom),
    child: child,
  );

  Widget _paragraph(
    BuildContext context,
    List<md.Node> nodes,
    TextStyle style,
  ) {
    final span = TextSpan(
      style: style,
      children: [for (final n in nodes) _inline(context, n, style)],
    );
    return widget.selectable ? SelectableText.rich(span) : Text.rich(span);
  }

  InlineSpan _inline(BuildContext context, md.Node node, TextStyle style) {
    if (node is md.Text) return TextSpan(text: _unescape(node.text));
    if (node is! md.Element) return const TextSpan();
    final children = node.children ?? const <md.Node>[];
    switch (node.tag) {
      case 'strong':
        return TextSpan(
          style: const TextStyle(fontWeight: FontWeight.w700),
          children: [for (final c in children) _inline(context, c, style)],
        );
      case 'em':
        return TextSpan(
          style: const TextStyle(fontStyle: FontStyle.italic),
          children: [for (final c in children) _inline(context, c, style)],
        );
      case 'del':
        return TextSpan(
          style: const TextStyle(decoration: TextDecoration.lineThrough),
          children: [for (final c in children) _inline(context, c, style)],
        );
      case 'code':
        return TextSpan(
          text: node.textContent,
          style: TextStyle(
            fontFamily: AppTheme.monoFamily,
            fontSize: (style.fontSize ?? 14) * 0.9,
            backgroundColor: context.scheme.primary.withValues(alpha: 0.08),
          ),
        );
      case 'br':
        return const TextSpan(text: '\n');
      case 'a':
        final href = node.attributes['href'];
        final recognizer = TapGestureRecognizer()
          ..onTap = () {
            final uri = href == null ? null : Uri.tryParse(href);
            if (uri != null) {
              launchUrl(uri, mode: LaunchMode.externalApplication);
            }
          };
        _recognizers.add(recognizer);
        return TextSpan(
          recognizer: recognizer,
          style: TextStyle(
            color: context.scheme.primary,
            fontWeight: FontWeight.w600,
            decoration: TextDecoration.underline,
            decorationColor: context.scheme.primary.withValues(alpha: 0.4),
          ),
          children: [for (final c in children) _inline(context, c, style)],
        );
      case 'img':
        return TextSpan(text: node.attributes['alt'] ?? '');
      default:
        return TextSpan(
          children: [for (final c in children) _inline(context, c, style)],
        );
    }
  }

  static String _unescape(String s) => s
      .replaceAll('&amp;', '&')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&#39;', "'");
}
