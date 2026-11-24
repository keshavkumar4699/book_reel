import 'package:book_reel/core/habit/habit_engine.dart';
import 'package:book_reel/core/models/book.dart';
import 'package:book_reel/data/habit.dart';
import 'package:book_reel/data/sessions.dart';
import 'package:book_reel/features/share/progress_shares.dart';
import 'package:book_reel/features/share/share_sheet.dart';
import 'package:book_reel/ui/kit.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final now = DateTime(2026, 11, 17, 21);
  final habit = HabitState(
    stats: {
      dateKey(now): const DailyStat(verifiedCards: 24, skimmedCards: 9, minutes: 18.4, words: 3120),
      dateKey(DateTime(2026, 11, 16)): const DailyStat(verifiedCards: 30, minutes: 25, words: 4100),
    },
    streak: const StreakState(current: 12, best: 20),
    wpm: 248,
    booksFinished: 3,
  );

  test('counts read at a glance', () {
    expect([for (final n in [950, 1200, 1000, 9950, 12400, 999999, 1300000]) compactCount(n)],
        ['950', '1.2k', '1k', '9.9k', '12k', '1000k', '1.3M']);
  });

  test('goal done: today’s cards, words and time, the streak, pace and the book; skimmed reels left out', () {
    final share = goalShare(habit: habit, streak: 12, bookTitle: 'Emma', bookProgress: 0.34, now: now);
    expect(share.headline, 'Today’s reading goal, done');
    expect(share.subtitle, 'Reading Emma');
    expect(share.stats, [
      ('24', 'cards', KitHue.activity),
      ('3.1k', 'words', KitHue.pages),
      ('18 min', 'time', KitHue.time),
      ('12', 'day streak', KitHue.growth),
      ('248', 'words/min', KitHue.pages),
      ('34%', 'of the book', KitHue.books),
    ]);
    expect(goalShare(habit: habit, streak: 30, milestone: 30, bookTitle: 'Emma', bookProgress: 0, now: now).headline, '30-day reading streak!');
  });

  test('a finished book: its words, cards, time and days, the streak and books so far', () {
    final book = BookMeta(
      id: 'b1', title: 'Emma', author: 'Jane Austen', format: BookFormat.epub, addedAt: now, wordCount: 160000, chapterCount: 55, wordsRead: 131200);
    ReadingSession s(String book, DateTime at, double minutes, int cards) =>
        ReadingSession(id: '$at', bookId: book, title: 'Emma', author: 'Jane Austen', startedAt: at, endedAt: at, minutes: minutes, cards: cards);
    final share = bookShare(
      book: book,
      sessions: [s('b1', DateTime(2026, 11, 1, 9), 40, 30), s('b1', DateTime(2026, 11, 1, 21), 25, 20), s('b2', DateTime(2026, 11, 2), 99, 99), s('b1', DateTime(2026, 11, 3), 70, 51)],
      streak: 12,
      booksFinished: 4,
    );
    expect(share.headline, 'Finished Emma');
    expect(share.stats, [
      ('131k', 'words read', KitHue.pages),
      ('101', 'cards', KitHue.activity),
      ('2 h 15 min', 'time', KitHue.time),
      ('2', 'days', KitHue.growth),
      ('12', 'day streak', KitHue.growth),
      ('4', 'books read', KitHue.books),
    ]);
    expect(share.book, same(book), reason: 'its cover on the card');
  });

  test('the profile: all-time figures', () {
    final share = profileShare(name: 'Asha', handle: 'asha.reads', reading: 'Emma', habit: habit, streak: 12, booksFinished: 3);
    expect(share.headline, 'Asha · @asha.reads');
    expect(share.stats, [
      ('3', 'books read', KitHue.books),
      ('54', 'cards', KitHue.activity),
      ('7.2k', 'words read', KitHue.pages),
      ('43 min', 'time', KitHue.time),
      ('12', 'day streak', KitHue.growth),
      ('20', 'best streak', KitHue.growth),
    ]);
    expect(share.statsLine, '3 books read · 54 cards · 7.2k words read · 43 min · 12 day streak · 20 best streak');
  });

  test('from the Journal, any time: the book and page, then time, pages, cards and the streak', () {
    final emma = BookMeta(
        id: 'b1', title: 'Emma', author: 'Jane Austen', format: BookFormat.epub, addedAt: now, wordCount: 160000, chapterCount: 55, progress: 0.34);
    final week = {
      for (var d = 0; d < 9; d++)
        dateKey(DateTime(2026, 11, 17 - d)): DailyStat(verifiedCards: 10, minutes: 12, words: d == 0 ? 2750 : 1100),
    };
    final h = HabitState(stats: week, streak: const StreakState(current: 9, best: 20), wpm: 248, booksFinished: 3);
    ProgressShare card(SharePeriod p, {BookMeta? reading}) =>
        journalShare(period: p, habit: h, streak: 9, reading: reading, booksFinished: 3, now: now);

    final today = card(SharePeriod.today, reading: emma);
    expect(today.headline, 'Today’s reading');
    // 160,000 words is about 582 pages; a third of the way in is page 198.
    expect(today.subtitle, 'Reading Emma · page 198 of 582');
    expect(today.book, same(emma));
    expect(today.stats, [
      ('12 min', 'time', KitHue.time),
      ('10', 'pages', KitHue.pages),
      ('10', 'cards', KitHue.activity),
      ('9', 'day streak', KitHue.growth),
      ('248', 'words/min', KitHue.pages),
      ('34%', 'of the book', KitHue.books),
    ]);

    // The last 7 days: today and the six before (not the two days before those).
    final last7 = card(SharePeriod.week, reading: emma);
    expect(last7.headline, 'My week of reading');
    expect(last7.stats.take(5), [
      ('1 h 24 min', 'time', KitHue.time),
      ('34', 'pages', KitHue.pages),
      ('70', 'cards', KitHue.activity),
      ('9', 'day streak', KitHue.growth),
      ('7/7', 'days read', KitHue.growth),
    ]);

    final all = card(SharePeriod.all);
    expect(all.headline, 'My reading so far');
    expect(all.subtitle, isNull, reason: 'no book being read');
    expect(all.stats, [
      ('1 h 48 min', 'time', KitHue.time),
      ('42', 'pages', KitHue.pages),
      ('90', 'cards', KitHue.activity),
      ('9', 'day streak', KitHue.growth),
      ('20', 'best streak', KitHue.growth),
      ('3', 'books read', KitHue.books),
    ]);
    expect(pagesFor(0), 0);
    expect(pagesFor(40), 1, reason: 'a few words still make a page');
    expect(journalShare(period: SharePeriod.today, habit: h, streak: 2, weekly: true, reading: null, booksFinished: 0, now: now).stats[3],
        ('2', 'week streak', KitHue.growth));
  });

  testWidgets('figures wear the app’s colours on the plain cards, white on the coloured ones', (tester) async {
    final share = goalShare(habit: habit, streak: 12, bookTitle: 'Emma', bookProgress: 0.34, now: now);
    Color colourOf(String value) => tester.widget<Text>(find.text(value)).style!.color!;
    for (final (template, kit) in [(ShareTemplate.paper, Kit.appLight), (ShareTemplate.minimal, Kit.appLight), (ShareTemplate.dark, Kit.appDark)]) {
      await tester.pumpWidget(MaterialApp(home: Center(child: ShareCardArt(content: share, template: template, aspect: ShareAspect.story))));
      expect(colourOf('18 min'), kit.hue(KitHue.time), reason: '${template.name}: time in orange');
      expect(colourOf('24'), kit.hue(KitHue.activity), reason: 'cards in blue');
      expect(colourOf('12'), kit.hue(KitHue.growth), reason: 'the streak in green');
      expect(colourOf('34%'), kit.hue(KitHue.books), reason: 'the book in pink');
    }
    await tester.pumpWidget(MaterialApp(home: Center(child: ShareCardArt(content: share, template: ShareTemplate.ember, aspect: ShareAspect.story))));
    expect(colourOf('18 min'), Colors.white);
    expect(find.text('cloro.in'), findsOneWidget);
  });

  testWidgets('the card shows every figure, in a grid, on both shapes', (tester) async {
    final share = goalShare(habit: habit, streak: 12, bookTitle: 'Emma', bookProgress: 0.34, now: now);
    for (final aspect in ShareAspect.values) {
      await tester.pumpWidget(MaterialApp(
        home: Center(child: ShareCardArt(content: share, template: ShareTemplate.dark, aspect: aspect)),
      ));
      for (final (value, label, _) in share.stats) {
        expect(find.text(value), findsOneWidget, reason: '$label on ${aspect.name}');
        expect(find.text(label.toUpperCase()), findsOneWidget);
      }
      expect(tester.takeException(), isNull, reason: 'nothing overflows on ${aspect.name}');
      // Three figures to a row.
      expect(tester.getTopLeft(find.text('24')).dy, tester.getTopLeft(find.text('18 min')).dy);
      expect(tester.getTopLeft(find.text('12')).dy, greaterThan(tester.getTopLeft(find.text('24')).dy));
    }
  });
}
