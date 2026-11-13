import 'book.dart';

/// Where a book's own text begins (Cloro plan §7): books open at the
/// introduction or first chapter, not at the title page, copyright notice,
/// contents or dedication. Front matter stays in the book (reachable from
/// Contents and by scrolling back); it is only skipped when a book is opened
/// for the first time.

/// Titles of sections that come before the book's own text.
final _frontTitle = RegExp(
  r'^(cover|title( page)?|half[- ]title|copyright|copyright page|imprint|colophon|legal|license|licen[cs]e information|'
  r'(table of )?contents|toc|list of (illustrations|figures|tables|maps)|illustrations|dedication|epigraph|frontispiece|'
  r'also by .*|other books by .*|books by .*|praise( for .*)?|about (this|the) (e-?book|edition)|'
  r'(the )?project gutenberg.*|start of (the|this) project gutenberg.*|front ?matter)$',
  caseSensitive: false,
);

/// Titles that start the book's own text, even when they come first. (Not
/// "Section N" or "Opening": the parsers make those up when a file has no title.)
final _bodyTitle = RegExp(
  r'^(introduction|introductory|preface|foreword|fore-word|prologue|prelude|author.s note|a note .*|'
  r'(chapter|part|book|canto|act|letter|volume)\b.*|\d+[.:]?(\s.*)?|one)$',
  caseSensitive: false,
);

/// A Roman-numeral chapter title ("IV", "XII. The Trial"), upper case only.
final _romanTitle = RegExp(r'^[IVXLC]{1,7}([.:]|\s|$)');

/// Content that only front matter carries.
final _frontText = RegExp(
  r'©|\(c\) ?\d{4}|copyright|all rights reserved|isbn[\s:-]*[\dx-]{10,}|printed in|published by|first published|'
  r'library of congress|cataloging-in-publication|project gutenberg|gutenberg\.org|this e-?book is for the use of anyone|'
  r'no part of this (publication|book)',
  caseSensitive: false,
);

String _clean(String title) => title.replaceAll(RegExp(r'\s+'), ' ').replaceAll(RegExp(r'[.:]+$'), '').trim();

/// Whether [chapter] is front matter rather than the book's own text.
bool isFrontMatter(Chapter chapter) {
  final title = _clean(chapter.title);
  if (_bodyTitle.hasMatch(title) || _romanTitle.hasMatch(title)) return false;
  if (_frontTitle.hasMatch(title)) return true;
  final words = chapter.wordCount;
  final text = chapter.blocks.take(40).map((b) => b.text).join(' ');
  // Short sections with legal or publishing notices.
  if (_frontText.hasMatch(text) && words < 1500) return true;
  // A contents page: many short lines and little prose.
  final blocks = chapter.blocks.where((b) => b.text.trim().isNotEmpty).toList();
  if (blocks.length >= 6 && words < 600) {
    final short = blocks.where((b) => countWords(b.text) <= 8).length;
    if (short / blocks.length > 0.8) return true;
  }
  return false;
}

/// The chapter index where the book's own text begins.
///
/// [marked] is the publisher's mark, when the file has one (EPUB 3
/// `bodymatter` landmark, EPUB 2 guide `text` reference). An introduction,
/// preface, foreword or prologue just before the mark is included. Without a
/// mark, leading chapters that look like front matter are skipped. At most
/// half of the book is ever skipped.
int findBodyStart(List<Chapter> chapters, {int? marked}) {
  if (chapters.length < 2) return 0;
  final limit = chapters.length ~/ 2;
  int start;
  if (marked != null && marked > 0 && marked <= limit) {
    start = marked;
  } else {
    start = 0;
    while (start < limit && isFrontMatter(chapters[start])) {
      start++;
    }
  }
  // Keep an introduction (or preface, foreword…) that sits just before.
  while (start > 0) {
    final prev = _clean(chapters[start - 1].title);
    // Only an introduction-like section, not an earlier numbered chapter.
    if (_bodyTitle.hasMatch(prev) && !_romanTitle.hasMatch(prev) && !RegExp(r'^\d|^(chapter|part|book)\b', caseSensitive: false).hasMatch(prev)) {
      start--;
    } else {
      break;
    }
  }
  return start;
}
