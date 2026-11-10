import 'package:book_reel/core/models/book.dart';
import 'package:book_reel/core/models/reel_card.dart';
import 'package:book_reel/features/reader/cards/lyric_layout.dart';
import 'package:flutter_test/flutter_test.dart';

LyricSentence s(String sid, String text, {int block = 0, BlockType type = BlockType.paragraph}) =>
    (sid: sid, text: text, block: block, type: type);

void main() {
  test('AI emphasis phrases become their own big lines, the rest stays regular', () {
    const text = 'Small habits compound over time, and the key lesson is that systems beat goals.';
    final pieces = buildLyricPieces([
      s('c0.b0.s0', text),
    ], emphasis: const [Emphasis(sid: 'c0.b0.s0', text: 'systems beat goals', level: 3)]);
    expect(pieces.map((p) => (p.text, p.level)).toList(), [
      ('Small habits compound over time,', 1),
      ('and the key lesson is that', 1),
      ('systems beat goals.', 3), // trailing punctuation joins the phrase
    ]);
    expect(pieces.last.start, text.indexOf('systems'));
  });

  test('case-insensitive emphasis keeps the author\'s casing; overlapping phrases are ignored', () {
    final pieces = buildLyricPieces([
      s('c0.b0.s0', 'Down, down, down. Would the fall never come to an end?'),
    ], emphasis: const [
      Emphasis(sid: 'c0.b0.s0', text: 'would the fall never come to an end', level: 2),
      Emphasis(sid: 'c0.b0.s0', text: 'never come', level: 3),
    ]);
    expect(pieces.where((p) => p.level == 2).single.text, 'Would the fall never come to an end?');
    expect(pieces.any((p) => p.level == 3), isFalse);
  });

  test('long plain sentences split at clause breaks; tiny fragments merge', () {
    final pieces = buildLyricPieces([
      s('a', 'So she was considering in her own mind, as well as she could, for the hot day made her feel very sleepy and stupid, whether the pleasure would be worth it.'),
    ]);
    expect(pieces.length, greaterThanOrEqualTo(3));
    expect(pieces.every((p) => p.text.split(' ').length >= 3), isTrue);
    expect(pieces.map((p) => p.text).join(' '), contains('whether the pleasure would be worth it.'));
  });

  test('new paragraphs are marked so they get extra space', () {
    final pieces = buildLyricPieces([
      s('c0.b0.s0', 'First paragraph has a few words in it.', block: 0),
      s('c0.b1.s0', 'Second paragraph starts here with more words.', block: 1),
    ]);
    expect(pieces.first.newBlock, isFalse);
    expect(pieces.last.newBlock, isTrue);
  });

  test('free tier: key sentence and short punchy lines get bigger, capped', () {
    final pieces = buildLyricPieces([
      s('a', 'The rabbit ran past her and vanished down a large hole under the hedge.'),
      s('b', 'Down she went!'),
      s('c', 'Never once did she stop to think.'),
    ], keySids: {'c'});
    expect(pieces.firstWhere((p) => p.sid == 'b').level, 2);
    expect(pieces.firstWhere((p) => p.sid == 'c').level, 3);
    expect(pieces.firstWhere((p) => p.sid == 'a').level, 1);
    expect(pieces.where((p) => p.level == 3), hasLength(1));
  });

  test('layout: AI choice when valid, else dialogue staggered, short centered', () {
    final short = buildLyricPieces([s('a', 'Curiouser and curiouser!')]);
    expect(lyricAlignFor(null, short), LyricAlign.centered);
    expect(lyricAlignFor('left', short), LyricAlign.left);
    expect(lyricAlignFor('spiral', short), LyricAlign.centered);
    final dialogue = buildLyricPieces([
      s('a', '"Who are you?" said the Caterpillar.', block: 0, type: BlockType.dialogue),
      s('b', '"I hardly know, sir, just at present."', block: 1, type: BlockType.dialogue),
    ]);
    expect(lyricAlignFor(null, dialogue), LyricAlign.staggered);
    expect(levelScale(3) > levelScale(2) && levelScale(2) > levelScale(1), isTrue);
  });

  test('closing punctuation stays with the previous line, opening with the next', () {
    const text = 'In another moment down went Alice after it, never once considering how she would get out.';
    final pieces = buildLyricPieces([s('c0.b3.s0', text)],
        emphasis: const [Emphasis(sid: 'c0.b3.s0', text: 'down went Alice after it', level: 3)]);
    expect(pieces.map((p) => p.text), ['In another moment', 'down went Alice after it,', 'never once considering how she would get out.']);
    for (final p in pieces) {
      expect(text.substring(p.start, p.end), p.text);
    }
    const paren = 'She felt very sleepy and stupid (as well as she could, for the day was hot), whether the pleasure was worth it.';
    final more = buildLyricPieces([s('x', paren)], emphasis: const [Emphasis(sid: 'x', text: 'very sleepy and stupid', level: 2)]);
    expect(more.any((p) => p.text.startsWith(')') || p.text.startsWith(',')), isFalse);
    expect(more.any((p) => p.text.endsWith('(')), isFalse);
  });

  test('AI-directed cards without emphasis stay plain (no heuristics)', () {
    final pieces = buildLyricPieces([
      s('a', 'A plain transitional line about walking.'),
      s('b', 'Down she went!'),
    ], aiDirected: true);
    expect(pieces.every((p) => p.level == 1), isTrue);
  });
}
