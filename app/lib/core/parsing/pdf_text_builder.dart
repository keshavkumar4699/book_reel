import 'dart:math' as math;

import '../models/book.dart';
import 'block_builder.dart';
import 'epub_parser.dart' show ParseException;

/// A chapter start taken from the PDF outline (bookmarks). [page] is 1-based.
class PdfChapterStart {
  const PdfChapterStart(this.page, this.title);
  final int page;
  final String title;
}

final RegExp _chapterHeading = RegExp(
  r'^(chapter|part|book|section|prologue|epilogue|introduction|preface|foreword|afterword|conclusion)\b.{0,80}$',
  caseSensitive: false,
);
final RegExp _pageNumberLine = RegExp(r'^\s*(page\s*)?[\divxlc]+\s*(of\s*\d+)?\s*$', caseSensitive: false);

/// Rebuilds book structure from raw per-page PDF text: removes running
/// headers/footers and page numbers, undoes hyphenation, rebuilds paragraphs
/// and detects chapter headings. Pure Dart so it can be unit-tested.
BookContent buildBookFromPdfPages(
  List<String> pages, {
  required String title,
  required String author,
  List<PdfChapterStart> outline = const [],
}) {
  if (pages.isEmpty) throw ParseException('This PDF has no pages.');
  final emptyPages = pages.where((p) => p.replaceAll(RegExp(r'\s'), '').length < 25).length;
  if (emptyPages / pages.length > 0.2 && emptyPages > 1) {
    throw ParseException(
        'This looks like a scanned PDF (no text layer). BookReel needs PDFs with selectable text.');
  }

  final pageLines = [
    for (final page in pages)
      page.split(RegExp(r'\r?\n')).map((l) => l.replaceAll(RegExp(r'[ \t ]+'), ' ').trim()).toList(),
  ];
  final running = _runningLines(pageLines);

  // Per-page paragraphs.
  final allLengths = <int>[
    for (final lines in pageLines)
      for (final l in lines)
        if (l.length > 20) l.length,
  ]..sort();
  final medianLen = allLengths.isEmpty ? 60 : allLengths[allLengths.length ~/ 2];

  final pageParas = <List<_Para>>[];
  _Para? carry;
  for (var pi = 0; pi < pageLines.length; pi++) {
    final paras = <_Para>[];
    final buffer = StringBuffer();
    if (carry != null) {
      buffer.write(carry.text);
      carry = null;
    }
    void flush({bool heading = false}) {
      final t = buffer.toString().trim();
      if (t.isNotEmpty) paras.add(_Para(t, heading: heading));
      buffer.clear();
    }

    final lines = pageLines[pi];
    for (var li = 0; li < lines.length; li++) {
      final line = lines[li];
      if (line.isEmpty) {
        flush();
        continue;
      }
      if (running.contains(_normLine(line)) || _pageNumberLine.hasMatch(line)) continue;
      if (_looksLikeHeading(line, medianLen) && buffer.isEmpty) {
        paras.add(_Para(line, heading: true));
        continue;
      }
      final current = buffer.toString();
      if (current.isEmpty) {
        buffer.write(line);
      } else if (current.endsWith('-') && RegExp(r'^[a-z]').hasMatch(line)) {
        buffer
          ..clear()
          ..write(current.substring(0, current.length - 1))
          ..write(line);
      } else {
        buffer
          ..write(' ')
          ..write(line);
      }
      final endsSentence = RegExp(r'''[.!?:"”’)]$''').hasMatch(line);
      if (endsSentence && line.length < medianLen * 0.75) flush();
    }
    // A paragraph that runs off the bottom of the page continues on the next.
    final tail = buffer.toString().trim();
    if (tail.isNotEmpty && !RegExp(r'''[.!?"”’]$''').hasMatch(tail)) {
      carry = _Para(tail);
    } else {
      flush();
    }
    pageParas.add(paras);
  }
  if (carry != null) pageParas.last.add(carry);

  // Chapter boundaries: outline first, then detected chapter headings, then fixed-size parts.
  final chapters = <({String title, List<RawBlock> blocks})>[];
  final starts = {for (final o in outline) o.page: o.title};
  if (starts.isNotEmpty) {
    for (var pi = 0; pi < pageParas.length; pi++) {
      final t = starts[pi + 1];
      if (t != null || chapters.isEmpty) chapters.add((title: t ?? title, blocks: <RawBlock>[]));
      for (final para in pageParas[pi]) {
        chapters.last.blocks.add(_toRaw(para));
      }
    }
  } else {
    for (final paras in pageParas) {
      for (final para in paras) {
        if (para.heading && _chapterHeading.hasMatch(para.text)) {
          chapters.add((title: para.text, blocks: <RawBlock>[]));
          continue;
        }
        if (chapters.isEmpty) chapters.add((title: 'Opening', blocks: <RawBlock>[]));
        chapters.last.blocks.add(_toRaw(para));
      }
    }
    if (chapters.length <= 1) {
      final blocks = chapters.isEmpty ? <RawBlock>[] : chapters.first.blocks;
      chapters
        ..clear()
        ..addAll(_chunkByWords(blocks, 3000));
    }
  }

  final result = <Chapter>[];
  for (final c in chapters) {
    final words = c.blocks.fold(0, (s, b) => s + countWords(b.text));
    if (words < 20) continue;
    final index = result.length;
    final blocks = buildBlocks(index, c.blocks);
    if (blocks.isEmpty) continue;
    result.add(Chapter(index: index, title: c.title, blocks: blocks));
  }
  if (result.isEmpty) throw ParseException('No readable text was found in this PDF.');
  return BookContent(title: title, author: author, chapters: result);
}

class _Para {
  _Para(this.text, {this.heading = false});
  final String text;
  final bool heading;
}

RawBlock _toRaw(_Para p) => RawBlock(p.heading ? BlockType.heading : classifyParagraph(p.text), p.text);

String _normLine(String line) => line.toLowerCase().replaceAll(RegExp(r'\d+'), '#').trim();

/// Lines that repeat at the top or bottom of many pages (running heads, footers).
Set<String> _runningLines(List<List<String>> pageLines) {
  if (pageLines.length < 4) return const {};
  final counts = <String, int>{};
  for (final lines in pageLines) {
    final nonEmpty = lines.where((l) => l.isNotEmpty).toList();
    final edge = <String>{
      ...nonEmpty.take(2).map(_normLine),
      ...nonEmpty.skip(math.max(0, nonEmpty.length - 2)).map(_normLine),
    };
    for (final l in edge) {
      counts[l] = (counts[l] ?? 0) + 1;
    }
  }
  return {
    for (final e in counts.entries)
      if (e.value >= math.max(3, pageLines.length * 0.4) && e.key.length < 80) e.key,
  };
}

bool _looksLikeHeading(String line, int medianLen) {
  if (line.length > 80 || line.length > medianLen * 0.8) return false;
  if (RegExp(r'[.,;:!?]$').hasMatch(line)) return false;
  if (_chapterHeading.hasMatch(line)) return true;
  final letters = line.replaceAll(RegExp(r'[^A-Za-z]'), '');
  return letters.length >= 4 && letters == letters.toUpperCase();
}

List<({String title, List<RawBlock> blocks})> _chunkByWords(List<RawBlock> blocks, int target) {
  final out = <({String title, List<RawBlock> blocks})>[];
  var words = 0;
  for (final b in blocks) {
    if (out.isEmpty || words >= target) {
      out.add((title: 'Part ${out.length + 1}', blocks: <RawBlock>[]));
      words = 0;
    }
    out.last.blocks.add(b);
    words += countWords(b.text);
  }
  return out;
}
