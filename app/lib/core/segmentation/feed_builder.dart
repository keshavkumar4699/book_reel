import '../models/book.dart';
import '../models/reel_card.dart';
import '../text/lyric_layout.dart';

class FeedOptions {
  const FeedOptions({
    this.recallCards = true,
    this.reflectCards = true,
    this.recallEvery = 10,
    this.spotlights = true,
    this.maxReelWords = 0,
  });

  final bool recallCards;
  final bool reflectCards;
  final int recallEvery;

  /// Give hero lines a reel of their own (UX_DESIGN.md Revision 4).
  final bool spotlights;

  /// Most words on one reel; longer text continues on the next reel.
  /// 0 = no limit. See `reelWordBudget` (lyric_layout.dart).
  final int maxReelWords;
}

/// Spotlight lines are whole sentences short enough to read at display size.
const spotlightMinWords = 3;
const spotlightMaxWords = 18;

/// Text left before or after a spotlight must make a reel of its own.
const spotlightMinRemainder = 8;

/// Reels between spotlights, so they stay special: the AI chooses its heroes
/// deliberately; on-device rules are only a guess, so they are rarer.
const spotlightGapAi = 4;
const spotlightGapRules = 7;

/// The sentence of [card] to show as a spotlight, or null.
String? spotlightSid(SegmentCard card, Sentence? Function(String sid) sentence, BlockType? Function(String sid) blockType) {
  final ai = card.layout != null || card.emphasis.isNotEmpty;
  final candidates = ai ? [for (final e in card.emphasis) if (e.level >= 3) e.sid] : card.keySids;
  for (final sid in candidates) {
    final s = sentence(sid);
    final type = blockType(sid);
    if (s == null || type == BlockType.heading || type == BlockType.list || type == BlockType.preformatted) continue;
    final words = s.wordCount;
    if (words < spotlightMinWords || words > (ai ? spotlightMaxWords : 14)) continue;
    final at = card.sentenceIds.indexOf(sid);
    if (at < 0) continue;
    int wordsOf(Iterable<String> ids) => ids.fold(0, (n, id) => n + (sentence(id)?.wordCount ?? 0));
    final before = wordsOf(card.sentenceIds.take(at));
    final after = wordsOf(card.sentenceIds.skip(at + 1));
    if ((before > 0 && before < spotlightMinRemainder) || (after > 0 && after < spotlightMinRemainder)) continue;
    return sid;
  }
  return null;
}

/// Text reels already laid out, by chapter. Rebuilding the feed (when recaps
/// or quick checks arrive, say) then lays out only the chapters whose cards
/// changed, and the other chapters keep their very reels, so the reader can
/// find the one it was on (see [feedIndexAfterRebuild]).
class FeedCache {
  final Map<int, _ChapterReels> _chapters = {};
}

class _ChapterReels {
  const _ChapterReels(this.chapter, this.cards, this.spotlights, this.maxReelWords, this.reels);
  final Chapter chapter;
  final List<SegmentCard> cards;
  final bool spotlights;
  final int maxReelWords;

  /// The reels of each card, in order.
  final List<List<FeedItem>> reels;

  bool fits(Chapter chapter, List<SegmentCard> cards, FeedOptions o) =>
      identical(this.chapter, chapter) &&
      identical(this.cards, cards) &&
      spotlights == o.spotlights &&
      maxReelWords == o.maxReelWords;
}

/// Turns per-chapter segments into the reader feed: chapter cards, text cards,
/// recap/recall cards, reflect cards at chapter ends and a final milestone
/// (DESIGN.md §2.2, UX_DESIGN.md §5.2). With a [cache], chapters whose cards
/// haven't changed reuse the reels they were given before.
List<FeedItem> buildFeed(BookContent book, Map<int, ChapterSegments> segments, FeedOptions options, {FeedCache? cache}) {
  final feed = <FeedItem>[];
  for (final chapter in book.chapters) {
    final seg = segments[chapter.index];
    if (seg == null || seg.cards.isEmpty) continue;
    final total = seg.cards.length;
    final kept = cache?._chapters[chapter.index];
    final List<List<FeedItem>> reels;
    if (kept != null && kept.fits(chapter, seg.cards, options)) {
      reels = kept.reels;
    } else {
      reels = _chapterReels(chapter, seg.cards, options);
      cache?._chapters[chapter.index] = _ChapterReels(chapter, seg.cards, options.spotlights, options.maxReelWords, reels);
    }
    feed.add(FeedItem(
      kind: CardKind.chapterTitle,
      chapterIndex: chapter.index,
      cardsInChapter: total,
      teaser: seg.teaser,
    ));
    for (var i = 0; i < total; i++) {
      feed.addAll(reels[i]);
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

/// The text reels of each card of a chapter: the whole card, or text ·
/// spotlight · text, with text too long for one screen continued on the
/// next reel. This is the slow part of building a feed (line layout).
List<List<FeedItem>> _chapterReels(Chapter chapter, List<SegmentCard> cards, FeedOptions options) {
  final total = cards.length;
  final sentences = <String, (Sentence, Block)>{
    for (final b in chapter.blocks)
      for (final s in b.sentences) s.id: (s, b),
  };
  int wordsOf(Iterable<String> ids) => ids.fold(0, (n, id) => n + (sentences[id]?.$1.wordCount ?? 0));
  var sinceSpotlight = 1 << 20;
  final out = <List<FeedItem>>[];
  for (var i = 0; i < total; i++) {
    final card = cards[i];
    final ai = card.layout != null || card.emphasis.isNotEmpty;
    final spot = options.spotlights && sinceSpotlight >= (ai ? spotlightGapAi : spotlightGapRules)
        ? spotlightSid(card, (id) => sentences[id]?.$1, (id) => sentences[id]?.$2.type)
        : null;
    // 1. Parts: the whole card, or text · spotlight · text.
    final at = spot == null ? -1 : card.sentenceIds.indexOf(spot);
    final parts = <(List<String>?, bool)>[
      if (spot == null)
        (null, false)
      else ...[
        if (at > 0) (card.sentenceIds.sublist(0, at), false),
        ([spot], true),
        if (at < card.sentenceIds.length - 1) (card.sentenceIds.sublist(at + 1), false),
      ],
    ];
    // 2. Reels: text too long for one screen continues on the next reel.
    final reels = <FeedItem>[];
    for (final (sids, spotlight) in parts) {
      final basis = sids ?? card.sentenceIds;
      FeedItem reel({({int from, int to})? lines, List<String>? lineSids, String? anchor, int? offset, int? words}) => FeedItem(
            kind: CardKind.text,
            chapterIndex: chapter.index,
            card: card,
            cardIndexInChapter: i,
            cardsInChapter: total,
            sids: sids,
            lines: lines,
            lineSids: lineSids,
            anchor: anchor,
            offset: offset,
            words: words ?? (sids == null ? null : wordsOf(basis)),
            spotlight: spotlight,
            lastPart: false,
          );
      if (spotlight || options.maxReelWords <= 0 || wordsOf(basis) <= options.maxReelWords) {
        reels.add(reel());
        continue;
      }
      final pieces = piecesForCard(card, [
        for (final id in basis)
          if (sentences[id] != null)
            (sid: id, text: sentences[id]!.$1.text, block: sentences[id]!.$2.index, type: sentences[id]!.$2.type),
      ]);
      final ranges = chunkPieces(pieces, options.maxReelWords);
      if (ranges.length == 1) {
        reels.add(reel());
        continue;
      }
      for (final r in ranges) {
        final shown = pieces.sublist(r.from, r.to);
        reels.add(reel(
          lines: r,
          lineSids: {for (final p in shown) p.sid}.toList(),
          anchor: shown.first.sid,
          offset: shown.first.start,
          words: lyricWords(shown),
        ));
      }
    }
    // The card counts once, on its last reel.
    final last = reels.last;
    reels[reels.length - 1] = FeedItem(
      kind: last.kind,
      chapterIndex: last.chapterIndex,
      card: last.card,
      cardIndexInChapter: last.cardIndexInChapter,
      cardsInChapter: last.cardsInChapter,
      sids: last.sids,
      lines: last.lines,
      lineSids: last.lineSids,
      anchor: last.anchor,
      offset: last.offset,
      words: last.words,
      spotlight: last.spotlight,
    );
    // Spacing between spotlights counts the reels after the last one.
    final lastSpot = reels.lastIndexWhere((r) => r.spotlight);
    sinceSpotlight = lastSpot < 0 ? sinceSpotlight + reels.length : reels.length - 1 - lastSpot;
    out.add(List.unmodifiable(reels));
  }
  return out;
}

/// Index of the reel showing [sid] at character [offset] (a long sentence can
/// continue over several reels), or the closest earlier text reel.
int feedIndexForSid(List<FeedItem> feed, String? sid, {int offset = 0}) {
  if (sid == null) return 0;
  final target = parseSid(sid);
  if (target == null) return 0;
  var best = 0;
  int? showing;
  for (var i = 0; i < feed.length; i++) {
    final card = feed[i].card;
    if (card == null) continue;
    if (feed[i].shownSids.contains(sid)) {
      // Where this reel starts within the sentence.
      final from = feed[i].anchorSid == sid ? (feed[i].offset ?? 0) : 0;
      if (showing == null || from <= offset) showing = i;
      continue;
    }
    if (showing != null) break;
    final start = parseSid(feed[i].anchorSid ?? card.startSid)!;
    final before = start.chapter < target.chapter ||
        (start.chapter == target.chapter &&
            (start.block < target.block || (start.block == target.block && start.sentence <= target.sentence)));
    if (before) best = i;
  }
  return showing ?? best;
}

/// Where a reader who was on [old]\[[index]\] belongs in [feed], the same
/// book's feed rebuilt (recaps added, the AI's cut arrived): the same reel
/// when it's still there, else the one showing the same text, and for a
/// chapter, recap or quiz card the same kind of card after the same text.
/// A rebuild never moves the reader back to text already read.
int feedIndexAfterRebuild(List<FeedItem> old, int index, List<FeedItem> feed) {
  if (feed.isEmpty || old.isEmpty) return 0;
  index = index.clamp(0, old.length - 1);
  final item = old[index];
  // Chapters that didn't change keep their reels (see [FeedCache]).
  final same = feed.indexWhere((f) => identical(f, item));
  if (same >= 0) return same;
  if (item.kind == CardKind.text) return feedIndexForSid(feed, item.anchorSid, offset: item.offset ?? 0);
  var text = index - 1;
  while (text >= 0 && old[text].kind != CardKind.text) {
    text--;
  }
  final from = text < 0 ? 0 : feedIndexAfterRebuild(old, text, feed) + 1;
  for (var i = from; i < feed.length && feed[i].kind != CardKind.text; i++) {
    if (feed[i].kind == item.kind && feed[i].chapterIndex == item.chapterIndex) return i;
  }
  return from.clamp(0, feed.length - 1);
}
