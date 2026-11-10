import 'package:book_reel/core/models/book.dart';
import 'package:book_reel/core/models/reel_card.dart';
import 'package:book_reel/core/text/lyric_layout.dart';
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

  test('free tier: only the key sentence is emphasised (same size, no heroes)', () {
    final pieces = buildLyricPieces([
      s('a', 'The rabbit ran past her and vanished down a large hole under the hedge.'),
      s('b', 'Down she went!'),
      s('c', 'Never once did she stop to think.'),
    ], keySids: {'c'});
    expect(pieces.firstWhere((p) => p.sid == 'c').level, 2);
    expect(pieces.firstWhere((p) => p.sid == 'b').level, 1);
    expect(pieces.firstWhere((p) => p.sid == 'a').level, 1);
    expect(pieces.any((p) => p.level == 3), isFalse);
  });

  test('spotlight focus is the hero phrase, or the whole line', () {
    const line = '‘Curiouser and curiouser!’ cried Alice.';
    final f = spotlightFocus(line, const [Emphasis(sid: 'x', text: 'Curiouser and curiouser!', level: 3)], 'x');
    expect(line.substring(f.start, f.end), 'Curiouser and curiouser!');
    expect(spotlightFocus(line, const [], 'x'), (start: 0, end: line.length));
    // A phrase covering most of the line colours all of it.
    const short = 'It was all very strange.';
    expect(spotlightFocus(short, const [Emphasis(sid: 'y', text: 'was all very strange', level: 3)], 'y'), (start: 0, end: short.length));
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
    final long = buildLyricPieces([
      s('a', 'Alice was beginning to get very tired of sitting by her sister on the bank, and of having nothing to do.'),
    ]);
    expect(lyricAlignFor(null, long), LyricAlign.left);
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

  test('emphasis never covers most of a reel', () {
    // A card that is only its key sentence stays plain.
    final solo = limitEmphasis(buildLyricPieces([
      s('a', 'In another moment down went Alice after it, never once considering how she would get out.'),
    ], keySids: {'a'}));
    expect(solo.every((p) => p.level == 1), isTrue);
    // A long key sentence is not stressed inline at all.
    final long = buildLyricPieces([
      s('a', 'The rabbit ran past her.'),
      s('b', 'She had never before seen a rabbit with either a waistcoat-pocket, or a watch to take out of it at all.'),
    ], keySids: {'b'});
    expect(long.every((p) => p.level == 1), isTrue);
    // Too much AI emphasis: only the first phrase survives.
    final pieces = limitEmphasis(buildLyricPieces([
      s('a', 'Down she went, never once considering how she would get out again.'),
    ], emphasis: const [
      Emphasis(sid: 'a', text: 'Down she went', level: 2),
      Emphasis(sid: 'a', text: 'how she would get out again', level: 2),
    ]));
    expect(pieces.where((p) => p.level > 1).map((p) => p.text), ['Down she went,']);
    // A sensible amount is left alone.
    final fine = buildLyricPieces([
      s('a', 'The rabbit-hole went straight on like a tunnel for some way, and then dipped suddenly down.'),
    ], emphasis: const [Emphasis(sid: 'a', text: 'dipped suddenly down', level: 2)]);
    expect(limitEmphasis(fine), same(fine));
  });

  test('long text is split into even reels at line ends, preferring sentence ends', () {
    final pieces = buildLyricPieces([
      s('a', 'It occurred to her that she ought to have wondered at this, but at the time it all seemed quite natural.'),
      s('b', 'But when the Rabbit actually took a watch out of its waistcoat-pocket, and looked at it, and then hurried on, '
          'Alice started to her feet, for it flashed across her mind that she had never before seen a rabbit with either a '
          'waistcoat-pocket, or a watch to take out of it.'),
      s('c', 'Burning with curiosity, she ran across the field after it.'),
    ]);
    final total = lyricWords(pieces);
    expect(chunkPieces(pieces, total), [(from: 0, to: pieces.length)]);
    expect(chunkPieces(pieces, 0), [(from: 0, to: pieces.length)]);
    final ranges = chunkPieces(pieces, 30);
    expect(ranges.length, (total / 30).ceil());
    // Consecutive, complete and in order.
    expect(ranges.first.from, 0);
    expect(ranges.last.to, pieces.length);
    for (var i = 1; i < ranges.length; i++) {
      expect(ranges[i].from, ranges[i - 1].to);
    }
    for (final r in ranges) {
      final words = lyricWords(pieces.sublist(r.from, r.to));
      expect(words, lessThanOrEqualTo(33), reason: 'at most a tenth over the budget');
      expect(words, greaterThanOrEqualTo(12), reason: 'no scraps');
    }
    // An extra reel is used when that is the only way to stay within the budget.
    final tight = chunkPieces(pieces, 27);
    for (final r in tight) {
      expect(lyricWords(pieces.sublist(r.from, r.to)), lessThanOrEqualTo(29));
    }
    // A split at a sentence end wins over a slightly more even one mid-sentence.
    final two = buildLyricPieces([
      s('a', 'One two three four five six seven eight nine ten, eleven twelve thirteen.'),
      s('b', 'One two three, four five six seven eight nine ten eleven twelve thirteen fourteen fifteen sixteen seventeen.'),
    ]);
    expect(two.map((p) => lyricWords([p])), [10, 3, 3, 14]);
    expect(chunkPieces(two, 20), [(from: 0, to: 2), (from: 2, to: 4)]);
  });

  test('unspaced dashes are clause breaks too', () {
    const text = 'And the moral of that is--"Be what you would seem to be"--or if you would like it put more simply--never imagine yourself otherwise.';
    final pieces = buildLyricPieces([s('a', text)]);
    expect(pieces.length, greaterThanOrEqualTo(3));
    expect(pieces.first.text, 'And the moral of that is--');
    // Nothing is lost or repeated at the breaks.
    expect(pieces.map((p) => p.text).join().replaceAll(' ', ''), text.replaceAll(' ', ''));
    for (final p in pieces) {
      expect(text.substring(p.start, p.end), p.text);
    }
    // Hyphenated words and number ranges are left alone.
    final plain = buildLyricPieces([s('b', 'She went down the rabbit-hole to-day between 1914–1918 and never once looked back at all.')]);
    expect(plain, hasLength(1));
  });

  test('AI-directed cards without emphasis stay plain (no heuristics)', () {
    final pieces = buildLyricPieces([
      s('a', 'A plain transitional line about walking.'),
      s('b', 'Down she went!'),
    ], aiDirected: true);
    expect(pieces.every((p) => p.level == 1), isTrue);
  });
}
