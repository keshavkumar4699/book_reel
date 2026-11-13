import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../ui/kit.dart';

/// The privacy policy or the terms (Production plan A5), from the app's own
/// copy in assets/legal (the server shows the same files at /privacy and
/// /terms), so they can be read offline.
enum LegalDoc {
  privacy('Privacy policy'),
  terms('Terms of use');

  const LegalDoc(this.title);
  final String title;

  static LegalDoc? byName(String name) => LegalDoc.values.where((d) => d.name == name).firstOrNull;
}

final legalTextProvider = FutureProvider.family<String, LegalDoc>((ref, doc) => rootBundle.loadString('assets/legal/${doc.name}.md'));

class LegalScreen extends ConsumerWidget {
  const LegalScreen({super.key, required this.doc});
  final LegalDoc doc;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final kit = Kit.of(context);
    final text = ref.watch(legalTextProvider(doc));
    return KitPage(
      title: doc.title,
      children: [
        text.when(
          loading: () => const Padding(padding: EdgeInsets.all(40), child: Center(child: KitSpinner())),
          error: (e, _) => Text('Couldn’t open it.', style: kit.caption),
          // The first heading is the page title already.
          data: (md) => MarkdownText(md.replaceFirst(RegExp(r'^# .*\n'), '')),
        ),
      ],
    );
  }
}

/// The small part of Markdown the legal texts use: # and ## headings,
/// paragraphs, "- " lists, tables and **bold**.
class MarkdownText extends StatelessWidget {
  const MarkdownText(this.markdown, {super.key});
  final String markdown;

  @override
  Widget build(BuildContext context) {
    final kit = Kit.of(context);
    final blocks = <Widget>[];
    var para = <String>[];
    var list = <String>[];
    var table = <List<String>>[];

    TextSpan rich(String s, TextStyle base) {
      final spans = <TextSpan>[];
      final parts = s.split('**');
      for (final (i, p) in parts.indexed) {
        if (p.isNotEmpty) spans.add(TextSpan(text: p, style: i.isOdd ? base.copyWith(fontWeight: FontWeight.w700) : null));
      }
      return TextSpan(style: base, children: spans);
    }

    void flush() {
      if (para.isNotEmpty) {
        blocks.add(Padding(padding: const EdgeInsets.only(bottom: 12), child: Text.rich(rich(para.join(' '), kit.body))));
      }
      if (list.isNotEmpty) {
        blocks.add(Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            for (final l in list)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('•  ', style: kit.body),
                  Expanded(child: Text.rich(rich(l, kit.body))),
                ]),
              ),
          ]),
        ));
      }
      if (table.isNotEmpty) {
        final head = table.first;
        // Narrow screens: each row as a small block, headed by its first cell.
        blocks.add(Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            for (final row in table.skip(1))
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(row.first, style: kit.strong),
                  for (var i = 1; i < row.length && i < head.length; i++)
                    Text.rich(TextSpan(children: [
                      TextSpan(text: '${head[i]}: ', style: kit.caption),
                      rich(row[i], kit.body),
                    ])),
                ]),
              ),
          ]),
        ));
      }
      para = [];
      list = [];
      table = [];
    }

    for (final raw in markdown.replaceAll('\r\n', '\n').split('\n')) {
      final line = raw.trimRight();
      if (line.trim().isEmpty) {
        flush();
      } else if (line.startsWith('## ')) {
        flush();
        blocks.add(Padding(padding: const EdgeInsets.only(top: 12, bottom: 8), child: Text(line.substring(3), style: kit.heading)));
      } else if (line.startsWith('# ')) {
        flush();
        blocks.add(Padding(padding: const EdgeInsets.only(bottom: 8), child: Text(line.substring(2), style: kit.title)));
      } else if (line.startsWith('- ')) {
        if (para.isNotEmpty || table.isNotEmpty) flush();
        list.add(line.substring(2));
      } else if (line.startsWith('|')) {
        if (para.isNotEmpty || list.isNotEmpty) flush();
        final inner = line.endsWith('|') ? line.substring(1, line.length - 1) : line.substring(1);
        final cells = [for (final c in inner.split('|')) c.trim()];
        if (!cells.every((c) => RegExp(r'^:?-{3,}:?$').hasMatch(c))) table.add(cells);
      } else {
        if (list.isNotEmpty || table.isNotEmpty) flush();
        para.add(line.trim());
      }
    }
    flush();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: blocks);
  }
}
