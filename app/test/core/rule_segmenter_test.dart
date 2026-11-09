import 'dart:io';

import 'package:book_reel/core/models/book.dart';
import 'package:book_reel/core/parsing/block_builder.dart';
import 'package:book_reel/core/parsing/epub_parser.dart';
import 'package:book_reel/core/segmentation/rule_segmenter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final book = const EpubParser().parse(File('assets/books/alice.epub').readAsBytesSync()).content;

  for (final length in CardLength.values) {
    test('covers every sentence exactly once, in order (${length.name})', () {
      final segmenter = RuleSegmenter(length: length);
      var inBand = 0;
      var total = 0;
      for (final chapter in book.chapters) {
        final cards = segmenter.segment(chapter).cards;
        final expected = chapter.blocks.where((b) => !isSceneBreakBlock(b)).expand((b) => b.sentences).map((s) => s.id).toList();
        expect(cards.expand((c) => c.sentenceIds).toList(), expected);
        for (final c in cards) {
          total++;
          if (c.wordCount >= length.min && c.wordCount <= length.max) inBand++;
          expect(c.startSid, c.sentenceIds.first);
          expect(c.endSid, c.sentenceIds.last);
        }
      }
      // Dialogue-heavy fiction is the hardest case; most cards must still fit the band.
      expect(inBand / total, greaterThan(0.85), reason: '$inBand of $total cards in band');
    });
  }

  test('keeps headings attached to the following text and avoids cutting inside quotes', () {
    final chapter = Chapter(
      index: 0,
      title: 'T',
      blocks: buildBlocks(0, [
        RawBlock(BlockType.paragraph, List.filled(12, 'This is a fairly ordinary sentence about habits.').join(' ')),
        const RawBlock(BlockType.heading, 'The Second Idea'),
        RawBlock(BlockType.paragraph, List.filled(12, 'Another plain sentence follows the heading here.').join(' ')),
        RawBlock(BlockType.quote, List.filled(6, 'A quoted line that belongs together.').join('\n')),
      ]),
    );
    final cards = const RuleSegmenter().segment(chapter).cards;
    for (final c in cards) {
      // A card never ends on a heading.
      expect(c.endSid, isNot('c0.b1.s0'));
    }
    final quoteSids = chapter.blocks[3].sentences.map((s) => s.id).toSet();
    final cardsWithQuote = cards.where((c) => c.sentenceIds.any(quoteSids.contains)).toList();
    expect(cardsWithQuote, hasLength(1));
  });

  test('scene breaks are strong cut points and are not part of any card', () {
    final para = List.filled(9, 'The night was quiet and the road was long.').join(' ');
    final chapter = Chapter(
      index: 0,
      title: 'T',
      blocks: buildBlocks(0, [
        RawBlock(BlockType.paragraph, para),
        const RawBlock(BlockType.paragraph, '* * *'),
        RawBlock(BlockType.paragraph, para),
      ]),
    );
    final cards = const RuleSegmenter().segment(chapter).cards;
    expect(cards, hasLength(2));
    expect(cards.first.endSid, 'c0.b0.s8');
    expect(cards.last.startSid, 'c0.b2.s0');
  });

  test('picks a key sentence only when there is a clear cue', () {
    final chapter = Chapter(
      index: 0,
      title: 'T',
      blocks: buildBlocks(0, [
        const RawBlock(BlockType.paragraph,
            'Small habits compound over time. The key lesson is that you must focus on systems, not goals. Most people never notice.'),
      ]),
    );
    final card = const RuleSegmenter(length: CardLength.bite).segment(chapter).cards.single;
    expect(card.keySids, ['c0.b0.s1']);
  });
}
