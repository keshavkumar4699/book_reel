import '../../../core/models/book.dart';
import '../../../core/models/reel_card.dart';

/// One display line of a card in the lyric-style layout: a phrase of the
/// author's text, sized by importance (1 regular · 2 large · 3 hero).
class LyricPiece {
  const LyricPiece({
    required this.text,
    required this.sid,
    required this.level,
    required this.start,
    required this.end,
    required this.blockType,
    this.newBlock = false,
  });

  final String text;
  final String sid;
  final int level;

  /// Character range of [text] within its sentence.
  final int start;
  final int end;
  final BlockType blockType;

  /// First piece of a new paragraph (gets a larger gap above).
  final bool newBlock;

  LyricPiece copyWith({String? text, int? level, int? end}) => LyricPiece(
        text: text ?? this.text,
        sid: sid,
        level: level ?? this.level,
        start: start,
        end: end ?? this.end,
        blockType: blockType,
        newBlock: newBlock,
      );
}

typedef LyricSentence = ({String sid, String text, int block, BlockType type});

final RegExp _word = RegExp(r"[\p{L}\p{N}][\p{L}\p{N}'’\-]*", unicode: true);
final RegExp _letter = RegExp(r'[\p{L}\p{N}]', unicode: true);
int _words(String s) => _word.allMatches(s).length;

/// Closing punctuation that belongs to the end of the previous line.
final RegExp _leadingClose = RegExp(r'''^(?:[,.;:!?)\]}”’»…]+|['"](?=\s|$))+''');

/// Opening punctuation that belongs to the start of the next line.
final RegExp _trailingOpen = RegExp(r'[(\[{“‘«]+$');

/// Clause boundaries inside plain text: after , ; : or around dashes.
final RegExp _clauseBreak = RegExp(r'(?<=[,;:])\s+|\s+(?=[—–]\s)|(?<=\s[—–])\s+');

/// Splits a card into display lines. AI [emphasis] phrases become their own
/// lines at their level; the rest is split at clause boundaries so the card
/// reads like song lyrics. Without AI emphasis, [keySids] and short punchy
/// sentences are made larger (free tier).
List<LyricPiece> buildLyricPieces(
  List<LyricSentence> sentences, {
  List<Emphasis> emphasis = const [],
  Set<String> keySids = const {},
  bool aiDirected = false,
}) {
  final pieces = <LyricPiece>[];
  int? previousBlock;
  for (final s in sentences) {
    final text = s.text;
    // 1. Locate emphasis spans in this sentence.
    final spans = <(int, int, int)>[];
    for (final e in emphasis.where((e) => e.sid == s.sid)) {
      var at = text.indexOf(e.text);
      if (at < 0) at = text.toLowerCase().indexOf(e.text.toLowerCase());
      if (at < 0) continue;
      final end = at + e.text.length;
      if (spans.any((x) => at < x.$2 && end > x.$1)) continue;
      spans.add((at, end, e.level.clamp(2, 3)));
    }
    spans.sort((a, b) => a.$1.compareTo(b.$1));

    // 2. Segments: emphasis spans and the plain text between them.
    final segments = <(int, int, int)>[];
    var cursor = 0;
    for (final sp in spans) {
      if (sp.$1 > cursor) segments.add((cursor, sp.$1, 1));
      segments.add(sp);
      cursor = sp.$2;
    }
    if (cursor < text.length) segments.add((cursor, text.length, 1));

    // 3. Plain segments split at clause boundaries (long ones only).
    final ranges = <(int, int, int)>[];
    for (final seg in segments) {
      if (seg.$3 > 1 || _words(text.substring(seg.$1, seg.$2)) <= 8) {
        ranges.add(seg);
        continue;
      }
      var from = seg.$1;
      for (final m in _clauseBreak.allMatches(text.substring(seg.$1, seg.$2))) {
        final cut = seg.$1 + m.start;
        if (_words(text.substring(from, cut)) >= 3 && _words(text.substring(seg.$1 + m.end, seg.$2)) >= 3) {
          ranges.add((from, cut, 1));
          from = seg.$1 + m.end;
        }
      }
      ranges.add((from, seg.$2, 1));
    }

    // 4. Trim, attach punctuation-only fragments, merge tiny plain fragments.
    final local = <LyricPiece>[];
    for (final r in ranges) {
      var a = r.$1, b = r.$2;
      while (a < b && text[a].trim().isEmpty) {
        a++;
      }
      while (b > a && text[b - 1].trim().isEmpty) {
        b--;
      }
      if (a >= b) continue;
      // Keep closing punctuation with the previous line ("…stupid)," not "), whether").
      final close = _leadingClose.firstMatch(text.substring(a, b));
      if (close != null && local.isNotEmpty && local.last.end <= a) {
        final last = local.removeLast();
        final to = a + close.end;
        local.add(last.copyWith(end: to, text: text.substring(last.start, to)));
        a = to;
        while (a < b && text[a].trim().isEmpty) {
          a++;
        }
        if (a >= b) continue;
      }
      final piece = text.substring(a, b);
      if (!_letter.hasMatch(piece) && local.isNotEmpty) {
        final last = local.removeLast();
        local.add(last.copyWith(end: b, text: text.substring(last.start, b)));
        continue;
      }
      local.add(LyricPiece(text: piece, sid: s.sid, level: r.$3, start: a, end: b, blockType: s.type));
    }
    // Move opening punctuation at a line's end to the next line ("(as" not "(" + "as").
    for (var i = 0; i + 1 < local.length; i++) {
      final open = _trailingOpen.firstMatch(local[i].text);
      if (open == null || open.start == 0) continue;
      final cut = local[i].start + open.start;
      var head = cut;
      while (head > local[i].start && text[head - 1].trim().isEmpty) {
        head--;
      }
      local[i] = local[i].copyWith(end: head, text: text.substring(local[i].start, head));
      final next = local[i + 1];
      local[i + 1] = LyricPiece(
        text: text.substring(cut, next.end),
        sid: next.sid,
        level: next.level,
        start: cut,
        end: next.end,
        blockType: next.blockType,
        newBlock: next.newBlock,
      );
    }
    for (var i = 0; i < local.length; i++) {
      final p = local[i];
      if (p.level > 1 || _words(p.text) >= 2 || local.length == 1) continue;
      final j = i > 0 && local[i - 1].level == 1 ? i - 1 : (i + 1 < local.length && local[i + 1].level == 1 ? i + 1 : -1);
      if (j < 0) continue;
      final lo = j < i ? local[j] : p;
      final hi = j < i ? p : local[j];
      local[j < i ? j : i] = lo.copyWith(end: hi.end, text: text.substring(lo.start, hi.end));
      local.removeAt(j < i ? i : i + 1);
      i--;
    }
    for (var i = 0; i < local.length; i++) {
      final first = i == 0 && previousBlock != null && previousBlock != s.block;
      pieces.add(LyricPiece(
        text: local[i].text,
        sid: local[i].sid,
        level: local[i].level,
        start: local[i].start,
        end: local[i].end,
        blockType: local[i].blockType,
        newBlock: first,
      ));
    }
    previousBlock = s.block;
  }
  // The AI may deliberately leave a plain card plain; only rule cards get heuristics.
  return emphasis.isEmpty && !aiDirected ? _heuristicLevels(pieces, sentences, keySids) : pieces;
}

/// Free-tier emphasis: key sentences and short punchy lines get larger,
/// capped at one hero and two large lines per card.
List<LyricPiece> _heuristicLevels(List<LyricPiece> pieces, List<LyricSentence> sentences, Set<String> keySids) {
  if (pieces.length <= 1) return pieces;
  final wordsBySid = {for (final s in sentences) s.sid: _words(s.text)};
  var hero = 0, large = 0;
  return [
    for (final p in pieces)
      () {
        final sentenceWords = wordsBySid[p.sid] ?? 99;
        var level = 1;
        if (keySids.contains(p.sid)) {
          level = sentenceWords <= 8 ? 3 : 2;
        } else if (sentenceWords <= 6 && sentences.length > 1) {
          level = 2;
        }
        if (level == 3 && hero >= 1) level = 2;
        if (level == 2 && large >= 2) level = 1;
        if (level == 3) hero++;
        if (level == 2) large++;
        return p.copyWith(level: level);
      }(),
  ];
}

enum LyricAlign { centered, left, staggered }

/// The AI's layout when valid; otherwise dialogue → staggered, short → centered.
LyricAlign lyricAlignFor(String? aiLayout, List<LyricPiece> pieces) {
  switch (aiLayout) {
    case 'centered':
      return LyricAlign.centered;
    case 'left':
      return LyricAlign.left;
    case 'staggered':
      return LyricAlign.staggered;
  }
  final words = pieces.fold(0, (s, p) => s + _words(p.text));
  if (pieces.where((p) => p.blockType == BlockType.dialogue).length >= 2) return LyricAlign.staggered;
  return words <= 32 ? LyricAlign.centered : LyricAlign.left;
}

/// Size multipliers per level (1 regular · 2 large · 3 hero).
double levelScale(int level) => switch (level) { 3 => 1.85, 2 => 1.38, _ => 1.0 };
