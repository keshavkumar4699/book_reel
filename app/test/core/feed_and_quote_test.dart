import 'dart:io';
import 'dart:ui' show Size;

import 'package:book_reel/core/models/book.dart';
import 'package:book_reel/core/models/reel_card.dart';
import 'package:book_reel/core/parsing/epub_parser.dart';
import 'package:book_reel/core/segmentation/feed_builder.dart';
import 'package:book_reel/core/segmentation/rule_segmenter.dart';
import 'package:book_reel/core/share/quote_limit.dart';
import 'package:book_reel/core/text/lyric_layout.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final book = const EpubParser().parse(File('assets/books/alice.epub').readAsBytesSync()).content;
  final segments = {for (final c in book.chapters) c.index: const RuleSegmenter().segment(c)};

  test('feed has chapter cards, text cards, reflect cards and a final milestone', () {
    final feed = buildFeed(book, segments, const FeedOptions());
    expect(feed.first.kind, CardKind.chapterTitle);
    expect(feed.last.kind, CardKind.milestone);
    expect(feed.where((f) => f.kind == CardKind.chapterTitle), hasLength(11));
    expect(feed.where((f) => f.kind == CardKind.reflect), isNotEmpty);
    // Each card ends in exactly one reel (a split card has several).
    final lastParts = feed.where((f) => f.kind == CardKind.text && f.lastPart).length;
    expect(lastParts, segments.values.fold(0, (s, c) => s + c.cards.length));
    final plain = buildFeed(book, segments, const FeedOptions(spotlights: false));
    expect(plain.where((f) => f.kind == CardKind.text).length, lastParts);
    expect(plain.any((f) => f.spotlight || f.sids != null), isFalse);
  });

  test('spotlight reels: one short sentence, parts cover the card in order, spaced out', () {
    final feed = buildFeed(book, segments, const FeedOptions());
    final words = {for (final c in book.chapters) for (final s in c.sentences) s.id: s.wordCount};
    final spots = feed.where((f) => f.spotlight).toList();
    expect(spots, isNotEmpty);
    for (final f in spots) {
      expect(f.shownSids, hasLength(1));
      expect(words[f.shownSids.single], inInclusiveRange(spotlightMinWords, spotlightMaxWords));
    }
    // The reels of each card show all of its sentences, in order, once.
    final byCard = <String, List<String>>{};
    for (final f in feed.where((f) => f.kind == CardKind.text)) {
      byCard.putIfAbsent('${f.chapterIndex}:${f.card!.startSid}', () => []).addAll(f.shownSids);
    }
    for (final seg in segments.values) {
      for (final c in seg.cards) {
        expect(byCard['${c.chapterIndex}:${c.startSid}'], c.sentenceIds);
      }
    }
    // Text left beside a spotlight is a real reel, not a scrap.
    for (final f in feed.where((f) => f.kind == CardKind.text && f.sids != null && !f.spotlight)) {
      expect(f.shownSids.fold(0, (n, id) => n + words[id]!), greaterThanOrEqualTo(spotlightMinRemainder));
    }
    // Rule-based spotlights are at least spotlightGapRules reels apart.
    var last = -1000;
    for (var i = 0; i < feed.length; i++) {
      if (feed[i].kind == CardKind.chapterTitle) last = -1000;
      if (!feed[i].spotlight) continue;
      final reels = feed.sublist(last < 0 ? 0 : last + 1, i).where((f) => f.kind == CardKind.text).length;
      if (last >= 0) expect(reels, greaterThanOrEqualTo(spotlightGapRules));
      last = i;
    }
  });

  test('reels hold at most a comfortable amount of text; longer cards continue on the next reel', () {
    const budget = 40;
    final feed = buildFeed(book, segments, const FeedOptions(maxReelWords: budget));
    final text = {for (final c in book.chapters) for (final s in c.sentences) s.id: s};
    final reels = feed.where((f) => f.kind == CardKind.text).toList();
    final continued = reels.where((f) => f.lines != null).toList();
    expect(continued, isNotEmpty, reason: 'Alice has sentences far longer than one reel');
    var over = 0;
    for (final f in reels) {
      final words = f.words ?? f.card!.wordCount;
      // Only a clause with no natural break can exceed the budget.
      if (words > budget * 1.1) over++;
      if (f.lines != null) {
        expect(f.spotlight, isFalse);
        expect(f.lineSids, isNotEmpty);
        expect(f.shownSids, contains(f.anchorSid));
        expect(f.layoutSids, containsAll(f.shownSids));
      }
    }
    expect(over / reels.length, lessThan(0.02));
    // Every card still ends in exactly one reel, and its reels cover its sentences in order.
    expect(reels.where((f) => f.lastPart).length, segments.values.fold(0, (s, c) => s + c.cards.length));
    final byCard = <String, List<String>>{};
    for (final f in reels) {
      final seen = byCard.putIfAbsent('${f.chapterIndex}:${f.card!.startSid}', () => []);
      for (final sid in f.shownSids) {
        if (seen.isEmpty || seen.last != sid) seen.add(sid);
      }
    }
    for (final seg in segments.values) {
      for (final c in seg.cards) {
        expect(byCard['${c.chapterIndex}:${c.startSid}'], c.sentenceIds);
      }
    }
    // Continued reels show consecutive line ranges that cover the text exactly once.
    final blocks = {for (final c in book.chapters) for (final b in c.blocks) for (final s in b.sentences) s.id: b};
    for (var i = 0; i < reels.length; i++) {
      final f = reels[i];
      if (f.lines == null) continue;
      final previous = i > 0 && identical(reels[i - 1].card, f.card) && reels[i - 1].lines != null && reels[i - 1].sids == f.sids
          ? reels[i - 1]
          : null;
      expect(f.lines!.from, previous?.lines!.to ?? 0, reason: f.anchorSid);
      final next = i + 1 < reels.length && identical(reels[i + 1].card, f.card) && reels[i + 1].lines != null && reels[i + 1].sids == f.sids;
      if (!next) {
        final pieces = piecesForCard(f.card!, [
          for (final id in f.layoutSids) (sid: id, text: text[id]!.text, block: blocks[id]!.index, type: blocks[id]!.type),
        ]);
        expect(f.lines!.to, pieces.length, reason: f.anchorSid);
      }
    }
    // Word counts add up (a dash can count a joined pair of words as two).
    final cardWords = <String, int>{};
    for (final f in reels) {
      final key = '${f.chapterIndex}:${f.card!.startSid}';
      cardWords[key] = (cardWords[key] ?? 0) + (f.words ?? f.card!.wordCount);
    }
    for (final seg in segments.values) {
      for (final c in seg.cards) {
        final expected = c.sentenceIds.fold(0, (n, id) => n + text[id]!.wordCount);
        final dashes = c.sentenceIds.fold(0, (n, id) => n + '--'.allMatches(text[id]!.text).length);
        expect(cardWords['${c.chapterIndex}:${c.startSid}'], closeTo(expected, dashes), reason: c.startSid);
      }
    }
    // Every reel's reading position (sentence + offset inside it) leads back to that reel,
    // even when one long sentence runs over several reels.
    var shared = 0;
    for (var i = 0; i < feed.length; i++) {
      final f = feed[i];
      if (f.kind != CardKind.text) continue;
      expect(feedIndexForSid(feed, f.anchorSid, offset: f.offset ?? 0), i, reason: '${f.anchorSid}@${f.offset}');
      if (i > 0 && feed[i - 1].kind == CardKind.text && feed[i - 1].anchorSid == f.anchorSid) shared++;
    }
    expect(shared, greaterThan(0), reason: 'Alice has sentences spanning several reels');
    // A plain sentence position (from a highlight or an older save) opens where the sentence starts.
    final target = continued.firstWhere((f) => (f.offset ?? 0) > 0);
    final at = feedIndexForSid(feed, target.anchorSid);
    expect(feed[at].shownSids, contains(target.anchorSid));
    expect(at, lessThan(feed.indexOf(target)));
    // No budget, no continuation.
    expect(buildFeed(book, segments, const FeedOptions()).any((f) => f.lines != null), isFalse);
  });

  test('the reel budget follows the screen, the font size and the chosen card length', () {
    int budget({Size screen = const Size(412, 915), double font = 22, CardLength length = CardLength.snack, double scale = 1}) =>
        reelWordBudget(screen: screen, topInset: 32, bottomInset: 20, fontSize: font, length: length, textScale: scale);
    final phone = budget();
    expect(phone, inInclusiveRange(34, 52));
    expect(budget(screen: const Size(360, 720)), lessThan(phone));
    expect(budget(font: 30), lessThan(phone));
    expect(budget(scale: 1.3), budget(font: 22 * 1.3));
    expect(budget(length: CardLength.deep), greaterThan(budget(length: CardLength.standard)));
    expect(budget(length: CardLength.standard), greaterThan(phone));
    // Always a usable amount, even on a tiny screen with huge text.
    expect(budget(screen: const Size(320, 480), font: 32, scale: 2), greaterThanOrEqualTo(14));
  });

  test('AI hero lines become spotlights; too-long lines stay inline', () {
    Sentence sen(String id, String t) => Sentence(id: id, text: t);
    final chapter = Chapter(index: 0, title: 'One', blocks: [
      Block(index: 0, type: BlockType.paragraph, sentences: [
        sen('c0.b0.s0', 'Alice was beginning to get very tired of sitting by her sister on the bank.'),
        sen('c0.b0.s1', 'Curiouser and curiouser!'),
        sen('c0.b0.s2', 'She was so much surprised that for the moment she quite forgot how to speak good English, and stood there for a while.'),
      ]),
    ]);
    final b = BookContent(title: 'T', author: 'A', chapters: [chapter]);
    SegmentCard card(List<Emphasis> e) => SegmentCard(
          chapterIndex: 0,
          startSid: 'c0.b0.s0',
          endSid: 'c0.b0.s2',
          sentenceIds: const ['c0.b0.s0', 'c0.b0.s1', 'c0.b0.s2'],
          wordCount: 36,
          emphasis: e,
          layout: 'left',
        );
    final hero = buildFeed(b, {
      0: ChapterSegments(chapterIndex: 0, source: SegmentSource.ai, cards: [card(const [Emphasis(sid: 'c0.b0.s1', text: 'Curiouser and curiouser!', level: 3)])]),
    }, const FeedOptions(reflectCards: false));
    final reels = hero.where((f) => f.kind == CardKind.text).toList();
    expect(reels.map((f) => (f.shownSids.join(','), f.spotlight, f.lastPart)), [
      ('c0.b0.s0', false, false),
      ('c0.b0.s1', true, false),
      ('c0.b0.s2', false, true),
    ]);
    expect(feedIndexForSid(hero, 'c0.b0.s2'), hero.indexOf(reels.last));
    // A level-2 phrase or an over-long hero sentence keeps the card whole.
    final inline = buildFeed(b, {
      0: ChapterSegments(chapterIndex: 0, source: SegmentSource.ai, cards: [card(const [Emphasis(sid: 'c0.b0.s2', text: 'quite forgot', level: 3)])]),
    }, const FeedOptions(reflectCards: false));
    expect(inline.where((f) => f.kind == CardKind.text).single.sids, isNull);
  });

  test('options turn off recall and reflect cards', () {
    final feed = buildFeed(book, segments, const FeedOptions(recallCards: false, reflectCards: false));
    expect(feed.where((f) => f.kind == CardKind.reflect || f.kind == CardKind.recall), isEmpty);
  });

  test('finds the feed position for a sentence ID, even after re-segmenting', () {
    final feed = buildFeed(book, segments, const FeedOptions());
    final target = segments[3]!.cards[4];
    final idx = feedIndexForSid(feed, target.sentenceIds.last);
    expect(feed[idx].card!.sentenceIds, contains(target.sentenceIds.last));

    final bite = {for (final c in book.chapters) c.index: const RuleSegmenter(length: CardLength.bite).segment(c)};
    final biteFeed = buildFeed(book, bite, const FeedOptions());
    final idx2 = feedIndexForSid(biteFeed, target.sentenceIds.last);
    expect(biteFeed[idx2].card!.sentenceIds, contains(target.sentenceIds.last));
  });

  test('a cached feed lays out only chapters whose cards changed, and matches a fresh build', () {
    const options = FeedOptions(maxReelWords: 45);
    final cache = FeedCache();
    final first = buildFeed(book, segments, options, cache: cache);
    // Recaps added to chapter 2 (as the on-device model does): the cards are the same objects.
    final seg = segments[2]!;
    final withRecap = {
      ...segments,
      2: ChapterSegments(chapterIndex: 2, cards: seg.cards, source: seg.source, recaps: {...seg.recaps, 3: ['A recap.']}, recalls: seg.recalls),
    };
    final second = buildFeed(book, withRecap, options, cache: cache);
    expect(second.length, first.length + 1);
    final firstText = first.where((f) => f.kind == CardKind.text).toList();
    final secondText = second.where((f) => f.kind == CardKind.text).toList();
    expect(secondText.length, firstText.length);
    for (var i = 0; i < firstText.length; i++) {
      expect(identical(firstText[i], secondText[i]), isTrue, reason: 'reel $i reused');
    }
    // A chapter cut again (other cards) is laid out again; the rest stay.
    final recut = {...withRecap, 4: const RuleSegmenter(length: CardLength.bite).segment(book.chapters[4])};
    final third = buildFeed(book, recut, options, cache: cache);
    expect(third.where((f) => f.chapterIndex == 4 && f.kind == CardKind.text).every((f) => identical(f.card, recut[4]!.cards[f.cardIndexInChapter!])), isTrue);
    expect(identical(third.firstWhere((f) => f.chapterIndex == 3 && f.kind == CardKind.text), firstText.firstWhere((f) => f.chapterIndex == 3)), isTrue);
    // The same feed as without the cache, reel for reel.
    final fresh = buildFeed(book, recut, options);
    expect(third.length, fresh.length);
    for (var i = 0; i < fresh.length; i++) {
      expect((third[i].kind, third[i].anchorSid, third[i].lines, third[i].lastPart, third[i].spotlight),
          (fresh[i].kind, fresh[i].anchorSid, fresh[i].lines, fresh[i].lastPart, fresh[i].spotlight),
          reason: 'item $i');
    }
    // Another text size lays everything out again.
    final larger = buildFeed(book, recut, const FeedOptions(maxReelWords: 30), cache: cache);
    expect(larger.length, greaterThan(third.length));
  });

  test('after a rebuild the reader stays on the same reel, recap or quiz card; never back on read text', () {
    const options = FeedOptions(maxReelWords: 45);
    final cache = FeedCache();
    final old = buildFeed(book, segments, options, cache: cache);
    // A quick check in chapter 1 (rule cards get one every 10 cards).
    final recall = old.indexWhere((f) => f.kind == CardKind.recall && f.chapterIndex == 1);
    expect(recall, greaterThan(0));
    // Recaps arrive for chapter 1 before and after the reader's place, and for chapter 2.
    final s1 = segments[1]!, s2 = segments[2]!;
    final more = {
      ...segments,
      1: ChapterSegments(chapterIndex: 1, cards: s1.cards, source: s1.source, recaps: {0: ['Earlier.'], 9: ['Here.'], 14: ['Later.']}),
      2: ChapterSegments(chapterIndex: 2, cards: s2.cards, source: s2.source, recaps: {0: ['Next chapter.']}),
    };
    final feed = buildFeed(book, more, options, cache: cache);
    final at = feedIndexAfterRebuild(old, recall, feed);
    expect(feed[at].kind, CardKind.recall, reason: 'still on the quick check');
    expect(at, recall + 2, reason: 'the recap at card 0 and the one just before it came in earlier');
    // On a text reel: the very same reel.
    final text = old.indexWhere((f) => f.kind == CardKind.text && f.chapterIndex == 1 && f.cardIndexInChapter == 12);
    expect(identical(feed[feedIndexAfterRebuild(old, text, feed)], old[text]), isTrue);
    // On a chapter card: the same chapter card.
    final title = old.indexWhere((f) => f.kind == CardKind.chapterTitle && f.chapterIndex == 2);
    final t2 = feedIndexAfterRebuild(old, title, feed);
    expect((feed[t2].kind, feed[t2].chapterIndex), (CardKind.chapterTitle, 2));
    // The quick checks turned off: the reel after the text read last, not that text again.
    final none = buildFeed(book, more, const FeedOptions(maxReelWords: 45, recallCards: false), cache: cache);
    final moved = feedIndexAfterRebuild(old, recall, none);
    final lastRead = old.lastIndexWhere((f) => f.kind == CardKind.text, recall);
    expect(identical(none[moved - 1], old[lastRead]) || none[moved].kind == CardKind.recap, isTrue);
    expect(moved, greaterThan(none.indexWhere((f) => identical(f, old[lastRead]))));
  });

  test('quote limit keeps whole sentences up to 75 words for copyrighted books', () {
    final sentences = List.generate(15, (i) => 'Sentence n$i has exactly seven words here.');
    final limited = limitQuote(sentences, publicDomain: false);
    expect(limited.truncated, isTrue);
    expect(limited.text.split(' ').length, lessThanOrEqualTo(75));
    expect(limitQuote(sentences, publicDomain: true).truncated, isFalse);
    final long = limitQuote([List.filled(100, 'word').join(' ')], publicDomain: false);
    expect(long.text, endsWith('…'));
  });
}
