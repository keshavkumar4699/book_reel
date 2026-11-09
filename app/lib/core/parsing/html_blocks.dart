import 'package:html/dom.dart';
import 'package:html/parser.dart' as html_parser;

import '../models/book.dart';
import 'block_builder.dart';

const _blockTags = {
  'p', 'div', 'h1', 'h2', 'h3', 'h4', 'h5', 'h6', 'blockquote', 'li', 'pre', 'hr', 'section',
  'article', 'aside', 'header', 'footer', 'main', 'ul', 'ol', 'dl', 'dd', 'dt', 'figure',
  'figcaption', 'table', 'tr', 'td', 'th', 'tbody', 'thead', 'body', 'nav',
};

const _skipTags = {'script', 'style', 'head', 'title', 'svg', 'math', 'img', 'sup'};

/// Converts an XHTML document into paragraph-level [RawBlock]s.
List<RawBlock> htmlToRawBlocks(String markup) {
  final doc = html_parser.parse(markup);
  final body = doc.body;
  if (body == null) return const [];
  final out = <RawBlock>[];
  _walk(body, out, inQuote: false);
  return out;
}

void _walk(Element el, List<RawBlock> out, {required bool inQuote}) {
  final tag = el.localName ?? '';
  if (_skipTags.contains(tag)) return;
  if (el.attributes['epub:type']?.contains('footnote') == true ||
      el.attributes['epub:type']?.contains('pagebreak') == true) {
    return;
  }
  if (tag == 'hr') {
    out.add(const RawBlock(BlockType.paragraph, '', sceneBreak: true));
    return;
  }
  if (RegExp(r'^h[1-6]$').hasMatch(tag)) {
    final text = _inlineText(el);
    if (text.isNotEmpty) out.add(RawBlock(BlockType.heading, text));
    return;
  }
  if (tag == 'pre') {
    out.add(RawBlock(BlockType.preformatted, el.text.trim()));
    return;
  }
  if (tag == 'blockquote') {
    final hasBlockChildren = el.children.any((c) => _blockTags.contains(c.localName));
    if (!hasBlockChildren) {
      _emitText(el, out, BlockType.quote);
      return;
    }
    for (final child in el.children) {
      _walk(child, out, inQuote: true);
    }
    return;
  }
  if (tag == 'li') {
    final text = _inlineText(el);
    if (text.isNotEmpty) out.add(RawBlock(BlockType.list, '• $text'));
    return;
  }

  final hasBlockChildren = el.children.any((c) => _blockTags.contains(c.localName));
  if (!hasBlockChildren) {
    if (tag == 'p' || tag == 'div' || tag == 'dd' || tag == 'dt' || tag == 'td' || tag == 'figcaption') {
      _emitText(el, out, inQuote ? BlockType.quote : null);
    }
    return;
  }
  // Mixed content: emit loose text runs between block children as paragraphs.
  final buffer = StringBuffer();
  void flush() {
    final t = buffer.toString().trim();
    if (t.isNotEmpty) {
      out.add(RawBlock(inQuote ? BlockType.quote : classifyParagraph(t), _clean(t)));
    }
    buffer.clear();
  }

  for (final node in el.nodes) {
    if (node is Element && _blockTags.contains(node.localName)) {
      flush();
      _walk(node, out, inQuote: inQuote);
    } else if (node is Element) {
      if (!_skipTags.contains(node.localName)) buffer.write(_inlineText(node, raw: true));
    } else if (node is Text) {
      buffer.write(node.text);
    }
  }
  flush();
}

void _emitText(Element el, List<RawBlock> out, BlockType? forced) {
  final hasBreaks = el.getElementsByTagName('br').isNotEmpty;
  if (hasBreaks && (forced == BlockType.quote || _looksLikeVerse(el))) {
    // Verse: keep line structure. Each line becomes a sentence.
    final lines = _linesOf(el).where((l) => l.isNotEmpty).toList();
    if (lines.isNotEmpty) out.add(RawBlock(BlockType.quote, lines.join('\n')));
    return;
  }
  final text = _inlineText(el);
  if (text.isEmpty) return;
  if (isSceneBreakText(text)) {
    out.add(const RawBlock(BlockType.paragraph, '', sceneBreak: true));
    return;
  }
  out.add(RawBlock(forced ?? classifyParagraph(text), text));
}

bool _looksLikeVerse(Element el) {
  final cls = '${el.className} ${el.parent?.className ?? ''}'.toLowerCase();
  return cls.contains('poem') || cls.contains('verse') || cls.contains('stanza') || cls.contains('line');
}

List<String> _linesOf(Element el) {
  final lines = <String>[];
  final buffer = StringBuffer();
  void visit(Node n) {
    if (n is Element && n.localName == 'br') {
      lines.add(_clean(buffer.toString()));
      buffer.clear();
    } else if (n is Element) {
      if (_skipTags.contains(n.localName)) return;
      n.nodes.forEach(visit);
    } else if (n is Text) {
      buffer.write(n.text);
    }
  }

  el.nodes.forEach(visit);
  lines.add(_clean(buffer.toString()));
  return lines;
}

String _inlineText(Element el, {bool raw = false}) {
  final buffer = StringBuffer();
  void visit(Node n) {
    if (n is Element) {
      if (_skipTags.contains(n.localName)) return;
      if (n.localName == 'br') {
        buffer.write(' ');
        return;
      }
      n.nodes.forEach(visit);
    } else if (n is Text) {
      buffer.write(n.text);
    }
  }

  el.nodes.forEach(visit);
  return raw ? buffer.toString() : _clean(buffer.toString());
}

String _clean(String s) => s.replaceAll(RegExp(r'[\s ]+'), ' ').trim();
