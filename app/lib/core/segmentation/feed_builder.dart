import '../models/book.dart';
import '../models/reel_card.dart';

class FeedOptions {
  const FeedOptions({this.recallCards = true, this.reflectCards = true, this.recallEvery = 10});

  final bool recallCards;
  final bool reflectCards;
  final int recallEvery;
}

/// Turns per-chapter segments into the reader feed: chapter cards, text cards,
/// recap/recall cards, reflect cards at chapter ends and a final milestone
/// (DESIGN.md §2.2, UX_DESIGN.md §5.2).
List<FeedItem> buildFeed(BookContent book, Map<int, ChapterSegments> segments, FeedOptions options) {
  final feed = <FeedItem>[];
  for (final chapter in book.chapters) {
    final seg = segments[chapter.index];
    if (seg == null || seg.cards.isEmpty) continue;
    final total = seg.cards.length;
    feed.add(FeedItem(
      kind: CardKind.chapterTitle,
      chapterIndex: chapter.index,
      cardsInChapter: total,
      teaser: seg.teaser,
    ));
    for (var i = 0; i < total; i++) {
      feed.add(FeedItem(
        kind: CardKind.text,
        chapterIndex: chapter.index,
        card: seg.cards[i],
        cardIndexInChapter: i,
        cardsInChapter: total,
      ));
      final recap = seg.recaps[i];
      if (recap != null && recap.isNotEmpty) {
        feed.add(FeedItem(kind: CardKind.recap, chapterIndex: chapter.index, recapBullets: recap));
      }
      if (options.recallCards) {
        final aiRecall = seg.recalls[i];
        if (aiRecall != null) {
          feed.add(FeedItem(kind: CardKind.recall, chapterIndex: chapter.index, recall: aiRecall));
        } else if (seg.source == SegmentSource.rules && (i + 1) % options.recallEvery == 0 && i < total - 1) {
          final keys = seg.cards
              .sublist(i + 1 - options.recallEvery, i + 1)
              .expand((c) => c.keySids)
              .toList();
          if (keys.isNotEmpty) {
            feed.add(FeedItem(kind: CardKind.recall, chapterIndex: chapter.index, recallSids: keys.take(3).toList()));
          }
        }
      }
    }
    if (options.reflectCards && total >= 5) {
      feed.add(FeedItem(kind: CardKind.reflect, chapterIndex: chapter.index));
    }
  }
  if (feed.isNotEmpty) {
    feed.add(FeedItem(kind: CardKind.milestone, chapterIndex: book.chapters.last.index));
  }
  return feed;
}

/// Index of the feed item that contains [sid], or the closest earlier text card.
int feedIndexForSid(List<FeedItem> feed, String? sid) {
  if (sid == null) return 0;
  final target = parseSid(sid);
  if (target == null) return 0;
  var best = 0;
  for (var i = 0; i < feed.length; i++) {
    final card = feed[i].card;
    if (card == null) continue;
    if (card.sentenceIds.contains(sid)) return i;
    final start = parseSid(card.startSid)!;
    final before = start.chapter < target.chapter ||
        (start.chapter == target.chapter &&
            (start.block < target.block || (start.block == target.block && start.sentence <= target.sentence)));
    if (before) best = i;
  }
  return best;
}
