import 'dart:math' as math;
import 'dart:ui' show Size;

import '../models/book.dart';
import '../models/reel_card.dart';
import '../segmentation/rule_segmenter.dart' show CardLength;

/// One display line of a card in the lyric-style layout: a phrase of the
/// author's text. Every line of a reel has the same size; [level] > 1 marks
/// emphasis (brighter colour, heavier weight). Hero lines get a spotlight reel
/// of their own (feed_builder.dart), so big and small type never mix.
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

/// Clause boundaries inside plain text: after , ; : or around dashes
/// (spaced, or unspaced between words: "simply—never", "is--be").
final RegExp _clauseBreak = RegExp(
  r'(?<=[,;:])\s+|\s+(?=[—–]\s)|(?<=\s[—–])\s+|(?<=[\p{L}"\x27’”!?](?:[—–]|--))(?=["\x27‘“\p{L}])',
  unicode: true,
);

/// Splits a card into display lines: AI [emphasis] phrases become their own
/// lines, the rest is split at clause boundaries (phrase-per-line reading).
/// Without AI direction, the card's key sentence is emphasised (free tier).
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

/// Free-tier emphasis: the card's key sentence, when it is short enough to
/// work as a stressed phrase (a long emphasised sentence stresses nothing).
List<LyricPiece> _heuristicLevels(List<LyricPiece> pieces, List<LyricSentence> sentences, Set<String> keySids) {
  if (pieces.length <= 1 || keySids.isEmpty) return pieces;
  final key = sentences.where((s) => keySids.contains(s.sid)).firstOrNull;
  if (key == null || _words(key.text) > 14) return pieces;
  return [for (final p in pieces) p.sid == key.sid ? p.copyWith(level: 2) : p];
}

/// The display lines of [sentences] (a card, or one part of it) with the
/// card's art direction. The feed builder and the reel widget both use this,
/// so line ranges ([chunkPieces]) mean the same thing in both.
List<LyricPiece> piecesForCard(SegmentCard card, List<LyricSentence> sentences) => buildLyricPieces(
      sentences,
      emphasis: card.emphasis,
      keySids: card.keySids.toSet(),
      // Cards that went through AI art direction always carry a layout.
      aiDirected: card.layout != null,
    );

/// Emphasis only works as contrast: when more than 40 % of the words on a
/// reel would be emphasised, keep the first emphasised line if it is small
/// enough, otherwise none.
List<LyricPiece> limitEmphasis(List<LyricPiece> pieces) {
  final total = pieces.fold(0, (n, p) => n + _words(p.text));
  final marked = pieces.where((p) => p.level > 1).fold(0, (n, p) => n + _words(p.text));
  if (marked == 0 || marked <= total * 0.4) return pieces;
  final first = pieces.indexWhere((p) => p.level > 1);
  final keep = _words(pieces[first].text) <= total * 0.4 ? first : -1;
  return [
    for (var i = 0; i < pieces.length; i++)
      i == keep || pieces[i].level == 1 ? pieces[i] : pieces[i].copyWith(level: 1),
  ];
}

int lyricWords(Iterable<LyricPiece> pieces) => pieces.fold(0, (n, p) => n + _words(p.text));

/// Splits a reel's lines into consecutive ranges of at most about [maxWords]
/// words each, so a long sentence continues on the next reel instead of
/// filling the screen. Reels come out as even as the lines allow, never
/// over the budget when that can be avoided, and preferably end where a
/// sentence ends. Returns a single range when everything fits.
List<({int from, int to})> chunkPieces(List<LyricPiece> pieces, int maxWords) {
  final whole = [(from: 0, to: pieces.length)];
  final m = pieces.length;
  if (maxWords <= 0 || m < 2) return whole;
  final cum = <int>[0];
  for (final p in pieces) {
    cum.add(cum.last + _words(p.text));
  }
  final total = cum.last;
  if (total <= maxWords) return whole;

  // Cost of one reel holding lines [a, b).
  double cost(int a, int b, double target) {
    final words = cum[b] - cum[a];
    var c = (words - target) * (words - target);
    // The budget is an estimate: a tenth over is fine, more is not.
    final over = words - maxWords * 1.1;
    if (over > 0) c += 400.0 * over * over;
    // Ending on a full sentence reads better than stopping mid-sentence.
    if (b < m && pieces[b].sid != pieces[b - 1].sid) c -= target * target * 0.06;
    return c;
  }

  List<int>? bestBreaks;
  var bestCost = double.infinity;
  final least = (total / maxWords).ceil();
  // One more reel than strictly needed is allowed when it avoids an overfull one.
  for (var k = least; k <= math.min(least + 1, m); k++) {
    final target = total / k;
    // dp[j][i]: cheapest way to put the first i lines on j reels.
    final dp = List.generate(k + 1, (_) => List.filled(m + 1, double.infinity));
    final from = List.generate(k + 1, (_) => List.filled(m + 1, 0));
    dp[0][0] = 0;
    for (var j = 1; j <= k; j++) {
      for (var i = j; i <= m - (k - j); i++) {
        for (var a = j - 1; a < i; a++) {
          if (dp[j - 1][a] == double.infinity) continue;
          final c = dp[j - 1][a] + cost(a, i, target);
          if (c < dp[j][i]) {
            dp[j][i] = c;
            from[j][i] = a;
          }
        }
      }
    }
    // An extra reel must earn its place.
    final c = dp[k][m] + (k - least) * maxWords * maxWords * 0.3;
    if (c < bestCost) {
      bestCost = c;
      final breaks = <int>[];
      var i = m;
      for (var j = k; j > 0; j--) {
        breaks.add(i);
        i = from[j][i];
      }
      bestBreaks = breaks.reversed.toList();
    }
  }
  if (bestBreaks == null) return whole;
  final out = <({int from, int to})>[];
  var prev = 0;
  for (final b in bestBreaks) {
    out.add((from: prev, to: b));
    prev = b;
  }
  return out;
}

/// The part of a spotlight line drawn in the spotlight colour: the AI's hero
/// phrase, or the whole line (same size either way).
({int start, int end}) spotlightFocus(String text, List<Emphasis> emphasis, String sid) {
  for (final e in emphasis.where((e) => e.sid == sid && e.level >= 3)) {
    var at = text.indexOf(e.text);
    if (at < 0) at = text.toLowerCase().indexOf(e.text.toLowerCase());
    if (at < 0) continue;
    if (_words(e.text) >= _words(text) * 0.75) break;
    return (start: at, end: at + e.text.length);
  }
  return (start: 0, end: text.length);
}

enum LyricAlign { centered, left, staggered }

/// The AI's layout when valid; otherwise dialogue → staggered, a few short
/// lines → centered, anything longer → left-aligned (easier to read).
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
  return words <= 20 ? LyricAlign.centered : LyricAlign.left;
}

// ---------------------------------------------------------------------------
// Reel geometry

/// Where a reel's text may sit: below the top bar and above the book row, and
/// never in the top or bottom fifth of the screen, so the scene always shows
/// above and below the words (and text stays where the scene's shade gives
/// it full contrast).
({double top, double bottom}) reelTextInsets({required Size screen, required double topInset, required double bottomInset}) {
  final gap = (screen.height * 0.055).clamp(20.0, 60.0);
  return (
    top: math.max(topInset + 70 + gap, screen.height * 0.2),
    bottom: math.max(bottomInset + 92 + gap * 0.6, screen.height * 0.2),
  );
}

/// Widest text column (a comfortable measure on tablets too).
const reelMaxTextWidth = 540.0;

/// Space kept free beside the text: the margin, and the action rail.
const reelSideMargin = 30.0, reelRailMargin = 78.0;

/// How many words sit comfortably on one reel at the reader's font size: the
/// text may use only part of the text area, so there is always air around it.
/// Readers who choose longer cards accept denser reels.
int reelWordBudget({
  required Size screen,
  required double topInset,
  required double bottomInset,
  required double fontSize,
  required CardLength length,
  double textScale = 1,
}) {
  final insets = reelTextInsets(screen: screen, topInset: topInset, bottomInset: bottomInset);
  final height = screen.height - insets.top - insets.bottom;
  final width = math.min(reelMaxTextWidth, screen.width - reelSideMargin - reelRailMargin);
  final size = fontSize * textScale;
  // About half an em per character and 5.7 characters per word with its
  // space; a phrase per line leaves roughly a sixth of each line unused.
  final wordsPerLine = width / (size * 0.5) / 5.7 * 0.84;
  final lineHeight = size * 1.5 + size * 0.12;
  final fill = switch (length) {
    CardLength.snack => 0.68,
    CardLength.bite => 0.76,
    CardLength.standard => 0.86,
    CardLength.deep => 0.94,
  };
  final lines = height * fill / lineHeight;
  return (lines * wordsPerLine).floor().clamp(14, 90);
}
