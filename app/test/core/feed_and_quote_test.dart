import 'dart:io';

import 'package:book_reel/core/models/reel_card.dart';
import 'package:book_reel/core/parsing/epub_parser.dart';
import 'package:book_reel/core/segmentation/feed_builder.dart';
import 'package:book_reel/core/segmentation/rule_segmenter.dart';
import 'package:book_reel/core/share/quote_limit.dart';
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
    final textCards = feed.where((f) => f.kind == CardKind.text).length;
    expect(textCards, segments.values.fold(0, (s, c) => s + c.cards.length));
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
